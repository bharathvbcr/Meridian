// GlassNavBar.swift
// Meridian — iOS 27  Swift 6  SwiftUI
// Floating glass bottom tab bar (compact) and floating side rail (regular/iPad).
//
// Ported from Android's GlassNavBar.kt / GlassNavRail.kt:
//   • AI is the prominent CENTER slot (sparkles launcher).
//   • Active tab shows an expanding label pill; inactive tabs are icon-only.
//   • The rail floats (rounded, centered) — no "M" wordmark.
//   • iOS 27: native `.glassEffect` + `GlassEffectContainer` with `glassEffectID` morphing,
//     no `#available(iOS 26)` branches.
//   • `.sensoryFeedback(.selection)` replaces UIImpactFeedbackGenerator.

import SwiftUI

// MARK: - MeridianTab

enum MeridianTab: String, CaseIterable, Identifiable {
    case now
    case world
    case ai
    case plan
    case settings

    var id: String { rawValue }

    /// Ordered for display: Now · World · AI(center) · Plan · Settings.
    /// AI sits in the middle slot for center prominence (matches Android).
    static let displayOrder: [MeridianTab] = [.now, .world, .ai, .plan, .settings]

    var title: String {
        switch self {
        case .now:      return "Now"
        case .world:    return "World"
        case .ai:       return "AI"
        case .plan:     return "Plan"
        case .settings: return "Settings"
        }
    }

    /// Accessibility label for the tab control.
    ///
    /// Retained for backward compatibility with any external caller. Prefer the
    /// role-free `title` for the VoiceOver *label* on nav items (the `.isButton`
    /// / `.isSelected` traits already convey the control's role, so appending the
    /// word "tab" produces a redundant "Now tab, button" announcement).
    var accessibilityLabel: String {
        self == .ai ? "AI Assistant tab" : "\(title) tab"
    }

    /// VoiceOver label for a nav item — role-free so the button/selected trait is
    /// not spoken twice. AI keeps its fuller name since "AI" alone is terse.
    var navAccessibilityLabel: String {
        self == .ai ? "AI Assistant" : title
    }

    /// VoiceOver hint announced after the label: explains that activating the
    /// primary-navigation control switches screens.
    var navAccessibilityHint: String {
        "Switches to the \(self == .ai ? "AI Assistant" : title) screen"
    }

    /// Outline (inactive) SF Symbol name.
    var icon: String {
        switch self {
        case .now:      return "sun.max"
        case .world:    return "globe"
        case .ai:       return "sparkles"
        case .plan:     return "calendar"
        case .settings: return "gearshape"
        }
    }

    /// Filled (active) SF Symbol name.
    var activeIcon: String {
        switch self {
        case .now:      return "sun.max.fill"
        case .world:    return "globe.americas.fill"
        case .ai:       return "sparkles"          // sparkles has no distinct fill variant
        case .plan:     return "calendar.badge.clock"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Shared nav metrics

/// Sizing constants shared by the two bottom-bar item variants (`CompactNavItem`
/// and `NavBarItem`) so they render the same tab-bar concept identically. Values
/// are expressed against the design scale (spacing tokens, 44 pt touch target).
private enum NavMetrics {
    /// Bottom-bar icon point size. `CompactNavItem` (18) and `NavBarItem` (20)
    /// previously diverged; unify on 20 so the active/inactive weight step reads
    /// the same across both shells.
    static let iconSize: CGFloat = 20
    /// Center-slot / rail icon glyph size.
    static let prominentIconSize: CGFloat = 20
    /// Gap between icon and expanded label.
    static let iconLabelGap = MeridianSpacing.xs.rawValue + 2   // 6
    /// Horizontal padding when the label pill is expanded.
    static let activeHPadding = MeridianSpacing.md.rawValue + 2  // 14
    /// Horizontal padding when icon-only.
    static let inactiveHPadding = MeridianSpacing.md.rawValue    // 12
    /// Vertical padding for the item content.
    static let vPadding = MeridianSpacing.sm.rawValue + 2        // 10
    /// Minimum square touch target (Apple HIG ≥ 44 pt).
    static let minTouchTarget: CGFloat = 44
    /// Fixed square for the circular center/rail slots.
    static let prominentSlot: CGFloat = 48
    /// Weight step: inactive icons are regular, active icons semibold.
    static func iconWeight(active: Bool) -> Font.Weight { active ? .semibold : .regular }
}

// MARK: - GlassCompactNavBar (iPhone shell — minimize-on-scroll)

/// Floating glass pill used by `ContentView` on iPhone. Mirrors Android `GlassNavBar`:
/// active tabs expand to show a label; `collapsed` hides labels while scrolling down.
struct GlassCompactNavBar: View {
    @Binding var selectedTab: MeridianTab
    var collapsed: Bool = false

    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: MeridianSpacing.xs.rawValue) {
            HStack(spacing: MeridianSpacing.xs.rawValue) {
                ForEach(MeridianTab.displayOrder) { tab in
                    if tab == .ai {
                        AiNavButton(isActive: selectedTab == .ai, action: { select(.ai) })
                    } else {
                        CompactNavItem(
                            tab: tab,
                            isActive: selectedTab == tab,
                            showLabel: !collapsed,
                            namespace: glassNamespace,
                            action: { select(tab) }
                        )
                    }
                }
            }
            .padding(.horizontal, collapsed ? MeridianSpacing.sm.rawValue : MeridianSpacing.md.rawValue)
            .padding(.vertical, MeridianSpacing.sm.rawValue)
        }
        .glassEffect(.regular, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .meridianAnimation(Motion.snappy(), value: collapsed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }

    private func select(_ tab: MeridianTab) {
        guard selectedTab != tab else { return }
        withAnimation(Motion.reduced(Motion.snappy(), reduceMotion: reduceMotion)) {
            selectedTab = tab
        }
    }
}

// MARK: - CompactNavItem

private struct CompactNavItem: View {
    let tab: MeridianTab
    let isActive: Bool
    let showLabel: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NavMetrics.iconLabelGap) {
                Image(systemName: isActive ? tab.activeIcon : tab.icon)
                    .font(.system(size: NavMetrics.iconSize, weight: NavMetrics.iconWeight(active: isActive)))
                    .symbolRenderingMode(.hierarchical)

                if isActive && showLabel {
                    Text(tab.title)
                        .font(.labelMedium)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(
                isActive ? MeridianColors.onPrimaryContainer : MeridianColors.onSurfaceVariant
            )
            .padding(.horizontal, isActive && showLabel ? NavMetrics.activeHPadding : NavMetrics.inactiveHPadding)
            .padding(.vertical, NavMetrics.vPadding)
            .frame(minWidth: NavMetrics.minTouchTarget, minHeight: NavMetrics.minTouchTarget)
            .background {
                if isActive {
                    Capsule()
                        .fill(MeridianColors.primaryContainer)
                        .matchedGeometryEffect(id: "compact-nav-active", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(NavPressStyle())
        .sensoryFeedback(.selection, trigger: isActive) { _, now in now }
        .accessibilityLabel(tab.navAccessibilityLabel)
        .accessibilityHint(tab.navAccessibilityHint)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .meridianAnimation(Motion.smooth(), value: isActive)
        .meridianAnimation(Motion.smooth(), value: showLabel)
    }
}

// MARK: - AiNavButton (center-prominent launcher)

private struct AiNavButton: View {
    let isActive: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Suppress the emphasis-grow when Reduce Motion is on — the pulse is the
    /// motion-sensitive part; the fill/tint change alone still signals selection.
    private var activeScale: CGFloat {
        isActive && !reduceMotion ? 1.06 : 1.0
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: NavMetrics.prominentIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? MeridianColors.onPrimary : MeridianColors.primary)
                .frame(width: NavMetrics.prominentSlot, height: NavMetrics.prominentSlot)
                .background {
                    Circle()
                        .fill(isActive ? MeridianColors.primary : MeridianColors.primary.opacity(0.16))
                }
                .overlay {
                    Circle().strokeBorder(MeridianColors.primary.opacity(0.5), lineWidth: 1)
                }
                .scaleEffect(activeScale)
                .contentShape(Circle())
        }
        .buttonStyle(NavPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isActive) { _, now in now }
        .accessibilityLabel(MeridianTab.ai.navAccessibilityLabel)
        .accessibilityHint(MeridianTab.ai.navAccessibilityHint)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .meridianAnimation(Motion.bouncy(), value: isActive)
    }
}

// MARK: - GlassTabBar (compact — floating pill at bottom)

struct GlassTabBar: View {
    @Binding var selectedTab: MeridianTab
    var isHidden: Bool = false

    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            pill
                .padding(.bottom, MeridianSpacing.lg.rawValue)
                .offset(y: isHidden ? 120 : 0)
                // Reduce Motion: the tuck-away slide becomes a plain hide/show.
                .meridianAnimation(Motion.bouncy(), value: isHidden)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var pill: some View {
        GlassEffectContainer(spacing: MeridianSpacing.xs.rawValue) {
            HStack(spacing: MeridianSpacing.xs.rawValue) {
                ForEach(MeridianTab.displayOrder) { tab in
                    NavBarItem(
                        tab: tab,
                        isActive: selectedTab == tab,
                        namespace: glassNamespace
                    ) { select(tab) }
                }
            }
            .padding(.horizontal, MeridianSpacing.sm.rawValue)
            .padding(.vertical, NavMetrics.vPadding)
        }
        .liquidGlass(cornerRadius: MeridianRadius.extraLarge.rawValue, tint: MeridianColors.primary)
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }

    private func select(_ tab: MeridianTab) {
        guard selectedTab != tab else { return }
        withAnimation(Motion.reduced(Motion.snappy(), reduceMotion: reduceMotion)) {
            selectedTab = tab
        }
    }
}

// MARK: - NavBarItem (compact)

/// A single bottom-bar item. Active tabs expand to show a label pill backed by the primary
/// container; inactive tabs are icon-only. AI keeps the same shape but is the center slot.
private struct NavBarItem: View {
    let tab: MeridianTab
    let isActive: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    private var contentColor: Color {
        // Inactive tabs use the solid `onSurfaceVariant` (#94A3B8) rather than a
        // low-alpha `onSurface`, which over the frosted primary-tinted glass and
        // busy celestial backdrop could drop below WCAG-AA (4.5:1) for the small
        // labels. The solid token keeps inactive tabs legible.
        isActive
            ? MeridianColors.onPrimaryContainer
            : MeridianColors.onSurfaceVariant
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: NavMetrics.iconLabelGap) {
                Image(systemName: isActive ? tab.activeIcon : tab.icon)
                    .font(.system(size: NavMetrics.iconSize, weight: NavMetrics.iconWeight(active: isActive)))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(contentColor)

                if isActive {
                    Text(tab.title)
                        .font(.labelMedium)
                        .foregroundStyle(contentColor)
                        .fixedSize()
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.6, anchor: .leading)),
                                removal: .opacity.combined(with: .scale(scale: 0.6, anchor: .leading))
                            )
                        )
                }
            }
            .padding(.horizontal, isActive ? NavMetrics.activeHPadding : NavMetrics.inactiveHPadding)
            .padding(.vertical, NavMetrics.vPadding)
            .frame(minWidth: NavMetrics.minTouchTarget, minHeight: NavMetrics.minTouchTarget)
            .background {
                if isActive {
                    Capsule()
                        .fill(MeridianColors.primaryContainer)
                        .matchedGeometryEffect(id: "nav-active-pill", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(NavPressStyle())
        .meridianAnimation(Motion.smooth(), value: isActive)
        .sensoryFeedback(.selection, trigger: isActive) { _, now in now }
        .accessibilityLabel(tab.navAccessibilityLabel)
        .accessibilityHint(tab.navAccessibilityHint)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - GlassNavRail (regular — floating side rail)

/// Floating vertical glass rail. Same destinations and glass language as the bottom bar,
/// with AI as the prominent center slot. No "M" wordmark (dropped per spec); the rail is
/// centered vertically and floats with rounded corners.
struct GlassNavRail: View {
    @Binding var selectedTab: MeridianTab

    @Namespace private var glassNamespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: MeridianSpacing.md.rawValue) {
            VStack(spacing: MeridianSpacing.md.rawValue) {
                ForEach(MeridianTab.displayOrder) { tab in
                    RailItem(
                        tab: tab,
                        isActive: selectedTab == tab,
                        namespace: glassNamespace
                    ) { select(tab) }
                }
            }
            .padding(.vertical, MeridianSpacing.lg.rawValue)
            .padding(.horizontal, MeridianSpacing.md.rawValue)
        }
        .liquidGlass(cornerRadius: MeridianRadius.extraLarge.rawValue, tint: MeridianColors.primary)
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 8)
        .padding(.leading, MeridianSpacing.md.rawValue)
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }

    private func select(_ tab: MeridianTab) {
        guard selectedTab != tab else { return }
        withAnimation(Motion.reduced(Motion.snappy(), reduceMotion: reduceMotion)) {
            selectedTab = tab
        }
    }
}

// MARK: - RailItem

private struct RailItem: View {
    let tab: MeridianTab
    let isActive: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    private var contentColor: Color {
        // Inactive icons use the solid `onSurfaceVariant` (#94A3B8) instead of a
        // low-alpha `onSurface`, keeping them above WCAG-AA contrast over the
        // translucent glass rail and celestial backdrop.
        isActive
            ? MeridianColors.onPrimaryContainer
            : MeridianColors.onSurfaceVariant
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? tab.activeIcon : tab.icon)
                .font(.system(size: NavMetrics.prominentIconSize, weight: NavMetrics.iconWeight(active: isActive)))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(contentColor)
                .frame(width: NavMetrics.prominentSlot, height: NavMetrics.prominentSlot)
                .background {
                    if isActive {
                        Circle()
                            .fill(MeridianColors.primaryContainer)
                            .matchedGeometryEffect(id: "rail-active-pill", in: namespace)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(NavPressStyle())
        .meridianAnimation(Motion.smooth(), value: isActive)
        .sensoryFeedback(.selection, trigger: isActive) { _, now in now }
        .accessibilityLabel(tab.navAccessibilityLabel)
        .accessibilityHint(tab.navAccessibilityHint)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Press scale style (tactile shrink, matches Android `scale 0.88` on press)

private struct NavPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        // Skip the tactile shrink entirely under Reduce Motion; the selection
        // haptic still confirms the press for those users.
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.88 : 1.0))
            .animation(Motion.reduced(Motion.quick(), reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Compact Nav Bar — collapsed", traits: .sizeThatFitsLayout) {
    @Previewable @State var tab: MeridianTab = .now

    GlassCompactNavBar(selectedTab: $tab, collapsed: true)
        .padding()
        .background(MeridianColors.background)
        .preferredColorScheme(.dark)
}

#Preview("Tab Bar — compact", traits: .sizeThatFitsLayout) {
    @Previewable @State var tab: MeridianTab = .now

    ZStack(alignment: .bottom) {
        MeridianColors.background.ignoresSafeArea()
        GlassTabBar(selectedTab: $tab, isHidden: false)
    }
    .preferredColorScheme(.dark)
}

#Preview("Nav Rail — iPad") {
    @Previewable @State var tab: MeridianTab = .world

    HStack(spacing: 0) {
        GlassNavRail(selectedTab: $tab)
        MeridianColors.background
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}
#endif
