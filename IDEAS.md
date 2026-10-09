# Hacklanta Ideas

Single source of truth for our hackathon ideas. Humans and Claude agents both read and write here.

## Instructions for Claude agents
- Read this whole file before answering anything about ideas, scope, or what to build.
- **Append, don't rewrite.** Add new ideas under `## Ideas` using the template. Only edit an entry if its `Owner` is the current user or they ask you to.
- Never delete another dev's idea. To disagree, add a bullet under that idea's `Notes / feedback`.
- Keep entries short and concrete. Speed matters more than polish (hackathon).
- Once an idea is chosen, record it in the `Decision log` and set its status to `chosen`. Build work then moves to code; this file stays the reference for scope.
- If a fact needs a source, link it. Mark anything unverified as `(unverified)`.

## Hackathon context
- **Theme / direction:** connecting people through shared music taste
- **Time limit:** TBD
- **Team size:** TBD
- **Judging criteria:** TBD
- **Required tech / sponsors:** TBD

## Research summary (as of 2026-10-09)

### Existing players
| Company | What it does | Funding / stage |
|---|---|---|
| [Airbuds](https://finder.techleap.nl/news/feed/airbuds-raises-5m-challenges-music-giants) | Widget showing what friends play; surfaces friends with similar taste; weekly recaps | ~$10M total (a16z, Seven Seven Six); ~5M MAU reported. Biggest in the niche |
| [makromusic](https://apps.apple.com/us/app/makromusic-dating-for-spotify/id1498773489) | Dating/friend matching from Spotify, YouTube Music, Apple Music | Small |
| [Vinylly](https://www.okayplayer.com/originals/vinylly-dating-app-spotify.html) | Dating app matching on Spotify data plus questions | Small |
| [Meet Music](https://play.google.com/store/apps/details?id=com.meetthemusicapp&hl=en_US) | Anonymous chat with people playing the same song | Small |
| [Turn Up](https://turn-up.app/) | "Dates" and "friends" modes, concert/festival buddies | Small |
| [Tastebuds.fm](https://www.prnewswire.co.uk/news-releases/tastebudsfm-raises-600k-seed-round-to-help-people-meet-through-music-203549411.html) | Meet people by favorite bands | $600k seed (older) |
| [Hook](https://musically.com/2026/02/18/social-music-remixing-startup-hook-raises-10m-funding-round/) | Social AI song remixing, licensed catalog (adjacent) | $10M Series A (Khosla, Feb 2026) |
| [Suno](https://www.billboard.com/lists/top-ai-music-companies-2026-future-music/) | AI song generation (adjacent) | $250M Series C |

### Takeaways
- No Series A–C company found whose core product is taste-based matching. Most are seed-stage dating apps.
- Typical failure mode: cold start (a matching app is empty until enough people join).
- Investor money is going to AI plus music plus social (Hook, Suno, GRAI). An AI angle should land well.

### Gaps worth exploiting
1. Match for a specific event (concert/festival) to solve cold start.
2. Compare *how* people listen (replays, late-night patterns, discovery rate, formative era), not just top artists.
3. Match on shared moments, not just taste.
4. Group matching (4–6 people) instead of one-to-one.
5. No-signup cold start: paste a playlist link or Wrapped screenshot.
6. LLM explains *why* two people match and writes the opener.

## Idea template
Copy this block, fill it in, append under `## Ideas`.

```md
### <Idea name>
- **Owner:** <dev name / handle>
- **Status:** proposed | exploring | chosen | parked | rejected
- **One-liner:**
- **Problem:**
- **How it works:**
- **Stack:**
- **MVP scope (what we build in the time limit):**
- **Demo moment (what judges see):**
- **Risks / unknowns:**
- **Effort:** S | M | L
- **Notes / feedback:**
  - 
```

## Ideas

### Taste twin matching
- **Owner:** unassigned
- **Status:** proposed
- **One-liner:** Connect Spotify, get a compatibility score with other users and the one song each of you should send the other.
- **Problem:** Top-artist overlap is a shallow signal for who you'd actually click with.
- **How it works:** Spotify OAuth, pull listening history, compute similarity (audio features, obscurity, listening times), show a match card.
- **Stack:** TBD
- **MVP scope:** OAuth, similarity score, match card.
- **Demo moment:** Two teammates connect accounts and see their score live.
- **Risks / unknowns:** Spotify API limits on listening history and audio features (unverified). Needs seeded users for a demo.
- **Effort:** S
- **Notes / feedback:**
  -

### Live listening rooms by taste cluster
- **Owner:** unassigned
- **Status:** proposed
- **One-liner:** Cluster users by taste, drop them in a shared room with a synced queue and live reactions.
- **Problem:** Discovery feels solitary; shared listening is more fun.
- **How it works:** Taste embeddings, clustering, realtime room with a synced queue.
- **Stack:** TBD (websockets or similar)
- **MVP scope:** One room, synced playback or queue, reactions.
- **Demo moment:** Several people in a room reacting to the same track.
- **Risks / unknowns:** Synced playback is hard with Spotify's SDK (unverified). Needs enough concurrent users.
- **Effort:** L
- **Notes / feedback:**
  -

### Formative era matching
- **Owner:** unassigned
- **Status:** proposed
- **One-liner:** Match people by the music they loved at 15 (shared formative albums and era).
- **Problem:** Emotional connection comes from shared nostalgia, not current playlists.
- **How it works:** User picks or imports formative albums/years; match on era and album overlap.
- **Stack:** TBD
- **MVP scope:** Input flow, matching, match card with the shared albums.
- **Demo moment:** "You both loved this album in 2009."
- **Risks / unknowns:** Needs manual input or data that may not exist in the API.
- **Effort:** S–M
- **Notes / feedback:**
  -

### AI icebreaker
- **Owner:** unassigned
- **Status:** proposed
- **One-liner:** For any two users, an LLM generates a mashup playlist, a conversation starter, and a "you two should hear this" track.
- **Problem:** Matches die at the first message.
- **How it works:** Feed two users' libraries to an LLM; output playlist, opener, and recommendation.
- **Stack:** TBD (Claude API)
- **MVP scope:** Two inputs in, icebreaker out.
- **Demo moment:** Live-generated opener from two real libraries.
- **Risks / unknowns:** Quality and latency of generated output; Spotify data access.
- **Effort:** S
- **Notes / feedback:**
  -

### Local meetup matching
- **Owner:** unassigned
- **Status:** proposed
- **One-liner:** Match by taste plus nearby concerts, then suggest going together.
- **Problem:** Online matches rarely turn into real meetups.
- **How it works:** Taste match combined with a local events source.
- **Stack:** TBD (events API, e.g. Ticketmaster or Bandsintown, unverified)
- **MVP scope:** Atlanta events only, match by taste, "go together" suggestion.
- **Demo moment:** "3 people near you share your taste and are going to this show."
- **Risks / unknowns:** Events API access; needs users.
- **Effort:** M
- **Notes / feedback:**
  -

### Event-based group matching with AI explanation (recommended by research)
- **Owner:** unassigned
- **Status:** proposed
- **One-liner:** Pick a concert/festival, get grouped with 4–6 attendees who overlap in taste, and an LLM explains why you were grouped and gives the group an opener.
- **Problem:** Going to a show alone, and one-to-one matching apps suffer cold start.
- **How it works:** Event picker, taste match limited to that event's attendees, group formation, LLM explanation and icebreaker.
- **Stack:** TBD
- **MVP scope:** One or two seeded events, Spotify connect, group formation, AI explanation card.
- **Demo moment:** Join an event live and watch a group form with an AI "why you match" blurb.
- **Risks / unknowns:** Needs seeded users for the demo; events data source.
- **Effort:** M
- **Notes / feedback:**
  - Combines gaps 1, 4, and 6 above. Avoids cold start by scoping to an event.

## Decision log
| Date | Decision | Decided by | Why |
|---|---|---|---|
|  |  |  |  |

## Open questions
- Time limit, team size, and judging criteria?
- Which music data source: Spotify, Apple Music, Last.fm, or user-pasted playlists?
- Web app or mobile?
- Who owns each role (frontend, backend, data/ML, demo/pitch)?
