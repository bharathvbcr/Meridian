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

// MARK: - Local design tokens

private extension Color {
    static let settingsPrimary      = Color(hex: "#60CDFF")
    static let settingsBackground   = Color(hex: "#020617")
    static let settingsSurface      = Color(hex: "#0F172A")
    static let settingsOnSurface    = Color(hex: "#F1F5F9")
    static let settingsOnSurfaceVar = Color(hex: "#94A3B8")
    static let settingsPositive     = Color(hex: "#4CAF50")
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

    private var settings: MeridianSettings { viewModel.settings }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.settingsBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        homeSection
                        PermissionsCard()
                        appearanceSection
                        AiEngineCard(viewModel: viewModel)
                        RemindersCard(viewModel: viewModel)
                        DataManagementCard()
                        aboutSection
                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.settingsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showHomeCityPicker) {
            HomeCitySearchSheet(title: "Choose your home city", viewModel: viewModel) { match in
                viewModel.setHomeZone(id: match.zoneId, displayName: match.displayName)
                locationStatus = "Home set to \(match.displayName)"
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

    // MARK: - Home section

    private var homeSection: some View {
        VStack(spacing: 16) {
            SettingsCard {
                HStack(spacing: 8) {
                    Image(systemName: "house")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.settingsPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.homeZone.map { "Home · \($0.displayName)" } ?? "No home set")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.settingsOnSurface)
                        Text("Your usual base for the Now card and planning. Resolved on-device — never sent anywhere.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.settingsOnSurfaceVar)
                    }
                }
                .padding(.bottom, 12)

                Button {
                    Task { await resolveHomeFromLocation() }
                } label: {
                    HStack(spacing: 8) {
                        if resolving {
                            ProgressView().controlSize(.small).tint(Color.settingsBackground)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text(resolving ? "Locating…" : "Use my location")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.settingsBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.settingsPrimary))
                }
                .buttonStyle(.plain)
                .disabled(resolving)

                Button {
                    showHomeCityPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Set city manually")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.settingsPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background {
                        Capsule().strokeBorder(Color.settingsPrimary.opacity(0.4), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                if let locationStatus {
                    Text(locationStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.settingsOnSurface.opacity(0.7))
                        .padding(.top, 8)
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
                .tint(Color.settingsPrimary)

                if settings.homeCountryEnabled {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.vertical, 12)

                    HStack(spacing: 8) {
                        Image(systemName: "globe.americas")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.settingsPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.homeCountryZone.map { "City · \($0.displayName)" } ?? "No city chosen")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.settingsOnSurface)
                            Text("Pick the city that represents your home-country time zone.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.settingsOnSurfaceVar)
                        }
                    }
                    .padding(.bottom, 12)

                    Button {
                        showHomeCountryPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text(viewModel.homeCountryZone == nil ? "Pick city" : "Change city")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.settingsPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            Capsule().strokeBorder(Color.settingsPrimary.opacity(0.4), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
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
                    .font(.system(size: 12))
                    .foregroundStyle(Color.settingsOnSurfaceVar)
                    .padding(.bottom, 8)

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
                    .padding(.top, 12)
                }
            }

            // Map style
            SettingsCard {
                sectionTitle("World map style")
                Text("Realistic uses the full texture, atmosphere and night-lights. Balanced drops the heavy effects. Performance shades a flat globe. Vector is a 2D outline map that recolors with the theme.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.settingsOnSurfaceVar)
                    .padding(.bottom, 8)

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
                VStack(spacing: 10) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 44, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.settingsPrimary)
                    Text("Meridian")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.settingsOnSurface)
                    Text("Version \(AppInfo.versionLabel)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.settingsOnSurfaceVar)
                    if AppInfo.isDebugBuild {
                        Text("Debug build")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.settingsPrimary)
                    }
                    Text("Local clocks, multi-zone planning, and optional on-device AI — built with a privacy-first, on-device engine.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.settingsOnSurface.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            }

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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.settingsOnSurface)
                    .padding(.bottom, 4)

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
        VStack(spacing: 4) {
            Text("© \(currentYear) Meridian")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurfaceVar.opacity(0.7))
            Text("On-device first · Last updated \(kLegalLastUpdated)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurfaceVar.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    // MARK: - Location resolution

    @MainActor
    private func resolveHomeFromLocation() async {
        resolving = true
        defer { resolving = false }
        let resolver = LocationZoneResolver()
        if let zoneId = await resolver.resolveHomeZoneId() {
            let name = zoneId.split(separator: "/").last
                .map { $0.replacingOccurrences(of: "_", with: " ") } ?? zoneId
            viewModel.setHomeZone(id: zoneId, displayName: name)
            locationStatus = "Home set to \(name)"
        } else {
            locationStatus = "Couldn't read your location. Pick a city manually below."
        }
    }

    // MARK: - Reusable bits

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.settingsOnSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 14)
    }

    @ViewBuilder
    private func settingsSwitch(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.settingsOnSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.settingsOnSurfaceVar)
            }
        }
        .tint(Color.settingsPrimary)
    }

    @ViewBuilder
    private func settingRowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.settingsPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.settingsOnSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.settingsOnSurfaceVar)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.settingsPrimary)
                    .frame(width: 22)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.settingsOnSurface)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.settingsPrimary)
                    .monospacedDigit()
            }

            if let description {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.settingsOnSurfaceVar)
            }

            Slider(value: $value, in: kMinGlassFraction...kMaxGlassFraction)
                .tint(Color.settingsPrimary)
                .sensoryFeedback(.selection, trigger: Int((value * 100).rounded()))
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
                Color(hex: "#020617").ignoresSafeArea()

                List(results) { match in
                    Button {
                        onSelect(match)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(match.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: "#F1F5F9"))
                            Text(match.zoneId)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: "#94A3B8"))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color(hex: "#0F172A").opacity(0.5))
                    .listRowSeparator(.hidden)
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
            .toolbarBackground(Color(hex: "#020617"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(hex: "#60CDFF"))
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
