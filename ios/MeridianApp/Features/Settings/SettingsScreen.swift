// SettingsScreen.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// The full settings surface. Behavioral port of Android `SettingsScreen.kt`, organized into
// the same logical sections:
//
//   • Home          — home city (location resolve + manual pick) and home-country anchor.
//   • Permissions   — notifications / calendar / contacts / location (PermissionsCard).
//   • Appearance    — clock format, Liquid Glass toggle + opacity (now WORKS), reduce
//                     transparency, celestial backdrop + intensity, world-map style (Vector
//                     default), all bound to MainViewModel settings delegates.
//   • AI engine     — On-Device / Cloud selector (AiEngineCard).
//   • Reminders     — lead-time + default work hours (RemindersCard).
//   • Database      — local data management (DataManagementCard).
//   • About & Legal — about card, legal notices (LegalNoticeSheet), support links, and the
//                     previously-dead Auto-sync toggle, now wired to a real persisted flag.
//
// State is read from the shared `MainViewModel` injected via `\.mainViewModel`; every mutation
// goes through the view-model's settings delegates so persistence + glass live-updates work.

import SwiftUI
import UIKit

// MARK: - SettingsSection

/// The eight logical settings groups. Port of Android's `SettingsSection` enum:
/// each drives a quick-nav chip, a collapsible header card, and a collapsed summary.
private enum SettingsSection: String, CaseIterable, Identifiable {
    case home, permissions, appearance, ai, reminders, workHours, database, about

    var id: String { rawValue }

    var pillLabel: String {
        switch self {
        case .home: "Home"
        case .permissions: "Permissions"
        case .appearance: "Appearance"
        case .ai: "AI engine"
        case .reminders: "Reminders"
        case .workHours: "Work hours"
        case .database: "Database"
        case .about: "About"
        }
    }

    var headerLabel: String {
        switch self {
        case .home: "HOME LOCATION"
        case .permissions: "PERMISSIONS"
        case .appearance: "APPEARANCE & CLOCK"
        case .ai: "ON-DEVICE AI ENGINE"
        case .reminders: "EVENT REMINDERS"
        case .workHours: "DEFAULT WORK HOUR WINDOW"
        case .database: "DATABASE & STORAGE"
        case .about: "ABOUT & LEGAL"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .permissions: "lock.shield"
        case .appearance: "paintpalette"
        case .ai: "memorychip"
        case .reminders: "bell.badge"
        case .workHours: "briefcase"
        case .database: "externaldrive"
        case .about: "building.columns"
        }
    }
}

// MARK: - SettingsScreen

struct SettingsScreen: View {

    @Environment(\.mainViewModel) private var injectedViewModel

    var body: some View {
        if let viewModel = injectedViewModel {
            SettingsContent(viewModel: viewModel)
        } else {
            // The root always injects the view-model; this guards previews / misuse.
            ContentUnavailableView(
                "Settings unavailable",
                systemImage: "gearshape",
                description: Text("The app model is not available.")
            )
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - SettingsContent

private struct SettingsContent: View {
    @Bindable var viewModel: MainViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Home city picker sheets.
    @State private var showHomeCityPicker = false
    @State private var showHomeCountryPicker = false

    // Location resolution state.
    @State private var locationStatus: String?
    @State private var resolving = false

    // Auto-sync interop (Settings-local persisted flag).
    @State private var autoSync = CalendarAutoSync.isEnabled

    // Active legal document sheet.
    @State private var activeLegalDocument: LegalDocument?

    // Section navigation (Android: focusedSection / expandedSections).
    @State private var focusedSection: SettingsSection?
    @State private var expandedSections: Set<SettingsSection> = []

    // Transient "Diagnostics copied" state (Android: AboutCard `copied`).
    @State private var diagnosticsCopied = false
    @State private var quickNavTap = 0
    @State private var scrollTarget: SettingsSection?

    private var settings: MeridianSettings { viewModel.settings }

    private var visibleSections: [SettingsSection] {
        focusedSection.map { [$0] } ?? SettingsSection.allCases
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MeridianColors.background.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            Color.clear
                                .frame(height: 0)
                                .reportScrollOffset(in: "settingsScroll")

                            Text("Configure Meridian's engine, surfaces, and integrations.")
                                .font(.bodyMedium)
                                .foregroundStyle(MeridianColors.onSurfaceVariant)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            CompanionAppCard()

                            quickNav

                            ForEach(visibleSections) { section in
                                collapsibleSection(section)
                                    .id(section.id)
                            }

                            footer
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                    }
                    .coordinateSpace(name: "settingsScroll")
                    .onChange(of: focusedSection) { _, section in
                        guard let section else { return }
                        withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) {
                            proxy.scrollTo(section.id, anchor: .top)
                        }
                    }
                    .onChange(of: scrollTarget) { _, section in
                        guard let section else { return }
                        withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) {
                            proxy.scrollTo(section.id, anchor: .top)
                        }
                        scrollTarget = nil
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(MeridianColors.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showHomeCityPicker) {
            HomeCitySearchSheet(title: "Choose your home city", viewModel: viewModel) { match in
                viewModel.setHomeZone(id: match.zoneId, displayName: match.displayName)
                announceStatus("Home set to \(match.displayName)")
            }
        }
        .sheet(isPresented: $showHomeCountryPicker) {
            HomeCitySearchSheet(title: "Choose your home-country city", viewModel: viewModel) { match in
                viewModel.setAnchorZone(id: match.zoneId, displayName: match.displayName, role: .homeCountry)
            }
        }
        .sheet(item: $activeLegalDocument) { document in
            LegalNoticeSheet(document: document) { activeLegalDocument = nil }
        }
    }

    // MARK: - Quick nav (Android: SettingsQuickNav)

    private var quickNav: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
            Text("Quick actions")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    if focusedSection != nil {
                        MeridianChip(label: "All", isSelected: false) {
                            select(nil)
                        }
                    }
                    ForEach(visibleSections) { section in
                        MeridianChip(label: section.pillLabel, isSelected: focusedSection == section) {
                            select(focusedSection == section ? nil : section)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.selection, trigger: quickNavTap)
    }

    private func select(_ section: SettingsSection?) {
        quickNavTap &+= 1
        withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) {
            focusedSection = section
            expandedSections = section.map { [$0] } ?? []
        }
    }

    // MARK: - Collapsible sections (Android: CollapsibleSettingsSection)

    @ViewBuilder
    private func collapsibleSection(_ section: SettingsSection) -> some View {
        let isExpanded = focusedSection != nil || expandedSections.contains(section)

        VStack(spacing: MeridianSpacing.md.rawValue) {
            if focusedSection == nil {
                Button {
                    withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) {
                        if expandedSections.contains(section) {
                            expandedSections.remove(section)
                        } else {
                            expandedSections.insert(section)
                            scrollTarget = section
                        }
                    }
                } label: {
                    sectionHeaderCard(section, expanded: isExpanded)
                }
                .buttonStyle(SettingsPressableStyle(reduceMotion: reduceMotion))
                .sensoryFeedback(.impact(weight: .medium), trigger: expandedSections.contains(section))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Double-tap to collapse" : "Double-tap to expand")
            } else {
                // Focused mode: a plain labeled divider header instead of the toggle card.
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    Text(section.headerLabel)
                        .font(.labelMedium)
                        .kerning(1.1)
                        .foregroundStyle(MeridianColors.primary)
                    Rectangle()
                        .fill(MeridianColors.primary.opacity(0.15))
                        .frame(height: 1)
                }
                .padding(.top, MeridianSpacing.xs.rawValue)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }

            if isExpanded {
                sectionContent(section)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
    }

    private func sectionHeaderCard(_ section: SettingsSection, expanded: Bool) -> some View {
        SettingsCard {
            HStack(spacing: MeridianSpacing.md.rawValue) {
                Image(systemName: section.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.pillLabel)
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                    if !expanded {
                        Text(sectionSummary(section))
                            .font(.labelMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                            .transition(.opacity)
                    }
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
    }

    /// One-line collapsed summary per section (Android: settingsSectionSummary).
    private func sectionSummary(_ section: SettingsSection) -> String {
        switch section {
        case .home:
            return viewModel.homeZone?.displayName ?? "Home not set"
        case .permissions:
            return "Location, notifications, calendar, contacts"
        case .appearance:
            let map = "\(settings.mapStyle.rawValue) map"
            switch settings.hourCycle {
            case .twelve: return "12-hour · \(map)"
            case .twentyFour: return "24-hour · \(map)"
            case .system: return "System format · \(map)"
            }
        case .ai:
            return settings.aiEngine == .cloud
                ? "Cloud Gemini · opt-in"
                : "Apple Intelligence · on-device first"
        case .reminders:
            return settings.reminderLeadMinutes < 0
                ? "Reminders disabled"
                : "\(settings.reminderLeadMinutes) min before events"
        case .workHours:
            return String(format: "%02d:00 – %02d:00", settings.defaultWorkStartHour, settings.defaultWorkEndHour)
        case .database:
            return "Pinned zones & local storage"
        case .about:
            return "Privacy · support · v\(AppInfo.versionLabel)"
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: SettingsSection) -> some View {
        switch section {
        case .home:
            homeSection
        case .permissions:
            PermissionsCard()
        case .appearance:
            appearanceSection
        case .ai:
            AiEngineCard(viewModel: viewModel)
        case .reminders:
            RemindersCard(viewModel: viewModel, part: .reminders)
        case .workHours:
            RemindersCard(viewModel: viewModel, part: .workHours)
        case .database:
            VStack(spacing: 16) {
                ReseedCard(viewModel: viewModel)
                DataManagementCard()
            }
        case .about:
            aboutSection
        }
    }

    // MARK: - Home section

    private var homeSection: some View {
        VStack(spacing: 16) {
            SettingsCard {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    Image(systemName: "house")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MeridianColors.primary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.homeZone.map { "Home · \($0.displayName)" } ?? "No home set")
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.onSurface)
                        Text("Your usual base for the Now card and planning. Resolved on-device — never sent anywhere.")
                            .font(.labelMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                    }
                }
                .padding(.bottom, MeridianSpacing.md.rawValue)
                .accessibilityElement(children: .combine)

                Button {
                    Task { await resolveHomeFromLocation() }
                } label: {
                    HStack(spacing: MeridianSpacing.sm.rawValue) {
                        if resolving {
                            ProgressView().controlSize(.small).tint(MeridianColors.background)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text(resolving ? "Locating…" : "Use my location")
                    }
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MeridianSpacing.md.rawValue)
                    .frame(minHeight: kSettingsHitTarget)
                    .background(Capsule().fill(MeridianColors.primary))
                    .contentShape(Capsule())
                }
                .buttonStyle(SettingsPressableStyle(reduceMotion: reduceMotion))
                .disabled(resolving)
                .sensoryFeedback(.impact(weight: .light), trigger: resolving)
                .accessibilityLabel(resolving ? "Locating your position" : "Use my location")
                .accessibilityHint("Sets your home city from your current location, resolved on-device.")

                Button {
                    showHomeCityPicker = true
                } label: {
                    HStack(spacing: MeridianSpacing.sm.rawValue) {
                        Image(systemName: "magnifyingglass")
                        Text("Set city manually")
                    }
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MeridianSpacing.md.rawValue)
                    .frame(minHeight: kSettingsHitTarget)
                    .background {
                        Capsule().strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(SettingsPressableStyle(reduceMotion: reduceMotion))
                .padding(.top, MeridianSpacing.sm.rawValue)

                if let locationStatus {
                    Text(locationStatus)
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                        .padding(.top, MeridianSpacing.sm.rawValue)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }

            // Home country anchor
            SettingsCard {
                Toggle(isOn: Binding(
                    get: { settings.homeCountryEnabled },
                    set: { viewModel.setHomeCountryEnabled($0) }
                )) {
                    settingRowLabel(
                        icon: "globe",
                        title: "Home country",
                        subtitle: "Show your origin-country clock on the Now card — e.g. India for family calls."
                    )
                }
                .tint(MeridianColors.primary)

                if settings.homeCountryEnabled {
                    cardDivider

                    HStack(spacing: MeridianSpacing.sm.rawValue) {
                        Image(systemName: "globe.americas")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MeridianColors.primary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.homeCountryZone.map { "City · \($0.displayName)" } ?? "No city chosen")
                                .font(.titleMedium)
                                .foregroundStyle(MeridianColors.onSurface)
                            Text("Pick the city that represents your home-country time zone.")
                                .font(.labelMedium)
                                .foregroundStyle(MeridianColors.onSurfaceVariant)
                        }
                    }
                    .padding(.bottom, MeridianSpacing.md.rawValue)
                    .accessibilityElement(children: .combine)

                    Button {
                        showHomeCountryPicker = true
                    } label: {
                        HStack(spacing: MeridianSpacing.sm.rawValue) {
                            Image(systemName: "magnifyingglass")
                            Text(viewModel.homeCountryZone == nil ? "Pick city" : "Change city")
                        }
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MeridianSpacing.md.rawValue)
                        .frame(minHeight: kSettingsHitTarget)
                        .background {
                            Capsule().strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(SettingsPressableStyle(reduceMotion: reduceMotion))
                }
            }
        }
    }

    // MARK: - Appearance section

    private var appearanceSection: some View {
        VStack(spacing: 16) {
            // Clock format
            SettingsCard {
                sectionTitle("Clock format")
                Text("Choose how every clock renders the hour.")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .padding(.bottom, MeridianSpacing.sm.rawValue)

                Picker("Hour cycle", selection: Binding(
                    get: { settings.hourCycle },
                    set: { viewModel.setHourCycle($0) }
                )) {
                    Text("System").tag(HourCycle.system)
                    Text("12-hour").tag(HourCycle.twelve)
                    Text("24-hour").tag(HourCycle.twentyFour)
                }
                .pickerStyle(.segmented)
            }

            // Glass + backdrop
            SettingsCard {
                settingsSwitch(
                    title: "Liquid Glass",
                    subtitle: "Apply hardware-accelerated blur to surfaces.",
                    isOn: Binding(
                        get: { settings.glassEnabled },
                        set: { viewModel.setGlassEnabled($0) }
                    )
                )

                cardDivider

                settingsSwitch(
                    title: "Reduce transparency",
                    subtitle: "Swap glass for opaque surfaces for maximum legibility.",
                    isOn: Binding(
                        get: { settings.reduceTransparency },
                        set: { viewModel.setReduceTransparency($0) }
                    )
                )

                cardDivider

                // Glass opacity — now functional (drives the glassOpacity setting).
                PercentSlider(
                    label: "Agenda & scrubber glass",
                    icon: "rectangle.on.rectangle",
                    description: "Opacity and contrast for the agenda pill, the scrubber, and the time dial. Higher means a more solid, legible card.",
                    value: Binding(
                        get: { settings.glassOpacity },
                        set: { viewModel.setGlassOpacity($0) }
                    )
                )
                .disabled(!settings.glassEnabled)
                .opacity(settings.glassEnabled ? 1 : 0.4)
                .accessibilityHint(settings.glassEnabled ? "" : "Enable Liquid Glass to adjust this.")

                cardDivider

                settingsSwitch(
                    title: "Celestial backdrop",
                    subtitle: "Show the sun and moon behind the interface. Glass surfaces refract this layer.",
                    isOn: Binding(
                        get: { settings.backdropEnabled },
                        set: { viewModel.setBackdropEnabled($0) }
                    )
                )

                if settings.backdropEnabled {
                    PercentSlider(
                        label: "Backdrop intensity",
                        icon: "sparkles",
                        description: "How strongly the sun and moon glow through the glass.",
                        value: Binding(
                            get: { settings.backdropIntensity },
                            set: { viewModel.setBackdropIntensity($0) }
                        )
                    )
                    .padding(.top, MeridianSpacing.md.rawValue)
                }
            }

            // Map style
            SettingsCard {
                sectionTitle("World map style")
                Text("Realistic uses the full texture, atmosphere and night-lights. Balanced drops the heavy effects. Performance shades a flat globe. Vector is a 2D outline map that recolors with the theme.")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .padding(.bottom, MeridianSpacing.sm.rawValue)

                Picker("Map style", selection: Binding(
                    get: { settings.mapStyle },
                    set: { viewModel.setMapStyle($0) }
                )) {
                    Text("Realistic").tag(MapStyle.realistic)
                    Text("Balanced").tag(MapStyle.balanced)
                    Text("Performance").tag(MapStyle.performance)
                    Text("Vector").tag(MapStyle.vector)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - About & Legal section

    private var aboutSection: some View {
        VStack(spacing: 16) {
            // App identity
            SettingsCard {
                VStack(spacing: MeridianSpacing.sm.rawValue + 2) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 44, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(MeridianColors.primary)
                        .accessibilityHidden(true)
                    Text("Meridian")
                        .font(.titleLarge)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text("Time & world planner")
                        .font(.bodySmall)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)

                    // Tap the version to copy a diagnostic snapshot (Android: AboutCard).
                    Button {
                        UIPasteboard.general.string = SettingsActions.buildDiagnosticText()
                        withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) { diagnosticsCopied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) { diagnosticsCopied = false }
                        }
                    } label: {
                        HStack(spacing: MeridianSpacing.xs.rawValue + 2) {
                            Text(diagnosticsCopied ? "Diagnostics copied" : "Version \(AppInfo.versionLabel)")
                                .font(.labelMedium)
                                .foregroundStyle(diagnosticsCopied ? MeridianColors.primary : MeridianColors.onSurfaceVariant)
                            if !diagnosticsCopied {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, MeridianSpacing.md.rawValue)
                        .padding(.vertical, MeridianSpacing.sm.rawValue)
                        .frame(minHeight: kSettingsHitTarget)
                        .contentShape(RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous))
                    }
                    .buttonStyle(SettingsPressableStyle(reduceMotion: reduceMotion))
                    .sensoryFeedback(.impact(weight: .medium), trigger: diagnosticsCopied)
                    .accessibilityLabel("Copy diagnostics")
                    .accessibilityValue("Version \(AppInfo.versionLabel)")
                    .accessibilityHint("Copies a diagnostic snapshot to the clipboard.")
                    if AppInfo.isDebugBuild {
                        Text("Debug build")
                            .font(.labelSmall)
                            .foregroundStyle(MeridianColors.primary)
                    }
                    Text("Local clocks, multi-zone planning, and optional on-device AI — built with a privacy-first, on-device engine.")
                        .font(.bodySmall)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.top, MeridianSpacing.xs.rawValue)
                }
                .frame(maxWidth: .infinity)
            }

            OnDeviceCard()

            // Auto-sync interop (previously dead toggle — now persisted).
            SettingsCard {
                settingsSwitch(
                    title: "Auto-sync calendar events",
                    subtitle: "Pull upcoming device-calendar events into the Plan screen.",
                    isOn: Binding(
                        get: { autoSync },
                        set: { newValue in
                            autoSync = newValue
                            CalendarAutoSync.isEnabled = newValue
                            if newValue {
                                Task { await viewModel.loadCalendarEvents() }
                            } else {
                                viewModel.calendarEvents = []
                            }
                        }
                    )
                )
            }

            // Legal notices
            SettingsCard {
                Text("Legal & privacy")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                    .padding(.bottom, MeridianSpacing.xs.rawValue)
                    .accessibilityAddTraits(.isHeader)

                legalRow(.privacy, icon: "hand.raised", subtitle: "What Meridian accesses and how data is used")
                SettingsLinkDivider()
                legalRow(.dataHandling, icon: "externaldrive", subtitle: "On-device storage, cloud fallback, and retention")
                SettingsLinkDivider()
                legalRow(.terms, icon: "doc.text", subtitle: "Acceptable use, disclaimers, and liability")
                SettingsLinkDivider()
                legalRow(.openSource, icon: "chevron.left.forwardslash.chevron.right", subtitle: "Third-party libraries used by Meridian")
                SettingsLinkDivider()
                legalRow(.thirdPartyPolicies, icon: "arrow.up.right.square", subtitle: "Platform privacy and terms")
            }

            SupportCard()
        }
    }

    private func legalRow(_ document: LegalDocument, icon: String, subtitle: String) -> some View {
        SettingsLinkRow(icon: icon, title: document.title, subtitle: subtitle) {
            activeLegalDocument = document
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: MeridianSpacing.xs.rawValue) {
            Text("© \(currentYear) Meridian")
                .font(.labelSmall)
                .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.7))
            Text("On-device first · Last updated \(kLegalLastUpdated)")
                .font(.labelSmall)
                .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MeridianSpacing.lg.rawValue)
        .accessibilityElement(children: .combine)
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    // MARK: - Location resolution

    @MainActor
    private func resolveHomeFromLocation() async {
        resolving = true
        defer { resolving = false }
        if let name = await viewModel.resolveHomeFromLocation() {
            announceStatus("Home set to \(name)")
        } else {
            announceStatus("Couldn't read your location. Pick a city manually below.")
        }
    }

    /// Updates the visible status line and posts a VoiceOver announcement so the
    /// outcome is spoken even though the label is off-screen or unfocused.
    @MainActor
    private func announceStatus(_ message: String) {
        locationStatus = message
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    // MARK: - Reusable bits

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.titleMedium)
            .foregroundStyle(MeridianColors.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// Standard intra-card hairline. Matches the shared `SectionHeader`
    /// (white@0.10) and uses one spacing token so every rule reads identically.
    private var cardDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .padding(.vertical, MeridianSpacing.md.rawValue)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func settingsSwitch(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                Text(subtitle)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
            }
        }
        .tint(MeridianColors.primary)
        .accessibilityHint(subtitle)
    }

    @ViewBuilder
    private func settingRowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: MeridianSpacing.sm.rawValue) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MeridianColors.primary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                Text(subtitle)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
            }
        }
    }
}

// MARK: - SettingsPressableStyle

/// Shared press-feedback style for the Settings action buttons that aren't glass
/// chips or nav items. Scales the label down on press with a `Motion.quick()`
/// spring — the same tactile language as the design system's `PressableScaleStyle`
/// (which is file-private to GlassComponents) and the nav bar's `NavPressStyle`.
/// Reduce-Motion drops the scale so nothing moves for motion-sensitive users.
private struct SettingsPressableStyle: ButtonStyle {
    var reduceMotion: Bool = false
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? nil : Motion.quick(), value: configuration.isPressed)
    }
}

/// Apple HIG minimum touch-target edge (points); mirrors Android's 48 dp.
private let kSettingsHitTarget: CGFloat = 44

// MARK: - CompanionAppCard

/// Shows whether ChronosFlow (the companion planner) has shared data into the App
/// Group container, so the user knows whether cross-app task/event sharing is active.
/// Port of Android `CompanionAppCard`, which asked the package manager; on iOS the
/// closest observable signal is the peer snapshot probed by `InteropClient`.
/// Re-checks whenever the app returns to the foreground.
private struct CompanionAppCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var installed = InteropClient().isPeerInstalled()

    var body: some View {
        SettingsCard {
            HStack(spacing: MeridianSpacing.md.rawValue) {
                Image(systemName: installed ? "checkmark.circle" : "xmark.circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(installed ? MeridianColors.primary : MeridianColors.onSurfaceVariant.opacity(0.7))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ChronosFlow")
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text(installed
                         ? "Connected — tasks and events are shared between apps."
                         : "Not installed — Meridian runs on its own. Install ChronosFlow to share tasks and events.")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                installed = InteropClient().isPeerInstalled()
            }
        }
    }
}

// MARK: - OnDeviceCard

/// Static "on-device first" reassurance card (Android: OnDeviceCard).
private struct OnDeviceCard: View {
    var body: some View {
        SettingsCard {
            HStack(spacing: MeridianSpacing.md.rawValue) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("On-device first validation")
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text("All time-zone lookups and slot math run on-device. Cloud AI is an opt-in fallback only.")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - PercentSlider

/// A labeled slider that displays its value as a percentage and an optional description.
/// `value` is a normalized fraction in 0.10...1.0 (the contract glass/backdrop form).
private struct PercentSlider: View {
    let label: String
    let icon: String
    var description: String? = nil
    @Binding var value: Double

    private var percent: Int { Int((value * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue + 2) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundStyle(MeridianColors.onSurface)
                Spacer()
                Text("\(percent)%")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.primary)
                    .monospacedDigit()
            }
            .accessibilityHidden(true)

            if let description {
                Text(description)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .accessibilityHidden(true)
            }

            Slider(value: $value, in: kMinGlassFraction...kMaxGlassFraction)
                .tint(MeridianColors.primary)
                .sensoryFeedback(.selection, trigger: percent)
                .accessibilityLabel(label)
                .accessibilityValue("\(percent) percent")
        }
    }
}

// MARK: - HomeCitySearchSheet

/// A search sheet backed by `MainViewModel.searchTimeZones` (the full multi-layer merge).
/// Mirrors Android `HomeCityPickerSheet`.
private struct HomeCitySearchSheet: View {
    let title: String
    @Bindable var viewModel: MainViewModel
    let onSelect: (ZoneMatch) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ZoneMatch] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                MeridianColors.background.ignoresSafeArea()

                List(results) { match in
                    Button {
                        onSelect(match)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(match.displayName)
                                .font(.titleMedium)
                                .foregroundStyle(MeridianColors.onSurface)
                            Text(match.zoneId)
                                .font(.labelMedium)
                                .foregroundStyle(MeridianColors.onSurfaceVariant)
                        }
                        .padding(.vertical, MeridianSpacing.xs.rawValue)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(MeridianColors.surface.opacity(0.5))
                    .listRowSeparator(.hidden)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if results.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "Search for a city" : "No matches",
                            systemImage: "magnifyingglass"
                        )
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MeridianColors.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MeridianColors.primary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search city or time zone")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    let hits = await viewModel.searchTimeZones(newValue)
                    if !Task.isCancelled { results = hits }
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    SettingsScreen()
        .preferredColorScheme(.dark)
}
#endif
