// MeridianApp.swift
// Meridian — iOS 27  Swift 6  SwiftUI
//
// App entry point. Owns the SwiftData ModelContainer (backed by the App Group so the
// widget can read the same store), the singleton repositories, first-launch permission
// + background-task wiring, and the URL / App-Intent / reminder deep-link router.
//
// Behavioral port of Android `MainActivity` + `MeridianApplication`:
//   - MeridianApplication.onCreate     → ModelContainer + BGAppRefreshTask registration
//                                         + notification "channels" (categories) + initial
//                                         interop sync.
//   - MainActivity.onCreate            → enableEdgeToEdge + Live-Update periodic schedule
//                                         + notification permission request.
//   - MainActivity.onResume            → interopSyncManager.syncFromPeer() (here:
//                                         scenePhase == .active).
//   - navDeepLink meridian://world|plan → onOpenURL → tab selection.

import SwiftUI
import SwiftData

// MARK: - MeridianApp

@main
struct MeridianApp: App {

    // MARK: SwiftData container (App-Group backed)

    /// Shared store, persisted in the App Group container so the widget extension reads the
    /// same SwiftData database. Falls back to a default on-disk store if the group container
    /// is unavailable (misconfigured entitlements in a debug build) so the app still launches.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedZone.self,
            Person.self,
            PlannedTask.self,
        ])

        // Prefer the App Group container so the widget and watch read the same store. But
        // SwiftData calls `fatalError` (it does NOT throw) when the requested App Group is not
        // present in the runtime entitlements — e.g. a debug build signed without the group, or
        // a build run from Xcode with no `DEVELOPMENT_TEAM`, where the group is never provisioned.
        // A `do/catch` therefore cannot save us: the process aborts inside `ModelContainer.init`
        // before any error is thrown. So we must probe for the container ourselves first and only
        // ask SwiftData for the group store when it actually exists, otherwise fall back to a
        // per-app local store so the app still launches.
        let groupContainerAvailable = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) != nil

        let primaryConfig = groupContainerAvailable
            ? ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier))
            : ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [primaryConfig])
        } catch {
            // Last-resort fallback so a store-creation failure does not hard-crash the app.
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            if let container = try? ModelContainer(for: schema, configurations: [local]) {
                return container
            }
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: Singleton repositories / services

    @State private var settingsRepo = SettingsRepository.shared

    // MARK: Scene lifecycle

    @Environment(\.scenePhase) private var scenePhase

    // MARK: Init — background-task registration (must happen during launch)

    init() {
        // Register the BGAppRefreshTask handler before the app finishes launching, per
        // BGTaskScheduler requirements (Android `LiveUpdates.schedulePeriodic`). The handler
        // re-evaluates which event is "next" and reconciles the Live Activity from a fresh
        // background ModelContext — the VM may not exist while suspended.
        BackgroundRefreshScheduler.shared.register {
            await Self.reconcileLiveActivityInBackground()
        }
    }

    // MARK: Scene

    var body: some Scene {
        WindowGroup {
            MainAppView()
                .modelContainer(Self.sharedModelContainer)
                .environment(settingsRepo)
                .environment(TimeEngine.shared)
                .environment(\.glassEnabled, settingsRepo.settings.glassEnabled)
                .environment(\.glassOpacity, settingsRepo.settings.glassOpacity)
                .environment(\.reduceTransparencyOverride, settingsRepo.settings.reduceTransparency)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Keep the periodic background-refresh chain alive on backgrounding (Android periodic
            // WorkManager). Foreground interop sync is driven from `MainAppView`, where the
            // SwiftData-backed `InteropSyncManager` and model context are available.
            if newPhase == .background {
                BackgroundRefreshScheduler.shared.schedule()
            }
        }
    }

    // MARK: - Background Live Activity reconcile

    /// Fetches planned tasks from a fresh background context off the shared container and
    /// reconciles the Live Activity. Runs on the main actor (ActivityKit + the manager are
    /// main-actor isolated); the fetch is cheap.
    @MainActor
    private static func reconcileLiveActivityInBackground() async {
        let context = ModelContext(sharedModelContainer)
        let descriptor = FetchDescriptor<PlannedTask>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        let entries = tasks.map { (id: $0.id, title: $0.title, date: $0.timestamp) }
        await LiveActivityManager.shared.reconcile(tasks: entries, now: Date())
    }
}

// MARK: - MainAppView

/// Shell view that builds the ``MainViewModel`` on the main actor, wires the shared
/// deep-link router (URL scheme + App Intents + reminder taps), runs first-launch
/// permission + background scheduling, and overlays ``OnboardingView`` when needed.
struct MainAppView: View {

    // MARK: Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsRepository.self) private var settingsRepo
    @Environment(\.scenePhase) private var scenePhase

    // MARK: State

    @State private var viewModel: MainViewModel?
    @State private var showOnboarding: Bool = false
    /// The currently selected tab — shared with `ContentView` and driven by deep links.
    @State private var selectedTab: MeridianTab = .now
    /// One-shot flag: World screen should open the city search sheet (from widget / addzone link).
    @State private var worldCityPickerPending = false
    /// Strong reference to the notification delegate (the center holds it weakly).
    @State private var notificationDelegate = NotificationDelegate()
    /// Cross-app (ChronosFlow) sync manager — SwiftData-backed; built once in `bootstrap`.
    @State private var interopSync: InteropSyncManager?
    /// Publishes OUR tasks/zones/people into the App Group for the peer to read —
    /// the write half of interop (Android: the always-live `InteropProvider`).
    @State private var interopExporter: InteropExporter?

    // MARK: Body

    var body: some View {
        Group {
            if let viewModel {
                ContentView(viewModel: viewModel, selectedTab: $selectedTab)
                    .environment(\.worldCityPickerRequest, $worldCityPickerPending)
                    .meridianEnvironment(
                        viewModel: viewModel,
                        settings: settingsRepo.settings,
                        selectTab: { tab in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab = tab
                            }
                        }
                    )
                    .overlay {
                        if showOnboarding {
                            OnboardingView {
                                completeOnboarding()
                            }
                            .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                            .zIndex(100)
                        }
                    }
            } else {
                // Splash / loading state while the view-model initialises.
                ZStack {
                    MeridianColors.background.ignoresSafeArea()
                    VStack(spacing: 20) {
                        MeridianWordmark()
                        ProgressView()
                            .tint(MeridianColors.primary)
                    }
                }
            }
        }
        .onAppear { bootstrap() }
        // External deep links (meridian://world | meridian://plan).
        .onOpenURL { url in
            if let link = MeridianDeepLink(url: url) {
                route(link)
            }
        }
        .task {
            // First-launch authorization for reminders (Android POST_NOTIFICATIONS request).
            // Reminders degrade silently if denied; the in-app countdown still works.
            await NotificationService.shared.requestAuthorizationIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Pull whatever the peer app (ChronosFlow) shared every time Meridian comes to the
            // foreground — mirrors Android `MainActivity.onResume`. The interop manager writes
            // mirrored rows straight to SwiftData, so screen `@Query`s pick them up automatically.
            if newPhase == .active, let interopSync {
                Task { await interopSync.syncFromPeer() }
            }
            // Publish our own snapshot both ways across the transition, and re-arm the Live
            // Activity on foreground (ActivityKit only permits starting one while active, so
            // an event that entered the 24 h window in the background starts here).
            if newPhase == .active || newPhase == .background {
                interopExporter?.exportSnapshot()
            }
            if newPhase == .active {
                viewModel?.refreshLiveActivity()
                viewModel?.prewarmAi()
            }
            if newPhase == .background {
                viewModel?.releaseAiModels()
            }
        }
        // Every persisted change (any context) re-publishes the interop snapshot, keeping the
        // shared file as current as Android's live ContentProvider. Same didSave-driven pattern
        // as WatchSyncManager.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in
            interopExporter?.exportSnapshot()
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() {
        guard viewModel == nil else { return }

        let vm = MainViewModel(modelContext: modelContext, settingsRepo: settingsRepo)
        viewModel = vm
        showOnboarding = !settingsRepo.settings.onboardingComplete

        // Build the SwiftData-backed cross-app sync manager and pull immediately
        // (Android `MeridianApplication.onCreate` initial sync). It mirrors ChronosFlow's
        // shared tasks/events into our store and reconciles reminders.
        let sync = InteropSyncManager(
            repository: TaskInteropRepository(context: modelContext)
        )
        interopSync = sync
        Task { await sync.syncFromPeer() }

        // Publish our first snapshot so the peer sees Meridian data without waiting for an
        // edit (Android's provider served fresh rows from the moment it was installed).
        let exporter = InteropExporter(repository: TaskInteropRepository(context: modelContext))
        interopExporter = exporter
        exporter.exportSnapshot()

        // Route reminder taps and App-Intent launches through the same handler as onOpenURL.
        notificationDelegate.onDeepLink = { url in
            if let link = MeridianDeepLink(url: url) { route(link) }
        }
        NotificationService.shared.installDelegate(notificationDelegate)
        MeridianIntentRouter.shared.install { link in route(link) }

        // Arm the first background refresh (the handler was registered in `MeridianApp.init`).
        BackgroundRefreshScheduler.shared.schedule()

        // Kick off Apple Watch sync (Android `WearSyncManager`). Self-wiring: activates the
        // WCSession, pushes an initial snapshot, and re-syncs on every SwiftData save.
        WatchSyncManager.shared.activate(modelContainer: MeridianApp.sharedModelContainer)
    }

    // MARK: - Deep-link routing

    /// Single navigation entry point shared by URL scheme, App Intents, and reminder taps.
    private func route(_ link: MeridianDeepLink) {
        if link.opensWorldCityPicker {
            worldCityPickerPending = true
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedTab = link.tab
        }
    }

    // MARK: - Onboarding

    private func completeOnboarding() {
        settingsRepo.setOnboardingComplete(true)
        withAnimation(.easeInOut(duration: 0.35)) {
            showOnboarding = false
        }
    }
}
