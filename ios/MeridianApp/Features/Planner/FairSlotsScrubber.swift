// FairSlotsScrubber.swift
// Meridian — iOS 27 / Swift 6
//
// Horizontal "fairness dial" across the 24 hours of the selected day. Direct behavioral port of
// Android `FairSlotsScrubber.kt`. Colored bands mark Optimal / Fair / Difficult hours; a compact
// glass pill expands on press and supports drag-to-scrub, snapping the handle to the nearest
// selectable hour and auto-collapsing ~0.4s after the last interaction.

import SwiftUI

// MARK: - DialHour

/// One hour of the planning window. `slot` is `nil` when filtered out (e.g. a weekend with
/// "Exclude weekends" on) — rendered as a muted, non-selectable band. Mirrors Android `DialHour`.
struct DialHour: Identifiable, Sendable {
    let instant: Date
    let slot: MeetingSlot?
    /// `nil` when the band is filtered out, else the slot's rating bucket.
    let label: SlotLabel?

    var id: Date { instant }
}

// MARK: - FairSlotsScrubber

struct FairSlotsScrubber: View {
    let hours: [DialHour]
    let selectedIndex: Int
    let localZoneId: String
    let durationMinutes: Int
    let use24Hour: Bool
    let onSelect: (Int) -> Void

    @State private var expanded = false
    @State private var dialPressed = false
    /// Bumped on every interaction so the auto-collapse task restarts.
    @State private var interactionTick = 0
    @State private var collapseTask: Task<Void, Never>? = nil
    /// Bumped whenever the selection snaps to a new band — drives `.sensoryFeedback`.
    @State private var selectionTick = 0

    /// Honour the user's Reduce Motion setting: skip press bounce and switch the
    /// expand/collapse morph to a near-instant crossfade (matches the World scrubber).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the accessory glass tints so the dial tracks the glass-opacity slider.
    @Environment(\.glassOpacity) private var glassOpacity

    private var localZone: TimeZone { TimeFormats.safeTimeZone(id: localZoneId) }

    private var selected: DialHour? {
        guard !hours.isEmpty else { return nil }
        return hours.indices.contains(selectedIndex) ? hours[selectedIndex] : hours.first
    }

    /// "09:00 – 09:45" — start in context, end without.
    private var pillTime: String {
        guard let selected else { return "" }
        let start = TimeFormats.hourMinute(date: selected.instant, timeZone: localZone, use24Hour: use24Hour)
        let endDate = selected.instant.addingTimeInterval(Double(durationMinutes) * 60.0)
        let end = TimeFormats.hourMinute(date: endDate, timeZone: localZone, use24Hour: use24Hour)
        return "\(start) – \(end)"
    }

    /// Spoken rating for VoiceOver — e.g. "Optimal". Falls back to "no overlap" when filtered out.
    private var ratingSpoken: String {
        selected?.label?.displayName ?? "No overlap"
    }

    /// The single value read to VoiceOver for the dial and collapsed pill.
    private var accessibilityValue: String {
        "\(pillTime), \(ratingSpoken)"
    }

    var body: some View {
        if hours.isEmpty {
            EmptyView()
        } else {
            content
                .onChange(of: interactionTick) { _, _ in scheduleAutoCollapse() }
                .onChange(of: dialPressed) { _, pressed in if !pressed { scheduleAutoCollapse() } }
                .sensoryFeedback(.selection, trigger: selectionTick)
                .sensoryFeedback(.impact(weight: .medium), trigger: expanded) { was, now in
                    !was && now
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if expanded {
            expandedDial
                .transition(Motion.scrubberContentTransition(reduceMotion: reduceMotion))
        } else {
            collapsedPill
                .transition(Motion.scrubberContentTransition(reduceMotion: reduceMotion))
        }
    }

    // MARK: Collapsed pill

    private var collapsedPill: some View {
        HStack(spacing: MeridianSpacing.sm.rawValue) {
            Image(systemName: "slider.horizontal.3")
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.primary)
                .accessibilityHidden(true)
            Text(pillTime)
                .font(.titleMedium)
                .fontWeight(.heavy)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.9))
            if let label = selected?.label {
                let color = SlotCard.ratingColor(for: label)
                Text(label.displayName)
                    .font(.labelMedium)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                    .padding(.horizontal, MeridianSpacing.sm.rawValue)
                    .padding(.vertical, MeridianSpacing.xs.rawValue)
                    .background { Capsule().fill(color.opacity(0.18)) }
            }
        }
        .padding(.horizontal, MeridianSpacing.lg.rawValue)
        .padding(.vertical, MeridianSpacing.md.rawValue)
        .frame(minHeight: 48)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay { Capsule().fill(MeridianColors.accessoryPillTint(opacity: glassOpacity)) }
                .overlay { Capsule().strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1) }
        }
        .scaleEffect((dialPressed && !reduceMotion) ? 0.94 : 1)
        .contentShape(Capsule())
        .onTapGesture {
            expand()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fair-time dial")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Double-tap to expand and scrub across the day")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Expanded dial

    private var expandedDial: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fair-time dial")
                .font(.titleMedium)
                .fontWeight(.heavy)
                .foregroundStyle(MeridianColors.onSurface)
                .accessibilityAddTraits(.isHeader)
            Spacer().frame(height: 2)
            Text("\(pillTime) · \(ratingSpoken)")
                .font(.bodyMedium)
                .fontWeight(.semibold)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.9))
                // Header + readout are voiced through the dial's accessibilityValue.
                .accessibilityHidden(true)

            Spacer().frame(height: MeridianSpacing.lg.rawValue)

            dialTrack
                .frame(height: 72)

            Spacer().frame(height: MeridianSpacing.sm.rawValue)
            legend
        }
        .padding(MeridianSpacing.xl.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: MeridianRadius.medium.rawValue, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: MeridianRadius.medium.rawValue, style: .continuous)
                        .fill(MeridianColors.accessoryCardTint(opacity: glassOpacity))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: MeridianRadius.medium.rawValue, style: .continuous)
                        .strokeBorder(MeridianColors.primary.opacity(0.5), lineWidth: 1.5)
                }
        }
    }

    /// Colour-coded legend under the dial: each band word is tinted to the band it names,
    /// so the sentence visually matches the track it explains.
    private var legend: some View {
        legendText
            .font(.labelMedium)
            .accessibilityLabel("Bands rank hours from Optimal to Difficult.")
    }

    /// Assembled step-by-step (rather than one long `+` chain) so the type-checker can
    /// resolve it in reasonable time. Each band word is tinted to its rating color.
    private var legendText: Text {
        let plain = MeridianColors.onSurfaceVariant
        var text = Text("Hold & drag across the day — ").foregroundColor(plain)
        text = text + Text("Optimal").foregroundColor(SlotCard.ratingColor(for: .optimal))
        text = text + Text(" is best, ").foregroundColor(plain)
        text = text + Text("Fair").foregroundColor(SlotCard.ratingColor(for: .fair))
        text = text + Text(" works, ").foregroundColor(plain)
        text = text + Text("Difficult").foregroundColor(SlotCard.ratingColor(for: .difficult))
        text = text + Text(" is hard.").foregroundColor(plain)
        return text
    }

    private var dialTrack: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let n = hours.count
                guard n > 0 else { return }
                let gap: CGFloat = 3
                let segW = size.width / CGFloat(n)
                let trackTop: CGFloat = 12
                let trackBottom = size.height - 16
                let radius: CGFloat = 4

                for (i, hour) in hours.enumerated() {
                    let isSel = i == selectedIndex
                    let color = bandColor(hour.label)
                    let left = CGFloat(i) * segW + gap / 2
                    let top = isSel ? trackTop - 4 : trackTop
                    let bottom = isSel ? trackBottom + 4 : trackBottom
                    let rect = CGRect(x: left, y: top, width: segW - gap, height: bottom - top)
                    let fill = hour.slot == nil
                        ? color
                        : color.opacity(isSel ? 0.95 : 0.5)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: radius),
                        with: .color(fill)
                    )
                }

                // Handle dot with a surface-colored halo so it reads against any band color.
                let cx = CGFloat(selectedIndex) * segW + segW / 2
                let cy = trackTop - 8
                context.fill(
                    Path(ellipseIn: CGRect(x: cx - 6.5, y: cy - 6.5, width: 13, height: 13)),
                    with: .color(MeridianColors.surface)
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)),
                    with: .color(MeridianColors.primary)
                )

                // Sparse hour labels (every 6th hour) under the track.
                for (i, hour) in hours.enumerated() where i % 6 == 0 {
                    let text = TimeFormats.hourMinute(
                        date: hour.instant, timeZone: localZone, use24Hour: use24Hour
                    )
                    let resolved = context.resolve(
                        Text(text)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MeridianColors.onSurface.opacity(0.85))
                    )
                    let measured = resolved.measure(in: size)
                    let maxX = max(0, size.width - measured.width)
                    let x = (CGFloat(i) * segW + segW / 2 - measured.width / 2)
                        .clamped(to: 0...maxX)
                    context.draw(resolved, at: CGPoint(x: x, y: trackBottom + 4), anchor: .topLeading)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !dialPressed { dialPressed = true }
                        interactionTick += 1
                        let width: CGFloat = geo.size.width
                        let fraction: CGFloat = value.location.x / width
                        let idx = Int(fraction * CGFloat(hours.count))
                        selectAt(idx)
                    }
                    .onEnded { _ in
                        dialPressed = false
                        interactionTick += 1
                    }
            )
        }
        // The Canvas paints an interactive control that is otherwise invisible to VoiceOver.
        // Expose it as one adjustable element whose increment/decrement steps between the
        // selectable (non-filtered) hours, voicing the new time + rating on each move.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fair-time dial")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Swipe up or down to move to the next selectable hour")
        // `.accessibilityAdjustableAction` already marks the element adjustable; no
        // explicit trait is needed (there is no `.isAdjustable` AccessibilityTraits member).
        .accessibilityAdjustableAction(handleAccessibilityAdjust)
    }

    // MARK: Behavior

    private func expand() {
        withAnimation(Motion.scrubberExpandCollapse(expanding: true, reduceMotion: reduceMotion)) {
            expanded = true
        }
        interactionTick += 1
    }

    private func scheduleAutoCollapse() {
        collapseTask?.cancel()
        guard expanded, !dialPressed else { return }
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, !dialPressed else { return }
            withAnimation(Motion.scrubberExpandCollapse(expanding: false, reduceMotion: reduceMotion)) {
                expanded = false
            }
        }
    }

    /// VoiceOver adjustable handler: steps the selection to the neighbouring selectable
    /// (non-filtered) hour. Increment moves later in the day, decrement earlier — mirroring
    /// the visual left→right ordering of the bands.
    private func handleAccessibilityAdjust(_ direction: AccessibilityAdjustmentDirection) {
        if !expanded { expand() }
        let next = direction == .increment
            ? nextSelectable(after: selectedIndex)
            : previousSelectable(before: selectedIndex)
        interactionTick += 1
        guard next != selectedIndex else { return }
        selectionTick += 1
        onSelect(next)
    }

    /// Snaps the requested index to the nearest selectable (non-`nil` slot) band and notifies.
    private func selectAt(_ target: Int) {
        let next = nearestSelectable(target)
        guard next != selectedIndex else { return }
        selectionTick += 1
        onSelect(next)
    }

    private func nearestSelectable(_ target: Int) -> Int {
        let clamped = min(max(target, 0), hours.count - 1)
        if hours[clamped].slot != nil { return clamped }
        var best = -1
        var bestDist = Int.max
        for (i, hour) in hours.enumerated() where hour.slot != nil {
            let d = abs(i - clamped)
            if d < bestDist { bestDist = d; best = i }
        }
        return best >= 0 ? best : clamped
    }

    /// First selectable band strictly after `index`; returns `index` when none exists.
    private func nextSelectable(after index: Int) -> Int {
        var i = index + 1
        while i < hours.count {
            if hours[i].slot != nil { return i }
            i += 1
        }
        return index
    }

    /// First selectable band strictly before `index`; returns `index` when none exists.
    private func previousSelectable(before index: Int) -> Int {
        var i = index - 1
        while i >= 0 {
            if hours[i].slot != nil { return i }
            i -= 1
        }
        return index
    }

    private func bandColor(_ label: SlotLabel?) -> Color {
        guard let label else { return MeridianColors.onSurface.opacity(0.12) }
        return SlotCard.ratingColor(for: label)
    }
}

// MARK: - Comparable clamp

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
