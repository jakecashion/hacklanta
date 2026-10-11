# Requirements: Tandem

**Defined:** 2026-10-10
**Core Value:** Two editors change the same Premiere timeline at the same time, and each sees the other's change in their own Premiere within 1–2 seconds, live on stage at judging.

**Time budget:** 6–8 hours of build (cut on 2026-10-10 from the earlier 12-hour scope).

## v1 Requirements

Requirements for the 9am 2026-10-11 demo. Each one maps to a roadmap phase.

### Environment & Probes

- [ ] **ENV-01**: Editor can open the collab panel from Window > Extensions in Premiere Pro 22.3.1 on both laptops (unsigned panel via `PlayerDebugMode` in `CSXS.11`; the panel folder is copied by hand)
- [ ] **ENV-03**: Kill test passes and the results are committed: `ComponentParam.setValue` on Motion Scale, Motion Rotation and Opacity visibly updates the Program monitor, and the value read back is recorded
- [ ] **ENV-04**: The guest laptop reaches the host's relay over the hotspot, with a firewall rule for TCP 8080 using `profile=any`
- [ ] **ENV-05**: The demo project exists at `C:\collab-demo\` on both laptops: one sequence, 4 clips on V1 (Hero, Logo, Card, BG), no keyframes, Uniform Scale ON, English UI

### Session

- [ ] **SESS-02**: Guest can type the host's IP and their own name, then click Connect
- [ ] **SESS-04**: Each panel shows a status badge: Not connected → Connected
- [ ] **SESS-05**: Each panel shows both users' names

### Sync

- [ ] **SYNC-01**: On connect, the guest's timeline is set to match the host's timeline, with clips matched by position (`v{track}:{clip}`)
- [ ] **SYNC-03**: Either editor can change Motion Scale on a clip, and the other's Premiere shows it within 1–2 s
- [ ] **SYNC-04**: Either editor can change Motion Rotation on a clip, and the other's Premiere shows it within 1–2 s
- [ ] **SYNC-05**: Either editor can change Opacity on a clip, and the other's Premiere shows it within 1–2 s
- [ ] **SYNC-06**: When both editors change the same field, both machines end up with the same value. The last edit in relay order wins; the relay assigns `rev` numbers.
- [x] **SYNC-02**: Either editor can change Motion Position (X or Y) on a clip, and the other's Premiere shows it within 1–2 s. Check the units first (normalized or pixels). Moved from v2 on 2026-10-10
- [x] **SYNC-10**: Either editor can change Motion Anchor Point (X or Y) on a clip, and the other's Premiere shows it within 1–2 s. Added 2026-10-10
- [ ] **SYNC-07**: A remote edit is never sent back as a new edit (no echo loops). This holds even when Premiere rounds the value that was written.

### Presence & Feed

- [ ] **PRES-04**: Each editor sees the other's live mouse pointer, with their name, over their own Premiere window (per-laptop overlay helper; both Premieres maximized with the same workspace)
- [ ] **PRES-03**: Each panel shows a change feed with author names, e.g. `Sam set Hero Scale to 150 (rev 12)`

### Demo

- [ ] **DEMO-01**: A core-only demo script, rewritten from `08` §11 around big Scale/Rotation/Opacity jump edits, the live cursor and the feed, has been run once end to end, clean, on two laptops over the hotspot

## v2 Requirements

Stretch goals. Only start these after v1 is demo-solid.

### Cut from v1 for time (2026-10-10)

- **ENV-02**: One-script install (`install.ps1`)
- **ENV-06**: Remaining `08` §12 probes: `nodeId` stability, `start`/`end`/`move()`, `inPoint`/`outPoint`, event coverage
- **SESS-01**: Host starts a session with a 6-character code, and the panel shows the host's LAN IP
- **SESS-03**: Host sees the join request and clicks Approve
- **SESS-06**: User colors
- **SYNC-08**: Resync button
- **SYNC-09**: Join refuses a mismatched project
- **PRES-01**: Each panel shows which clips the other editor has selected (replaced in Phase 3 by PRES-04 live cursor, 2026-10-10)
- **PRES-02**: The other editor's playhead time
- **DEMO-02**: 3 clean rehearsal runs in a row

### Timeline Edits

- **EDIT-01**: Either editor can rename a clip, and the other sees the new name
- **EDIT-02**: Either editor can move a clip on the same track. Needs `nodeId` identity and the probe results.
- **EDIT-03**: Either editor can trim a clip's in and out points. Needs a composite timing op.

### Resilience

- **RES-01**: Rejoin button after a Wi-Fi blip
- **RES-02**: Prerecorded fallback demo video
- **RES-03**: A single-laptop live fallback against `fake-peer.js`
- **RES-04**: Automatic drift detection with a state hash

## Out of Scope

| Feature | Reason |
|---------|--------|
| Add or remove clips, cross-track moves | Structural edits are risky in ExtendScript; not needed for the demo |
| Audio, transitions, titles, nested sequences | Beyond what the demo needs |
| Effects other than Motion and Opacity | Keeps the parameter surface small and testable |
| Keyframes | `getValue`/`setValue` can't handle keyframed params |
| Multiple sequences, more than 2 users | The demo is one sequence on two machines |
| Locks | Last-writer-wins per field is enough |
| Shared undo, one undo step per remote edit | Premiere undo integration is unknown; don't press Ctrl+Z on stage |
| Screen streaming, cloud server, accounts | Wrong problem; the relay runs on the LAN |
| Project-file merge, Frame.io-style comments, AI features | Not the core value |
| Render badge | Cosmetic |
| After Effects version | Premiere first (decided 2026-10-10) |
| UXP plugin | Needs Premiere 25.6; the machines have 22.3.1 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ENV-01 | Phase 1 | Pending |
| ENV-03 | Phase 1 | Pending |
| ENV-04 | Phase 1 | Pending |
| ENV-05 | Phase 1 | Pending |
| SESS-02 | Phase 2 | Pending |
| SESS-04 | Phase 2 | Pending |
| SESS-05 | Phase 2 | Pending |
| SYNC-01 | Phase 3 | Pending |
| SYNC-03 | Phase 2 | Pending |
| SYNC-04 | Phase 2 | Pending |
| SYNC-05 | Phase 2 | Pending |
| SYNC-06 | Phase 2 | Pending |
| SYNC-07 | Phase 2 | Pending |
| SYNC-02 | Phase 2.1 | Complete |
| SYNC-10 | Phase 2.1 | Complete |
| PRES-04 | Phase 3 | Pending |
| PRES-03 | Phase 3 | Pending |
| DEMO-01 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 18 total (ENV 4, SESS 3, SYNC 8, PRES 2, DEMO 1)
- Mapped to phases: 18
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-10*
*Last updated: 2026-10-10 after scope cut to 6–8 hours*
