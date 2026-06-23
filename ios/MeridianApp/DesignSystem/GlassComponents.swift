// GlassComponents.swift
// Meridian — iOS 27  Swift 6  SwiftUI
// Shared reusable design-system components. Glass surfaces read the glass environment
// (glassEnabled / glassOpacity / reduceTransparencyOverride) via `liquidGlass`.

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SectionHeader
// ─────────────────────────────────────────────────────────────────────────────

/// A section title with an optional subtitle and a full-width divider underneath.
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)

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
                    .padding(.top, 6)
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

    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.labelMedium)
                .foregroundStyle(isSelected ? MeridianColors.background : MeridianColors.onSurfaceVariant)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
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
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
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
        .padding(16)
        .liquidGlass(cornerRadius: 16)
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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(MeridianColors.primary.opacity(0.70))

            VStack(spacing: 6) {
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
        }
        .padding(32)
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
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(color)
            }
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
        HStack(spacing: 12) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .shadow(color: accent.opacity(0.55), radius: 4)

            Text(displayName)
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.onSurface)
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(time)
                    .font(.bodyLarge)
                    .foregroundStyle(MeridianColors.onSurface)
                    .monospacedDigit()

                Text(utcOffset)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(glow.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(glow.opacity(0.18), lineWidth: 1)
                }
        }
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
