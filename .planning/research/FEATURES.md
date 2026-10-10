# Feature Research

**Domain:** Live collaborative video editing ("Google Docs for Premiere Pro"), two editors, one timeline, 3-minute hackathon demo (Creative track, Adobe-sponsored)
**Researched:** 2026-10-10
**Confidence:** MEDIUM (competitor facts come from vendor/help-doc search snippets and the team's earlier research files; the demo-impact ranking is judgement, not measured)

> Scope rule: PROJECT.md locks the core/stretch split and the Out of Scope list. This file does not expand core. It ranks what is already in scope by demo impact, names the cheap stretch items worth doing first, and lists what to refuse.

## How to read "table stakes" here

There are two different bars, and the roadmap needs both:

1. **Market table stakes** = what real collaborative editors ship (Team Projects, Resolve, Frame.io, Descript, Kapwing, Figma). Most of this is out of reach in 12 hours.
2. **Demo table stakes** = what a judge must see in 3 minutes for "live collaborative editing" to be believable. This is the bar that drives requirements. Everything in PROJECT.md "Core" is demo table stakes; the market table stakes that are NOT in core are listed below so nobody re-adds them by accident.

## Feature Landscape

### Table Stakes (Users Expect These)

Market view: what judges will assume a "collaborative editor" has. Rows marked CORE are in PROJECT.md core. Rows marked OUT are consciously not built and must be answered in Q&A, not in code.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Create/join a session with a short code (CORE) | Every collab tool has an invite/share step; Collabify promo opens with it | LOW | 6-char code, relay `create`/`join`. Relay ~100 lines. |
| Host approval of joiner (CORE) | Trust gate; also an easy on-stage beat | LOW | `join_request` -> `approve`. Doubles as the security answer. |
| Connection status badge: Not connected -> Waiting -> Connected (CORE) | Users need to know sync is live; mirrors Collabify promo | LOW | Pure UI state from WS events. |
| Both editors see the same starting timeline (CORE) | Without a shared baseline nothing else is meaningful | MEDIUM | Snapshot + host-nodeId -> local-nodeId map by track/clip index. Depends on identical project at `C:\collab-demo\`. Highest-risk core item after API checks. |
| Edits propagate to the other machine in 1-2 s, both directions (CORE) | The definition of "live" | MEDIUM-HIGH | Motion (Position/Scale/Rotation) + Opacity only. Event + 1 s snapshot diff -> ops -> host `rev` -> `commit`. Depends on 08 checks 5 and 6. |
| No echo/flicker, deterministic conflict result (CORE) | Figma-style multiplayer feels broken without it | MEDIUM | `applying` flag + shadow + pending-field rule (08 section 8). Pure `sync.js`, testable with `node --test`. |
| See who is in the session (names + colors) (CORE) | Figma/Docs/Descript all show collaborators | LOW | Part of `join`/`presence`. |
| See what the other person has selected (CORE) | Selection is the "cursor" of an editor; Descript, Figma, Resolve all show activity location | MEDIUM | `presence` 4 Hz; panel lists the other user's selected clips in their color. No literal canvas cursor is possible (no API). |
| See the other person's playhead time (CORE) | Frame.io click-to-seek and Descript scene presence set the expectation | LOW-MEDIUM | `presence` carries playhead ticks; show as timecode + colored marker text in panel. |
| Attribution / who changed what (change feed) (STRETCH) | Every serious tool has history or an activity log (Team Projects, Resolve, Docs) | LOW | Falls out of the commit stream for free. Highest-value stretch item (see below). |
| Version history / restore (OUT) | Docs/Figma/Team Projects all have it | HIGH | Not built. Answer: host autosaves the project; change feed is the lightweight audit trail. |
| Locks / permissions (OUT) | Resolve locks bins and timelines; Productions has file locks and read/write | MEDIUM | Not built. Answer: per-field last-writer-wins in host order (Figma's model), no locks needed for two users. |
| Add/remove clips, cross-track moves, audio, effects, keyframes (OUT) | Real editing involves all of these | HIGH | Excluded in PROJECT.md for ExtendScript risk. Pitch language: "starting with the properties editors tweak most." |
| Reconnect without rejoin, 3+ users (OUT) | Normal for production tools | MEDIUM-HIGH | Out of scope; keep a prerecorded fallback video instead. |

### Differentiators (Competitive Advantage)

What makes the demo stand out. Ranked by expected judge "wow" per hour of build.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **A. Live, visible change in the OTHER editor's Program monitor (CORE)** | The single biggest wow: one person drags Scale/Opacity/Rotation, the other person's real Premiere updates a second later, no export, no file passing. Adobe's own answer (Team Projects) is per-user copies; Frame.io is review on rendered media | MEDIUM-HIGH | This IS the core value. Stage it with large, unambiguous edits (Opacity -> 0 makes a clip vanish, Scale -> 200, Rotation -> 90) rather than subtle nudges. A 1 s poll makes continuous drags look stepwise, so prefer jump edits over slow scrubs. |
| **B. Simultaneous two-way editing on different clips/fields (CORE)** | "Both of us edit at the same time" is what separates this from copy/lock workflows and from screen-sharing | MEDIUM | Needs the same engine as A. Demo beat: host changes Hero Scale while guest changes Logo Opacity at the same instant; both screens end identical. |
| **C. Visible conflict resolution on the same field (CORE)** | Shows the sync is a real engine, not a macro: both set Hero Rotation at once, both machines converge to the host-ordered last write | MEDIUM | Free once pending rule works. Rehearse one scripted collision as an optional 10-second beat; skip if short on time. |
| **D. Presence layer: other user's selected clips + playhead in their color (CORE)** | Figma/Descript-style awareness; judges recognise the multiplayer pattern immediately | MEDIUM | Panel-level only. Whether Premiere timeline UI itself can show the selection/color is unverified; do not promise it. |
| **E. Clean connect flow: code -> Join -> Approve -> Connected (CORE)** | Looks polished and mirrors the Collabify promo's opening; costs almost nothing | LOW | Judges score polish; this is the first 30 seconds. Make the badge large and readable from across a table. |
| **F. Change feed with names ("Sam moved Hero (rev 12)") (STRETCH, first pick)** | Attribution and a visible proof of sync for judges who cannot see small property changes; also gives the presenter a narration anchor | LOW | Same op stream as sync, so it is a view, not new sync logic. Recommend it as the first stretch item once core is demo-solid. Note the feed text should reflect core ops (e.g. "Alex set Hero Scale to 150") since move is itself stretch. |
| G. Move clip on the same track (STRETCH) | Most recognisable "editing" gesture; strong visual on a timeline | MEDIUM-HIGH | Depends on 08 check 3 (nodeId stable) and check 4 (start/end writes work). Do only if checks pass. |
| H. Trim in/out (STRETCH) | Second most recognisable editing gesture | MEDIUM-HIGH | Same dependencies as G. |
| I. Rename clip (STRETCH) | Cheap shared-state proof | LOW-MEDIUM | Good fallback if move/trim API checks fail; visible in both Project panels. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Real mouse cursors on the other person's timeline | Collabify promo shows "labeled cursor"; Figma has it | No Premiere/CEP API for the other app's cursor position; would require a screen overlay app | Selected-clip list + playhead time in the other user's color (feature D). Be honest in Q&A. |
| Shared undo/redo | Docs/Figma users expect Ctrl+Z to work | Premiere gives no read access to undo history; PROJECT.md already marks one-undo-per-remote-edit as unknown territory | Local undo only; say "undo is per-editor, like Figma" if asked. |
| Project file merge / .prproj sync | "Just sync the file" sounds simple | Opaque format, no stable IDs, asset-path mismatches | Sync operations, both machines start from the identical `C:\collab-demo\` copy. |
| Screen/desktop streaming (Parsec-style) | Easy, robust, uses the host's GPU | Not collaboration: one cursor, no per-user views; also removes the whole product | Keep as an emergency fallback only (prerecorded video), not a feature. |
| Cloud server, accounts, auth, NAT traversal | "Real products" have them | Eats the build budget; the demo works on one LAN or hotspot with a relay on the host laptop | Host-local `ws` relay; `cloudflared` only as network fallback. |
| Comments / markers / Frame.io-style review | Frame.io makes review the default collab feature | Different product (async review on rendered media); no live-state value; scope creep | Mention Frame.io as complementary in the pitch ("review after, co-edit during"). |
| AI assistant / auto-edit | Adobe loves AI; judges may ask | Dilutes a tight story, adds a failure mode, no time | Do not build. If asked: honest "core is not AI". |
| Generic platform / many users / rooms list | Feels ambitious | Realtime-API lesson in earlier research: build one tight demo, not a platform | Two users, one sequence, one code. |
| Third-party effect, keyframe or audio sync | Editors use them constantly | Parameter surface explodes; keyframe sync semantics are hard | Motion + Opacity only (already locked). |
| Render/"Rendering" badge with avatars | Present in the Collabify promo | Cosmetic; already Out of Scope | Skip. |

## Feature Dependencies

```
[Panel loads in Premiere 22.3.1 (CEP, PlayerDebugMode)]
    └──requires──> [Session create/join + approve + status badge]
                       └──requires──> [Snapshot + clip ID map on join]
                                          └──requires──> [Edit propagation (Motion/Opacity ops via host rev)]
                                                             ├──requires──> [Echo suppression + pending-field LWW rule]
                                                             ├──enhances──> [Simultaneous two-way edit demo beat (B, C)]
                                                             └──enhances──> [Change feed (F)]

[Presence (selection + playhead + names/colors)] ──enhances──> [Edit propagation demo]
    └──requires──> [Session connected]  (independent of the snapshot/ID map; can be built in parallel)

[Move clip (G)] ──requires──> [nodeId stable after move (08 check 3)] + [start/end writes work (check 4)]
[Trim (H)]      ──requires──> same as G
[Rename (I)]    ──requires──> [clip ID map]
[Change feed (F)] ──requires──> [commit stream with author + rev]

[Param edit propagation] ──requires──> [ComponentParam.setValue updates Program monitor (08 check 6)]
[Fast event detection]   ──enhances──> [Edit propagation latency] (onActiveSequenceStructureChanged, 08 check 5; fall back to 1 s timer)
```

### Dependency Notes

- **Edit propagation requires snapshot + ID map:** ops address clips by host `nodeId`; the guest cannot apply or emit ops until the map exists.
- **Edit propagation requires echo suppression:** without `applying` + shadow, every applied remote edit is re-detected locally and bounces back. These ship as one unit, not separately.
- **Presence is independent of edit sync:** it only needs a connected socket and `selection`/`playhead` reads. Build it early in parallel so something visible works even if param writes fail.
- **Change feed is a view over commits:** zero new sync logic, so it is the cheapest stretch item and the best insurance if the live property change is hard to see from the back of the room.
- **Move/trim are gated by 08 checks 3 and 4:** if `nodeId` changes on move or writes do not take, they are cut, not debugged.
- **Param sync is gated by 08 check 6:** if `setValue` does not update the Program monitor, the core itself needs re-planning. This is the project's kill test.

## MVP Definition

### Launch With (v1) = PROJECT.md core, ordered by build sequence

- [ ] Panel loads on both machines; run the 6 API pre-checks first (set final scope)
- [ ] Host session + 6-char code, guest join + host approve, status badge
- [ ] Names and colors for both users
- [ ] Snapshot + clip ID map on join (guest timeline matches host)
- [ ] Motion (Position, Scale, Rotation) + Opacity sync both ways within 1-2 s
- [ ] Echo suppression + last-writer-wins per field in host order
- [ ] Presence: other user's selected clips + playhead in panel

### Add After Validation (v1.x) = PROJECT.md stretch, in recommended order

- [ ] Change feed (F) — lowest cost, highest narration value; build first
- [ ] Rename clip (I) — cheap, low-risk shared-state proof; good if G/H checks fail
- [ ] Move clip on same track (G) — big visual, only if checks 3 and 4 pass
- [ ] Trim (H) — only if G works

### Future Consideration (v2+)

- [ ] After Effects version (decided: Premiere first)
- [ ] Add/remove clips and cross-track moves — structural edits
- [ ] Locks or soft per-clip lock indicator
- [ ] Reconnect/catch-up, 3+ users
- [ ] Keyframes, audio, more effects
- [ ] UXP port once the target Premiere version supports it (25.6+)

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Live Motion/Opacity propagation, both ways | HIGH | MEDIUM-HIGH | P1 |
| Snapshot + clip ID map on join | HIGH | MEDIUM | P1 |
| Echo suppression + LWW conflict rule | HIGH | MEDIUM | P1 |
| Session code / join / approve / status badge | HIGH | LOW | P1 |
| Presence (selection + playhead + names/colors) | HIGH | MEDIUM | P1 |
| Change feed with author names | MEDIUM-HIGH | LOW | P2 |
| Rename clip | MEDIUM | LOW-MEDIUM | P2 |
| Move clip (same track) | HIGH | MEDIUM-HIGH | P2 (gated by checks 3, 4) |
| Trim in/out | MEDIUM | MEDIUM-HIGH | P3 |
| Locks, undo, history, reconnect, 3+ users | MEDIUM | HIGH | Out |

**Priority key:**
- P1: Must have for launch (core)
- P2: Should have, add when core is demo-solid (stretch)
- P3: Nice to have

## Competitor Feature Analysis

| Feature | Premiere Team Projects / Productions | Frame.io | DaVinci Resolve + Blackmagic Cloud | Descript / Kapwing | Figma (reference) | Our Approach |
|---------|--------------------------------------|----------|-------------------------------------|--------------------|-------------------|--------------|
| Simultaneous editing of one timeline | No. Team Projects: each user works on a copy; Productions: shared folder, file locks, read/write permissions | No (review of rendered media) | Yes, multiple users on one project, with bin/timeline locking and accept/merge | Yes (shared project; Descript shows teammates' cursor and who is in each composition on Business+ plans; Kapwing advertises simultaneous workspace editing) | Yes, property-level last-writer-wins | Yes, two editors, per-field last-writer-wins in host order |
| Live presence (who/where) | Shows who is working on a project (Productions) | Real-time comment arrival; click to seek playhead | Locks indicate who owns a bin/timeline | Descript cursor presence; Kapwing: not confirmed | Cursors and selections | Selected clips + playhead + names/colors in the panel |
| Review comments on the timeline | Via Frame.io | Core feature, comments tied to timeline markers (V4 panel, Premiere 25.6+) | Review/notes tooling (not researched in depth) | Frame-accurate timeline comments (Kapwing) | Comments | Not built (anti-feature) |
| Version history / restore | Team Projects: auto-save + history | Version stacks | Project server incremental saves | Yes | Yes | Not built; change feed only (stretch) |
| Conflict model | Copies + locks | n/a | Locks + merge/decompose | Not verified | LWW per property | LWW per field, no locks (2 users) |
| Lives inside the editor | Yes | Yes (panel) | Native | Browser-based editors | Browser-based | Yes, a Premiere panel; this is the Adobe-fit argument |
| Setup | Cloud account / shared storage | Account + upload | Project server or Cloud | Account | Link | Host IP + 6-char code on one LAN/hotspot |

## What wins a 3-minute Creative-track demo

Judging criteria (from CLAUDE.md): fits the track prompt, polish of the demo, presentation, clear use case. Mapping features to those:

1. **Clear use case** -> "remote editor pairs who need to work on one cut together, live." Opening line contrasts with Team Projects (copies/locks, not simultaneous; say "as we understand it", official 2026 status was not re-verified) and Frame.io (review after render).
2. **Demo polish** -> the connect flow (E) in the first 30 s, then three visible beats with large, obvious edits:
   - Guest sets Hero Opacity/Scale; host's Program monitor changes (A).
   - Host and guest edit different clips at the same time; screens converge (B).
   - Selections and playhead show up in each other's panel in their colors (D).
3. **Track fit (Adobe, Creative)** -> it lives inside Premiere as a panel; pitch it as making a core Adobe tool multiplayer. Honest note: Creative track prompt ("make something people feel") fits a productivity tool less naturally; the "feel" is watching two real Premiere windows move together.
4. **Presentation** -> two laptops side by side facing the judges, big badge, change feed as a narration anchor (F), and a prerecorded fallback video in case venue Wi-Fi blocks laptop-to-laptop traffic.

Demo-ordering caveat: the demo script in `research/live-collab/08-mvp.md` section 11 uses "guest moves Hero" (step 4) and a change feed (step 7), but PROJECT.md moved both to stretch. The core-only script must be rewritten around Scale/Position/Rotation/Opacity edits and panel presence; the move and feed beats are added back only if those stretch items land.

## Sources

- `.planning/PROJECT.md` and `research/live-collab/08-mvp.md` (locked scope, demo script, API checks) [local, HIGH for scope facts]
- `research/live-collab/04-after-effects-and-creative-collab-precedents.md` and `05-architecture-and-plan.md` (Figma LWW, Resolve locking, Blender/Unreal multi-user, Collabify feature set, ruled-out list) [local; many inherited claims are snippet-only]
- `research/tiktok-collabify-observations.md` (feature reference only; no product found) [local]
- Team Projects / Productions: [AppleInsider 2020](https://appleinsider.com/articles/20/04/14/adobe-improves-remote-collaboration-with-productions-and-team-projects), [Pro Video Coalition: Productions versus Team Projects](https://www.provideocoalition.com/productions-versus-team-projects/), [Adobe Team Projects overview](https://helpx.adobe.com/premiere-pro/using/video/team-projects-overview-video.html). Search found no official discontinuation notice; current status not confirmed. [MEDIUM]
- Frame.io V4 panel: [Frame.io help, Premiere V4 panel overview (25.6+)](https://help.frame.io/articles/12833113-adobe-premiere-frame-io-v4-panel-overview-25-6-and-later). Comments arrive in real time, click seeks playhead, comments tied to markers. [MEDIUM]
- DaVinci Resolve 18 / Blackmagic Cloud: [Business Wire announcement](https://www.businesswire.com/news/home/20220418005496/en); locking and merge model from [Blackmagic collaboration page](https://www.blackmagicdesign.com/products/davinciresolve/collaboration) via earlier research. Chat/presence in current Resolve not verified. [MEDIUM]
- Descript cursor presence: [Descript help center](https://help.descript.com/hc/en-us/articles/38909859604365-Cursor-Presence-See-teammates-cursors-in-real-time) (Business/Enterprise only). Kapwing: [Kapwing collaboration page](https://www.kapwing.com/video-editor/collaboration) (vendor marketing; cursors/presence not confirmed). [MEDIUM / LOW for Kapwing]
- Avid shared projects: not researched in this pass; treat as a locking/bin-sharing model like Resolve and Productions [LOW].
- Note: the `gsd_run` research-plan seam was not installed in this environment, so searches went through the built-in WebSearch directly and were not cached.

---
*Feature research for: live collaborative video editing in Premiere Pro (hackathon demo)*
*Researched: 2026-10-10*
