# Project Research Summary

**Project:** Premiere Live Collab
**Domain:** Live two-user timeline sync for Premiere Pro 22.3.1 (CEP 11 panel + ExtendScript bridge + Node `ws` relay, Windows)
**Researched:** 2026-10-10
**Confidence:** MEDIUM

## Executive Summary

This project is a "Google Docs for Premiere" CEP panel for two editors on Premiere 22.3.1. Premiere has no collaboration API, so it uses the standard approach for that case:

- Poll the timeline and compare it to a shadow copy.
- Send every edit through one sequencer, which puts them in a single order.
- When two edits hit the same field, the last one wins.

The panel is vanilla JS on CEP 11 (Chromium 88, native WebSocket, no build step). A `ws` relay runs on the host laptop. `bridge.jsx` (ES3) is the only code that touches Premiere. `sync.js` is a pure engine, so about 90% of the logic can be proven with `node --test`, a FakeBridge and `fake-peer.js`.

Recommended build order:

1. API probes first.
2. Then two parallel lanes: the Premiere-free engine and relay, and the Premiere-bound bridge.
3. An early end-to-end slice by hour 5–6: the host changes Opacity and the guest updates within about 1 s.
4. Session UX and presence.
5. Hardening and rehearsal. This gates any stretch work.

Main risks:

- Echo ping-pong.
- Premiere rounding the values we write.
- Motion Position units.
- Event coverage for parameter edits.
- `evalScript` blocking Premiere.
- CEP load failures.
- Venue Wi-Fi client isolation.

Mitigations:

- Only one `evalScript` call runs at a time.
- The shadow is set from a read-back and compared with an epsilon.
- Polling is the truth; events are only hints.
- The hotspot is the default network.
- A state hash check and a Resync button.
- A prerecorded fallback video.

## Key Findings

### Recommended Stack (HIGH)

Detail: [STACK.md](STACK.md)

**Runtime (read from the installed binaries):**
- CEP 11.3 / `CSXS.11`, Chromium 88.0.4324.182. Chromium 88 has a native `WebSocket`, so the panel needs no Node.
- Do not use `--enable-nodejs` or `--mixed-context`.

**Libraries:**
- `CSInterface.js` v11.0.0 (CEP_11.x).
- `json2.js` 2023-05-10.
- Node 24 with `ws` 8.22.0 pinned (8.21.3 as a fallback). Only the host needs Node.
- `node --test` for tests.

**Manifest and debugging:**
- Manifest schema `6.0`, `RequiredRuntime CSXS 6.0`, PPRO host range `[14.3,99.9]`.
- `PlayerDebugMode` is a `REG_SZ` `"1"` under `HKCU\Software\Adobe\CSXS.11`.
- A `.debug` file on port 8088. Its Extension Id must match the manifest Id.

**Install and network:**
- `install.ps1` copies the panel with `robocopy /MIR`, or a `mklink /J` junction on the dev machine.
- One elevated `netsh` firewall rule: TCP 8080, `profile=any`.
- `cloudflared` quick tunnel is plan C only. It is unconfirmed whether it carries WebSockets.

**Do not use:** UXP, Bolt CEP, frameworks or bundlers, TypeScript, `socket.io`/Express, Node-enabled CEP, ES modules over `file://`, ZXP signing.

### Expected Features (MEDIUM)

Detail: [FEATURES.md](FEATURES.md)

No competitor ships true simultaneous co-editing of one Premiere timeline. Team Projects, Productions, Frame.io and Resolve all use copies, locks or review instead. That gap is the differentiator.

**Core:**
- Session code and Approve.
- Status badge.
- Names and colors.
- Snapshot plus a clip ID map.
- Two-way Motion and Opacity sync.
- Echo suppression with last-writer-wins per field.
- Presence.

**Stretch, in this order:** change feed, then rename, then move, then trim.

**Anti-features:** real cursors, shared undo, history, locks, reconnect, AI features, project-file merge, screen streaming, a cloud server and accounts.

**Demo staging:** use big jump edits (Opacity 0, Scale 200, Rotation 90), not slow scrubs. The 1 s poll makes continuous drags look stepwise.

### Architecture Approach (MEDIUM: sync model HIGH, Premiere API MEDIUM-LOW)

Detail: [ARCHITECTURE.md](ARCHITECTURE.md)

Keep the `08` architecture, hardened as follows.

**Polling:**
- Tiered: about 4 Hz for selection, playhead and the selected clips' params; a 1 Hz full scan.
- Adaptive interval: `max(250ms, 5 × scan duration)`.
- Events trigger an immediate scan. They are never the source of truth.

**Echo guard and shadow:**
- The guard is a shadow comparison, not the `applying` flag. CSXSEvents and `evalScript` callbacks are asynchronous, so a flag cannot stop the echo.
- The shadow is set from a read-back after apply.
- `applyOps` is compare-and-set against the shadow.

**Pending edits:**
- `pending[field]` holds the latest opId.
- It clears only when a commit arrives for that exact opId.
- It has a TTL of about 3 s.

**Join and recovery:**
- Join is snapshot at rev N, then `resume{lastRev:N}`, then the relay replays newer commits.
- A state-hash message and a Resync-from-host button catch drift.

**Components:** `bridge.jsx`, `bridge-client.js` (one call in flight, batched, JSON envelope, about 5 s watchdog), `sync.js`, `main.js`/UI, `relay.js`, `fake-peer.js`/FakeBridge.

### Critical Pitfalls (MEDIUM-LOW)

Detail: [PITFALLS.md](PITFALLS.md)

1. **Stale-snapshot race and echo loop.** A snapshot started before a remote apply can return after the shadow is updated. It then looks like a local edit. Fix: one call in flight, sequence-tagged snapshots, and a per-field loop breaker.
2. **Premiere doesn't store the exact value sent.** Float32 drift and frame snapping cause a permanent diff. Fix: shadow from read-back plus epsilon compare.
3. **Param traps.**
   - Motion Position units may be normalized, unconfirmed.
   - `displayName` is localized, so both laptops need an English UI.
   - Keyframed params cannot be read or written; skip them.
   - Uniform Scale must be ON.
   - Look components up by name, not index.
4. **Events are unreliable.** `onActiveSequenceStructureChanged` probably doesn't fire for param edits. Handlers stack up on each panel reload.
5. **CEP load failures and the network.**
   - Debug mode not set, or the manifest host range too narrow.
   - Windows marks venue and hotspot Wi-Fi as Public, so a Private-only firewall rule won't apply.
   - The venue Wi-Fi may isolate clients.

Also:

- Never string-concatenate peer data into `evalScript`, which is an injection risk.
- Never apply a remote selection or playhead locally.
- Don't press Ctrl+Z on stage.
- A composite timing op is needed before trim can work.

## Implications for Roadmap

Four coarse phases, about 12 h in total.

### Phase 1: Environment, probes and bridge contract (~1.5 h)

**Rationale:** Most of the Premiere runtime behavior is undocumented, so these probes are the real research.

**Delivers:**
- An empty panel that loads on both laptops.
- The six `08` §12 checks.
- A committed component/param dump.
- A `setValue` round trip for Position, Scale, Rotation and Opacity.
- An event-coverage test and scan timing.
- A relay round trip from the second laptop, with the firewall rule and hotspot.
- The demo project: 4 clips, no keyframes, Uniform Scale ON, English UI.
- The bridge JSON contract.

**Kill gate:** if `setValue` does not update the Program monitor, re-plan the core before building more.

### Phase 2: Sync engine and first end-to-end slice (~4.5 h)

**Two parallel lanes:**
- **Lane S (Premiere-free):** `sync.js`, FakeBridge, `relay.js`, `fake-peer.js`, `node --test`.
- **Lane P (Premiere-bound):** `bridge.jsx`, `bridge-client.js`.

**Milestone (by hour 5–6):** the host changes Opacity and the guest updates within about 1 s. Then widen to all four fields, in both directions.

**Avoids:** pitfalls 1 and 2.

### Phase 3: Session UX, join and presence (~2.5 h)

**Delivers:**
- Host/Join/Approve UI, status badge, names and colors.
- Snapshot-then-replay join, with a fingerprint pre-check that refuses a mismatched project.
- Display-only presence.
- Change feed, if it is promoted from stretch.

### Phase 4: Hardening, rehearsal and stretch gate (~3 h + buffer)

**Delivers:**
- Hash check, Resync button, watchdog, Rejoin, loop breaker.
- Hotspot rehearsal and a pristine-project reset.
- A rewritten core-only demo script.
- A fallback video and a single-laptop `fake-peer` live fallback.

**Stretch, only after this phase passes:** rename, then move (only if the probes pass), then trim.

### Phase Ordering Rationale

- The probes come first because the kill test (`setValue` updating the Program monitor) decides whether the core is possible at all.
- Splitting the engine and the bridge into lanes lets about 90% of the logic be tested without Premiere, while Premiere-bound work goes ahead in parallel.
- An end-to-end slice at hour 5–6 leaves margin for UX and rehearsal.
- Hardening gates stretch, so the demo never depends on unfinished stretch work.

### Research Flags

- **Phase 1:** the probes are the research. Commit their output.
- **Phase 2, Lane P:** fold the Phase 1 results into the plan. No separate research phase.
- **Engine/relay, Phase 3 and Phase 4:** standard patterns. Skip research.

### Open decisions for the roadmap

1. **Sequencer placement.** ARCHITECTURE recommends the relay owns `rev++` and the op log, so every client runs the same code path. `08` puts it in the host panel. The host still approves and supplies the snapshot either way.
2. **Clip IDs.** Core could use positional IDs (`v{track}:{clip}` at join time), with `nodeId` only as an integrity check, and switch to `nodeId` when stretch `move` lands. PROJECT.md's Key Decision currently says `nodeId` plus a guest index map.
3. **Change feed.** Research recommends promoting it to core. It is about 30 lines over the commit stream.
4. **Demo script.** The `08-mvp.md` §11 script uses a move (step 4) and a change feed (step 7). It needs a core-only rewrite.

Smaller conflicts, settled by research:

- Follow STACK: no `--enable-nodejs`. ARCHITECTURE's structure sketch lists it.
- The firewall rule uses `profile=any`, not Private only.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Versions verified on the installed Premiere and in Adobe repos |
| Features | MEDIUM | Competitor facts from vendor pages; the demo-impact ranking is judgement |
| Architecture | MEDIUM | The sync model is HIGH; Premiere API behavior is MEDIUM-LOW until the probes run |
| Pitfalls | MEDIUM-LOW | Runtime API behavior is undocumented and rests on forum reports |

**Overall confidence:** MEDIUM

### Gaps to Address

- Whether `setValue` updates the Program monitor. This is the kill test.
- The Position value format, Rotation above 360, and Uniform Scale behavior.
- Event coverage for param edits, and whether the selection event is `onActiveSequenceSelectionChanged` or `onSequenceSelectionChanged`.
- `nodeId` stability, and what `start`/`end`/`move()` actually do. Stretch only.
- Scan cost for 4 clips and for 50.
- Whether a changed `.jsx` needs a Premiere restart, and whether CEP follows a junction.
- Venue Wi-Fi client isolation, and whether cloudflared passes WebSockets there.
- Undo behavior after a remote `setValue`.
- Team Projects' current status, for the pitch claim.

## Sources

### Primary (HIGH confidence)
- Installed Premiere 22.3.1 binaries: `CEPHtmlEngine` 11.3.0, `libcef.dll` Chromium 88, strings in `ScriptLayerPPro.dll`
- Adobe CEP-Resources (CEP 11.1 Cookbook, `CSInterface.js` v11.0.0) and the manifests of Adobe's own panels in this install
- npm registry (`ws` 8.22.0)

### Secondary (MEDIUM confidence)
- Adobe Premiere Pro scripting docs repo and the PProPanel sample
- Cloudflare Tunnel and proxy docs
- Competitor vendor and help pages (Team Projects, Productions, Frame.io, Resolve, Descript)

### Tertiary (LOW confidence)
- Adobe community forum reports on Position units, `setValue` behavior, event names and the ExtendScript Debugger with 22.x

---
*Research completed: 2026-10-10*
*Ready for roadmap: yes*
*Written by orchestrator (#222 self-heal: synthesizer could not write the file and returned the synthesis inline)*
