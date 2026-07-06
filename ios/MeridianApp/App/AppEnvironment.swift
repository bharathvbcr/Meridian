// AppEnvironment.swift
// Meridian — iOS 27  Swift 6  SwiftUI
//
// Custom EnvironmentKey definitions and a convenience View modifier that injects the
// full Meridian environment in one call. Mirrors Android's `CompositionLocalProvider`
// block in `MainAppHost` (LocalGlassEnabled / LocalGlassOpacity / LocalReduceTransparency
// / LocalContentColor), plus a deep-link tab router so screens can navigate programmatically.

import SwiftUI

// MARK: - glassEnabled

private struct GlassEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var glassEnabled: Bool {
        get { self[GlassEnabledKey.self] }
        set { self[GlassEnabledKey.self] = newValue }
    }
}

// MARK: - glassOpacity

private struct GlassOpacityKey: EnvironmentKey {
    static let defaultValue: Double = 0.6
}

extension EnvironmentValues {
    var glassOpacity: Double {
        get { self[GlassOpacityKey.self] }
        set { self[GlassOpacityKey.self] = newValue }
    }
}

// MARK: - reduceTransparencyOverride

private struct ReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var reduceTransparencyOverride: Bool {
        get { self[ReduceTransparencyOverrideKey.self] }
        set { self[ReduceTransparencyOverrideKey.self] = newValue }
    }
}

// MARK: - mainViewModel

private struct MainViewModelKey: EnvironmentKey {
    static let defaultValue: MainViewModel? = nil
}

extension EnvironmentValues {
    var mainViewModel: MainViewModel? {
        get { self[MainViewModelKey.self] }
        set { self[MainViewModelKey.self] = newValue }
    }
}

// MARK: - selectTab (programmatic navigation)

/// A closure screens can call to switch the active tab (e.g. AI → Plan after confirming a draft),
/// sharing the shell's single tab-selection state. Defaults to a no-op so screens used outside the
/// shell (previews) still compile and run.
private struct SelectTabKey: EnvironmentKey {
    static let defaultValue: @MainActor (MeridianTab) -> Void = { _ in }
}

private struct WorldCityPickerRequestKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

private struct TabBarInsetHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 96
}

extension EnvironmentValues {
    var selectTab: @MainActor (MeridianTab) -> Void {
        get { self[SelectTabKey.self] }
        set { self[SelectTabKey.self] = newValue }
    }

    /// When set to `true`, `WorldClockScreen` opens the city picker then clears the flag.
    var worldCityPickerRequest: Binding<Bool> {
        get { self[WorldCityPickerRequestKey.self] }
        set { self[WorldCityPickerRequestKey.self] = newValue }
    }

    /// Reserved height for the floating tab bar (72 collapsed, 96 expanded). Scrubbers use this
    /// so they stay above the pill when it minimizes on scroll.
    var tabBarInsetHeight: CGFloat {
        get { self[TabBarInsetHeightKey.self] }
        set { self[TabBarInsetHeightKey.self] = newValue }
    }
}

// MARK: - Convenience modifier

extension View {
    /// Injects the complete Meridian environment in a single call.
    ///
    /// - Parameters:
    ///   - viewModel: The root ``MainViewModel`` shared across all screens.
    ///   - settings:  The current ``MeridianSettings`` snapshot from ``SettingsRepository``.
    ///   - selectTab: Optional tab-router so screens can navigate programmatically. Defaults to a
    ///     no-op when omitted.
    func meridianEnvironment(
        viewModel: MainViewModel,
        settings: MeridianSettings,
        selectTab: @escaping @MainActor (MeridianTab) -> Void = { _ in }
    ) -> some View {
        self
            .environment(\.mainViewModel, viewModel)
            .environment(\.selectTab, selectTab)
            .environment(\.glassEnabled, settings.glassEnabled)
            .environment(\.glassOpacity, settings.glassOpacity)
            .environment(\.reduceTransparencyOverride, settings.reduceTransparency)
    }
}
