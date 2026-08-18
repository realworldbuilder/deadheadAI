# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Deadhead AI (repo name ShakedownAI) — a native SwiftUI iOS app (iOS 18+, Swift 6) that layers AI discovery over the Internet Archive's Grateful Dead collection. Audio streams from archive.org via AVPlayer; the app hosts no recordings.

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

Debug launch arguments: `--demo-autoplay` (streams Cornell '77, logs to subsystem `ai.deadheads`), `--tab explore|chat|library|settings`, `--stage-show` / `--stage-player` (open Cornell '77's show page / full-screen player for CLI screenshot capture), `--force-ai-gate` (exercise the locked AI gate in DEBUG builds).

## Releasing

Push to `main` → CI tests, then archives and uploads to TestFlight ([.github/workflows/ci.yml](.github/workflows/ci.yml)). PRs run tests only. `CFBundleVersion` is stamped from the CI run number — never bump it by hand; bump `MARKETING_VERSION` in project.yml for new App Store versions. The bundle ID must stay `com.deadhead.ai` (matches the App Store Connect record).

## Architecture

- **Swift 6 approachable concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` project-wide. Everything is MainActor by default; networking/parsing code opts out with `nonisolated`. Provider protocols are MainActor-isolated and `await` into the nonisolated networking layer.
- **Dependency injection**: `AppEnvironment` ([ShakedownAI/App/AppEnvironment.swift](ShakedownAI/App/AppEnvironment.swift)) is the single container, injected via `.environment(...)`. `AppEnvironment.live()` wires archive.org providers; `.mock()` wires in-memory mocks for previews/tests.
- **Provider seams** ([ShakedownAI/Core/Providers/Providers.swift](ShakedownAI/Core/Providers/Providers.swift)): `LiveRecordingProvider`, `MetadataProvider`, `StreamingProvider`, `AIProvider`, `AuthProvider`, `SocialProvider`. UI only talks to protocols. `ArchiveShowProvider` backs recording/metadata against archive.org with TTL caching; `MockSocialProvider` and `MockAuthProvider` back the demo social layer and local accounts — a real backend would plug in at those seams.
- **AI fallback chain**: `CompositeAIProvider` ([ShakedownAI/Core/AI/OpenAIResponsesAI.swift](ShakedownAI/Core/AI/OpenAIResponsesAI.swift)) tries the OpenAI Responses API when `KeychainStore.resolveAPIKey()` returns a key, and falls back per-call to `LocalKnowledgeAI` — a deterministic offline brain over the bundled knowledge base (`ShakedownAI/Resources/knowledge_base/*.json`: curated shows, song histories, eras, journeys, quotes). The build-time bundled key (Info.plist `OpenAIAPIKey`) is gated behind Sign in with Apple: `resolveAPIKey()` returns nil until `KeychainStore.unlockAI()` runs, so locked users get the offline brain. DEBUG builds skip the gate (Apple sign-in can't complete in unsigned simulator builds); pass `--force-ai-gate` to exercise the locked UI. Prompts are grounded: the model only chooses among real archive candidates and real setlists. The app must remain fully functional with no key and no sign-in.
- **Smart collections** (`Core/AI/SmartCollections.swift`, `SmartCollectionEngine.swift`): a pure planner (`SmartCollectionPlanner`) turns clock/calendar/listening trends into grounded briefs; the AI provider names each shelf and orders picks constrained to offered candidates. Results cache in SwiftData per day/daypart slot.
- **Persistence**: SwiftData stores in `Core/Persistence/` (cache, history/taste profile, library, smart collections, journeys). The container has two configurations (`ModelContainerFactory`): `default.store` for device-local models, and `shakedown-cloud.store` for `ShowCollection`/`CollectionItem`/`JournalEntry`, which opens with CloudKit private-database sync (`iCloud.com.deadhead.ai`) when a persisted Apple sign-in exists and local-only otherwise (never on simulator builds — without the runtime entitlement CloudKit traps asynchronously and uncatchably, so `ModelContainerFactory` forces sync off there) — same file either way, so flipping sync moves no data. Sign-in/out posts `.shakedownAuthChanged` and `ShakedownAIApp` rebuilds the whole `AppEnvironment` (container mode is fixed at creation). The synced models carry no unique constraints (CloudKit forbids them) — `LibraryStore.dedupAfterSync()` collapses duplicates deterministically at launch/foreground. `CloudStoreMigrator` one-time-copies legacy rows into the cloud store from a `pre-cloud-backup.store` file snapshot (flag `cloudStoreMigrationV1Done`). Cache tables hold opaque encoded domain structs; SwiftData models never cross actor boundaries — domain structs (`Core/Models/DomainModels.swift`) do.
- **Audio**: `PlayerEngine` (`Core/Audio/`) wraps a single AVPlayer with an explicit queue; handles background audio, lock-screen Now Playing, remote commands, interruptions. Listening events flow to `HistoryStore` via a callback set in `AppEnvironment`.

## Secrets

`Config/Secrets.xcconfig` is gitignored and optionally `#include?`d from `Config/Shared.xcconfig`; copy `Config/Secrets.example.xcconfig` to bundle an OpenAI key locally. CI injects `OPENAI_API_KEY` from a repo secret. Never commit a real key.
