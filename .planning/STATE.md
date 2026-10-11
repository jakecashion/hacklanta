---
gsd_state_version: "1.0"
current_phase: 4
current_phase_name: Join, Live Cursor & Demo
status: in_progress
stopped_at: "Phase 3 closed (move e31b7bc, trim 15b79a7, nodeId f95c25b; host-only verified with a simulated guest). Next: Phase 4 live cursor (PRES-04)"
last_updated: "2026-10-11T05:20:00.000Z"
last_activity: 2026-10-11
last_activity_desc: Phase 3 closed - clip ID switched to nodeId, move and trim sync as one Clip.timing op; verified on the host with a simulated guest
state_head: 0f7ff959c32468f66ba5b95beb32e837553e3c40
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-10)

**Core value:** Two editors change the same Premiere timeline at the same time, and each sees the other's change in their own Premiere within 1-2 seconds, live on stage at judging.
**Current focus:** Phase 4 - Join, Live Cursor & Demo (live cursor next)

## Current Position

Phase: 4 of 5 (Join, Live Cursor & Demo) - Phase 3 closed 2026-10-11 ~1:15 AM: clip ID = `nodeId` (f95c25b), move and trim as one `Clip.timing` op (e31b7bc, 15b79a7), rename (f32667d). Verified on the host only (simulated guest). Next: live cursor (PRES-04), then guest checks, demo script, rehearsal
Plan: 0 of TBD in current phase
Status: In progress (Phase 4 code mostly done; cursor next)
Last activity: 2026-10-11 — EDIT-01 rename sync verified on two laptops

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: - min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Scope cut to a 6-8 h build (2026-10-10): 3 phases (~1 h, ~3 h, ~2.5 h plus buffer). Join is a snapshot on Connect from a typed host IP (no code, no Approve). Position, playhead, colors, Resync, mismatch refusal, install script and the nodeId/move/trim probes moved to v2
- [Roadmap]: Relay on the host laptop is the sequencer (assigns `rev`, keeps the op log); host panel supplies the snapshot
- [Roadmap]: Clip ID = position (`v{track}:{clip}`) for core; `nodeId` only if stretch move lands (superseded by Phase 3, see next line)
- [Phase 3]: Clip ID is `nodeId` for all ops; move and trim are one `Clip.timing` op ("start:end:inPoint" ticks) that replaces the short-lived `Clip.start` field. Clips added in the session are still synced (ROADMAP rule 3 not built)
- [Roadmap]: Change feed promoted to core (PRES-03); demo script is core-only (DEMO-01) with one clean rehearsal
- [Roadmap]: No `--enable-nodejs`; firewall rule is TCP 8080 with `profile=any`; Tailscale (same account on both laptops) is the default network, phone hotspot with the direct IP is the fallback, cloudflared dropped (2026-10-10); panel folder is copied by hand
- [Roadmap]: All v2 items (including Resync SYNC-08 and EDIT-*/RES-*) stay behind the stretch gate after Phase 4, worked in the priority order listed in ROADMAP.md

### Roadmap Evolution

- Phases 3 and 4 swapped (2026-10-10): Timeline Integration is now Phase 3 (depends on Phase 2.1, runs until a cutoff time); Join, Live Cursor & Demo is now Phase 4, the final phase (wrap-up checks, demo script, rehearsal on the final code). Entries below use the old numbers
- Phase 4 added (2026-10-10): Timeline Integration (ENV-06 probes, EDIT-01 rename, EDIT-02 move, EDIT-03 trim), pulled out of the stretch list; runs after Phase 3, not on the demo path
- Phase 3 edited: PRES-01 selection presence replaced by PRES-04 live mouse cursor over Premiere (per-laptop PowerShell overlay helper, probed first); PRES-01 moved to v2; Phase 3 budget ~3 h
- Phase 02.1 inserted after Phase 2: Position & Anchor Point Sync (SYNC-02 from stretch + new SYNC-10); next work, via /gsd-fast

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 1]: Kill gate PASSED 2026-10-10 (see premiere-collab/KILL-TEST.md)
- [Phase 1]: Unknowns to note during the kill test: Rotation above 360, Uniform Scale behavior, scan cost for 4 clips, whether a changed `.jsx` needs a Premiere restart. Skipped for now (v2): Position units, `nodeId`/move/trim probes, event coverage (sync relies on the 1 s poll)
- [Phase 1]: Tailscale needs internet on the venue network or hotspot; untested between the two laptops until Task 4
- [Phase 2]: Echo loops and Premiere rounding the written value (shadow from read-back plus epsilon compare)
- [Phase 4]: Guest checks from Phase 3: guest `git pull`, rerun `install-panel.ps1`, reopen panel; List V1 must show `000f4242` (else ROADMAP Phase 3 rule 5); test move and trim both ways; hand trim. Restart the host relay after every relay.js change
- [Phase 4]: `displayName` is localized, so both laptops need an English UI; keyframed params can't be read or written

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-11 01:15
Stopped at: Phase 3 closed. Move (EDIT-02) and trim (EDIT-03) built and verified on the host with a simulated guest. Next: Phase 4 live cursor (PRES-04)
Resume file: .planning/phases/01-panel-kill-test/.continue-here.md (Phase 4 handoff)
