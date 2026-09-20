# App Store Submission Pack — Nethead 1.0

Everything needed to submit in [App Store Connect](https://appstoreconnect.apple.com). Paste-ready copy is in code blocks. Items marked **TODO** need a decision or an asset from you.

---

## 1. Version setup

| Field | Value |
|---|---|
| App name | Nethead (rename the record from Deadhead AI / TapeTree in App Information → Name) |
| Bundle ID | com.deadhead.ai |
| Version | 1.0 |
| Build | Latest CI upload from `main` (the run that lands the account-deletion PR; check the build number in the Archive step log, `CFBundleVersion = …`) |
| Primary category | Music |
| Secondary category | Entertainment (optional) |
| Price | Free |

## 2. Metadata copy

**Subtitle** (30 chars max — this is exactly 30):

```
AI guide to live Grateful Dead
```

**Promotional text** (170 chars max, editable without review — this is ~150, and it echoes the app's own chat greeting):

```
It's heard every tape and read every review — decades of comment-section wisdom from real tapers and heads, in your pocket. No account, no key, nothing sent anywhere.
```

**Description** (4000 chars max):

```
The music never stopped. Neither should discovering it.

You know how it goes. Somebody says "man, you GOTTA hear 5/8/77" and suddenly it's 3am, you're six shows deep, and Jerry is peeling the paint off some field house in 1974. The Internet Archive holds thousands of tapes — auds, boards, matrixes, thirty years of the boys cooking — and the only map has ever been the heads in the comment section.

Nethead puts one of those heads in your pocket. The app hosts no music. It just knows the road.

IT READS THE COMMENT SECTION
For twenty years, picking a tape has meant scrolling the reviews under every show — tapers talking mic placement, heads naming the minute the X-factor arrives, somebody who was on the floor settling the argument. Nethead reads all of it: every rating, every source note, every review on every recording feeds its answers, and the real reviews sit right on the show page. When it tells you which Cornell source to trust, it's channeling the people who were there.

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

THE BRAIN LIVES ON THE PHONE
No account, no key, no server in the loop. On iPhones with Apple Intelligence, Apple's on-device model does the talking; everywhere else a curated offline knowledge base of essential shows, song histories, and eras answers instead. Either way nothing you ask leaves the phone.

SHELVES THAT FOLLOW YOU
Sign in with Apple and your shelves are the same on every phone and on the notesfile, Nethead's home on the web. Skip it and everything still works — just ride along.

Nethead streams from the Internet Archive's Grateful Dead collection, where the band's long-standing taping tradition lives on. This app is an independent project and is not affiliated with the Grateful Dead, Rhino, or Warner Music.
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

No analytics, no ads, no trackers. AI runs on the phone (Apple's on-device model on iOS 26, the built-in knowledge base elsewhere). Signed out, the only network traffic is archive.org for the tapes. **Signed in with Apple, the app creates an account on the notesfile** (our Cloudflare Worker, `nethead.nethead-web.workers.dev`) and keeps the user's shelves there — that is collection, and it has to be declared.

Answer **Yes, we collect data from this app**, then declare exactly these three, each with *Linked to the user: Yes*, *Used for tracking: No*, purpose **App Functionality** only:

| Data type | Category | What it actually is |
|---|---|---|
| **User ID** | Identifiers | Apple's per-app user identifier (`sub`) and the notesfile account id |
| **Name** | Contact Info | The given name Apple shares at first sign-in, used once to seed the handle (e.g. `BUS::WILL`) |
| **Other User Content** | User Content | Shelves: their names and the show identifiers on them |

Everything else (listening history, taste profile, journal, mix tapes, chat, downloads, device data, diagnostics): **not collected**. The privacy policy at the URL in §3 says the same, in the same words, and names the in-app deletion path.

Result: privacy label shows "Data Linked to You: Identifiers, Contact Info, User Content" for App Functionality.

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
Nethead is a client for the Internet Archive's Grateful Dead collection (archive.org/details/GratefulDead). All audio streams directly from archive.org; the app hosts and stores no recordings. The Grateful Dead have permitted audience taping and free trading of their live recordings since the 1970s, and the Internet Archive hosts this collection publicly in cooperation with the band's representatives — the Archive enforces the streaming rules per recording. The app is an independent project, clearly disclaimed as unaffiliated in the description.

SIGN-IN IS OPTIONAL. No demo account is needed. Tap "Just ride along" on the welcome screen for full access to every feature without any account. Sign in with Apple creates an account on our server (nethead.nethead-web.workers.dev) whose only purpose is keeping the user's saved shelves the same across devices; it stores the Apple user identifier, a handle, and the shelves — nothing else. Account deletion is in the app: Settings → Account → "Leave the Bus" erases the account and everything stored under it immediately (Guideline 5.1.1(v)). AI runs on the device either way: Apple's on-device model on iOS 26, the app's built-in offline knowledge base everywhere else.

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
- **Sign in with Apple**: nothing extra to declare; the entitlement is in the build (the only one — CloudKit and push were removed). Account deletion (5.1.1(v)) is in Settings → Account → Leave the Bus, backed by `POST /api/delete` on the Worker. Follow-up, not needed for review: revoking the Apple token on deletion via Apple's `auth/revoke` endpoint needs a Sign in with Apple key (.p8) stored as a Worker secret.
- **App Store Connect → App Information → License Agreement**: default Apple EULA is fine.
- **Copyright field**: `2026 William Hussey` (or your entity name).

## 10. Pre-submit checklist

- [ ] **Worker deployed from current `main`** (`cd web && npm run deploy`) so `POST /api/delete` is live before the reviewed build is; then `curl https://nethead.nethead-web.workers.dev/api/apple/nonce` answers JSON. Reviewers tap Leave the Bus.
- [ ] Latest TestFlight build finished processing and is selectable
- [ ] Install that exact build from TestFlight on a real phone; complete Sign in with Apple once, make a shelf, see it on your notesfile page; then Settings → Account → Leave the Bus and confirm the head is gone on the web (and a fresh sign-in makes a new one); confirm Settings → The Brain reads "On-device brain running" on an Apple Intelligence phone and "Offline brain active" elsewhere
- [ ] Privacy policy URL live and pasted in
- [ ] Support URL pasted in
- [ ] Screenshots uploaded (6.9" set)
- [ ] Privacy questionnaire answered per §4, age rating per §5
- [ ] Review notes from §7 pasted
- [ ] Submit
