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

**Promotional text** (170 chars max, editable without review — this is ~152, and it echoes the app's own chat greeting):

```
It's heard every tape and read every review — decades of comment-section wisdom from real tapers and heads, in your pocket. Free AI with Apple sign-in.
```

**Description** (4000 chars max):

```
The music never stopped. Neither should discovering it.

You know how it goes. Somebody says "man, you GOTTA hear 5/8/77" and suddenly it's 3am, you're six shows deep, and Jerry is peeling the paint off some field house in 1974. The Internet Archive holds thousands of tapes — auds, boards, matrixes, thirty years of the boys cooking — and the only map has ever been the heads in the comment section.

Deadhead AI puts one of those heads in your pocket. The app hosts no music. It just knows the road.

IT READS THE COMMENT SECTION
For twenty years, picking a tape has meant scrolling the reviews under every show — tapers talking mic placement, heads naming the minute the X-factor arrives, somebody who was on the floor settling the argument. Deadhead AI reads all of it: every rating, every source note, every review on every recording feeds its answers, and the real reviews sit right on the show page. When it tells you which Cornell source to trust, it's channeling the people who were there.

ASK LIKE YOU'D ASK THE RAIL
"Mellow '73 for a rainy Sunday." "Hottest Scarlet>Fire of the eighties." "Five hour drive — build me a second set that never lands." Plain English in, real tapes out. Every answer is grounded in real recordings and real setlists. No hallucinated bootlegs, ever.

A GUIDE FOR EVERY SHOW
Open any night and get the story: why this one matters, which source to spin, what the crowd knew before the rest of the world did. The tapers' and heads' ratings pick the best tape of the night — the way it's always been done, just faster.

SHELVES THAT BUILD THEMSELVES
Anniversaries, tour seasons, songs rising out of your own listening. Smart shelves refresh through the day like a friend who keeps taping things for you. Pin one and it's yours to keep and edit.

JOURNEYS THROUGH THE CATALOG
Primal '68 weirdness. Europe '72. The '77 peak. The MIDI years (respect the MIDI years). Guided paths walk you show by show with the context the liner notes never gave you.

EXPLORE BY ERA AND SONG
Fly through thirty years era by era, or chase one song — Dark Star, Playing in the Band, Eyes of the World — as it stretches from three minutes to thirty across the decades.

A TASTE PROFILE THAT LEARNS YOUR EARS
The more you spin, the better the recs get. Your history, journal, and profile live on your device — nobody's reading your trip diary.

BUILT FOR LISTENING
Background audio, lock screen controls, gapless queues, streaming straight from archive.org. Setlists and metadata are cached so the app works offline; audio is never stored.

FREE AI, ON THE HOUSE
Sign in with Apple and the full AI brain is free — and your shelves and journal ride along in your own iCloud. No account? Everything still works on a curated offline knowledge base of essential shows, song histories, and eras. Hop on the bus either way.

Deadhead AI streams from the Internet Archive's Grateful Dead collection, where the band's long-standing taping tradition lives on. This app is an independent project and is not affiliated with the Grateful Dead, Rhino, or Warner Music.
```

**Keywords** (100 chars max — don't repeat words from the name; this is ~97):

```
grateful dead,jerry garcia,live music,setlist,jam band,tapes,archive,cornell,dicks picks,concert
```

**What's New** (first version):

```
First release. See you on the rail.
```

## 3. URLs

All three live on GitHub Pages (`docs/` on main → https://realworldbuilder.github.io/deadheadAI/):

| Field | Value |
|---|---|
| Support URL | `https://realworldbuilder.github.io/deadheadAI/support.html` |
| Marketing URL (optional) | `https://realworldbuilder.github.io/deadheadAI/` |
| Privacy Policy URL | `https://realworldbuilder.github.io/deadheadAI/privacy.html` |

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
- **Sign in with Apple**: nothing extra to declare; the entitlement is in the build. It now also enables iCloud sync of collections and journal entries (CloudKit private database, container `iCloud.com.deadhead.ai`).
- **App Store Connect → App Information → License Agreement**: default Apple EULA is fine.
- **Copyright field**: `2026 William Hussey` (or your entity name).

## 10. Pre-submit checklist

- [ ] **CloudKit schema deployed to Production** (CloudKit Console → `iCloud.com.deadhead.ai` → Deploy Schema Changes). TestFlight/App Store builds use the Production environment; without this, sync silently fails. Redo after any synced-model change.
- [ ] Latest TestFlight build finished processing and is selectable
- [ ] Install that exact build from TestFlight on a real phone; complete Sign in with Apple once and confirm Settings shows "Deadhead AI connected"; also confirm "Hop on the Bus" alone leaves the offline brain active
- [ ] OpenAI spending limit set (the bundled key ships in the binary — treat as semi-public)
- [ ] Privacy policy URL live and pasted in
- [ ] Support URL pasted in
- [ ] Screenshots uploaded (6.9" set)
- [ ] Privacy questionnaire answered per §4, age rating per §5
- [ ] Review notes from §7 pasted
- [ ] Submit
