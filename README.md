# Nethead

[![CI](https://github.com/realworldbuilder/deadheadAI/actions/workflows/ci.yml/badge.svg)](https://github.com/realworldbuilder/deadheadAI/actions/workflows/ci.yml)

**A head who lives on the net.** Formerly Deadhead AI, then TapeTree — Nethead is the friend who has heard every tape the Internet Archive holds.
*First generation, straight from the source.*

A native SwiftUI iOS app that sits as an intelligence layer above the Internet Archive's Grateful Dead collection: AI-powered recommendations, natural-language search, per-show listening guides, era and song explorers, guided listening journeys, journals, self-curating collections, and a taste profile that learns your ears. Audio streams directly from archive.org via AVPlayer — the app never hosts or stores recordings.

## Building & running

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), an iOS 18+ simulator.

```bash
xcodegen generate                 # produces ShakedownAI.xcodeproj from project.yml
open ShakedownAI.xcodeproj        # build & run the ShakedownAI scheme
```

Or from the CLI:

```bash
xcodebuild -project ShakedownAI.xcodeproj -scheme ShakedownAI \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

xcodebuild -project ShakedownAI.xcodeproj -scheme ShakedownAI \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

All project configuration lives in `project.yml` — never edit the `.xcodeproj` by hand; rerun `xcodegen generate` after adding files.

### The brain

There are no API keys and no accounts. On iOS 26 with Apple Intelligence, Apple's on-device model writes the prose and runs the chat; on every other device the built-in offline knowledge base answers instead. Either way nothing you ask leaves the phone, and every pick is grounded in real tapes and real setlists.

### Building your own copy

- **Simulator**: `xcodegen generate` and the build commands above are all you need; pass `CODE_SIGNING_ALLOWED=NO` so no team is required. Sign in with Apple and iCloud sync fail on unsigned builds by design and fall back to a local account.
- **Your own phone or TestFlight**: change `DEVELOPMENT_TEAM` in [project.yml](project.yml) and [ExportOptions.plist](ExportOptions.plist) to your team, and set your own `PRODUCT_BUNDLE_IDENTIFIER` in project.yml (`com.deadhead.ai` is this project's App Store record and won't sign for another team). If you want iCloud sync, change the container in project.yml and [ShakedownAI/App/ShakedownAI.entitlements](ShakedownAI/App/ShakedownAI.entitlements) to `iCloud.<your bundle id>`, create it in the developer portal, and enable Sign in with Apple on your App ID; if you don't, delete both entitlements. `run-on-phone.sh` hardcodes the bundle ID for its launch step.
- **CI**: forks need no secrets. Tests run on every push; the TestFlight upload job skips itself until the App Store Connect secrets exist (see Releasing).

## Architecture

- **Swift 6** strict concurrency with `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` (approachable concurrency). Networking/parsing code opts out with `nonisolated`.
- **Provider protocols** (`ShakedownAI/Core/Providers/Providers.swift`): `LiveRecordingProvider`, `MetadataProvider`, `StreamingProvider`, `AIProvider`, `AuthProvider`, `SocialProvider`. Live implementations hit archive.org; mocks power previews, tests, and the demo social layer. Swap providers without touching UI.
- **Bundled show catalog** (`Core/Catalog/`, built by [tools/catalog-pipeline](tools/catalog-pipeline/README.md)): every show 1965–95 offline — real setlists with sets/encores/segues, every tape ranked with detected source type (SBD/MTX/FM/AUD), instant FTS search (`5-8-77`, venues, songs), browse by year and venue ("The Vault"), song performance histories, and per-show fan-consensus digests. `CatalogFirstShowProvider` answers locally first; the network fills in whatever the catalog doesn't know.
- **AI**: `CompositeAIProvider` (`Core/AI/CompositeAIProvider.swift`) tries `AppleOnDeviceAI` — Apple's free on-device Foundation Models brain, iOS 26 on Apple Intelligence hardware — on every call, and falls back to `LocalKnowledgeAI`: a deterministic offline brain built on the bundled knowledge base (`Resources/knowledge_base/*.json`: 67 curated shows, 49 song histories, 7 eras, 6 journeys, quotes). Prompts are grounded: the model only ever chooses among real archive candidates and real setlists.
- **Smart collections** (`Core/AI/SmartCollections.swift`, `SmartCollectionEngine.swift`): four shelves the app builds for itself and rebuilds whenever the day or the daypart turns over. A pure planner (`SmartCollectionPlanner`) reads the clock, the calendar (show anniversaries, song debuts, tour seasons), and listening trends (`TrendEngine`) into grounded briefs; the AI provider names each shelf and orders its picks, constrained to shows it was offered. Results cache in SwiftData per slot, and any shelf can be pinned into a real, editable collection.
- **Persistence**: SwiftData (`Core/Persistence/`) for metadata caches, journal, collections, listening history, taste profile, journey progress, and chat. Cache tables store opaque encoded domain structs; models never cross actor boundaries.
- **Audio**: `PlayerEngine` wraps an `AVQueuePlayer` with an explicit queue and a preloaded next track, so segues play gapless; sleep timer with fade-out, AirPlay picker, lock-screen ±15s skips, background audio, Now Playing info and remote commands, interruption handling. Listening events feed the taste engine. Siri App Intents ("play tonight's show") and a dormant CarPlay scene (pending Apple's entitlement) live in `Features/Intents/` and `Features/CarPlay/`.

## Releasing

Every push to `main` runs the test suite and, if it passes, archives a signed build and uploads it straight to TestFlight / App Store Connect ([ci.yml](.github/workflows/ci.yml)). Pull requests run tests only.

- **Ship an update**: merge/push to `main`. The build appears in App Store Connect → TestFlight a few minutes after the workflow finishes (Apple then takes a few more minutes to process it).
- **Build numbers** (`CFBundleVersion`) are stamped automatically from the workflow run number, so you never bump them by hand. The marketing version lives in [project.yml](project.yml) (`MARKETING_VERSION`) — bump it when you cut a new App Store version.
- **Go live on the App Store**: in App Store Connect, create the new version, pick the latest TestFlight build, and submit for review. The pipeline gets the binary there; the submit button stays human.

### One-time CI setup

The workflow signs with Xcode cloud-managed signing and authenticates with an App Store Connect API key — no certificates or profiles to export. It needs three repository secrets:

1. In [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api), generate a **Team key** with the **App Manager** role. Note the Key ID and Issuer ID and download the `.p8` file (one-time download).
2. Add the secrets:

```bash
gh secret set ASC_KEY_ID --repo realworldbuilder/deadheadAI
```

```bash
gh secret set ASC_ISSUER_ID --repo realworldbuilder/deadheadAI
```

```bash
gh secret set ASC_PRIVATE_KEY --repo realworldbuilder/deadheadAI < ~/Downloads/AuthKey_XXXXXXXXXX.p8
```

Until the secrets exist, the upload job skips itself with a warning; tests still run. Those three are the only secrets the project has.

## Debug hooks

- `--demo-autoplay` — streams the best Cornell '77 source on launch and logs player state to `subsystem ai.deadheads` (verify with `log show`).
- `--tab explore|chat|library|settings` — open on a specific tab.

## Notes

- Works fully offline; Apple's on-device model only upgrades prose and free-form chat.
- AI needs no key and no sign-in. Sign in with Apple only turns on iCloud sync of collections and journal entries (CloudKit private database). It needs a signed build with the `com.apple.developer.applesignin` and iCloud entitlements; on unsigned simulator builds the flow fails and falls back to the local on-device account with local-only saves.
- Friends & Listening Sessions are backed by `MockSocialProvider` — the protocol seam is where a real backend plugs in.
