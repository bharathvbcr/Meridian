# Meridian — iOS

Native iOS 27 port of the Meridian world-clock and meeting-planner app, built with
SwiftUI, SwiftData, and the latest Apple frameworks. Behavior and data match the
Android source of truth; the code is idiomatic Swift 6.

## Requirements

- Xcode 27 or later
- iOS 27 / watchOS 27 or later (device or simulator)
- Swift 6.0 (strict concurrency: `complete`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj`

## Generate and Open the Project

Meridian uses XcodeGen to produce `Meridian.xcodeproj` from `project.yml`, keeping
the repository free of bloated Xcode project files.

```bash
# Install XcodeGen (one-time)
brew install xcodegen

# Generate Meridian.xcodeproj from project.yml
cd ios
xcodegen generate

# Open in Xcode
open Meridian.xcodeproj
```

Then select the **Meridian** scheme, choose your simulator or device, and press
Run (Cmd-R). The scheme builds all three targets together.

> Set your Apple Developer team id in `project.yml` (`DEVELOPMENT_TEAM`) before
> running on a device — the App Group and (optional) App Attest entitlements require
> a provisioning profile.

## Targets

The project builds **three** targets, all sharing the App Group
`group.com.example.meridian`:

| Target | Product type | Purpose |
|--------|--------------|---------|
| **MeridianApp** | iOS application (`com.example.meridian`) | The full app: five screens, SwiftData store, EventKit/Contacts/CoreLocation integration, AI assistant, Live Activity manager. Embeds the widget extension and the watch app. |
| **MeridianWidget** | App extension (`com.example.meridian.widget`) | WidgetKit + ActivityKit: home-screen World Clock widget, Control Center "World times" control, and the EventCountdown Live Activity. Links only App-Group-safe code — never the view-model, EventKit/Contacts, or the AI stack. |
| **MeridianWatch** | watchOS app (`com.example.meridian.watchkitapp`) | Companion app: the phone's pinned-zone list (home zone badged) plus a countdown to the next event. Fed over WatchConnectivity. |

### Shared code (`ios/Shared/`)

- `SharedModels.swift` — `WatchSyncPayload` / `WatchZone` / `WatchEvent`, the
  Sendable + Codable wire types. Compiled into **app + watch**.
- `EventCountdownAttributes.swift` — the `ActivityAttributes` for the Live Activity.
  Compiled into **app + widget**.

The widget additionally compiles a hand-picked set of app sources
(`SharedZoneStore.swift`, `TimeFormats.swift`, `Models.swift` for the plain enums)
rather than the whole app tree, so the extension stays free of the `@MainActor`
view-model and the SwiftData `@Model` object graph it must not link.

## App Group setup

All three targets declare `group.com.example.meridian` in their `.entitlements`
files (`MeridianApp/Resources/Meridian.entitlements`,
`MeridianWidget/MeridianWidget.entitlements`, `MeridianWatch/MeridianWatch.entitlements`).
This single shared container backs:

- the SwiftData store, via `ModelConfiguration(groupContainer: .identifier("group.com.example.meridian"))`;
- the pinned-zone snapshot the widget reads (`SharedZoneStore`, written to the
  shared `UserDefaults` suite);
- the cross-app interop snapshot (`Interop/`).

If you change the App Group identifier, update it in **all three** entitlements
files, in `AppGroup.identifier` (`SharedZoneStore.swift`), and in
`InteropContract.appGroupIdentifier`.

## Bundled cities database

"Every city" location search (`GeoPlaceRepository`) is backed by a prebuilt
read-only SQLite database, `cities.db` (~211k cities from GeoNames + ~5.5k airports
from OpenFlights). It is **not** checked into the repository — build it and drop it
into `MeridianApp/Resources/` so XcodeGen copies it into the app bundle:

```bash
# From the Android repo root (host the generator there):
python tools/citygen/build_cities_db.py            # emits cities.db (schema version 2)
cp cities.db ios/MeridianApp/Resources/cities.db
```

The schema must expose `schema_meta(version)` matching `expectedVersion` (2) plus
the `city(name, name_lower, ascii_lower, zone, population)` and
`airport(iata, iata_lower, city, name, name_lower, zone)` tables. If the file is
absent or the version mismatches, search fails soft — the curated `PlaceIndex` and
raw IANA ids still resolve. The app links the system `sqlite3` library
(`OTHER_LDFLAGS = -lsqlite3`) and opens the bundle copy read-only — no
extract-to-writable-storage step is needed (unlike Android).

## Dual AI engine (user-selectable)

The AI screen runs on one of two engines, chosen in Settings (`MeridianSettings.aiEngine`):

- **On-device** (default, `.onDevice`) — Apple's Foundation Models
  (`LanguageModelSession`) with a deterministic rules fallback when no on-device
  model is available. Zero network calls.
- **Cloud** (`.cloud`) — Gemini. Only this branch touches the network, and only when
  an API key is configured via the `MERIDIAN_GEMINI_API_KEY` environment variable
  (`GeminiCloudClient.makeFromEnvironment()`). Absent a key, the engine falls back to
  on-device/rules.

In both engines the model never computes timestamps: it returns a `@Generable`
draft and `ScheduleParser` resolves the concrete date/time locally, fixing the
Android parity bug.

## Architecture

```
ios/
├── Package.swift              # SPM manifest (app target only; links sqlite3)
├── project.yml                # XcodeGen spec — 3 targets, App Group, entitlements
├── Shared/                    # Sendable wire types shared across targets
│   ├── SharedModels.swift
│   └── EventCountdownAttributes.swift
├── MeridianApp/
│   ├── App/                   # @main entry, ContentView (5-tab TabView), deep links
│   ├── Models/                # SwiftData @Model types + plain enums
│   ├── ViewModels/            # @Observable @MainActor MainViewModel
│   ├── Core/                  # FindOverlapUseCase, TimeEngine, AI/, Location/, Notify/
│   ├── Data/                  # SettingsRepository, ReminderScheduler, Calendar/Contacts
│   ├── DesignSystem/          # LiquidGlass / .glassEffect helpers, tokens
│   ├── Features/              # Now, WorldClock, Planner, AI, Settings, Onboarding
│   ├── Interop/               # Cross-app App Group snapshot (ChronosFlow peer)
│   ├── Services/              # LiveActivityManager, SharedZoneStore, WatchSyncManager, BG refresh
│   └── Resources/             # Info.plist, Meridian.entitlements, cities.db (bundled)
├── MeridianWidget/            # WidgetKit + ActivityKit extension
└── MeridianWatch/             # watchOS companion app
```

### Key patterns

- **SwiftUI + `@Observable`** — view models use the `@Observable` macro; no
  `ObservableObject` boilerplate.
- **SwiftData** — `@Model` classes replace the Android `DataStore`; the store is in
  the App Group container so the widget can read it.
- **Swift 6 strict concurrency** — `SWIFT_STRICT_CONCURRENCY = complete`; shared
  mutable state is `@MainActor`-isolated or `Sendable`.
- **iOS 27 Liquid Glass** — `.glassEffect` / `GlassEffectContainer` used
  unconditionally (no `#available` fallbacks).
- **Sendable formatting** — `Date.FormatStyle` everywhere, never `DateFormatter`.
