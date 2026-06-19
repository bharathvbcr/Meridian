<div align="center">

<img src="store_assets/ic_launcher_512.png" width="120" alt="Meridian app icon" />

# Meridian — Time & World Planner

</div>

A Kotlin + Jetpack Compose Android app for **local time, world time, multi-zone planning, and
AI-assisted scheduling**, built on a bold **Material 3 Expressive** content layer wearing an
**Apple-style Liquid Glass** navigation surface (Haze blur + an AGSL refraction pass).

See [`docs/adr`](docs/adr) for the key architectural decisions.

<div align="center">
<img src="store_assets/screenshots/screenshot_world.png" width="200" alt="World map" />
<img src="store_assets/screenshots/screenshot_plan.png" width="200" alt="Meeting planner" />
<img src="store_assets/screenshots/screenshot_ai.png" width="200" alt="AI assistant" />
</div>

## What's implemented

- **Now** — live local clock with locale-aware 12/24h formatting and a pinned-zone board.
- **World** — a 2D equirectangular **day/night terminator** map (correct solar geometry), per-zone
  sun times, and a one-tap **home zone**, all driven by the shared time **scrubber** (`scrubInstant`).
- **World (3D)** — toggle to an asset-free **orthographic globe** (day/night shading, drag-to-spin,
  visible-hemisphere pins) that auto-drops to 2D under battery saver / low-RAM.
- **Plan** — a real **meeting planner**: add participant zones *and named people*, each with their
  own **working hours + do-not-disturb** window; pick a date and duration and get fairness-ranked
  slots annotated with everyone's local time and an awake/working/asleep tag. Create a zone-aware
  calendar event, share an RFC-5545 `.ics` invite, or generate a **rotating weekly series** that
  spreads the inconvenient hour between regions. Picking a slot schedules a reminder.
- **AI** — an **on-device** assistant (Gemini Nano via Firebase AI Logic, with automatic cloud
  fallback) that drafts events; writes only after an explicit confirm step, with schema/zone
  validation. Each reply is badged with where it ran (on-device vs cloud).
- **Settings** — DataStore-persisted clock format, glass compositor toggle, reduce-transparency
  override, and a privacy-friendly **location → home zone** resolver, all wired into the live UI.
- **Adaptive** — a floating glass bottom bar on phones, a glass navigation rail on tablets/foldables.
- **Surfaces** — a Glance home-screen world-clock board, a Quick Settings **world-times tile**,
  launcher **shortcuts** + `meridian://` deep links, exact-alarm **reminders**, an ongoing
  **Live Update** countdown to your next event, and a standalone **Wear OS tile** (`:wear` module).

The deterministic time/solar/fairness/rotation engine in `core/time` is unit-tested with an injected
`Clock`, and a Roborazzi **screenshot test** guards a design-system component. CI
(`.github/workflows/ci.yml`) runs the tests and assembles the APK on every push/PR.

## Run locally

**Prerequisites:** JDK 17+ and the Android SDK (compileSdk 36), with `ANDROID_HOME` (or a
`local.properties` with `sdk.dir`) configured. minSdk 26.

```bash
./gradlew :app:assembleDebug        # build the debug APK
./gradlew :app:installDebug         # build and install on a connected device/emulator
./gradlew :app:testDebugUnitTest    # run the unit test suite
```

The AI tab needs no API key — it runs on-device on Gemini-Nano-capable hardware. For the cloud
fallback on other devices, add your own Firebase `app/google-services.json` (excluded from this
repo); without it the app still builds and runs with the on-device path.
