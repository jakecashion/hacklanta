# Roadmap: Tandem

## Overview

The journey runs from "does Premiere even let us do this" to "two editors change one timeline live on stage," cut to a 6-8 hour build. Phase 1 proves the panel loads on both laptops, the guest can reach the host's relay over Tailscale (hotspot with the direct IP as fallback), and `ComponentParam.setValue` really changes Scale, Rotation and Opacity (kill test; if it fails, re-plan before Phase 2). Phase 2 builds the relay, sync engine and Premiere bridge, and syncs those three fields both ways in 1-2 s with last-write-wins and no echo loops, over a typed-in host IP. Phase 3 probes Premiere's timing API and syncs timeline edits (rename, move, trim). Phase 4 is the wrap-up: it adds the snapshot join, draws the other editor's live mouse pointer over Premiere (a per-laptop overlay helper, probed first) next to the change feed, and writes and rehearses the demo once on the final code. Everything cut for time (playhead, colors, Resync, session code and Approve, install script, resilience) is v2 behind the stretch gate.

**Hour budget (6-8 h build):** Phase 1 ~1 h, Phase 2 ~3 h, Phase 4 ~3 h = ~7 h planned, plus buffer up to the 8 h ceiling. Phase 3 (Timeline Integration) has no estimate; it runs until a set cutoff time, then Phase 4 starts. Demo is 9am 2026-10-11.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Panel + Kill Test** - Panel loads on both laptops, `setValue` kill test on Scale/Rotation/Opacity, guest reaches the host relay over Tailscale, demo project in place (~1 h)
- [ ] **Phase 2: Live Param Sync** - Relay, sync engine and Premiere bridge; Scale, Rotation and Opacity sync both ways in 1-2 s, last write wins, no echo loops, connect by typed IP with names on the badge (~3 h)
- [x] **Phase 2.1: Position & Anchor Point Sync** (INSERTED) - Motion Position and Anchor Point sync like Scale/Rotation/Opacity (SYNC-02, SYNC-10); next work, via `/gsd-fast`
- [ ] **Phase 3: Timeline Integration** - Probe Premiere's timing API, then sync clip rename, move on the same track, and trim between editors (runs until a cutoff time; not required for the demo)
- [ ] **Phase 4: Join, Live Cursor & Demo** - Final phase: snapshot join from the host, other editor's live mouse pointer over Premiere, change feed, demo script and one clean rehearsal (~3 h)

## Phase Details

### Phase 1: Panel + Kill Test

**Goal**: Both laptops run the panel, the guest reaches the host's relay over Tailscale, and a real `setValue` on Scale, Rotation and Opacity is proven to move the Program monitor, so the team knows the core is buildable before writing it.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: ENV-01, ENV-03, ENV-04, ENV-05
**Success Criteria** (what must be TRUE):
  1. An editor can open the collab panel from Window > Extensions in Premiere Pro 22.3.1 on both laptops, with `PlayerDebugMode` set and the panel folder copied by hand
  2. Kill gate: a `setValue` on Motion Scale, Motion Rotation and Opacity of a V1 clip each visibly changes the Program monitor, and the value read back is recorded and committed to the repo. If any of the three fails, the core is re-planned before Phase 2 starts
  3. A test message from the guest laptop reaches the relay running on the host laptop at the host's Tailscale `100.x` address and comes back (both laptops signed in to the same Tailscale account), with the TCP 8080 `profile=any` firewall rule in place. The fallback is also checked once: the phone hotspot with the host's direct LAN IP
  4. Both laptops open the same demo project (`premiere-collab/demo/demo.prproj`, copied to any folder; footage paths may differ and are relinked once) with no offline media: one sequence, 4 clips on V1 in the same order (Hero, Logo, Card, BG), no keyframes, Uniform Scale ON, English UI

**Plans**: TBD

### Phase 2: Live Param Sync

**Goal**: A Scale, Rotation or Opacity change made in one editor's Premiere shows up in the other's within 1-2 seconds, in both directions, without echo loops or divergence, over a connection the guest opens by typing the host's IP.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: SESS-02, SESS-04, SESS-05, SYNC-03, SYNC-04, SYNC-05, SYNC-06, SYNC-07
**Success Criteria** (what must be TRUE):
  1. The guest types the host's IP and their own name and clicks Connect; each panel's badge goes Not connected -> Connected, and both panels show both users' names
  2. Scale, Rotation and Opacity edits on a V1 clip each show up in the other editor's Premiere within 1-2 s, from host to guest and from guest to host
  3. When both editors change the same field at about the same time, both machines end up with the same value, and it is the later edit in relay order (the relay assigns the `rev` numbers)
  4. A received remote edit is never sent back as a new edit, including when Premiere rounds the value that was written: after one change, the rev counter stays still instead of climbing

**Plans**: TBD
**UI hint**: yes

### Phase 02.1: Position & Anchor Point Sync (INSERTED)

**Goal:** A Position or Anchor Point change (Effect Controls > Motion) made in one editor's Premiere shows up in the other's within 1-2 seconds, in both directions, with the same relay, `rev` order, catch-up on join and no-echo rules as Scale, Rotation and Opacity.
**Mode:** mvp
**Requirements**: SYNC-02, SYNC-10 (SYNC-02 pulled from the stretch list on 2026-10-10; next work, built with `/gsd-fast`)
**Depends on:** Phase 2
**Success Criteria** (what must be TRUE):
  1. Units checked first (one `getValue()` read in Premiere 22.3.1): whether Position and Anchor Point come back as `[x, y]` normalized to the frame (0..1) or in pixels, and the epsilon is chosen to match (0.05 is far too coarse for normalized values)
  2. Changing Position X or Y on a V1 clip in one editor moves the clip in the other's Program monitor within 1-2 s, both directions (SYNC-02)
  3. Changing Anchor Point X or Y does the same (SYNC-10)
  4. No echo: after one Position or Anchor Point change, the rev counter stays still (Premiere rounding on the read-back included)
  5. A guest who connects after the host changed Position or Anchor Point catches up to it (SYNC-01 catch-up covers the new fields)
  6. `npm test` covers the new fields; the relay accepts them (its `FIELDS` whitelist is updated) and still rejects unknown fields
**Notes:** Each value is 2D, while ops carry one finite number. Simplest fit: four scalar fields (`Motion.Position.x`, `.y`, `Motion.AnchorPoint.x`, `.y`) mapped in `bridge.jsx` onto one `[x, y]` `setValue`, so `sync.js` and the op format stay unchanged.
**Plans:** none (inline via `/gsd-fast`, commit 0f7ff95)
**Status:** Complete 2026-10-10. Units confirmed live (normalized [x, y], exact read-back); both directions confirmed on two laptops.

### Phase 3: Timeline Integration

**Goal**: Timeline edits, not just effect values, sync between the two editors: renaming a clip, moving it along its track, and trimming its in and out points in one editor's Premiere show up in the other's within 1-2 seconds, using the same relay, `rev` order and no-echo rules as Phase 2.
**Mode:** mvp
**Depends on**: Phase 2.1. Not required for the demo: set a cutoff time before starting. At the cutoff, stop and start Phase 4. If Phase 3 is not stable by then, demo from the `demo-safe` tag (the last commit before Phase 3)
**Requirements**: ENV-06, EDIT-01, EDIT-02, EDIT-03 (moved here from the stretch list on 2026-10-10)
**Success Criteria** (what must be TRUE):
  1. Probe results (ENV-06) are recorded in the repo before any edit sync is built: whether `nodeId` stays the same across a move, save and reopen; how `start`/`end`/`move()` and `inPoint`/`outPoint` read and write in ticks; and which `onActiveSequence*` events fire for a rename, a move and a trim
  2. Renaming a clip in one editor renames it in the other (EDIT-01)
  3. Moving a clip along the same track in one editor moves it in the other, and the clip keeps its identity, so Phase 2 param sync and the snapshot join catch-up (relay `collapseLog`, keyed by clip ID) still target the right clip afterwards (EDIT-02; clip identity switches from position `v{track}:{clip}` to `nodeId`, see Clip identity below)
  4. Trimming a clip's in or out point in one editor trims it in the other, sent as one combined timing op, so the other side never shows a half-applied trim (EDIT-03)
  5. None of these edits echo back: after one edit, the rev counter stays still
**Order:** probes, then rename (no change to clip identity, safest), then move, then trim. Move is where clip identity changes; if clip IDs switch to `nodeId`, update the relay `CLIP_ID` check, the bridge parser, `collapseLog` and the tests together, and re-test the snapshot join
**Cutoff:** 4:30 AM EDT 2026-10-11. At the cutoff, stop feature work, tag `stable`, and start Phase 4.
**Clip identity (decided 2026-10-11, Step 2):** Source: `premiere-collab/TIMELINE-PROBES.md` section 1.
  1. Use the clip `nodeId` as the shared clip ID for clips that are in `demo.prproj`. The `nodeId` does not change for a move, trim, rename, restart, or save and reopen.
  2. Both laptops get the same `nodeId` for the same clip, because Premiere reads it from the file or gives the next number after the highest ID in the file. Simulated guest load: V1 clip 0 = `000f4242`, same as the host.
  3. Do not sync clips that an editor adds in the session. Each laptop gives new clips the next number from the same counter, so two different clips can get the same `nodeId`. Ignore clips that are not in the starting scan.
  4. Before Step 4, confirm on the real guest: run `pc_listClips(0)` and read V1 clip 0 `nodeId`. Expect `000f4242`.
  5. If the guest value is different, keep `v{track}:{clip}` on the wire for move and map it to `nodeId` on each laptop at connect.
  6. Rename (EDIT-01, f32667d) still uses `v{track}:{clip}`. Step 4 changes all ops to the new ID at the same time: relay `CLIP_ID`, bridge `pc_applyOps` parser, `pc_scan`, `collapseLog`, and the tests.

**Plans**: TBD

### Phase 4: Join, Live Cursor & Demo

**Goal**: Connecting is all it takes to start from the host's timeline, each editor sees the other's mouse pointer moving live over their own Premiere window and a feed of what changed, and the demo has been written and run clean once on two laptops.
**Mode:** mvp
**Depends on**: Phase 3 (or its cutoff time). Final phase: wrap-up checks, demo script and rehearsal on the final code
**Requirements**: SYNC-01, PRES-04, PRES-03, DEMO-01
**Success Criteria** (what must be TRUE):
  1. After the host has changed a clip's Scale, Rotation or Opacity, a guest who clicks Connect sees their timeline set to match the host's, with no session code and no Approve step (clips matched by the clip ID in use: `v{track}:{clip}`, or `nodeId` if Phase 3 switched to it)
  2. Cursor probe first (~20 min, before any other Phase 4 work): a transparent, click-through, always-on-top overlay draws a test pointer over Premiere without blocking clicks or stealing focus, and a pointer position normalized to Premiere's main window lands on the same UI element on the other laptop (both Premieres maximized, same workspace). If it fails, re-plan the cursor before building it
  3. Each editor sees the other's mouse pointer with their name, drawn over their own Premiere window, following the other's mouse anywhere in the Premiere window with under 0.5 s lag (PRES-04). A per-laptop PowerShell helper (no Node on the guest) captures the pointer, sends it through the relay (which already forwards unknown message types) and draws the other's pointer; the CEP panel can't see or draw outside itself
  4. Each panel shows a change feed with author names, e.g. `Sam set Hero Scale to 150 (rev 12)` (already built in Phase 2)
  5. A core-only demo script (big jump edits such as Scale 200, Rotation 90, Opacity 0, plus the live cursor, the feed, and any Phase 3 timeline edits that are stable) is committed to the repo and has been run once end to end, clean, on two laptops over Tailscale, starting from a pristine copy of the demo project on each laptop

**Plans**: TBD
**UI hint**: yes

## Stretch Gate (not a phase)

v2 requirements are not part of this roadmap. They start only after every Phase 4 criterion passes, and only with time left in the 8 h ceiling. If the Phase 4 rehearsal is not clean, stretch does not start; fix the demo instead. Work down this list in order and stop when time runs out. The order is a judgment call (stage reliability first, then cheap visible polish), so reorder it if the demo story changes. Timeline edits (ENV-06, EDIT-01, EDIT-02, EDIT-03) moved out of this list into Phase 3 (renumbered from Phase 4 on 2026-10-10). SYNC-02 Position moved into Phase 2.1 (2026-10-10).

1. DEMO-02 - 3 clean rehearsal runs in a row (stage reliability; no new code)
2. RES-02 - Prerecorded fallback demo video (stage insurance; no new code)
3. SYNC-08 - Resync button (one-click recovery if timelines drift on stage)
4. PRES-02 - The other editor's playhead time (small, visible on stage)
5. SESS-06 - User colors (makes presence and the feed easier to read)
6. SESS-01 - Host starts a session with a 6-character code and sees the LAN IP
7. SESS-03 - Host sees the join request and clicks Approve
8. SYNC-09 - Join refuses a mismatched project
9. RES-01 - Rejoin button after a Wi-Fi blip
10. RES-03 - Single-laptop live fallback against `fake-peer.js` (the script exists since Phase 2; this item is the stage-ready version)
11. RES-04 - Automatic drift detection with a state hash (builds on SYNC-08)
12. ENV-02 - One-script install (`install.ps1`); manual copy works for two laptops

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 2.1 -> 3 -> 4. Phase 3 (Timeline Integration) runs until its cutoff time; Phase 4 (Join, Live Cursor & Demo) is the final phase and must pass before the demo. Renumbered 2026-10-10 (Timeline Integration was Phase 4).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Panel + Kill Test | 0/TBD | Not started | - |
| 2. Live Param Sync | 0/TBD | Not started | - |
| 2.1. Position & Anchor Point Sync | inline | Complete | 2026-10-10 |
| 3. Timeline Integration | 0/TBD | Not started | - |
| 4. Join, Live Cursor & Demo | 0/TBD | In progress | - |
