// TimelineScrubber.swift
// Meridian — iOS 27 / Swift 6
//
// Ported from the Android source of truth:
//   app/src/main/java/com/example/core/designsystem/TimelineScrubber.kt
//   app/src/main/java/com/example/core/designsystem/ScrubberGestures.kt
//
// Behaviour reproduced from Android, expressed idiomatically for SwiftUI:
//   • Collapsed-by-default *pill* that expands into a full physical *dial* on press,
//     and auto-collapses back to the pill after a short idle (DIAL_COLLAPSE_DELAY_MS).
//   • Drag-gain acceleration (`dragGain`) so slow drags stay ~1:1 (granular, 5-min grid)
//     while fast swipes multiply the distance covered.
//   • Velocity-based snap on release (`snapUnitForVelocity`): a hard flick rounds to the
//     hour, a gentle release stays on the fine 5-minute grid.
//   • Throttled detent haptics (DETENT_MIN_GAP_NANOS) so a fast spin whirrs rather than
//     machine-guns — delivered via `.sensoryFeedback` (no UIImpactFeedbackGenerator).
//   • A ruler Canvas drawing hour / half-hour / quarter-hour ticks with offset labels,
//     a center "now" band, glow line, and caret — matching the Android dial.
//
// The internal source of truth is the *offset in minutes* in the range −720…720
// (mirroring the Android `slider` Animatable). The single public surface remains a
// `Binding<TimeInterval>` of offset seconds (the View layer / WorldClockScreen converts
// that to `TimeEngine.scrubInstant`, an absolute Date — per the shared contract the model
// never bakes UTC strings; only the view renders to a zone's local time).

import SwiftUI
import Foundation

// MARK: - Constants

private enum ScrubberConstants {
    /// The finest grid the dial reports while dragging — slow, careful drags can land here.
    static let stepMinutes: Int = 5
    /// One 16-pt tick column == 15 minutes at 1× speed.
    static let minutesPerTick: CGFloat = 15
    /// Spacing between quarter-hour tick columns, in points (Android: 16.dp).
    static let tickSpacing: CGFloat = 16
    /// Offset bounds in minutes: ±12 h.
    static let minOffsetMinutes: CGFloat = -720
    static let maxOffsetMinutes: CGFloat = 720
    /// −48…+48 quarter-hour steps span the ±12 h range.
    static let totalSteps: Int = 48
    /// Detents fire at most this often (30 ms), so a fast spin whirrs rather than machine-guns.
    static let detentMinGap: TimeInterval = 0.030
    /// Idle time before the expanded dial snaps back to the pill (Android: 400 ms).
    static let dialCollapseDelay: Duration = .milliseconds(400)
    /// Dial track height (Android: 80.dp).
    static let dialHeight: CGFloat = 80
}

/// Acceleration curve for dragging: slow drags stay ~1:1 (granular), fast drags multiply the
/// distance so a quick swipe covers far more time. `speedPointsPerMs` is the finger's instant speed.
/// Ported verbatim from Android `dragGain`.
private func dragGain(speedPointsPerMs: CGFloat) -> CGFloat {
    min(max(1 + speedPointsPerMs * 1.1, 1), 4)
}

/// On release, the fling speed (points/sec) picks how coarsely the dial settles: a hard flick
/// rounds to the hour and covers lots of ground, a gentle release stays on the fine 5-minute grid.
/// Ported verbatim from Android `snapUnitForVelocity`.
private func snapUnitForVelocity(absVelocityPointsPerSec: CGFloat) -> Int {
    switch absVelocityPointsPerSec {
    case let v where v > 2500: return 60
    case let v where v > 1000: return 30
    case let v where v > 300:  return 15
    default:                   return ScrubberConstants.stepMinutes
    }
}

/// Compact offset label, e.g. "Live", "+3h 15m", "-2h". Ported from Android `offsetLabel`.
private func offsetLabel(totalMinutes: Int) -> String {
    if totalMinutes == 0 { return "Live" }
    let sign = totalMinutes > 0 ? "+" : "-"
    let absValue = abs(totalMinutes)
    let hours = absValue / 60
    let minutes = absValue % 60
    var result = sign
    if hours > 0 { result += "\(hours)h" }
    if minutes > 0 {
        if hours > 0 { result += " " }
        result += "\(minutes)m"
    }
    return result
}

// MARK: - ScrubberPillDefaults

/// Shared collapsed-pill sizing so the control stays easy to grab (Android `ScrubberPillDefaults`).
enum ScrubberPillDefaults {
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 14
    static let minHeight: CGFloat = 48
    static let minWidth: CGFloat = 132
    static let iconSize: CGFloat = 20
}

// MARK: - TimelineScrubber

/// An expand/collapse pill↔dial scrubber that drives the app's scrub offset.
///
/// The public surface is a `Binding<TimeInterval>` of *offset seconds* (positive = future,
/// negative = past). The owning screen converts this to `TimeEngine.scrubInstant` (an absolute
/// `Date`). Internally the scrubber works in offset *minutes* to mirror the Android dial exactly.
///
/// Usage:
/// ```swift
/// @State private var offsetSeconds: TimeInterval = 0
/// TimelineScrubber(offsetSeconds: $offsetSeconds)
/// ```
struct TimelineScrubber: View {

    /// Current scrub offset in seconds. Positive = future, negative = past.
    @Binding var offsetSeconds: TimeInterval

    /// When `true`, the dial readout uses 24-hour time. Defaults to 12-hour (matching Android `is24Hour = false`).
    var is24Hour: Bool = false

    // MARK: - Environment

    /// Gates every non-essential animation (expand/collapse morph, press-scale, glide) so
    /// users who ask for Reduce Motion get a fade / instant path instead of springs.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Live dial state (offset in minutes, mirroring the Android `slider`)

    /// Continuous dial offset in minutes (−720…720). Updated live while dragging; animated
    /// to a snapped target on release / reset / tap-to-jump.
    @State private var sliderMinutes: CGFloat = 0
    /// True while a finger is held on the dial (drives the press-scale + blocks auto-collapse).
    @State private var dialPressed = false
    /// True while the pill was already expanded when the current gesture began
    /// (so a tap on the *expanded* dial jumps to the tapped column; a tap on the *pill* only expands).
    @State private var wasExpandedAtStart = false
    /// Collapsed (pill) vs expanded (dial).
    @State private var expanded = false
    /// Width of the whole control, captured for accurate tap-to-jump column math.
    @State private var controlWidth: CGFloat = 0

    // MARK: Detent haptics

    /// Bumps every time a detent should fire; `.sensoryFeedback(trigger:)` reacts to changes.
    @State private var detentTick = 0
    /// Last time a detent haptic fired, for throttling (DETENT_MIN_GAP_NANOS).
    @State private var lastDetentTime: TimeInterval = 0
    /// Last quarter-hour-grid bucket we emitted a detent for, so we only fire on boundary crossings.
    @State private var lastDetentBucket: Int = 0

    // MARK: Velocity tracking (manual, for fidelity with Android VelocityTracker)

    /// Recent (timestamp, translationWidth) samples used to estimate release velocity.
    @State private var velocitySamples: [(t: TimeInterval, x: CGFloat)] = []

    // MARK: Auto-collapse

    /// Bumps on every interaction; the auto-collapse task observes it to restart its idle timer.
    @State private var interactionTick = 0

    // MARK: Derived

    /// The live offset, snapped to the fine 5-minute grid — the single source of truth for the
    /// readout, the pill, and the binding (mirrors Android `liveOffsetMin`).
    private var liveOffsetMinutes: Int {
        let step = CGFloat(ScrubberConstants.stepMinutes)
        return Int((sliderMinutes / step).rounded()) * ScrubberConstants.stepMinutes
    }

    private var scrubbed: Bool { liveOffsetMinutes != 0 }

    private var primary: Color { MeridianColors.primary }
    private var onSurface: Color { MeridianColors.onSurface }

    // MARK: - Body

    var body: some View {
        ZStack {
            if expanded {
                dialCard
                    .transition(Motion.scrubberContentTransition(reduceMotion: reduceMotion))
            } else {
                collapsedPill
                    .transition(Motion.scrubberContentTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { controlWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, w in controlWidth = w }
            }
        )
        // Purpose-built size-morph spring (never overshoots), collapsed to instant under Reduce Motion.
        .animation(Motion.scrubberExpandCollapse(expanding: expanded, reduceMotion: reduceMotion), value: expanded)
        // Single press+drag gesture spanning the whole control, mirroring Android's
        // `detectScrubberPressDrag`: a press expands the pill; the same finger then drags.
        .gesture(pressDragGesture)
        // Throttled detent haptic — fires when `detentTick` changes (we only bump it on a
        // genuine, throttled boundary crossing, so this never machine-guns).
        .sensoryFeedback(.selection, trigger: detentTick)
        // Expansion "open" haptic — fires only on the collapse→expand transition.
        .sensoryFeedback(.impact(weight: .light), trigger: expanded) { wasExpanded, isExpanded in
            !wasExpanded && isExpanded
        }
        // Keep the binding in sync whenever the snapped live offset changes.
        .onChange(of: liveOffsetMinutes) { _, newValue in
            offsetSeconds = TimeInterval(newValue * 60)
        }
        // External reset: parent cleared the offset → glide the dial home (unless a finger is down).
        .onChange(of: offsetSeconds) { _, newValue in
            if newValue == 0, !dialPressed, abs(sliderMinutes) > 0.001 {
                withAnimation(Motion.reducedOrInstant(Motion.smooth(), reduceMotion: reduceMotion)) {
                    sliderMinutes = 0
                }
            }
        }
        // Auto-collapse after a short idle, but never while a finger is still down.
        .task(id: interactionTick) {
            guard expanded, !dialPressed else { return }
            do {
                try await Task.sleep(for: ScrubberConstants.dialCollapseDelay)
            } catch {
                return // cancelled by a newer interaction
            }
            if !dialPressed {
                withAnimation(Motion.scrubberExpandCollapse(expanding: false, reduceMotion: reduceMotion)) { expanded = false }
            }
        }
        .onAppear {
            // Adopt any externally-set offset on first appearance.
            sliderMinutes = CGFloat(offsetSeconds / 60)
        }
    }

    // MARK: - Collapsed pill

    private var collapsedPill: some View {
        HStack(spacing: 0) {
            // Icon chip — reads as tappable chrome regardless of glass opacity.
            ZStack {
                Circle().fill(primary.opacity(0.16))
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(primary)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            Spacer().frame(width: MeridianSpacing.md.rawValue)

            Text(offsetLabel(totalMinutes: liveOffsetMinutes))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(liveOffsetMinutes == 0 ? onSurface : primary)
                .contentTransition(.numericText())
                .animation(Motion.reduced(Motion.quick(), reduceMotion: reduceMotion), value: liveOffsetMinutes)

            if !scrubbed {
                Spacer().frame(width: MeridianSpacing.xs.rawValue)
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(onSurface.opacity(0.5))
                    .accessibilityHidden(true)
            } else {
                // One-tap reset right on the pill — no need to expand.
                Spacer().frame(width: MeridianSpacing.sm.rawValue)
                Button {
                    goToStep(0)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(primary.opacity(0.15)))
                        // 44-pt hit target without inflating the compact pill's height.
                        .frame(width: 44, height: 44)
                        .padding(.vertical, -8)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset to live")
                .accessibilityHint("Returns the scrubber to the live time")
            }
        }
        .padding(.horizontal, ScrubberPillDefaults.horizontalPadding)
        .padding(.vertical, ScrubberPillDefaults.verticalPadding)
        .frame(minWidth: ScrubberPillDefaults.minWidth, minHeight: ScrubberPillDefaults.minHeight)
        .liquidGlass(cornerRadius: MeridianRadius.medium.rawValue, tint: primary)
        .overlay(
            RoundedRectangle(cornerRadius: MeridianRadius.medium.rawValue, style: .continuous)
                .strokeBorder(primary.opacity(0.4), lineWidth: 1)
        )
        .scaleEffect(dialPressed ? 0.94 : 1)
        .animation(Motion.reduced(Motion.bouncy(), reduceMotion: reduceMotion), value: dialPressed)
        // Group the chip/label/affordance into a single control and make it adjustable so
        // VoiceOver users can scrub the offset without performing the press-drag gesture.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time scrubber")
        .accessibilityValue(accessibilityReadout)
        .accessibilityHint("Swipe up or down to adjust the time offset")
        .accessibilityAdjustableAction(handleAccessibilityAdjust)
        .accessibilityAction(named: Text("Reset to live")) { goToStep(0) }
    }

    // MARK: - Expanded dial card

    private var dialCard: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.xl.rawValue) {
            // Header — the live readout is the focal point; the title sits above it as a quiet label.
            HStack(alignment: .firstTextBaseline, spacing: MeridianSpacing.sm.rawValue) {
                VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
                    Text("Time dial")
                        .font(.titleMedium)
                        .foregroundStyle(onSurface.opacity(0.6))
                        .accessibilityHidden(true)

                    Text(readoutText)
                        .font(.headlineMedium)
                        .foregroundStyle(onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.numericText())
                        .animation(Motion.reduced(Motion.quick(), reduceMotion: reduceMotion), value: liveOffsetMinutes)
                        .accessibilityHidden(true)
                }

                Spacer(minLength: 0)

                if scrubbed {
                    Button {
                        goToStep(0)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .background(
                                Circle()
                                    .fill(primary.opacity(0.1))
                                    .frame(width: 36, height: 36)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset to live")
                    .accessibilityHint("Returns the scrubber to the live time")
                }
            }

            // Draggable physical dial. The Canvas drawing itself is decorative (hidden), while
            // the containing region carries the semantic value + adjustable action so VoiceOver
            // can scrub without the press-drag gesture and never lands on an unlabeled canvas.
            dialCanvas
                .accessibilityHidden(true)
                .frame(height: ScrubberConstants.dialHeight)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                        .fill(onSurface.opacity(0.06))
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time offset")
                .accessibilityValue(accessibilityReadout)
                .accessibilityHint("Swipe up or down to adjust the time offset")
                .accessibilityAdjustableAction(handleAccessibilityAdjust)

            HStack(spacing: MeridianSpacing.sm.rawValue) {
                Text("-12 hrs")
                    .font(.labelMedium)
                    .foregroundStyle(onSurface.opacity(0.7))
                Spacer(minLength: 0)
                Text("Hold & drag to scrub · flick to jump hours")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(onSurface.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("+12 hrs")
                    .font(.labelMedium)
                    .foregroundStyle(onSurface.opacity(0.7))
            }
            .accessibilityHidden(true)
        }
        .padding(MeridianSpacing.xl.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: MeridianRadius.medium.rawValue, tint: primary)
        .overlay(
            RoundedRectangle(cornerRadius: MeridianRadius.medium.rawValue, style: .continuous)
                .strokeBorder(primary.opacity(0.5), lineWidth: 1.5)
        )
        // Group the card so VoiceOver reads it as one region containing the adjustable dial
        // element and the reset button, rather than stopping on decorative sub-views.
        .accessibilityElement(children: .contain)
    }

    private var readoutText: String {
        let off = liveOffsetMinutes
        if off == 0 { return "Synced with Live Ticker" }
        let date = Date().addingTimeInterval(TimeInterval(off * 60))
        // VERIFY: Date.FormatStyle template fields. Use 12/24-hour switch via .hour conversion.
        let timeStyle: Date.FormatStyle = is24Hour
            ? Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            : Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)
        let dayStyle = Date.FormatStyle()
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day(.defaultDigits)
        return "\(date.formatted(timeStyle)) · \(date.formatted(dayStyle))"
    }

    /// Spoken value for VoiceOver — a plain-language offset plus the resulting time, so the
    /// control announces both "how far from live" and "what time that is" on every adjustment.
    private var accessibilityReadout: String {
        let off = liveOffsetMinutes
        guard off != 0 else { return "Live, synced with the current time" }
        let direction = off > 0 ? "ahead of" : "behind"
        // Sign-free spoken magnitude, e.g. "3 hours 15 minutes".
        let absValue = abs(off)
        let hours = absValue / 60
        let minutes = absValue % 60
        var magnitude = ""
        if hours > 0 { magnitude += "\(hours) hour\(hours == 1 ? "" : "s")" }
        if minutes > 0 {
            if !magnitude.isEmpty { magnitude += " " }
            magnitude += "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        let date = Date().addingTimeInterval(TimeInterval(off * 60))
        let timeStyle: Date.FormatStyle = is24Hour
            ? Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            : Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)
        return "\(magnitude) \(direction) live, \(date.formatted(timeStyle))"
    }

    /// VoiceOver adjustable handler: steps the offset by the fine grid per increment / decrement
    /// and voices the new value (the control's `.accessibilityValue` is re-read automatically).
    private func handleAccessibilityAdjust(_ direction: AccessibilityAdjustmentDirection) {
        // Step from the currently-displayed (snapped) value so increments land exactly on the grid.
        let step = ScrubberConstants.stepMinutes
        let delta = direction == .increment ? step : -step
        let target = CGFloat(liveOffsetMinutes + delta)
        let clamped = min(
            max(target, ScrubberConstants.minOffsetMinutes),
            ScrubberConstants.maxOffsetMinutes
        )
        bumpInteraction()
        withAnimation(Motion.reducedOrInstant(Motion.quick(), reduceMotion: reduceMotion)) {
            sliderMinutes = clamped
        }
        detentTick &+= 1
    }

    // MARK: - Dial Canvas

    private var dialCanvas: some View {
        Canvas { context, size in
            drawDial(context: &context, size: size)
        }
    }

    private func drawDial(context: inout GraphicsContext, size: CGSize) {
        let tickSpacing = ScrubberConstants.tickSpacing
        let width = size.width
        let height = size.height
        let centerX = width / 2

        // High-contrast center highlight band marking the "now" column.
        let bandHalf = tickSpacing * 0.9
        context.fill(
            Path(CGRect(x: centerX - bandHalf, y: 0, width: bandHalf * 2, height: height)),
            with: .color(primary.opacity(0.18))
        )

        // Ticks. The dial scrolls by `sliderMinutes`; one step == 15 min == one column.
        let centerStep = sliderMinutes / 15
        let startTick = max(Int((centerStep - 20).rounded()), -ScrubberConstants.totalSteps)
        let endTick = min(max(Int((centerStep + 20).rounded()), startTick), ScrubberConstants.totalSteps)

        guard startTick <= endTick else { return }

        for tick in startTick...endTick {
            let itemX = centerX + (CGFloat(tick) - centerStep) * tickSpacing

            let isHourTick = tick % 4 == 0
            let isHalfHourTick = tick % 2 == 0

            let tickLen: CGFloat = isHourTick ? 24 : (isHalfHourTick ? 16 : 8)
            let tickColor: Color = isHourTick
                ? onSurface.opacity(0.95)
                : (isHalfHourTick ? onSurface.opacity(0.65) : onSurface.opacity(0.4))
            let strokeWidth: CGFloat = isHourTick ? 2.5 : 1.5

            var line = Path()
            line.move(to: CGPoint(x: itemX, y: height - tickLen))
            line.addLine(to: CGPoint(x: itemX, y: height))
            context.stroke(
                line,
                with: .color(tickColor),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )

            // Label major (hour) ticks with the offset.
            if isHourTick {
                let offsetHours = tick * 15 / 60
                let label: String
                if offsetHours > 0 { label = "+\(offsetHours)h" }
                else if offsetHours < 0 { label = "\(offsetHours)h" }
                else { label = "Live" }

                let resolved = context.resolve(
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(onSurface.opacity(0.85))
                )
                let textSize = resolved.measure(in: CGSize(width: 60, height: 20))
                context.draw(
                    resolved,
                    at: CGPoint(x: itemX, y: height - tickLen - textSize.height / 2 - 4),
                    anchor: .center
                )
            }
        }

        // Center indicator: soft glow underlay + crisp primary line.
        var glow = Path()
        glow.move(to: CGPoint(x: centerX, y: 0))
        glow.addLine(to: CGPoint(x: centerX, y: height))
        context.stroke(
            glow,
            with: .color(primary.opacity(0.35)),
            style: StrokeStyle(lineWidth: 7, lineCap: .round)
        )
        var centerLine = Path()
        centerLine.move(to: CGPoint(x: centerX, y: 0))
        centerLine.addLine(to: CGPoint(x: centerX, y: height))
        context.stroke(
            centerLine,
            with: .color(primary),
            style: StrokeStyle(lineWidth: 3, lineCap: .butt)
        )

        // Caret at the top of the center line.
        let caretSize: CGFloat = 6
        var caret = Path()
        caret.move(to: CGPoint(x: centerX - caretSize, y: 0))
        caret.addLine(to: CGPoint(x: centerX + caretSize, y: 0))
        caret.addLine(to: CGPoint(x: centerX, y: caretSize * 1.4))
        caret.closeSubpath()
        context.fill(caret, with: .color(primary))
    }

    // MARK: - Gesture (press → expand → drag, single finger)

    private var pressDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let now = ProcessInfo.processInfo.systemUptime

                if !dialPressed {
                    // Press start (mirrors Android onPressStart).
                    wasExpandedAtStart = expanded
                    if !expanded {
                        withAnimation(Motion.scrubberExpandCollapse(expanding: true, reduceMotion: reduceMotion)) { expanded = true }
                    }
                    dialPressed = true
                    velocitySamples = [(t: now, x: 0)]
                    lastDetentBucket = liveOffsetMinutes / 15
                    bumpInteraction()
                }

                // Record sample for velocity estimation.
                velocitySamples.append((t: now, x: value.translation.width))
                if velocitySamples.count > 12 { velocitySamples.removeFirst() }

                // Only treat as a drag once past a small slop (mirrors Android touchSlop).
                guard abs(value.translation.width) > 3 || abs(value.translation.height) > 3 else { return }

                // Instantaneous finger speed → drag gain.
                let prev = velocitySamples.count >= 2 ? velocitySamples[velocitySamples.count - 2] : (t: now, x: value.translation.width)
                let dtMs = max((now - prev.t) * 1000, 1)
                let dxThisFrame = value.translation.width - prev.x
                let speedPointsPerMs = abs(dxThisFrame) / CGFloat(dtMs)
                let gain = dragGain(speedPointsPerMs: speedPointsPerMs)

                // Drag left = positive offset = future (delta.x negative → +minutes).
                // Android maps a continuous translation; we re-derive from the per-frame delta so
                // gain applies to the incremental motion just like Android's onDrag.
                let minutesChange = -(dxThisFrame / ScrubberConstants.tickSpacing) * ScrubberConstants.minutesPerTick * gain
                let target = min(
                    max(sliderMinutes + minutesChange, ScrubberConstants.minOffsetMinutes),
                    ScrubberConstants.maxOffsetMinutes
                )
                sliderMinutes = target
                bumpInteraction()
                maybeFireDetent(now: now)
            }
            .onEnded { value in
                let now = ProcessInfo.processInfo.systemUptime
                let dragged = abs(value.translation.width) > 3 || abs(value.translation.height) > 3
                dialPressed = false
                bumpInteraction()

                if dragged {
                    // Release-velocity snap (mirrors Android snapUnitForVelocity).
                    let velocity = releaseVelocityPointsPerSec()
                    let unit = snapUnitForVelocity(absVelocityPointsPerSec: abs(velocity))
                    let unitF = CGFloat(unit)
                    let snapped = (sliderMinutes / unitF).rounded() * unitF
                    let clamped = min(max(snapped, ScrubberConstants.minOffsetMinutes), ScrubberConstants.maxOffsetMinutes)
                    withAnimation(Motion.reducedOrInstant(Motion.snappy(), reduceMotion: reduceMotion)) {
                        sliderMinutes = clamped
                    }
                } else if wasExpandedAtStart {
                    // Tap on the already-expanded dial → jump to the tapped column.
                    // `value.location.x` is in the control's coordinate space; the dial canvas is
                    // inset by 20-pt horizontal card padding, so its center sits at controlWidth/2.
                    let center = controlWidth > 0 ? controlWidth / 2 : value.location.x
                    let tappedStep = (sliderMinutes / 15
                        + (value.location.x - center) / ScrubberConstants.tickSpacing).rounded()
                    goToStep(Int(tappedStep))
                }
                velocitySamples.removeAll(keepingCapacity: true)
            }
    }

    // MARK: - Programmatic glide

    /// Glide the dial to a target quarter-hour step, then update the binding (mirrors Android `goToStep`).
    private func goToStep(_ step: Int) {
        let clamped = min(max(step, -ScrubberConstants.totalSteps), ScrubberConstants.totalSteps)
        let target = CGFloat(clamped * 15)
        bumpInteraction()
        withAnimation(Motion.reducedOrInstant(Motion.smooth(), reduceMotion: reduceMotion)) {
            sliderMinutes = target
        }
        // Fire one detent on arrival.
        detentTick &+= 1
    }

    // MARK: - Detent throttling

    private func maybeFireDetent(now: TimeInterval) {
        let bucket = liveOffsetMinutes / 15
        guard bucket != lastDetentBucket else { return }
        lastDetentBucket = bucket
        guard now - lastDetentTime > ScrubberConstants.detentMinGap else { return }
        lastDetentTime = now
        detentTick &+= 1
    }

    // MARK: - Velocity helpers

    /// Estimates release velocity in points/second from recent samples (mirrors VelocityTracker.x).
    private func releaseVelocityPointsPerSec() -> CGFloat {
        guard velocitySamples.count >= 2 else { return 0 }
        let last = velocitySamples[velocitySamples.count - 1]
        // Use the oldest sample within a ~100 ms window for a stable estimate.
        var refIndex = 0
        for i in stride(from: velocitySamples.count - 1, through: 0, by: -1) {
            if last.t - velocitySamples[i].t > 0.1 { refIndex = i; break }
        }
        let ref = velocitySamples[refIndex]
        let dt = last.t - ref.t
        guard dt > 0 else { return 0 }
        return (last.x - ref.x) / CGFloat(dt)
    }

    // MARK: - Interaction tick

    private func bumpInteraction() {
        interactionTick &+= 1
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Timeline Scrubber") {
    struct PreviewWrapper: View {
        @State private var offset: TimeInterval = 0
        var body: some View {
            ZStack {
                MeridianColors.background.ignoresSafeArea()
                VStack(spacing: 32) {
                    TimelineScrubber(offsetSeconds: $offset)
                        .padding(.horizontal, 16)
                    Text("Offset: \(Int(offset / 60)) min")
                        .foregroundStyle(MeridianColors.onBackground)
                        .font(.caption)
                }
            }
            .environment(\.glassEnabled, true)
            .environment(\.reduceTransparencyOverride, false)
        }
    }
    return PreviewWrapper()
}
#endif
