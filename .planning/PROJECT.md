# Premiere Live Collab

## What This Is

A Premiere Pro panel that lets two editors on two Windows machines join one live session and edit the same timeline together, like Google Docs for Premiere. One editor hosts the session and runs a small relay. The other connects by typing the host's IP. Each editor sees the other's edits, selection and a live change feed. Built for the Hacklanta Creative track (sponsored by Adobe). The After Effects version comes later.

## Core Value

Two editors change the same Premiere timeline at the same time, and each sees the other's change in their own Premiere within 1–2 seconds, live on stage at judging.

## Requirements

### Validated

(None yet — ship to validate)

### Active

Scope cut on 2026-10-10 to a 6–8 hour build. Detail and IDs are in `REQUIREMENTS.md`.

**Core (v1):**

- [ ] Panel loads in Premiere Pro 22.3.1 on both machines (unsigned CEP panel, `PlayerDebugMode`, manual copy)
- [ ] Kill test: `setValue` on Motion Scale, Rotation and Opacity updates the Program monitor
- [ ] Guest reaches the host relay over the hotspot
- [ ] Guest types the host IP and their name, then clicks Connect; badge shows Not connected → Connected; both names shown
- [ ] On connect, the guest timeline is set to match the host's (clips matched by position)
- [ ] Both users can change Motion Scale, Motion Rotation and Opacity; the other machine shows it within 1–2 s
- [ ] No echo loops; the last edit in relay order wins for each field
- [ ] Each panel shows the other user's selected clips
- [ ] Change feed with author names
- [ ] Core-only demo script rehearsed once, clean, on two laptops

**Stretch (v2, in roadmap priority order):** 3-run rehearsal, fallback video, Resync, playhead, colors, rename, Motion Position, session code + Approve, mismatch check, Rejoin, fake-peer fallback, remaining probes, move, trim, drift hash, install script

### Out of Scope

- Add or remove clips — structural edits are risky in ExtendScript; not needed for the demo
- Move a clip to a different track — same reason
- Audio, transitions, titles, nested sequences — beyond what the demo needs
- Effects other than Motion and Opacity — keeps the parameter surface small and testable
- Keyframes — complicated sync semantics
- More than one sequence — demo uses one sequence
- Locks — last-writer-wins per field is enough for the MVP
- One undo step per remote edit — Premiere undo integration is unknown territory
- Reconnect without a new join — rejoining is acceptable for a demo
- More than 2 users — demo is two machines
- Render badge — cosmetic
- After Effects version — decided 2026-10-10: Premiere first, AE after
- UXP plugin — needs Premiere 25.6; both machines have 22.3.1

## Context

- Hackathon: Hacklanta. Judging is 9am on 2026-10-11, with a 3-minute pitch and 2 minutes of Q&A. Build budget cut to 6–8 hours, overnight (2026-10-10).
- Judging criteria: fits the track prompt, how polished the demo is, how good the presentation is, and a clear use case.
- Pitch user: remote editor pairs who need to work on one cut together, live.
- Research already done in `research/live-collab/`:
  - `01`–`05`: collaborative-editing precedents (Google Docs, Word), networking and hosting models, live-collab architecture
  - `06`: Premiere UXP research (needs 25.6, so ruled out)
  - `07`: Premiere 22.3.1 CEP + ExtendScript plan (API, setup, tools)
  - `08`: the detailed MVP plan (scope, architecture, data model, messages, sync rules, network setup, demo project, demo script, pre-build checks)
- Architecture (from `08`): host panel is the authority and assigns `rev`; a Node `ws` relay on the host laptop forwards messages; each panel talks to Premiere through `bridge.jsx` (`snapshot()`, `presence()`, `applyOps()`, `bindEvents()`); `sync.js` is a pure sync engine with no Premiere calls, testable with `node --test`. Code goes in `premiere-collab/`.
- Environment verified on the dev machine (2026-10-10):
  - Premiere Pro 2022, version 22.3.1, at `C:\Program Files\Adobe\Adobe Premiere Pro 2022\`
  - After Effects 2023 (23.0) is also installed (for the later AE version)
  - Registry key `HKCU\Software\Adobe\CSXS.11` exists, but `PlayerDebugMode` is NOT set yet
  - The per-user CEP extensions folder `%APPDATA%\Adobe\CEP\extensions` does not exist yet
  - Node v24.21.0
- Known unknowns (`08` §14): whether `nodeId` stays the same during a session, whether the sequence events fire for every kind of edit, whether the venue Wi-Fi lets two laptops connect to each other, and how fast ExtendScript can snapshot about 50 clips each second.

## Constraints

- **Timeline**: 6–8 hours of build time; demo at 9am 2026-10-11. The core must be demo-solid before any stretch work starts.
- **Tech stack**: CEP 11 + ExtendScript (ES3) panel, Node.js `ws` relay. Premiere 22.3.1.2 can't run UXP.
- **Platform**: Two Windows laptops, both running Premiere 22.3.1.2.
- **Network**: Same Wi-Fi or a phone hotspot. Fallback is a `cloudflared` tunnel. Windows Firewall rule for TCP 8080 must use `profile=any`, because venue and hotspot Wi-Fi are usually marked Public.
- **Demo data**: The same project and media at `C:\collab-demo\` on both machines, unchanged before the join.
- **Process**: Hackathon. Fast development matters more than polish, except on the demo path.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Premiere first, After Effects later | Team decision 2026-10-10 | — Pending |
| CEP + ExtendScript instead of UXP | Both machines run 22.3.1; UXP needs 25.6 | — Pending |
| Relay on the host laptop is the sequencer (assigns `rev`, keeps the op log); host panel approves and supplies the snapshot | All clients run the same code path; no cloud server needed (research 2026-10-10) | — Pending |
| Clip ID = position (`v{track}:{clip}`) for core; switch to `nodeId` only if stretch move lands | Core never adds or moves clips; removes the unverified `nodeId` dependency (research 2026-10-10) | — Pending |
| Last-writer-wins per field, no locks | Simplest conflict rule that converges | — Pending |
| Core = connect by IP + snapshot join + Scale/Rotation/Opacity sync + selection + change feed; everything else stretch | Scope cut to a 6–8 hour budget (2026-10-10); feed is cheap and makes edits readable on stage | — Pending |
| Run the API checks (`08` §12) before building | Several of the API behaviours the plan depends on are unverified | — Pending |
| Pitch under the Creative (Adobe) track to remote editor pairs | It's an Adobe tool, and "Google Docs for Premiere" is a clear story | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-10 after scope cut to 6–8 hours*
