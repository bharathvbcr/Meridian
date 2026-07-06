// PermissionsCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Unified permissions panel: notifications, calendar, contacts, and location, each with a
// normalized status pill and a contextual action (request inline when undetermined, or open
// the system Settings app when denied). Behavioral port of Android `PermissionsCard`, driven
// by the shared `PermissionsManager` (which owns the actual EventKit / Contacts / Location /
// UNUserNotificationCenter requests). Re-polls on appear and when the app returns to the
// foreground, mirroring Android's `LifecycleResumeEffect` refresh.

import SwiftUI

// MARK: - Local design tokens
//
// Wherever a shared `MeridianColors` / `MeridianSpacing` / typography token already exists we
// use it directly so Settings stays in visual parity with Now and World Clock. Only two status
// hues are declared privately here: `settingsWarning` mirrors the day-glow token (#FFB703) and
// `settingsError` (#F87171) has no shared counterpart yet (`MeridianColors.error` is a softer
// M3 tone). Both clear WCAG-AA contrast on the #0F172A surface card. When these graduate into
// the shared palette this file should switch to those tokens for cross-platform parity.

private enum PermissionsPalette {
    /// Warm warning tone — the same hue as `MeridianColors.daylightGlow` (#FFB703).
    static let warning = MeridianColors.daylightGlow
    /// Denied / error tone. No shared equivalent yet; keep local until promoted.
    static let error = Color(hex: "F87171")
}

/// Minimum comfortable touch target (mirrors `MeridianHitTarget.minimum`, which is
/// file-private to the design system).
private let permissionsMinHitTarget: CGFloat = 44

// MARK: - Press feedback

/// Reduce-motion-aware press scale, matching the design system's `PressableScaleStyle`
/// / `NavPressStyle` tactile language (scale-down on `Motion.quick()`).
private struct PermissionPressStyle: ButtonStyle {
    var reduceMotion: Bool = false
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(reduceMotion ? nil : Motion.quick(), value: configuration.isPressed)
    }
}

// MARK: - PermissionsCard

struct PermissionsCard: View {
    @State private var permissions = PermissionsManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SettingsCard {
            HStack(spacing: MeridianSpacing.sm.rawValue) {
                Image(systemName: "lock.shield")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.primary)
                    .accessibilityHidden(true)
                Text("App permissions")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text("Meridian only asks for access when a feature needs it. Grant permissions here or in the system Settings app.")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, MeridianSpacing.sm.rawValue)
                .padding(.bottom, MeridianSpacing.md.rawValue)

            VStack(spacing: 0) {
                PermissionStatusRow(
                    icon: "location",
                    title: "Location",
                    description: "Resolve your home time zone from your current position.",
                    state: permissions.snapshot.location
                ) {
                    await permissions.requestLocation()
                }

                divider

                PermissionStatusRow(
                    icon: "bell.badge",
                    title: "Notifications",
                    description: "Post reminders before planned events.",
                    state: permissions.snapshot.notifications
                ) {
                    await permissions.requestNotifications()
                }

                divider

                PermissionStatusRow(
                    icon: "calendar",
                    title: "Calendar",
                    description: "Show your device calendar on the planner.",
                    state: permissions.snapshot.calendar
                ) {
                    await permissions.requestCalendar()
                }

                divider

                PermissionStatusRow(
                    icon: "person.crop.circle",
                    title: "Contacts",
                    description: "Import people into the planner from your address book.",
                    state: permissions.snapshot.contacts
                ) {
                    await permissions.requestContacts()
                }
            }
        }
        .task { await permissions.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await permissions.refresh() }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, MeridianSpacing.md.rawValue)
            .accessibilityHidden(true)
    }
}

// MARK: - PermissionStatusRow

/// One permission line: icon, title, status label, description, and a contextual action
/// row shown only when the permission is not yet usable.
struct PermissionStatusRow: View {
    let icon: String
    let title: String
    let description: String
    let state: PermissionState
    /// Inline request action (no-op when the only path forward is system Settings).
    let request: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRequesting = false
    /// Drives a per-tap haptic. Bumped on every action-button press; the paired
    /// `pendingHaptic` records which feedback to play for that tap.
    @State private var hapticTick = 0
    @State private var pendingHaptic: SensoryFeedback = .selection

    var body: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
            HStack(alignment: .top, spacing: MeridianSpacing.sm.rawValue) {
                Image(systemName: icon)
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .frame(width: 20)
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue / 2) {
                    HStack(spacing: MeridianSpacing.sm.rawValue) {
                        Text(title)
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.onSurface)
                        Spacer(minLength: MeridianSpacing.sm.rawValue)
                        statusBadge
                    }
                    Text(description)
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Read the whole header as one element: "Location, Not granted, Resolve your…"
            .accessibilityElement(children: .combine)
            .accessibilityValue(statusLabel)

            if !state.isUsable {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    if state == .notDetermined {
                        actionButton(title: "Allow \(title)", filled: true) {
                            fireHaptic(.impact(weight: .medium))
                            guard !isRequesting else { return }
                            isRequesting = true
                            Task {
                                await request()
                                isRequesting = false
                            }
                        }
                    }
                    actionButton(title: "System settings", filled: false) {
                        fireHaptic(.selection)
                        SettingsActions.openAppSettings()
                    }
                }
                .padding(.leading, 28)
                // Springy reveal/hide of the action row as state resolves.
                .transition(.opacity)
            }
        }
        .padding(.vertical, MeridianSpacing.xs.rawValue)
        .animation(Motion.reduced(Motion.snappy(), reduceMotion: reduceMotion), value: state.isUsable)
        .animation(Motion.reduced(Motion.quick(), reduceMotion: reduceMotion), value: isRequesting)
        // One place to play a queued action-button haptic.
        .sensoryFeedback(trigger: hapticTick) { _, _ in
            hapticTick == 0 ? nil : pendingHaptic
        }
    }

    /// Queues `feedback` to play on the next render via the shared `hapticTick` trigger.
    private func fireHaptic(_ feedback: SensoryFeedback) {
        pendingHaptic = feedback
        hapticTick &+= 1
    }

    // MARK: Status badge

    /// Leading status glyph + label so grant state is legible at a glance without relying on
    /// color alone (WCAG 1.4.1). The icon is decorative — VoiceOver reads `statusLabel` via the
    /// combined header's `.accessibilityValue`.
    private var statusBadge: some View {
        HStack(spacing: MeridianSpacing.xs.rawValue) {
            Image(systemName: statusSymbol)
                .font(.labelMedium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
            Text(statusLabel)
                .font(.labelMedium)
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    // MARK: Status mapping

    private var statusLabel: String {
        switch state {
        case .granted:       return "Granted"
        case .limited:       return "Limited"
        case .denied:        return "Not granted"
        case .notDetermined: return "Not set"
        }
    }

    private var statusSymbol: String {
        switch state {
        case .granted:       return "checkmark.circle.fill"
        case .limited:       return "exclamationmark.circle.fill"
        case .denied:        return "xmark.circle.fill"
        case .notDetermined: return "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch state {
        case .granted:       return MeridianColors.positive
        case .limited:       return PermissionsPalette.warning
        case .denied:        return PermissionsPalette.error
        case .notDetermined: return MeridianColors.onSurfaceVariant
        }
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        // Only the filled "Allow" button ever drives the async prompt, so an in-flight spinner
        // is scoped to it.
        let showsSpinner = filled && isRequesting
        Button(action: action) {
            ZStack {
                Text(title)
                    .opacity(showsSpinner ? 0 : 1)
                if showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .tint(MeridianColors.onPrimary)
                }
            }
            .font(.labelMedium)
            .foregroundStyle(filled ? MeridianColors.onPrimary : MeridianColors.primary)
            .padding(.horizontal, MeridianSpacing.md.rawValue + 2)
            .frame(maxWidth: .infinity)
            .frame(minHeight: permissionsMinHitTarget)
            .background {
                if filled {
                    Capsule().fill(MeridianColors.primary)
                } else {
                    Capsule().strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PermissionPressStyle(reduceMotion: reduceMotion))
        .disabled(showsSpinner)
        .accessibilityLabel(showsSpinner ? "\(title), requesting" : title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(filled
            ? "Requests \(title.replacingOccurrences(of: "Allow ", with: "")) access."
            : "Opens Meridian's page in the system Settings app.")
    }
}
