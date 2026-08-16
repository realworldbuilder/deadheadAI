# Deadheads.AI

[![CI](https://github.com/realworldbuilder/deadheadAI/actions/workflows/ci.yml/badge.svg)](https://github.com/realworldbuilder/deadheadAI/actions/workflows/ci.yml)

**The Deadhead's AI companion.**
*The music never stopped. Neither should discovering it.*

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

### Bundling an OpenAI key (optional)

The app works without any key (offline brain), and users can paste their own in Settings. To bake a key into your own builds, copy [Config/Secrets.example.xcconfig](Config/Secrets.example.xcconfig) to `Config/Secrets.xcconfig` (gitignored — never commit a real key) and fill in your key. A user's Settings key always takes priority over the bundled one.

## Architecture

- **Swift 6** strict concurrency with `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` (approachable concurrency). Networking/parsing code opts out with `nonisolated`.
- **Provider protocols** (`ShakedownAI/Core/Providers/Providers.swift`): `LiveRecordingProvider`, `MetadataProvider`, `StreamingProvider`, `AIProvider`, `AuthProvider`, `SocialProvider`. Live implementations hit archive.org; mocks power previews, tests, and the demo social layer. Swap providers without touching UI.
- **AI**: `CompositeAIProvider` uses the OpenAI Responses API when a key is available (Settings → Keychain, or a build-time bundled key — see "Bundling an OpenAI key"), and falls back to `LocalKnowledgeAI` — a deterministic offline brain built on the bundled knowledge base (`Resources/knowledge_base/*.json`: 67 curated shows, 45 song histories, 7 eras, 6 journeys, quotes). Prompts are grounded: the model only ever chooses among real archive candidates and real setlists.
- **Smart collections** (`Core/AI/SmartCollections.swift`, `SmartCollectionEngine.swift`): four shelves the app builds for itself and rebuilds whenever the day or the daypart turns over. A pure planner (`SmartCollectionPlanner`) reads the clock, the calendar (show anniversaries, song debuts, tour seasons), and listening trends (`TrendEngine`) into grounded briefs; the AI provider names each shelf and orders its picks, constrained to shows it was offered. Results cache in SwiftData per slot, and any shelf can be pinned into a real, editable collection.
- **Persistence**: SwiftData (`Core/Persistence/`) for metadata caches, journal, collections, listening history, taste profile, journey progress, and chat. Cache tables store opaque encoded domain structs; models never cross actor boundaries.
- **Audio**: `PlayerEngine` wraps one AVPlayer with an explicit queue; background audio, lock-screen Now Playing info and remote commands, interruption handling. Listening events feed the taste engine.

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

Until the secrets exist, the upload job skips itself with a warning; tests still run.

Optionally, add an `OPENAI_API_KEY` secret to bundle an OpenAI key into TestFlight builds (see "Bundling an OpenAI key" above — anyone can extract a key from a distributed .ipa, so treat it as semi-public and set spending limits):

```bash
gh secret set OPENAI_API_KEY --repo realworldbuilder/deadheadAI
```

## Debug hooks

- `--demo-autoplay` — streams the best Cornell '77 source on launch and logs player state to `subsystem ai.deadheads` (verify with `log show`).
- `--tab explore|chat|library|settings` — open on a specific tab.

## Notes

- Works fully offline-of-OpenAI; an API key only upgrades prose and free-form chat.
- Sign in with Apple renders behind the `AuthProvider` seam but requires a signed build; the local on-device account is the default path.
- Friends & Listening Sessions are backed by `MockSocialProvider` — the protocol seam is where a real backend plugs in.
