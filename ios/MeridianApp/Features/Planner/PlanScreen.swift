// PlanScreen.swift
// Meridian — iOS 27 / Swift 6  SwiftUI
//
// Plan tab: a fair cross-zone meeting finder. Direct behavioral port of Android `PlanScreen.kt`.
//
// All scheduling math goes through `MainViewModel.computeMeetingSlots` — the screen never bakes a
// UTC wall-clock string into a slot. Every time is rendered in the relevant LOCAL zone by SlotCard
// / FairSlotsScrubber (the UTC-bug fix).
//
// Flow:
//   • favorites pool → location groups (consolidated by IANA zone) → selection dicts
//   • 24 ranked slots (fairest first) drive the SlotCard + rotating series
//   • the same 24 slots, chronological, drive the pinned fair-time dial (weekend bands = nil)
//   • a "Your Plan" list shows persisted PlannedTasks with calendar / share / delete actions

import SwiftUI
import EventKit

struct PlanScreen: View {

    // MARK: Environment

    @Environment(\.mainViewModel) private var viewModelOptional
    @Environment(SettingsRepository.self) private var settingsRepo

    // MARK: Selection + window state

    @State private var selectedZones: [String: Bool] = [:]
    @State private var selectedPeople: [UUID: Bool] = [:]
    @State private var selectedDateMillis: Int = PlanScreen.todayUtcMidnightMillis()
    @State private var durationMinutes = 45
    @State private var meetingTitle = "Meridian sync"
    @State private var excludeWeekends = false
    /// The currently selected slot's absolute instant, snapped to the top of the hour.
    @State private var selectedSlotInstant: Date? = nil

    // MARK: Sheets / calendar

    @State private var showJumpModal = false
    @State private var showAddSheet = false
    @State private var calendarGranted = false

    // MARK: Derived

    private var localZoneId: String { TimeZone.current.identifier }

    private var use24Hour: Bool {
        TimeFormats.uses24Hour(cycle: settingsRepo.settings.hourCycle)
    }

    var body: some View {
        if let viewModel = viewModelOptional {
            PlanScreenContent(
                viewModel: viewModel,
                settingsRepo: settingsRepo,
                localZoneId: localZoneId,
                use24Hour: use24Hour,
                selectedZones: $selectedZones,
                selectedPeople: $selectedPeople,
                selectedDateMillis: $selectedDateMillis,
                durationMinutes: $durationMinutes,
                meetingTitle: $meetingTitle,
                excludeWeekends: $excludeWeekends,
                selectedSlotInstant: $selectedSlotInstant,
                showJumpModal: $showJumpModal,
                showAddSheet: $showAddSheet,
                calendarGranted: $calendarGranted
            )
        } else {
            // The view model is always injected at the app root; this is a defensive fallback.
            ZStack {
                MeridianColors.background.ignoresSafeArea()
                ProgressView().tint(MeridianColors.primary)
            }
        }
    }

    // MARK: - Statics

    /// UTC-midnight epoch (ms) of the device's current local day. Mirrors Android
    /// `todayUtcMidnightMillis`.
    static func todayUtcMidnightMillis() -> Int {
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = .current
        let comps = localCal.dateComponents([.year, .month, .day], from: Date())
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: comps) ?? Date()
        return Int(midnight.timeIntervalSince1970 * 1000)
    }
}

// MARK: - PlanScreenContent

/// The real screen body, separated so it can read the non-optional `MainViewModel` directly via
/// `@Bindable` for `@Observable` tracking.
private struct PlanScreenContent: View {

    @Bindable var viewModel: MainViewModel
    let settingsRepo: SettingsRepository
    let localZoneId: String
    let use24Hour: Bool

    @Binding var selectedZones: [String: Bool]
    @Binding var selectedPeople: [UUID: Bool]
    @Binding var selectedDateMillis: Int
    @Binding var durationMinutes: Int
    @Binding var meetingTitle: String
    @Binding var excludeWeekends: Bool
    @Binding var selectedSlotInstant: Date?
    @Binding var showJumpModal: Bool
    @Binding var showAddSheet: Bool
    @Binding var calendarGranted: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.selectTab) private var selectTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Hide-on-scroll state for the pinned dial (Android: dialVisible).
    @State private var dialVisible = true
    @State private var lastScrollOffset: CGFloat = 0

    // MARK: Data derivations

    private var localLocationName: String {
        viewModel.savedZones.localLocationLabel(localZoneId: localZoneId)
    }

    private var pool: PlannerParticipantPool {
        ParticipantGrouping.plannerParticipantPool(
            savedZones: viewModel.savedZones,
            people: viewModel.people,
            localZoneId: localZoneId
        )
    }

    private var locationGroups: [ParticipantLocationGroup] {
        ParticipantGrouping.visiblePlannerGroups(
            ParticipantGrouping.buildParticipantLocationGroups(zones: pool.zones, people: pool.people),
            localZoneId: localZoneId
        )
    }

    /// Start of the selected UTC day, expressed in the LOCAL zone. Mirrors Android
    /// `startOfDayInstant`.
    private var baseInstant: Date {
        let utcMidnight = Date(timeIntervalSince1970: Double(selectedDateMillis) / 1000)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = utc.dateComponents([.year, .month, .day], from: utcMidnight)
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = TimeFormats.safeTimeZone(id: localZoneId)
        return localCal.date(from: comps) ?? utcMidnight
    }

    private var participants: [MeetingParticipant] {
        ParticipantGrouping.buildMeetingParticipants(
            localZoneId: localZoneId,
            groups: locationGroups,
            selectedZones: selectedZones,
            selectedPeople: selectedPeople
        )
    }

    private var participantLabels: [ParticipantSlotLabel] {
        ParticipantGrouping.buildSelectedParticipantLabels(
            localZoneId: localZoneId,
            localLocationName: localLocationName,
            groups: locationGroups,
            selectedZones: selectedZones,
            selectedPeople: selectedPeople
        )
    }

    /// All 24 hourly slots ranked fairest-first (drives the default pick + rotating series).
    private var allSlots: [MeetingSlot] {
        viewModel.computeMeetingSlots(participants: participants, baseDate: baseInstant)
    }

    /// Ranked slots after the weekend filter.
    private var rankedSlots: [MeetingSlot] {
        excludeWeekends ? allSlots.filter { !isWeekendSlot($0) } : allSlots
    }

    /// The same 24 slots, chronological; weekend-filtered hours become nil bands.
    private var dialHours: [DialHour] {
        allSlots
            .sorted { $0.start < $1.start }
            .map { slot in
                let blocked = excludeWeekends && isWeekendSlot(slot)
                return DialHour(
                    instant: slot.start,
                    slot: blocked ? nil : slot,
                    label: blocked ? nil : slot.label
                )
            }
    }

    private var defaultSlotInstant: Date? {
        rankedSlots.first?.start
    }

    private var selectedIndex: Int {
        if let instant = selectedSlotInstant,
           let idx = dialHours.firstIndex(where: { $0.instant == instant && $0.slot != nil }) {
            return idx
        }
        return max(dialHours.firstIndex { $0.slot != nil } ?? 0, 0)
    }

    private var selectedSlot: MeetingSlot? {
        dialHours.indices.contains(selectedIndex) ? dialHours[selectedIndex].slot : nil
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [MeridianColors.background, MeridianColors.surface],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    PlannerHeaderView()
                        .reportScrollOffset(in: "plannerScroll")
                    DetailsCard(title: $meetingTitle)
                    ParticipantsCard(
                        locationGroups: locationGroups,
                        localLocationName: localLocationName,
                        selectedZones: $selectedZones,
                        selectedPeople: $selectedPeople,
                        onAddTapped: { showAddSheet = true },
                        onDeletePerson: { viewModel.deletePerson(id: $0) }
                    )
                    WindowCard(
                        selectedDateMillis: $selectedDateMillis,
                        durationMinutes: $durationMinutes,
                        excludeWeekends: $excludeWeekends,
                        onJumpTapped: { showJumpModal = true }
                    )

                    SectionLabel(label: "YOUR CALENDAR", subtitle: "Events from your device calendar.")
                    CalendarEventsCard(
                        events: viewModel.calendarEvents,
                        hasPermission: calendarGranted,
                        use24Hour: use24Hour,
                        onRequestPermission: requestCalendarAccess
                    )

                    SectionLabel(
                        label: "FAIR SLOTS",
                        subtitle: "Scrub the dial to explore every hour — bands mark the fair ones."
                    )
                    fairSlotsSection

                    plannedTasksSection

                    Spacer(minLength: 240)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .coordinateSpace(name: "plannerScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                // Hide the dial while scrolling down, reveal on scroll-up or at the top
                // (Android PlanScreen: dialVisible from firstVisibleItemIndex/scrollOffset).
                let delta = offset - lastScrollOffset
                lastScrollOffset = offset
                let shouldShow = offset >= -8 || delta > 4
                let shouldHide = delta < -4 && offset < -8
                if shouldShow, !dialVisible {
                    withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) { dialVisible = true }
                } else if shouldHide, dialVisible {
                    withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) { dialVisible = false }
                }
            }

            // Pinned fair-time dial above the tab bar (mirrors the World screen).
            if !rankedSlots.isEmpty, dialVisible {
                FairSlotsScrubber(
                    hours: dialHours,
                    selectedIndex: selectedIndex,
                    localZoneId: localZoneId,
                    durationMinutes: durationMinutes,
                    use24Hour: use24Hour,
                    onSelect: { idx in
                        selectedSlotInstant = dialHours.indices.contains(idx) ? dialHours[idx].instant : nil
                    }
                )
                .padding(.horizontal, MeridianSpacing.lg.rawValue)
                // Reuse the design-system pill↔dial transition (reduce-motion aware: it
                // collapses to a plain cross-fade), matching the World-screen scrubber this
                // Planner dial explicitly mirrors.
                .transition(Motion.scrubberContentTransition(reduceMotion: reduceMotion))
                // No extra bottom inset here: ContentView already reserves space for the floating
                // tab bar via `.safeAreaInset(.bottom)`, which this bare (non-NavigationStack) screen
                // inherits. Adding another 96pt would double-count and float the dial mid-screen.
            }
        }
        .task(id: TaskWindowKey(date: selectedDateMillis)) { await loadWindow() }
        .onChange(of: dialHours.map { "\($0.instant.timeIntervalSinceReferenceDate)-\($0.slot == nil)" }) { _, _ in resetSelectionIfNeeded() }
        .onAppear {
            // Passive status check — never prompt on appear; the button requests access.
            calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
            resetSelectionIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-check after the user grants access in system Settings and returns
            // (Android re-checks on every RESUMED).
            guard phase == .active else { return }
            let granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
            if granted != calendarGranted {
                calendarGranted = granted
                if granted { Task { await loadWindow() } }
            }
        }
        .sheet(isPresented: $showAddSheet) { addPersonSheet }
        .sheet(isPresented: $showJumpModal) { jumpModal }
    }

    // MARK: Fair slots section

    @ViewBuilder
    private var fairSlotsSection: some View {
        if rankedSlots.isEmpty {
            SlotsEmptyState(
                hint: emptyHint,
                actionLabel: "Pick another day",
                action: { showJumpModal = true }
            )
        } else {
            if let slot = selectedSlot {
                SlotCard(
                    slot: slot,
                    localZoneId: localZoneId,
                    localLocationName: localLocationName,
                    durationMinutes: durationMinutes,
                    use24Hour: use24Hour,
                    participantLabels: participantLabels,
                    interactive: false,
                    expanded: true,
                    meetingTitle: meetingTitle
                )
            }
            OutlinedActionButton(
                title: "Create rotating weekly series (4 weeks)",
                systemImage: "repeat",
                accessibilityHint: "Adds four weekly meetings that rotate the fair time across participants."
            ) {
                viewModel.createRotatingSeries(slots: rankedSlots, weeks: 4, zoneId: localZoneId, participantOrder: participants.map(\.zoneId))
            }
        }
    }

    // MARK: Your plan section

    @ViewBuilder
    private var plannedTasksSection: some View {
        SectionLabel(
            label: viewModel.plannedTasks.isEmpty
                ? "YOUR PLAN"
                : "YOUR PLAN  (\(viewModel.plannedTasks.count))",
            subtitle: "Events from Quick Schedule and the AI assistant."
        )

        if viewModel.plannedTasks.isEmpty {
            EmptyStateCard(
                icon: "calendar.badge.plus",
                title: "Nothing scheduled yet",
                message: "Save a fair slot above, use Quick Schedule in AI, or ask the assistant to plan a meeting.",
                actionLabel: "Ask AI",
                action: { selectTab(.ai) }
            )
        } else {
            ForEach(viewModel.plannedTasks, id: \.id) { task in
                PlannedTaskRow(
                    task: task,
                    use24Hour: use24Hour,
                    onDelete: { viewModel.deleteTask(id: task.id) }
                )
            }
        }
    }

    // MARK: Sheets

    private var addPersonSheet: some View {
        AddPersonSheet(
            searchZones: { query in await viewModel.searchTimeZones(query) },
            defaultWorkStart: settingsRepo.settings.defaultWorkStartHour,
            defaultWorkEnd: settingsRepo.settings.defaultWorkEndHour,
            onConfirm: { result in
                switch result {
                case let .city(zoneId, displayName):
                    viewModel.addZone(
                        SavedZone(id: zoneId, displayName: displayName, isFavorite: true)
                    )
                case let .person(name, zoneId, displayName, ws, we, ds, de):
                    viewModel.addPerson(
                        name: name,
                        zoneId: zoneId,
                        locationName: displayName,
                        workStartHour: ws,
                        workEndHour: we,
                        dndStartHour: ds,
                        dndEndHour: de,
                        isFavorite: true
                    )
                }
                showAddSheet = false
            },
            onDismiss: { showAddSheet = false }
        )
    }

    private var jumpModal: some View {
        JumpModal(
            localZoneId: localZoneId,
            localLocationName: localLocationName,
            savedZones: viewModel.savedZones,
            searchZones: { query in await viewModel.searchTimeZones(query) },
            use24Hour: use24Hour,
            onJump: { instant, _ in
                applyJump(to: instant)
                showJumpModal = false
            },
            onDismiss: { showJumpModal = false }
        )
    }

    // MARK: Behavior

    /// Re-base the window on the jumped-to instant: set the day (in local time) and snap the
    /// selection to the top of that hour. Mirrors Android's `onJump`.
    private func applyJump(to instant: Date) {
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = TimeFormats.safeTimeZone(id: localZoneId)
        let comps = localCal.dateComponents([.year, .month, .day], from: instant)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        if let utcMidnight = utc.date(from: comps) {
            selectedDateMillis = Int(utcMidnight.timeIntervalSince1970 * 1000)
        }
        selectedSlotInstant = floorToHour(instant)
    }

    /// Reset the selection to the fairest hour whenever the available slots change and the current
    /// selection is no longer a valid (non-nil) band. Mirrors Android's LaunchedEffect(dialHours).
    private func resetSelectionIfNeeded() {
        let stillValid = selectedSlotInstant.map { instant in
            dialHours.contains { $0.instant == instant && $0.slot != nil }
        } ?? false
        if !stillValid { selectedSlotInstant = defaultSlotInstant }
    }

    private func loadWindow() async {
        guard calendarGranted else { return }
        let from = baseInstant
        let to = from.addingTimeInterval(7 * 24 * 3600)
        await viewModel.loadCalendarEvents(from: from, to: to)
    }

    private func requestCalendarAccess() {
        Task {
            calendarGranted = await viewModel.requestCalendarAccess()
            await loadWindow()
        }
    }

    // MARK: Helpers

    /// True if the slot lands on a Saturday or Sunday in ANY participating zone. Mirrors Android
    /// `isWeekendSlot`.
    private func isWeekendSlot(_ slot: MeetingSlot) -> Bool {
        slot.localHours.keys.contains { zoneId in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeFormats.safeTimeZone(id: zoneId)
            let weekday = cal.component(.weekday, from: slot.start)
            return weekday == 1 || weekday == 7 // Sunday == 1, Saturday == 7
        }
    }

    private var emptyHint: String {
        let isWeekend: Bool = {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let date = Date(timeIntervalSince1970: Double(selectedDateMillis) / 1000)
            let weekday = utc.component(.weekday, from: date)
            return weekday == 1 || weekday == 7
        }()
        if excludeWeekends && isWeekend {
            return "Weekends are excluded and this is a weekend. Pick a weekday or turn off the filter."
        }
        if excludeWeekends {
            return "Every workable hour falls in someone's sleep window. Try another date, fewer zones, or turn off the weekends filter."
        }
        return "Every hour lands in someone's sleep window. Try another date or fewer zones."
    }

    private func floorToHour(_ date: Date) -> Date {
        let seconds = (date.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}

// MARK: - OutlinedActionButton

/// The shared full-width outlined-primary CTA used across the Planner (rotating series here,
/// and the visually-identical Jump / grant-calendar buttons in `PlannerComponents`). Factored
/// so all copies stay on-token: `MeridianRadius.small` (12) corner, 1pt `primary@0.4` stroke,
/// `.bodyLarge` primary label. Mirror-able to Android's shared outlined `Button` treatment.
///
/// Accessibility: exposes the `.isButton` trait, an optional hint, a pressed-scale feedback that
/// honours Reduce Motion, and a >=44pt tap target (the label's 11pt vertical padding around a
/// `.bodyLarge` line clears 44pt; `contentShape` makes the whole outlined pill tappable).
private struct OutlinedActionButton: View {
    let title: String
    let systemImage: String
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.bodyLarge)
                .foregroundStyle(MeridianColors.primary)
                .frame(maxWidth: .infinity)
                // Shared metric with the sibling outlined buttons (Jump / grant-calendar). Not a
                // spacing token — it is the canonical outlined-button inset, kept identical across
                // all three CTAs. Around a `.bodyLarge` line this clears the 44pt tap-target floor.
                .padding(.vertical, 11)
                .contentShape(
                    RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                )
                .background {
                    RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                        .strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
                }
        }
        .buttonStyle(OutlinedActionButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

/// Press feedback for `OutlinedActionButton`: a subtle scale-down on press with a light haptic,
/// mirroring the design system's `NavPressStyle`. Reduce-Motion collapses the scale animation to
/// a near-instant curve (via `Motion.reducedOrInstant`) while keeping the state change intact.
private struct OutlinedActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                Motion.reducedOrInstant(Motion.quick(), reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, now in now }
    }
}

// MARK: - TaskWindowKey

/// Equatable key so `.task(id:)` reloads calendar events only when the selected day changes.
private struct TaskWindowKey: Equatable, Sendable {
    let date: Int
}
