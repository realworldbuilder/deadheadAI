# App Store Submission Pack — Deadhead AI 1.0

Everything needed to submit in [App Store Connect](https://appstoreconnect.apple.com). Paste-ready copy is in code blocks. Items marked **TODO** need a decision or an asset from you.

---

## 1. Version setup

| Field | Value |
|---|---|
| App name (already on record) | Deadhead AI |
| Bundle ID | com.deadhead.ai |
| Version | 1.0 |
| Build | Latest from TestFlight (CI run — commit `416929a`, gated AI key) |
| Primary category | Music |
| Secondary category | Entertainment (optional) |
| Price | Free |

## 2. Metadata copy

**Subtitle** (30 chars max — this is exactly 30):

```
AI guide to live Grateful Dead
```

**Promotional text** (170 chars max, editable without review):

```
Thirty years of live Dead, one AI that knows every tape. Sign in with Apple for free AI access — for a limited time.
```

**Description** (4000 chars max):

```
The music never stopped. Neither should discovering it.

Deadhead AI is an intelligent companion for the Internet Archive's Grateful Dead collection — thousands of live recordings spanning 1965 to 1995, preserved by tapers and archivists over six decades. The app hosts no music; it adds the brain on top.

ASK FOR ANYTHING
Search in plain English: "mellow '73 for a rainy morning," "hottest Scarlet>Fire of the eighties," "what should I hear first?" The AI understands eras, venues, songs, and moods — and every answer is grounded in real recordings and real setlists.

A GUIDE FOR EVERY SHOW
Open any show and get a listening guide: what makes this night special, which songs to start with, how the tape sounds, what the crowd knew that night. Reviews and ratings from decades of listeners help pick the best source.

SMART COLLECTIONS THAT BUILD THEMSELVES
Shelves refresh through the day — show anniversaries, tour seasons, rising songs from your own listening, and picks tuned to your taste. Pin any shelf and it becomes a real collection you can edit.

JOURNEYS THROUGH THE CATALOG
Guided listening paths: the primal Dead of the sixties, the Europe '72 tour, the '77 peak, the MIDI years. Each journey walks you show by show with context along the way.

EXPLORE BY ERA AND SONG
Fly through thirty years of history era by era, or follow a single song — Dark Star, Playing in the Band, Eyes of the World — as it stretches and evolves across decades.

A TASTE PROFILE THAT LEARNS YOUR EARS
The more you listen, the better the recommendations get. Your history, journal, and profile live on your device.

BUILT FOR LISTENING
Background audio, lock screen controls, gapless queues, and streaming straight from archive.org. Setlists and metadata are cached so the app works offline; audio is never stored.

FREE AI, ON THE HOUSE
Sign in with Apple and the full AI brain is free for a limited time. No account? Everything still works — search, guides, journeys, and recommendations run on a curated offline knowledge base of essential shows, song histories, and eras.

Deadhead AI streams from the Internet Archive's Grateful Dead collection, where the band's long-standing taping tradition lives on. This app is an independent project and is not affiliated with the Grateful Dead, Rhino, or Warner Music.
```

**Keywords** (100 chars max — don't repeat words from the name; this is ~97):

```
grateful dead,jerry garcia,live music,setlist,jam band,tapes,archive,cornell,dicks picks,concert
```

**What's New** (first version):

```
First release. Hop on the bus.
```

## 3. URLs

| Field | Value |
|---|---|
| Support URL | **TODO** — simplest: `https://github.com/realworldbuilder/deadheadAI` (repo is public) or a GitHub Pages page with a contact email |
| Marketing URL (optional) | **TODO** — skip for 1.0 unless you have a site |
| Privacy Policy URL | **TODO — required.** A one-page policy hosted anywhere public (GitHub Pages works). It should state: everything (listening history, journal, taste profile, Apple sign-in name/ID) stays on the device; chat and search text is sent to OpenAI to generate responses and is not used to identify you; recordings stream from archive.org; no analytics, no ads, no tracking. |

## 4. App Privacy (Data Collection questionnaire)

The app has no backend and no analytics. The only data that leaves the device is the text of AI chats/searches, which goes to OpenAI's API to generate responses. Sign-in name and Apple user ID never leave the device (the auth layer is local).

Declare:

- **User Content → Other User Content** (the text of chat messages and AI searches)
  - Used for: **App Functionality**
  - Linked to identity: **No** (requests carry no user identifier)
  - Used for tracking: **No**
- Everything else: **not collected** (on-device only doesn't count as collection).

Result: privacy label shows "Data Not Linked to You — User Content."

## 5. Age rating questionnaire

Answer **None** to everything except:

- Alcohol, tobacco, or drug use or references: **Infrequent/Mild** (the era guides mention the Acid Tests and sixties history; AI chat can discuss band history)

Expected rating: **12+**. If the questionnaire asks about AI/chat features or unfiltered web content: the AI is topic-constrained to Grateful Dead history and recordings, has no web access, and produces no user-visible content from other users.

## 6. Content rights declaration

App Store Connect asks whether the app contains, shows, or accesses third-party content. Answer **Yes**, and confirm you have the rights — the basis:

- All audio streams directly from the Internet Archive's Grateful Dead collection (archive.org), which hosts these recordings publicly under the band's long-standing taper policy; soundboard/streaming rules are enforced by the Archive itself (stream-only where required).
- The app hosts, stores, and redistributes nothing; it links to and streams from the Archive the same way a browser does.
- Setlists, reviews, and metadata come from the same Archive items.

## 7. App Review notes (paste into "Notes" box)

```
Deadhead AI is a client for the Internet Archive's Grateful Dead collection (archive.org/details/GratefulDead). All audio streams directly from archive.org; the app hosts and stores no recordings. The Grateful Dead have permitted audience taping and free trading of their live recordings since the 1970s, and the Internet Archive hosts this collection publicly in cooperation with the band's representatives — the Archive enforces the streaming rules per recording. The app is an independent project, clearly disclaimed as unaffiliated in the description.

SIGN-IN IS OPTIONAL. No demo account is needed. Tap "Hop on the Bus" on the welcome screen for full access to every feature without any account. Sign in with Apple only unlocks the hosted AI mode (server-generated prose via OpenAI); without it, recommendations, search, show guides, and journeys run on the app's built-in offline knowledge base.

AI content: chat and recommendations are grounded — the AI only recommends real recordings from the Archive and quotes real setlists. It has no web access and is scoped to Grateful Dead history and music.

To test playback quickly: open any show from the home screen and tap a track; audio streams from archive.org (network required).
```

## 8. Screenshots

Required: **6.9" display set** (1320 × 2868 px portrait, from an iPhone 17 Pro Max / 16 Pro Max simulator). Apple scales these down for smaller sizes; iPad shots are not needed (iPhone-only app, `TARGETED_DEVICE_FAMILY: 1`).

Suggested five shots (in this order — first two matter most):

1. Home screen with smart collection shelves (the "wow" shot — space background + shelves)
2. Chat answering something evocative ("best Scarlet>Fire of the seventies?")
3. A show detail page with the AI listening guide
4. Era explorer or the Explore constellation
5. Full-screen player with a show playing

Grab them from the booted simulator with:

```bash
xcrun simctl io booted screenshot shot1.png
```

(Ask me and I'll launch the app in the simulator, stage each screen, and capture the full set.)

## 9. Remaining App Store Connect checkboxes

- **Export compliance**: already handled — `ITSAppUsesNonExemptEncryption: false` is in the Info.plist, so no prompt should appear.
- **Advertising Identifier (IDFA)**: No.
- **Sign in with Apple**: nothing extra to declare; the entitlement is in the build.
- **App Store Connect → App Information → License Agreement**: default Apple EULA is fine.
- **Copyright field**: `2026 William Hussey` (or your entity name).

## 10. Pre-submit checklist

- [ ] Latest TestFlight build finished processing and is selectable
- [ ] Install that exact build from TestFlight on a real phone; complete Sign in with Apple once and confirm Settings shows "Deadhead AI connected"; also confirm "Hop on the Bus" alone leaves the offline brain active
- [ ] OpenAI spending limit set (the bundled key ships in the binary — treat as semi-public)
- [ ] Privacy policy URL live and pasted in
- [ ] Support URL pasted in
- [ ] Screenshots uploaded (6.9" set)
- [ ] Privacy questionnaire answered per §4, age rating per §5
- [ ] Review notes from §7 pasted
- [ ] Submit
