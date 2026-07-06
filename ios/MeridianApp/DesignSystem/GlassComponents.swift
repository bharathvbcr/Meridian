// GlassComponents.swift
// Meridian — iOS 27  Swift 6  SwiftUI
// Shared reusable design-system components. Glass surfaces read the glass environment
// (glassEnabled / glassOpacity / reduceTransparencyOverride) via `liquidGlass`.

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Local design tokens (private to this file)
// ─────────────────────────────────────────────────────────────────────────────

/// Minimum interactive target sizes. HIG mandates ≥44 pt so touch controls stay
/// reliably tappable; mirrors Android's 48 dp equivalent.
private enum MeridianHitTarget {
    /// Apple HIG minimum touch-target edge (points).
    static let minimum: CGFloat = 44
}

/// Shared press-feedback style for glass controls that aren't nav items.
/// Scales the label down on press with a `Motion.quick()` spring — the same
/// tactile language as the nav bar's `NavPressStyle`, but reduce-motion aware.
private struct PressableScaleStyle: ButtonStyle {
    var reduceMotion: Bool = false
    var pressedScale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1.0)
            .animation(reduceMotion ? nil : Motion.quick(), value: configuration.isPressed)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SectionHeader
// ─────────────────────────────────────────────────────────────────────────────

/// A section title with an optional subtitle and a full-width divider underneath.
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Spacer()
                    Text(subtitle)
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
            }

            if showDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)
                    .padding(.top, MeridianSpacing.xs.rawValue)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MeridianChip
// ─────────────────────────────────────────────────────────────────────────────

/// A pill-shaped toggle chip. Fires a selection haptic on every tap.
struct MeridianChip: View {
    let label: String
    var isSelected: Bool = false
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tapCount = 0

    var body: some View {
        Button {
            tapCount &+= 1
            action()
        } label: {
            Text(label)
                .font(.labelMedium)
                .foregroundStyle(isSelected ? MeridianColors.background : MeridianColors.onSurfaceVariant)
                .padding(.horizontal, MeridianSpacing.md.rawValue)
                .padding(.vertical, MeridianSpacing.sm.rawValue)
                .frame(minHeight: MeridianHitTarget.minimum)
                .background {
                    Capsule()
                        .fill(isSelected
                              ? MeridianColors.primary
                              : MeridianColors.surface.opacity(0.6))
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected
                                        ? MeridianColors.primary.opacity(0.6)
                                        : Color.white.opacity(0.14),
                                    lineWidth: 1
                                )
                        }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableScaleStyle(reduceMotion: reduceMotion))
        .sensoryFeedback(.selection, trigger: tapCount)
        .animation(reduceMotion ? nil : Motion.snappy(), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SettingsCard
// ─────────────────────────────────────────────────────────────────────────────

/// A frosted-glass card that wraps arbitrary settings content.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MeridianSpacing.lg.rawValue)
        .liquidGlass(cornerRadius: MeridianRadius.medium.rawValue)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EmptyStateView
// ─────────────────────────────────────────────────────────────────────────────

/// Centered empty-state with an SF Symbol icon, title, and descriptive message.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: MeridianSpacing.lg.rawValue) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(MeridianColors.primary.opacity(0.70))
                .accessibilityHidden(true)

            VStack(spacing: MeridianSpacing.xs.rawValue + 2) {
                Text(title)
                    .font(.headlineLarge)
                    .foregroundStyle(MeridianColors.onSurface)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.bodyLarge)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .accessibilityElement(children: .combine)

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onPrimary)
                        .padding(.horizontal, MeridianSpacing.lg.rawValue)
                        .padding(.vertical, MeridianSpacing.sm.rawValue)
                        .frame(minHeight: MeridianHitTarget.minimum)
                        .background(Capsule().fill(MeridianColors.primary))
                }
                .buttonStyle(PressableScaleStyle(reduceMotion: reduceMotion))
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(MeridianSpacing.xxl.rawValue + MeridianSpacing.sm.rawValue)
        .frame(maxWidth: 320)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PillBadge
// ─────────────────────────────────────────────────────────────────────────────

/// A small pill-shaped badge: status, count, label, etc.
struct PillBadge: View {
    let text: String
    var color: Color = MeridianColors.primary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color == MeridianColors.primary
                             ? MeridianColors.background
                             : Color.white)
            .padding(.horizontal, MeridianSpacing.sm.rawValue + 1)
            .padding(.vertical, MeridianSpacing.xs.rawValue)
            .background {
                Capsule().fill(color)
            }
            .accessibilityElement(children: .combine)
    }
}

// Expose color token as static on PillBadge for convenience
extension PillBadge {
    static var primaryColor: Color  { MeridianColors.primary }
    static var positiveColor: Color { MeridianColors.positive }
    static var nightColor: Color    { MeridianColors.nightGlow }
    static var daylightColor: Color { MeridianColors.daylightGlow }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ZoneTimeRow
// ─────────────────────────────────────────────────────────────────────────────

/// A single row showing a timezone's display name, local time, and UTC offset.
/// `isDaytime` switches the accent: the dot uses the ICON *accent* (sun/moon glyph tint),
/// while the surrounding card uses the softer *glow* hue — the day/night accent-vs-glow split.
struct ZoneTimeRow: View {
    let displayName: String
    let time: String
    let utcOffset: String
    var isDaytime: Bool = true

    /// Sun/moon glyph accent — bright, used for the indicator dot + its halo.
    private var accent: Color {
        isDaytime ? MeridianColors.daylightAccent : MeridianColors.nightAccent
    }

    /// Card glow — softer hue counterpart, used for the row fill + border.
    private var glow: Color {
        isDaytime ? MeridianColors.daylightGlow : MeridianColors.nightGlow
    }

    var body: some View {
        HStack(spacing: MeridianSpacing.md.rawValue) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .shadow(color: accent.opacity(0.55), radius: 4)
                .accessibilityHidden(true)

            Text(displayName)
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.onSurface)
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: MeridianSpacing.xs.rawValue - 2) {
                Text(time)
                    .font(.bodyLarge)
                    .foregroundStyle(MeridianColors.onSurface)
                    .monospacedDigit()

                Text(utcOffset)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
            }
        }
        .padding(.vertical, MeridianSpacing.sm.rawValue + 2)
        .padding(.horizontal, MeridianSpacing.md.rawValue + 2)
        .background {
            RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                .fill(glow.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                        .strokeBorder(glow.opacity(0.18), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName), \(time), \(utcOffset), \(isDaytime ? "daytime" : "nighttime")")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ScrollOffsetKey
// ─────────────────────────────────────────────────────────────────────────────

/// Preference key scrollable screens publish so the shell can collapse the tab bar on scroll-down.
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Scroll offset reporting
// ─────────────────────────────────────────────────────────────────────────────

private struct ScrollOffsetReporter: ViewModifier {
    let coordinateSpace: String

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: geo.frame(in: .named(coordinateSpace)).minY
                )
            }
        }
    }
}

extension View {
    /// Publishes this view's vertical offset inside `coordinateSpace` for tab-bar collapse.
    func reportScrollOffset(in coordinateSpace: String) -> some View {
        modifier(ScrollOffsetReporter(coordinateSpace: coordinateSpace))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EmptyStateCard
// ─────────────────────────────────────────────────────────────────────────────

/// Inline empty-state card with an optional call-to-action button.
struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: MeridianSpacing.sm.rawValue) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(MeridianColors.primary.opacity(0.5))
                .accessibilityHidden(true)

            VStack(spacing: MeridianSpacing.xs.rawValue) {
                Text(title)
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)

                Text(message)
                    .font(.bodyMedium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
            }
            .accessibilityElement(children: .combine)

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onPrimary)
                        .padding(.horizontal, MeridianSpacing.lg.rawValue)
                        .padding(.vertical, MeridianSpacing.sm.rawValue)
                        .frame(minHeight: MeridianHitTarget.minimum)
                        .background(Capsule().fill(MeridianColors.primary))
                }
                .buttonStyle(PressableScaleStyle(reduceMotion: reduceMotion))
                .accessibilityAddTraits(.isButton)
                .padding(.top, MeridianSpacing.xs.rawValue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(MeridianSpacing.xl.rawValue)
        .liquidGlass(cornerRadius: MeridianRadius.medium.rawValue)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Previews
// ─────────────────────────────────────────────────────────────────────────────

#if DEBUG
#Preview("SectionHeader", traits: .sizeThatFitsLayout) {
    VStack(spacing: 20) {
        SectionHeader(title: "Saved Zones", subtitle: "Edit")
        SectionHeader(title: "No Subtitle", showDivider: false)
    }
    .padding()
    .background(MeridianColors.background)
}

#Preview("MeridianChip", traits: .sizeThatFitsLayout) {
    @Previewable @State var selected = false

    HStack(spacing: 10) {
        MeridianChip(label: "12h", isSelected: selected)   { selected.toggle() }
        MeridianChip(label: "24h", isSelected: !selected)  { selected.toggle() }
        MeridianChip(label: "System")                       { }
    }
    .padding()
    .background(MeridianColors.background)
}

#Preview("SettingsCard", traits: .sizeThatFitsLayout) {
    SettingsCard {
        Toggle("Glass UI", isOn: .constant(true))
            .foregroundStyle(MeridianColors.onSurface)
    }
    .padding()
    .background(MeridianColors.background)
}

#Preview("EmptyStateView", traits: .sizeThatFitsLayout) {
    EmptyStateView(
        icon: "clock.badge.questionmark",
        title: "No Zones Yet",
        message: "Add timezones from the World screen to see them here."
    )
    .background(MeridianColors.background)
}

#Preview("PillBadge", traits: .sizeThatFitsLayout) {
    HStack(spacing: 8) {
        PillBadge(text: "On-Device")
        PillBadge(text: "Excellent", color: PillBadge.positiveColor)
        PillBadge(text: "Night",     color: PillBadge.nightColor)
    }
    .padding()
    .background(MeridianColors.background)
}

#Preview("ZoneTimeRow", traits: .sizeThatFitsLayout) {
    VStack(spacing: 8) {
        ZoneTimeRow(displayName: "San Francisco", time: "9:41 AM", utcOffset: "UTC−7", isDaytime: true)
        ZoneTimeRow(displayName: "London",        time: "5:41 PM", utcOffset: "UTC+1", isDaytime: true)
        ZoneTimeRow(displayName: "Tokyo",         time: "1:41 AM", utcOffset: "UTC+9", isDaytime: false)
    }
    .padding()
    .background(MeridianColors.background)
}
#endif
