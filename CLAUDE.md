# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Deadhead AI (repo name ShakedownAI) — a native SwiftUI iOS app (iOS 18+, Swift 6) that layers AI discovery over the Internet Archive's Grateful Dead collection. Audio streams from archive.org via AVPlayer; the app re-hosts no recordings, though users can save shows to the device for offline listening.

## Commands

The `.xcodeproj` is **generated** — all project config lives in [project.yml](project.yml). Never edit the `.xcodeproj` by hand; after adding/removing files or changing settings, run:

```bash
xcodegen generate
```

Build and test (simulator builds skip signing). The `OS=` pin matters: without it xcodebuild resolves `OS:latest`, and on hosts whose newest runtime has no iPhone 16 Pro device the build fails with "Unable to find a device". If 18.6 isn't installed, pick any installed pairing from `xcrun simctl list devices available`:

```bash
xcodebuild -project ShakedownAI.xcodeproj -scheme ShakedownAI \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project ShakedownAI.xcodeproj -scheme ShakedownAI \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  CODE_SIGNING_ALLOWED=NO test
```

Run a single test (Swift Testing framework, not XCTest):

```bash
xcodebuild -project ShakedownAI.xcodeproj -scheme ShakedownAI \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:ShakedownAITests/SmartCollectionTests test
```

Install on a physical iPhone: `./run-on-phone.sh` (plugged in, unlocked, trusted).

Debug launch arguments: `--demo-autoplay` (streams Cornell '77, logs to subsystem `ai.deadheads`), `--demo-download` (downloads Cornell '77 and logs progress, for verifying the offline pipeline from the CLI), `--tab explore|chat|library|settings`, `--stage-show` / `--stage-player` (open Cornell '77's show page / full-screen player for CLI screenshot capture), `--force-ai-gate` (exercise the locked AI gate in DEBUG builds).

## Releasing

Push to `main` → CI tests, then archives and uploads to TestFlight ([.github/workflows/ci.yml](.github/workflows/ci.yml)). PRs run tests only. `CFBundleVersion` is stamped from the CI run number — never bump it by hand; bump `MARKETING_VERSION` in project.yml for new App Store versions. The bundle ID must stay `com.deadhead.ai` (matches the App Store Connect record).

## Architecture

- **Swift 6 approachable concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` project-wide. Everything is MainActor by default; networking/parsing code opts out with `nonisolated`. Provider protocols are MainActor-isolated and `await` into the nonisolated networking layer.
- **Dependency injection**: `AppEnvironment` ([ShakedownAI/App/AppEnvironment.swift](ShakedownAI/App/AppEnvironment.swift)) is the single container, injected via `.environment(...)`. `AppEnvironment.live()` wires archive.org providers; `.mock()` wires in-memory mocks for previews/tests.
- **Provider seams** ([ShakedownAI/Core/Providers/Providers.swift](ShakedownAI/Core/Providers/Providers.swift)): `LiveRecordingProvider`, `MetadataProvider`, `StreamingProvider`, `AIProvider`, `AuthProvider`, `SocialProvider`. UI only talks to protocols. `ArchiveShowProvider` backs recording/metadata against archive.org with TTL caching; `MockSocialProvider` and `MockAuthProvider` back the demo social layer and local accounts — a real backend would plug in at those seams.
- **AI fallback chain**: `CompositeAIProvider` ([ShakedownAI/Core/AI/OpenAIResponsesAI.swift](ShakedownAI/Core/AI/OpenAIResponsesAI.swift)) tries three tiers per call, best first: the OpenAI Responses API when `KeychainStore.resolveAPIKey()` returns a key; then `AppleOnDeviceAI` ([ShakedownAI/Core/AI/AppleOnDeviceAI.swift](ShakedownAI/Core/AI/AppleOnDeviceAI.swift)), Apple's free on-device Foundation Models brain, when the device reports the model ready; then `LocalKnowledgeAI` — a deterministic offline brain over the bundled knowledge base (`ShakedownAI/Resources/knowledge_base/*.json`: curated shows, song histories, eras, journeys, quotes). The build-time bundled key (Info.plist `OpenAIAPIKey`) is gated behind Sign in with Apple: `resolveAPIKey()` returns nil until `KeychainStore.unlockAI()` runs, so locked users get the offline brain. DEBUG builds skip the gate (Apple sign-in can't complete in unsigned simulator builds); pass `--force-ai-gate` to exercise the locked UI. Prompts are grounded: the model only chooses among real archive candidates and real setlists. The app must remain fully functional with no key and no sign-in.
- **On-device AI**: `AppleOnDeviceAI` is gated behind `#if canImport(FoundationModels)` (so older Xcode still builds) and `@available(iOS 26.0, *)`, and needs Apple Intelligence hardware. It is a ~3B model with a ~4k context window, so its prompts are far tighter than the OpenAI ones and it selects candidates *by number* rather than reproducing archive identifiers. `OnDeviceAnswer` holds the small-model guard rails (index clamping, blank-optional handling, dropping invented song titles, filtering the stream's `"null"` placeholder); it lives outside the availability gate so it stays unit-testable on any simulator. Verify changes to it against a real iOS 26 simulator — the model is genuinely available there on Apple Silicon hosts.
- **Smart collections** (`Core/AI/SmartCollections.swift`, `SmartCollectionEngine.swift`): a pure planner (`SmartCollectionPlanner`) turns clock/calendar/listening trends into grounded briefs; the AI provider names each shelf and orders picks constrained to offered candidates. Results cache in SwiftData per day/daypart slot.
- **Persistence**: SwiftData stores in `Core/Persistence/` (cache, history/taste profile, library, smart collections, journeys). The container has two configurations (`ModelContainerFactory`): `default.store` for device-local models, and `shakedown-cloud.store` for `ShowCollection`/`CollectionItem`/`JournalEntry`, which opens with CloudKit private-database sync (`iCloud.com.deadhead.ai`) when a persisted Apple sign-in exists and local-only otherwise (never on simulator builds — without the runtime entitlement CloudKit traps asynchronously and uncatchably, so `ModelContainerFactory` forces sync off there) — same file either way, so flipping sync moves no data. Sign-in/out posts `.shakedownAuthChanged` and `ShakedownAIApp` rebuilds the whole `AppEnvironment` (container mode is fixed at creation). The synced models carry no unique constraints (CloudKit forbids them) — `LibraryStore.dedupAfterSync()` collapses duplicates deterministically at launch/foreground. `CloudStoreMigrator` one-time-copies legacy rows into the cloud store from a `pre-cloud-backup.store` file snapshot (flag `cloudStoreMigrationV1Done`). Cache tables hold opaque encoded domain structs; SwiftData models never cross actor boundaries — domain structs (`Core/Models/DomainModels.swift`) do.
- **Audio**: `PlayerEngine` (`Core/Audio/`) wraps a single AVPlayer with an explicit queue; handles background audio, lock-screen Now Playing, remote commands, interruptions. Listening events flow to `HistoryStore` via a callback set in `AppEnvironment`.
- **Offline downloads** (`Core/Downloads/`): `DownloadManager` drives a background `URLSession` (id `ai.deadheads.downloads`; relaunch events land in `App/AppDelegate.swift`) that saves a show's MP3s to `Application Support/Downloads/{identifier}/` (backup-excluded); `DownloadStore` (`Core/Persistence/`) indexes them in the local SwiftData store, persisting full `Show`/`RecordingDetail` snapshots so downloaded shows open with no network. Playback needs no player changes: `OfflineFirstStreamingProvider` decorates `ArchiveStreamingProvider` and returns the `file://` URL when a track is on disk. The live `URLSession` is cached process-globally (auth changes rebuild `AppEnvironment`, and duplicate background-session identifiers are an error); tests/previews inject an ephemeral session via `makeSession`. Downloads default to Wi-Fi-only (Settings toggle). ⚠️ Background download tasks fail instantly with `NSURLErrorDomain Code=-1 "unknown error"` in `CODE_SIGNING_ALLOWED=NO` builds (nsurlsessiond can't attribute the session) — to exercise downloads in the simulator, build *without* that flag (ad-hoc signing needs no account); unit tests are unaffected. Also: `URL.path()` returns a percent-encoded path that `FileManager` rejects (the store's paths contain spaces and literal `%`) — always use `path(percentEncoded: false)` for FileManager calls.

## Secrets

`Config/Secrets.xcconfig` is gitignored and optionally `#include?`d from `Config/Shared.xcconfig`; copy `Config/Secrets.example.xcconfig` to bundle an OpenAI key locally. CI injects `OPENAI_API_KEY` from a repo secret. Never commit a real key.
