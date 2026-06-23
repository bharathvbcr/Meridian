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
    var accessibilityLabel: String {
        self == .ai ? "AI Assistant tab" : "\(title) tab"
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

// MARK: - GlassTabBar (compact — floating pill at bottom)

struct GlassTabBar: View {
    @Binding var selectedTab: MeridianTab
    var isHidden: Bool = false

    @Namespace private var glassNamespace

    var body: some View {
        VStack {
            Spacer()
            pill
                .padding(.bottom, 16)
                .offset(y: isHidden ? 120 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isHidden)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var pill: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(MeridianTab.displayOrder) { tab in
                    NavBarItem(
                        tab: tab,
                        isActive: selectedTab == tab,
                        namespace: glassNamespace
                    ) { select(tab) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .liquidGlass(cornerRadius: 36, tint: MeridianColors.primary)
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 8)
    }

    private func select(_ tab: MeridianTab) {
        guard selectedTab != tab else { return }
        withAnimation(Motion.snappy()) {
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
        isActive
            ? MeridianColors.onPrimaryContainer
            : MeridianColors.onSurface.opacity(0.55)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? tab.activeIcon : tab.icon)
                    .font(.system(size: 20, weight: isActive ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(contentColor)

                if isActive {
                    Text(tab.title)
                        .font(.system(size: 14, weight: .semibold))
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
            .padding(.horizontal, isActive ? 14 : 12)
            .padding(.vertical, 10)
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
        .animation(Motion.smooth(), value: isActive)
        .sensoryFeedback(.selection, trigger: isActive) { _, now in now }
        .accessibilityLabel(tab.accessibilityLabel)
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

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                ForEach(MeridianTab.displayOrder) { tab in
                    RailItem(
                        tab: tab,
                        isActive: selectedTab == tab,
                        namespace: glassNamespace
                    ) { select(tab) }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
        }
        .liquidGlass(cornerRadius: 36, tint: MeridianColors.primary)
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 8)
        .padding(.leading, 12)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func select(_ tab: MeridianTab) {
        guard selectedTab != tab else { return }
        withAnimation(Motion.snappy()) {
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
        isActive
            ? MeridianColors.onPrimaryContainer
            : MeridianColors.onSurface.opacity(0.6)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? tab.activeIcon : tab.icon)
                .font(.system(size: 20, weight: isActive ? .semibold : .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(contentColor)
                .frame(width: 48, height: 48)
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
        .animation(Motion.smooth(), value: isActive)
        .sensoryFeedback(.selection, trigger: isActive) { _, now in now }
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Press scale style (tactile shrink, matches Android `scale 0.88` on press)

private struct NavPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(Motion.quick(), value: configuration.isPressed)
    }
}

// MARK: - Previews

#if DEBUG
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
