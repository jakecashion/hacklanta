# 09 — Phase 1 probes: runbook and verdict

Date: 2026-10-10. Code: `premiere-collab/`.

## Verdict (so far)

**Viability: UNPROVEN. Not shown low, not shown high.**
The build machine has no Premiere Pro (no `C:\Program Files\Adobe`, no CEP registry key). The Premiere API probes could not run. Only the Premiere-free parts are verified. No claim about `setValue` on real clips is made here.

| Verified here (Node only) | Result |
|---|---|
| Relay: two clients, both directions, no self-echo, room isolation | pass (3 tests) |
| Relay reachable on the LAN IPv4 address (10.0.0.83), round trip ~63 ms | pass (same machine, not a second laptop) |
| `bridge.jsx` logic against a MOCK Premiere object | pass. Proves syntax and logic only |

## Runbook (about 20 minutes, two laptops with Premiere 22.3.1)

1. Both laptops: `powershell -ExecutionPolicy Bypass -File premiere-collab\scripts\install.ps1`. Restart Premiere. Open Window > Extensions > Live Collab. (Check 1.)
2. Both: open the demo project (4 clips on V1, no keyframes, Uniform Scale ON, English UI).
3. Host, elevated: `scripts\firewall.ps1`. Then `cd premiere-collab\relay; node relay.js`. Note the printed `ws://IP:8080`.
4. Click each section in the panel, top to bottom:
   - **Env + bridge**, **Dump components**, **setValue round trip**, then **Monitor changed YES/NO** (watch the Program monitor while the round trip runs). This is the kill gate (check 6).
   - **Move/trim test** (check 4), **Scan timing**.
   - **Record IDs**, move and trim a clip by hand, save and reopen, **Compare IDs** (check 3).
   - **Bind events**, then for each of move / trim / Scale-or-Opacity edit: do the edit, click its Read counts button (check 5).
   - **Connect** both panels to the relay (same room). Host uses `ws://localhost:8080`, guest the host IP. Click **Send Opacity to peer** on each laptop (checks 2 and 7).
5. **Export results** on each laptop. The JSON lands in Documents. Commit both as `research/live-collab/results/`.

## Decision rule

The core is viable only if all of these pass on the real machines:
- Check 6: `setValue` changes Position, Scale, Rotation and Opacity, reads back, and the Program monitor updates.
- Check 7: a message from one laptop changes the other laptop's timeline, in both directions.
- Check 1 and 2.

If check 6 or 7 fails in either direction, report viability **low** and re-plan. Checks 3, 4, 5 only shape scope: 3 and 4 gate stretch, and a failed 5 means the 1 s timer is the only change detector.

## Not covered by these probes

Firewall rule on the real hotspot, venue Wi-Fi isolation, `cloudflared` WebSocket pass-through, whether a changed `.jsx` needs a Premiere restart, undo behaviour after a remote `setValue`. ENV-05 (demo project) must be made by hand in Premiere.
