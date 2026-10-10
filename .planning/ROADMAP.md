# Roadmap: Premiere Live Collab

## Overview

The journey runs from "does Premiere even let us do this" to "two editors change one timeline live on stage," cut to a 6-8 hour build. Phase 1 proves the panel loads on both laptops, the guest can reach the host's relay over Tailscale (hotspot with the direct IP as fallback), and `ComponentParam.setValue` really changes Scale, Rotation and Opacity (kill test; if it fails, re-plan before Phase 2). Phase 2 builds the relay, sync engine and Premiere bridge, and syncs those three fields both ways in 1-2 s with last-write-wins and no echo loops, over a typed-in host IP. Phase 3 adds the snapshot join, shows the other editor's selection and the change feed, and writes and rehearses the demo once. The nodeId, move and trim probes are skipped. Everything cut for time (Position, playhead, colors, Resync, session code and Approve, install script, timeline edits, resilience) is v2 behind the stretch gate.

**Hour budget (6-8 h build):** Phase 1 ~1 h, Phase 2 ~3 h, Phase 3 ~2.5 h = ~6.5 h planned, plus buffer up to the 8 h ceiling. Demo is 9am 2026-10-11.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Panel + Kill Test** - Panel loads on both laptops, `setValue` kill test on Scale/Rotation/Opacity, guest reaches the host relay over Tailscale, demo project in place (~1 h)
- [ ] **Phase 2: Live Param Sync** - Relay, sync engine and Premiere bridge; Scale, Rotation and Opacity sync both ways in 1-2 s, last write wins, no echo loops, connect by typed IP with names on the badge (~3 h)
- [ ] **Phase 3: Join, Presence & Demo** - Snapshot join from the host, other editor's selection, change feed, demo script and one clean rehearsal (~2.5 h)

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
  4. Opening `C:\collab-demo\` on both laptops shows the same demo project: one sequence, 4 clips on V1 (Hero, Logo, Card, BG), no keyframes, Uniform Scale ON, English UI
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

### Phase 3: Join, Presence & Demo
**Goal**: Connecting is all it takes to start from the host's timeline, each editor can see what the other has selected and what changed, and the demo has been written and run clean once on two laptops.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: SYNC-01, PRES-01, PRES-03, DEMO-01
**Success Criteria** (what must be TRUE):
  1. After the host has changed a clip's Scale, Rotation or Opacity, a guest who clicks Connect sees their timeline set to match the host's, with no session code and no Approve step (clips matched by `v{track}:{clip}`)
  2. Each panel shows which clips the other editor has selected, and it updates as the other editor changes their selection
  3. Each panel shows a change feed with author names, e.g. `Sam set Hero Scale to 150 (rev 12)`
  4. A core-only demo script (big jump edits such as Scale 200, Rotation 90, Opacity 0, plus selection and the feed) is committed to the repo and has been run once end to end, clean, on two laptops over Tailscale, starting from a pristine `C:\collab-demo\`
**Plans**: TBD
**UI hint**: yes

## Stretch Gate (not a phase)

v2 requirements are not part of this roadmap. They start only after every Phase 3 criterion passes, and only with time left in the 8 h ceiling. If the Phase 3 rehearsal is not clean, stretch does not start; fix the demo instead. Work down this list in order and stop when time runs out. The order is a judgment call (stage reliability first, then cheap visible polish, then riskier timeline edits), so reorder it if the demo story changes.

1. DEMO-02 - 3 clean rehearsal runs in a row (stage reliability; no new code)
2. RES-02 - Prerecorded fallback demo video (stage insurance; no new code)
3. SYNC-08 - Resync button (one-click recovery if timelines drift on stage)
4. PRES-02 - The other editor's playhead time (small, visible on stage)
5. SESS-06 - User colors (makes presence and the feed easier to read)
6. EDIT-01 - Rename a clip (cheapest timeline edit)
7. SYNC-02 - Motion Position sync (check the units first: normalized or pixels)
8. SESS-01 - Host starts a session with a 6-character code and sees the LAN IP
9. SESS-03 - Host sees the join request and clicks Approve
10. SYNC-09 - Join refuses a mismatched project
11. RES-01 - Rejoin button after a Wi-Fi blip
12. RES-03 - Single-laptop live fallback against `fake-peer.js`
13. ENV-06 - Remaining `08` section 12 probes (`nodeId`, `start`/`end`/`move()`, `inPoint`/`outPoint`, event coverage); gates items 14 and 15
14. EDIT-02 - Move a clip on the same track (needs `nodeId` identity and ENV-06)
15. EDIT-03 - Trim a clip's in and out points (needs a composite timing op and ENV-06)
16. RES-04 - Automatic drift detection with a state hash (builds on SYNC-08)
17. ENV-02 - One-script install (`install.ps1`); manual copy works for two laptops

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Panel + Kill Test | 0/TBD | Not started | - |
| 2. Live Param Sync | 0/TBD | Not started | - |
| 3. Join, Presence & Demo | 0/TBD | Not started | - |
