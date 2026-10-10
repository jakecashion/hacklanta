# Requirements: Premiere Live Collab

**Defined:** 2026-10-10
**Core Value:** Two editors change the same Premiere timeline at the same time, and each sees the other's change in their own Premiere within 1–2 seconds, live on stage at judging.

## v1 Requirements

Requirements for the 9am 2026-10-11 demo. Each one maps to a roadmap phase.

### Environment & Probes

- [ ] **ENV-01**: Editor can open the collab panel from Window > Extensions in Premiere Pro 22.3.1 on both laptops (unsigned panel via `PlayerDebugMode` in `CSXS.11`)
- [ ] **ENV-02**: Developer can install or update the panel on a laptop with one script (`install.ps1`)
- [ ] **ENV-03**: The six `08-mvp.md` §12 checks have run on real Premiere, and the results are committed, including a component/param dump and a `setValue` read-back for Position, Scale, Rotation and Opacity
- [ ] **ENV-04**: The guest laptop reaches the host's relay over the hotspot, with a firewall rule for TCP 8080 using `profile=any`
- [ ] **ENV-05**: The demo project exists at `C:\collab-demo\` on both laptops: one sequence, 4 clips on V1 (Hero, Logo, Card, BG), no keyframes, Uniform Scale ON, English UI

### Session

- [ ] **SESS-01**: Host can start a session; the panel shows a 6-character code and the host's LAN IP
- [ ] **SESS-02**: Guest can enter the host address (`ws://` IP or full `wss://` URL) and the code, then click Join
- [ ] **SESS-03**: Host sees the join request with the guest's name and can click Approve
- [ ] **SESS-04**: Each panel shows a status badge: Not connected → Waiting → Connected
- [ ] **SESS-05**: Each panel shows both users' names and colors

### Sync

- [ ] **SYNC-01**: On join, the guest's timeline is set to match the host's timeline. Clips are matched by position (`v{track}:{clip}`), and the join refuses to proceed if the projects don't match.
- [ ] **SYNC-02**: Either editor can change Motion Position on a clip, and the other's Premiere shows it within 1–2 s
- [ ] **SYNC-03**: Either editor can change Motion Scale on a clip, and the other's Premiere shows it within 1–2 s
- [ ] **SYNC-04**: Either editor can change Motion Rotation on a clip, and the other's Premiere shows it within 1–2 s
- [ ] **SYNC-05**: Either editor can change Opacity on a clip, and the other's Premiere shows it within 1–2 s
- [ ] **SYNC-06**: When both editors change the same field, both machines end up with the same value. The last edit in relay order wins; the relay assigns `rev` numbers.
- [ ] **SYNC-07**: A remote edit is never sent back as a new edit (no echo loops). This holds even when Premiere rounds the value that was written.
- [ ] **SYNC-08**: Either editor can click Resync to make their timeline match the host's again

### Presence & Feed

- [ ] **PRES-01**: Each panel shows which clips the other editor has selected
- [ ] **PRES-02**: Each panel shows the other editor's playhead time
- [ ] **PRES-03**: Each panel shows a change feed with author names, e.g. `Sam set Hero Scale to 150 (rev 12)`

### Demo

- [ ] **DEMO-01**: A core-only demo script, rewritten from `08` §11 around Motion/Opacity edits, presence and the feed, has been rehearsed end to end on two laptops over the hotspot

## v2 Requirements

Stretch goals. Only start these after v1 is demo-solid.

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
| Real mouse cursors in the timeline | No API; presence stays in the panel only |
| Screen streaming, cloud server, accounts | Wrong problem; the relay runs on the LAN |
| Project-file merge, Frame.io-style comments, AI features | Not the core value |
| Render badge | Cosmetic |
| After Effects version | Premiere first (decided 2026-10-10) |
| UXP plugin | Needs Premiere 25.6; the machines have 22.3.1 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|

**Coverage:**
- v1 requirements: 23 total
- Mapped to phases: 0
- Unmapped: 23 ⚠️

---
*Requirements defined: 2026-10-10*
*Last updated: 2026-10-10 after initial definition*
