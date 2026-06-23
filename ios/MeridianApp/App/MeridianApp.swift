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
        // VERIFY: ModelConfiguration(groupContainer:) — available since iOS 17, current on iOS 27.
        let groupConfig = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier)
        )
        do {
            return try ModelContainer(for: schema, configurations: [groupConfig])
        } catch {
            // Last-resort fallback so a bad entitlement does not hard-crash the app.
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
    /// Strong reference to the notification delegate (the center holds it weakly).
    @State private var notificationDelegate = NotificationDelegate()
    /// Cross-app (ChronosFlow) sync manager — SwiftData-backed; built once in `bootstrap`.
    @State private var interopSync: InteropSyncManager?

    // MARK: Body

    var body: some View {
        Group {
            if let viewModel {
                ContentView(viewModel: viewModel, selectedTab: $selectedTab)
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
                Color(red: 0.008, green: 0.024, blue: 0.090)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .tint(Color(red: 0.376, green: 0.804, blue: 1.0))
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
        WatchSyncManager.shared.activate(modelContainer: Self.sharedModelContainer)
    }

    // MARK: - Deep-link routing

    /// Single navigation entry point shared by URL scheme, App Intents, and reminder taps.
    private func route(_ link: MeridianDeepLink) {
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
