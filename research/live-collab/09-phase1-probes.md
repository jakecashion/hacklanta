# 09 — Phase 1 viability status

Date: 2026-10-10.

## Verdict

**Viability: UNPROVEN. Not shown low, not shown high.**
The machine this was built on has no Premiere Pro, so the Premiere API could not be tested. The decisive question is still open: does `ComponentParam.setValue` on Motion and Opacity update the Program monitor, and can a message from one laptop apply to the other laptop's timeline in both directions?

## What is proven (Node only, no Premiere)

`premiere-collab/panel/js/sync.js` is the sync engine. `node --test premiere-collab/test/` runs 8 tests against a fake Premiere that rounds values:
- an edit on one client appears on the other;
- a rounded read-back is never re-sent (no echo), including Position arrays;
- simultaneous edits to one field converge on the later rev;
- different fields and clips merge;
- a timeline read that began before a remote apply is dropped, not sent as a revert;
- a 300-round fuzz of random edits and delivery order always converges and goes quiet.

The engine assumes one sequencer assigns `rev` (the relay, per `ARCHITECTURE.md`). That wiring is not built.

## What still needs a Premiere machine

Run the kill test in `premiere-collab/KILL-TEST.md` on both laptops (install with `scripts/install-panel.ps1`, relay with `node relay/relay.js`, firewall with `scripts/firewall.ps1`). The core is viable only if `setValue` visibly changes Position, Scale, Rotation and Opacity in the Program monitor and reads back, on both machines, and a relayed edit from each laptop applies on the other.

If either fails, report viability **low** and re-plan.

## Known gaps in the engine

- `EPS` (1e-3) must be at least Premiere's real rounding step. Check the read-back output of the kill test and widen it if needed.
- Pending edits have no timeout; an op the sequencer never commits blocks that field.
- Join and resync (`load()`), presence and the change feed are untested.
