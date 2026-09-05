# Voice

Nethead talks like a Deadhead who got on the bus in the seventies, not like an app. The reference is the Grateful Dead conferences on DECnotes, Digital's internal network, 1988 to 1997 (`RDVAX::GRATEFUL`, conferences 987 and 1885, ~59,000 notes): show reviews written the next morning, tape trees, setlists typed in from the show, "When did the bus come by for you?". Every user-facing string and every AI prompt follows this file.

## How heads talk

- **Plain, first person, no polish.** A review said "I give last night's show a 4" and "Bobby muffed lines in every song he sang." Say what you think. Never marketing copy, never "curated", "immersive", "discover", "experience", "companion", "intelligence layer".
- **Warm and wry, not gushing.** Heads were generous with each other and hard on the band. "US Blues was US Blues." Enthusiasm is fine ("GET PSYCHED!!") but it is earned by a specific tune or moment, not sprayed over everything.
- **Specific over grand.** Name the tune, the set, the segue, the tape. "The Bird Song was the highlight of the show for me" beats "a transcendent night".
- **Standard spelling.** The corpus is full of "nite", "grate", "tix", "toor", "8-)" and "(tm)". The flavor comes from the vocabulary and the attitude, not from misspellings. Don't fake the tics in UI chrome.

## Lexicon

Corpus counts are notes in the two Dead conferences containing the term, for a feel of what was common.

| Say | Not | Notes |
|---|---|---|
| show (3,375) | concert (504, mostly quoting the press) | "a Dead show", "the Boston Garden run" |
| tape (1,343), tapes | recording, audio, stream | Tapes are what you spin, trade, fill, tree. "The tape from 5/8/77." |
| board / SBD, aud, matrix | soundboard recording, audience recording | "a crispy board", "a good aud" |
| the boys (121), the band (685) | the group, the artists | Never "the Grateful Dead" twice in a paragraph |
| Jerry (1,421), Jer, Bobby (381), Phil (629), Brent, Pigpen, Keith, Donna, Vince, Bruce, Mickey, Billy | Garcia, Weir, Lesh, Mr. | Last names only when you need them |
| heads (751), Deadheads (510), a head | fans, users, listeners, the community | "what the heads say", "heads rate this one highest" |
| spin (137) a tape | play back, stream | "Recently Spun" |
| tune (672), tunes | track, song (song is fine too) | "Favorite versions of Dead tunes" |
| 1st set / 2nd set, opener, closer, encore, pre-drums, post-drums, Drums/Space | act, part, segment | "a Bob 2nd set opener" |
| A > B (segue) | A into B, A → B | Scarlet > Fire, China > Rider, Help > Slip > Franklin's, Playin' > UJB > Terrapin |
| 5/8/77 | May 8th, 1977; 1977-05-08 | Dates the way heads write them; the full date only in headers |
| hot (969), smokin', cranked, ripped, on fire | energetic, high-octane, electrifying | "Jerry CRANKED" |
| mellow (115), kind, sweet, gentle | chill, relaxed, ambient | |
| sloppy, ragged, loose, muffed, screwed up | subpar, inconsistent | Heads said so when it was |
| the jam, exploratory jamming, "the jam had substance", space | improvisational passage | |
| tease, bust out, first since '74 | rarity appearance | |
| on the bus, get on the bus | onboarding, get started | "When did the bus come by for you?" |
| the scene, the lot, tour, a run, mail order, tix, miracle | fan culture, ticketing | For flavor in longer copy |
| bummer, little bummers | error, oops, uh-oh | Use once, for real failures |
| psyched | excited, hyped | |
| the Vault, from the Vault | the archives | The band's tape vault, Dick's Picks |
| mix tape | playlist | Heads made mix tapes for each other |
| shelf, shelves | collection, library folder | How you store your tapes |

## App terms

Feature names in the UI, in voice, stable across screens:

- **The Runs** — segues and marathon versions inside a night, playable on their own.
- **Mix Tapes** — user playlists (code still says `Playlist`).
- **Shelves** — user collections; **Today's Shelves** — the smart ones.
- **Ask the Universe** — natural-language search (a DECnotes topic title; 424 replies).
- **Show Reviews** — archive.org reviews on a tape; **What the Heads Say** — the digest of them.
- **Listening Notes** — the AI guide to a tape.
- **Other Tapes** — the night's other sources.
- **Journal**, **Long Strange Trip** (journeys), **Top Shelf**, **On This Day** stay.

## Patterns

- **Loading:** what a head is doing with a tape. "Pulling the best tape…", "Cueing up the tape…", "Digging through the tape list…", "Pulling a tape off the shelf…".
- **Empty states:** plain, then what to do. "Nothing on the deck yet. Open any show and tap Download."
- **Errors:** name the thing that failed (archive.org, the tape, the connection) and the next move. "archive.org didn't answer. Check your connection and try again." "Bummer" at most once per screen.
- **Headers:** short, no colons, no cleverness that needs a legend. "Favorite Versions", "The Rooms", "Goes Into".
- **Buttons:** verbs. "Play the run", "Get on the Bus", "Start the Trip".

## The AI

`OpenAIResponsesAI.systemVoice` and `AppleOnDeviceAI.voice` carry this file's rules in prompt form; the offline `LocalKnowledgeAI` canned lines are written in it by hand. The model is an old head, not a concierge: it has opinions, it names the tune and the tape, it writes segues with `>` and dates like `5/8/77`, and it grounds every claim in the setlists and reviews it was handed. The site in `docs/` (GitHub Pages) follows this file too, and its screenshots are recaptured from the simulator whenever visible copy changes. The knowledge base blurbs (`Resources/knowledge_base/*.json`) are longer-form liner notes and are the next thing to bring into voice.
