# Architecture Research

**Domain:** Live two-user timeline sync for a desktop app with no collaboration API (Premiere Pro 22.3.1, CEP panel + ExtendScript bridge + Node `ws` relay)
**Researched:** 2026-10-10
**Confidence:** MEDIUM overall. The sync model is HIGH (well-established pattern, reasoned through for this case). The Premiere API behavior is MEDIUM-LOW: docs confirm the read/write surface, but event coverage, `nodeId` stability, scan cost and `evalScript` blocking are unverified until the Phase 0 checks run on real Premiere.

## Verdict on the `08-mvp.md` architecture

The architecture in `08` is the right shape. It is the standard pattern for this situation: poll-and-diff against a shadow copy to detect local edits, one total order for edits, last-writer-wins per field, optimistic local state with a pending mark. Keep it. The changes below fix specific failure modes that would otherwise surface during the overnight build or on stage.

| `08` decision | Verdict | Change |
|---|---|---|
| Host-authoritative `rev` ordering, LWW per field | **Validate the model; refine where it runs** | Run the sequencer (the `++rev` stamp and an op log) inside the relay, which already sits on the host laptop. All three clients (host panel, guest panel, fake-peer) then run one identical client code path. See Pattern 2. |
| Shadow + pending-field rule | **Validate, with 4 fixes** | (a) `pending[field]` stores the latest local opId and clears only on a commit for that exact opId. (b) Shadow is set from a read-back after apply, and compare uses an epsilon. (c) `applyOps` is compare-and-set against the shadow. (d) A pending TTL triggers resend or resync. See Pattern 3. |
| Snapshot diff every 1 s + sequence events | **Validate; change the mix** | Events are hints only, never the source of truth. Add a fast path: poll the selected clips' params and the playhead at about 4 Hz, and do the full scan at 1 Hz. A pure 1 Hz scan has a worst case near 1.1 s before network and apply time, which is too tight against the "1-2 s" goal. See Pattern 4. |
| `evalScript` bridge | **Validate; add a call discipline** | One `evalScript` in flight at a time, one call per tick, every JSX entry point wrapped in try/catch returning a JSON envelope, and a watchdog timeout. See Pattern 5. |
| Clip ID = host `nodeId`, guest map by track/clip index | **Validate the join-time map; challenge `nodeId` as the core wire ID** | The core has no structural edits, so `(trackIndex, clipIndex)` is already a stable ID for the whole session. Use it as the wire `clipId` in core and record `nodeId` only as an optional integrity check. Switch to `nodeId` when stretch `move` lands. This removes the biggest unverified API dependency from the critical path. See Pattern 6. |
| `applying = true` flag, ignore events while applying | **Challenge** | `CSXSEvent`s reach the panel asynchronously, so they can arrive after the flag clears. The flag cannot be the echo guard. Shadow comparison is the guard. |
| Relay as a separate Node process on the host laptop | **Validate** | Keep it separate: a panel reload during dev must not kill the session, and `fake-peer.js` and the integration tests need it standalone. |
| Join by snapshot + diff-apply | **Validate; add `rev` replay** | Guest sends `resume{lastRev}` after the snapshot. The relay replays buffered commits newer than the snapshot rev, so nothing is lost between snapshot and live. |
| Not in `08` | **Add** | A state-hash check and a manual "Resync from host" button. This is the demo safety net for any drift bug found at 3 a.m. |

## Standard Architecture

### System Overview

```
 HOST LAPTOP (Windows)                                              GUEST LAPTOP (Windows)
┌─────────────────────────────────────────┐                ┌─────────────────────────────────────────┐
│ Premiere Pro 22.3.1                     │                │ Premiere Pro 22.3.1                     │
│  ┌───────────────────────────────────┐  │                │  ┌───────────────────────────────────┐  │
│  │ bridge.jsx  (ExtendScript, ES3)   │  │                │  │ bridge.jsx  (ExtendScript, ES3)   │  │
│  │  tick() / applyOps() / bindEvents │  │                │  │  tick() / applyOps() / bindEvents │  │
│  └──────────────▲────────────────────┘  │                │  └──────────────▲────────────────────┘  │
│        evalScript│(string JSON) │CSXSEvent│                │        evalScript│(string JSON) │CSXSEvent│
│  ┌──────────────┴────────────────────┐  │                │  ┌──────────────┴────────────────────┐  │
│  │ CEP panel (Chromium + JS)         │  │                │  │ CEP panel (Chromium + JS)         │  │
│  │  bridge-client.js  JSX call queue │  │                │  │  bridge-client.js  JSX call queue │  │
│  │  sync.js           pure engine    │  │                │  │  sync.js           pure engine    │  │
│  │  main.js + UI      WS, timers     │  │                │  │  main.js + UI      WS, timers     │  │
│  └──────────────┬────────────────────┘  │                │  └──────────────┬────────────────────┘  │
└─────────────────┼───────────────────────┘                └─────────────────┼───────────────────────┘
        ws://localhost:8080                                       ws://<host IPv4>:8080
                  │                                                          │
                  └──────────────►  relay.js (Node, on host)  ◄──────────────┘
                                    rooms by code, join approval,
                                    rev stamping + op log (sequencer),
                                    fan-out, presence passthrough
```

### Component Responsibilities

| Component | Responsibility | Talks to | Must NOT |
|---|---|---|---|
| `bridge.jsx` | The only code that touches Premiere objects. `tick(mode, selectedClipIds)` returns playhead, selection, params of watched clips, and optionally the full clip list. `applyOps(ops)` does compare-and-set writes and returns read-backs. `bindEvents()` dispatches payload-free "dirty" `CSXSEvent`s. | `bridge-client.js` (only) | Hold sync state, know about the network, or return more than a few KB. |
| `bridge-client.js` | Wraps `csInterface.evalScript` in a serialized queue. Handles JSON encode/decode, the error envelope, the watchdog, and priority (apply before tick). Exposes `tick()` and `applyOps()` as promises. | `bridge.jsx`, `main.js` | Make sync decisions. |
| `sync.js` | Pure engine: shadow, pending, rev, diff, commit handling, state hash. Takes events in, returns effects out (`send`, `apply`, `ui`). No `window`, no `evalScript`, no `WebSocket`. | `main.js` (as a library) | Call anything with side effects. |
| `main.js` + `index.html` | Wires timers, WebSocket, bridge-client and sync.js together. Renders session UI, peers, presence, status badge. | everything in the panel | Contain sync rules. |
| `relay.js` | Rooms by code, `create`/`join`/`approve`, rev stamping, op log, fan-out, replay on `resume`. Never interprets edit contents beyond `{opId, author}`. | both panels, `fake-peer.js` | Know what a clip is. |
| `fake-peer.js` | A relay client that runs `sync.js` with a `FakeBridge`. Lets one person test with one Premiere, and drives the integration tests. | `relay.js` | Diverge from the panel's client logic (it must import the same `sync.js`). |
| `FakeBridge` (test) | In-memory object implementing the same `tick`/`applyOps` contract as `bridge.jsx`. | `sync.js` tests, `fake-peer.js` | — |

## Recommended Project Structure

```
premiere-collab/
├── relay/
│   ├── relay.js            # rooms + approval + sequencer (rev stamp, op log, resume replay)
│   ├── fake-peer.js        # headless client: sync.js + FakeBridge + scripted edits
│   └── package.json        # ws only
├── panel/
│   ├── CSXS/manifest.xml   # PPRO host, --enable-nodejs --mixed-context (Node optional; WS is browser-native)
│   ├── .debug              # port 8088
│   ├── index.html
│   ├── js/
│   │   ├── CSInterface.js  # CEP 11 copy
│   │   ├── sync.js         # PURE engine (UMD so node --test can require it)
│   │   ├── bridge-client.js# evalScript queue/envelope/watchdog
│   │   └── main.js         # glue + UI
│   └── jsx/
│       ├── json2.js        # ES3 JSON polyfill
│       └── bridge.jsx      # tick / applyOps / bindEvents
└── test/
    ├── fake-bridge.js      # in-memory timeline implementing the bridge contract
    ├── sync.test.js        # unit: diff, pending, CAS-retry, hash
    └── integration.test.js # real relay + 2 sync engines + 2 FakeBridges, concurrent edits converge
```

### Structure Rationale

- **`sync.js` pure, `FakeBridge` as a twin of `bridge.jsx`:** this is the single most valuable structural decision for a 12-hour build. Roughly 90 percent of the logic can be built and proven with `node --test` while nobody is at a Premiere machine. Premiere-bound work is confined to `bridge.jsx` and glue.
- **Bridge contract is the seam:** `tick()`/`applyOps()` JSON shapes are agreed first (Phase 1), so the Premiere-bound lane and the Premiere-free lane can work in parallel and meet at integration.
- **Relay stays dumb about edits:** the only edit-shaped data it reads is `opId`/`author`, so adding stretch op kinds never touches the relay.

## Architectural Patterns

### Pattern 1: Functional core, imperative shell

**What:** `sync.js` exports `createEngine(me)` with methods that take an input and return `{effects: [...]}`: `onScan(scan)`, `onCommit(commit)`, `onApplyResult(res)`, `onSnapshot(snap)`, `onTimer(now)`. `main.js` executes the effects. Time and randomness (opId generation) are injected.
**When to use:** always here. It is what makes the two-peer convergence tests possible without Premiere.
**Trade-offs:** a little ceremony up front; pays back at the first concurrency bug.

```js
// main.js shell (sketch)
for (const fx of engine.onScan(scan)) {
  if (fx.type === 'send')  ws.send(JSON.stringify(fx.msg));
  if (fx.type === 'apply') bridge.applyOps(fx.ops).then(r => run(engine.onApplyResult(r)));
  if (fx.type === 'ui')    render(fx);
}
```

### Pattern 2: Single sequencer, symmetric clients

**What:** one total order of edits, and every client runs the same algorithm. In `08`, the host has a special path: its edit is "already applied", gets a `rev` after the fact, and its shadow is updated differently from the guest's. That is two algorithms with a subtle interleaving between them. Instead, let the relay (which already runs on the host laptop, so "host-authoritative" still holds as a product story) own `rev++` and the op log. Every client, host included, does: local edit → pending + send `op` → receive `commit` in `rev` order → clear pending on own commit, skip foreign commits for pending fields, apply the rest.
**When to use:** whenever host and guest would otherwise need different code. For two peers and last-writer-wins fields it is strictly simpler.
**Trade-offs:** the relay gains about 10 lines (stamp, append, broadcast, replay). If the team prefers to keep the sequencer in the host panel, the same algorithm works with the host panel acting as sequencer, but then keep host-as-client and host-as-sequencer as two separate objects inside `sync.js` and test both. Either way the **host still provides the join snapshot** and the host still **approves joiners**.

Convergence check (field F, ops A then B or B then A):
- Order A(rev1), B(rev2): A clears pending on commit1, applies commit2 (B). B skips commit1 (pending), clears on commit2. Both end with B.
- Order B(rev1), A(rev2): symmetrical. Both end with A. The last op in `rev` order always wins.

### Pattern 3: Shadow + pending, hardened

**What:** the `08` rule plus four fixes.

```js
// sync.js core (sketch)
onScan(scan) {                                  // scan = {clips: {clipId: {field: value}}}
  const fx = [];
  for (const [k, v] of flatten(scan)) {
    if (!approxEq(v, this.shadow[k])) {         // epsilon, not ===
      this.shadow[k] = v;
      const opId = this.nextOpId();
      this.pending[k] = opId;                   // latest local op wins the slot
      fx.push(send({type:'op', opId, author:this.me, kind:'param', clipId:k.clip, field:k.field, value:v}));
    }
  }
  return coalesce(fx);                          // keep only the newest op per field per tick
}
onCommit(c) {
  if (c.rev !== this.rev + 1) return [send({type:'resume', lastRev:this.rev})]; // gap
  this.rev = c.rev;
  const k = key(c.op);
  if (c.op.author === this.me) { if (this.pending[k] === c.op.opId) delete this.pending[k]; return [feed(c)]; }
  if (this.pending[k]) return [feed(c)];        // local op will be later in order: it wins
  return [apply(c.op, /*expect*/ this.shadow[k])];
}
onApplyResult(r) {
  if (r.status === 'dirty') return [scanNow(), replay(r.commit)]; // CAS failed: scan first, then re-run onCommit
  this.shadow[key(r.op)] = r.readback;          // truth from Premiere, not from the sent value
  return [];
}
```

The four fixes:
1. **Pending holds the latest opId.** During a drag, a client emits several ops for one field. An early commit for `opA` must not clear the mark while `opA2` is still in flight.
2. **Read-back plus epsilon.** Premiere can round or quantize a written value. If the shadow holds the value we sent and Premiere reports a slightly different one, the next scan sees a "change" and ping-pongs forever. Set the shadow from the read-back returned by `applyOps`, and compare floats with a tolerance (about 1e-4 relative). Compare tick strings exactly.
3. **Compare-and-set on apply.** `applyOps` receives `expect` (the shadow value) and writes only if the current Premiere value still matches. If it does not, the user has an edit the panel has not scanned yet. Return `dirty`; the panel scans, which creates a pending local op, then re-runs the commit, which now skips. This closes the hole where a remote apply silently overwrites an unscanned local edit. It works the same on host and guest.
4. **Pending TTL.** If a pending mark is older than about 3 s (dropped socket), resend once, then resync. Otherwise the field is stuck ignoring remote changes forever.

### Pattern 4: Events are hints; tiered polling is the truth

**What:** treat `app.bind` events as "dirty" nudges that trigger an immediate scan, never as data. Correctness comes from polling, so a missing event costs latency, not correctness. Use two tiers:

| Tier | Rate | Content | Why |
|---|---|---|---|
| Fast | about 4 Hz | playhead, selection, params of the clips currently selected on either side | A user editing Motion or Opacity in Effect Controls has that clip selected. Few clips, few reads, sub-second latency. Doubles as presence. |
| Full | 1 Hz, plus any event nudge | all clips in the active sequence, all watched params (cap about 50 clips) | Catches edits made without selection, drift, and anything the fast path missed. |

Both tiers are the same `tick(mode, watchIds)` JSX call, so there is still one `evalScript` per tick. Make the interval adaptive: measure scan duration `d`; next interval = `max(250 ms, 5 * d)`. If a full scan takes 80 ms, the fast tier slows rather than starving Premiere's UI thread.

**When to use:** whenever event coverage is unverified. The docs and Adobe sample confirm the event names exist (`onActiveSequenceStructureChanged`, `onActiveSequenceSelectionChanged`, `onActiveSequenceChanged`, and others), but nothing found confirms that they fire for Motion/Opacity edits. Treat "fires for param edits" as probably false until Phase 0 shows otherwise.
**Trade-offs:** the fast tier adds a second code path in `tick()`. It is worth it because it is what makes the demo feel live.

### Pattern 5: A disciplined `evalScript` boundary

**What:** `evalScript` is an asynchronous string-in/string-out call into the ExtendScript engine, which runs on Premiere's host thread. Calls are serialized, and a slow call can stall Premiere's UI. Rules:
- **One in flight.** `bridge-client.js` keeps a priority queue: `applyOps` > `tick` > anything else. A tick is dropped, not queued, if one is already queued. Process each result (including the diff) synchronously in the callback **before** dispatching the next call. That guarantees a scan never overlaps an apply, so the shadow is never stale relative to the order of calls.
- **One call per tick.** Send everything the tick needs in one string and get everything back in one string. Never loop over clips from the panel.
- **Envelope.** Every JSX entry point is `try { return JSON.stringify({ok:true, data:...}) } catch(e) { return JSON.stringify({ok:false, err:String(e)}) }`. Uncaught errors return the non-JSON string `EvalScript error.` and kill the loop otherwise.
- **Watchdog.** If no callback in about 5 s, log, mark the bridge degraded, and continue. One report found `evalScript` never returning on a different Premiere version; 22.3.1 is untested, so assume it can happen.
- **Small payloads.** Return only watched params and ticks strings; send ops, not snapshots, in the JS→JSX direction. ExtendScript JSON handling is slow at large sizes (one report: 10 MB took tens of minutes), but the 50-clip scale here is roughly 10 KB and is fine.
- **Cache indices, not objects.** Object handles cannot live across calls. Resolve the Motion/Opacity component index and param indices once per clip at join, then reuse the indices, re-checking `displayName` only on a mismatch. Note `displayName` is localized, so the demo requires English UI on both machines.

### Pattern 6: Stable clip identity, in two layers

**What:** the wire `clipId` is the **host's join-time position** `v{trackIndex}:{clipIndex}` for the core. It is the same on both machines because both open the same project, and it cannot change because the core scope has no add, remove, or reorder. The bridge also reads each clip's local `nodeId` and stores `clipId → nodeId` as an integrity check: if a scan finds a different track/clip count, or a clip name/`nodeId` at a position no longer matches, the panel raises "structure diverged" and offers Resync, rather than writing params into the wrong clip.
**When to use:** core scope (Motion + Opacity). When stretch `move` lands, a clip can change index (passing a neighbor), so switch identity to the host `nodeId` with a guest map `hostNodeId → localNodeId` built at join, as `08` §6.1 describes. That map then depends on `nodeId` staying constant for one machine during a session (Phase 0 check), with the clip-name tag `Hero [cu:a1b2]` as the fallback.
**Trade-offs:** positional IDs are fragile only if someone edits structure mid-demo. The demo script forbids that, and the divergence check catches accidents.

### Pattern 7: Snapshot-then-replay join

**What:** the join order that loses nothing.
1. Guest `join` → host `approve` → relay admits guest.
2. Host sends `snapshot{rev: N, clips}` built from its shadow (not a fresh scan).
3. Guest diff-applies the snapshot through the same `applyOps` path, sets its shadow and `rev = N`, then sends `resume{lastRev: N}`.
4. Relay replays logged commits with `rev > N`, then streams live.
Edits during steps 2-3 are covered by the replay. Without step 4 you get a silent divergence window that only shows up under concurrent edits on stage.

## Data Flow

### Local edit → remote Premiere (the hot path)

```
User drags Opacity on A
  → [A bridge.jsx tick(fast)]  read selected-clip params, playhead
  → [A bridge-client] JSON string back to panel (in callback, before next call)
  → [A sync.js onScan] diff vs shadow → shadow updated, pending[F]=opId, effect: send op
  → [A main.js] ws.send(op) ──────────────► [relay] rev++ ; log.push ; broadcast commit
  ◄───────────── commit(rev, op) ──────────┤
  [A sync.js onCommit] own opId → clear pending[F] (value is already local)
  [B sync.js onCommit] foreign, F not pending → effect: apply(op, expect=shadow[F])
  → [B bridge-client] applyOps (priority) → [B bridge.jsx] CAS check, setValue, read back
  → [B sync.js onApplyResult] shadow[F] = readback   (next scan sees no diff → no echo)
```

Latency budget for this path (estimates, to be measured in Phase 0): detection up to 250 ms (fast tier) + scan 10-50 ms + LAN WebSocket under 10 ms + queue wait up to one tick + apply 10-50 ms, so roughly 0.3-0.6 s. The full-scan-only path is up to about 1.1 s plus the same network and apply time, which is why the fast tier exists.

### Presence (lossy, never logged)

```
tick(fast) → {playhead, selection} → sync.js → ws {type:'presence', user, selectedIds, playheadTicks}
relay: forward to others only, no rev, no log, drop if socket backed up
panel: render peer list, selected clip chips, remote timecode. Do NOT call setSelected()/setPlayerPosition()
       on the local sequence for remote presence, because that would hijack the user's own selection and playhead.
```

### State Management

```
sync.js state (per panel):  rev | shadow{clip|field → value} | pending{clip|field → opId} | peers | lastHash
Premiere timeline = the real store.  shadow = last value we believe Premiere held and the network agrees on.

   Premiere ──tick──► scan ──onScan──► shadow, pending, send(op)
   relay ──commit──► onCommit ──► apply(op) ──CAS+readback──► onApplyResult ──► shadow
```

### Key Data Flows

1. **Session start:** host panel → relay `create` → code; guest `join{code,name,color}` → relay → host `join_request` → host `approve` → Pattern 7.
2. **Local edit:** Pattern 4 scan → engine diff → `op` → relay stamp → `commit` to everyone (including the author, which uses it as the ack).
3. **Remote apply:** `commit` → engine → `applyOps` with CAS → read-back → shadow.
4. **Drift safety net:** every about 5 s each panel sends `hash` (hash of sorted shadow). Mismatch while no ops are pending → show a warning and auto-request `snapshot` from the host. A manual "Resync" button does the same.
5. **Change feed:** derived from the commit stream (`author`, `field`, `rev`). It costs about 30 lines on top of the commit handler, so build it right after presence even though `PROJECT.md` lists it as stretch.

### Message set (delta from `08` §7)

| Type | Direction | Notes |
|---|---|---|
| `create`/`created`, `join`, `join_request`, `approve`, `joined` | as in `08` | Unchanged. |
| `snapshot` | host → guest | `rev`, `clips` keyed by `clipId`, built from the host shadow. |
| `op` | client → relay | `opId`, `author`, `kind`, `clipId`, `field`, `value`. One field per op in core (Position is one field with an `[x,y]` value). |
| `commit` | relay → all | `rev` (gap-free), the op including `opId` and `author`. |
| `resume` | client → relay | `lastRev`. Relay replays the log tail. If the gap is too old or the log is missing, the host sends a fresh snapshot. |
| `presence` | each → others | Lossy, about 4 Hz, not logged. |
| `hash` | each → host | Drift check. |

## Scaling Considerations

The scale axis here is clips and tick rate, not users (the demo is 2 users; more than 2 is out of scope).

| Scale | Architecture Adjustments |
|---|---|
| 4 clips (demo project), 2 users | Everything above fits comfortably. Full scan of 4 clips x about 4 params is roughly 16-20 ExtendScript object reads per tick. Run both tiers as specified. |
| about 50 clips (the planning cap) | The full scan is about 200+ object reads. Measure it in Phase 0. If it exceeds about 100 ms, run full scan at 0.5 Hz and rely on the fast tier plus event nudges. |
| Hundreds of clips or more users | Out of scope. Would need event-driven dirty tracking (UXP) and a real server. Do not design for it. |

### Scaling Priorities

1. **First bottleneck:** ExtendScript scan duration. Fix: adaptive interval, fast tier limited to selected clips, cap at 50 clips.
2. **Second bottleneck:** apply-stall during active local drags (remote `setValue` with UI refresh while the user is mid-drag). Fix: the pending rule skips the same field; for different fields, apply with `updateUI` only when the clip is not the user's selection, if Phase 0 shows jank.

## Anti-Patterns

### Anti-Pattern 1: Trusting events for correctness

**What people do:** apply or send edits straight from `onActiveSequenceStructureChanged`.
**Why it's wrong:** event coverage for param edits is unverified, events can arrive late or in bursts, and they carry no values. A missing event becomes a missed edit.
**Do this instead:** events trigger an immediate scan; scans are the source of truth (Pattern 4).

### Anti-Pattern 2: An `applying` flag as the echo guard

**What people do:** set `applying = true` around `evalScript(applyOps)` and drop events while it is set.
**Why it's wrong:** the `evalScript` callback and `CSXSEvent` delivery are both asynchronous. Events from the apply can land after the flag clears, and a scan can start before the apply finishes.
**Do this instead:** serialize calls (Pattern 5), update the shadow from the read-back, and diff with an epsilon. If the shadow equals Premiere's actual value, no op is generated no matter when the event arrives. Keep a short ignore window only as a belt-and-braces measure.

### Anti-Pattern 3: Writing the sent value into the shadow

**What people do:** after applying a remote value, copy the value from the message into the shadow.
**Why it's wrong:** Premiere may round or clamp it. The next scan reads a different number, sees a "local edit", and sends it back; the other side does the same. Infinite ping-pong at tick rate.
**Do this instead:** shadow from the read-back, tolerance compare.

### Anti-Pattern 4: Unconditional remote apply

**What people do:** `setValue` immediately on every commit that is not pending.
**Why it's wrong:** an edit the user made in the last few hundred ms, not yet scanned, is overwritten and never sent. It looks like "my change reverted".
**Do this instead:** CAS on apply, scan on `dirty`, then re-evaluate (Pattern 3, fix 3).

### Anti-Pattern 5: Per-clip `evalScript` calls from a loop

**What people do:** `for each clip: evalScript(readClip(i))`.
**Why it's wrong:** each call waits in the queue and pays a round trip; 50 clips at 1 Hz floods the bridge and starves applies.
**Do this instead:** one batched JSX call per tick returning one JSON string.

### Anti-Pattern 6: Setting the local selection or playhead to show a remote user

**What people do:** mirror the remote playhead or selection into the local sequence for "presence".
**Why it's wrong:** it fights the local user and also generates fake local edits (selection changes trigger events and scans).
**Do this instead:** show presence in the panel only.

### Anti-Pattern 7: Two client code paths (host vs guest)

**What people do:** the host panel special-cases its own edits ("already applied, assign rev now"), the guest does something else.
**Why it's wrong:** every concurrency bug lives in the seam between the two. Tests must cover both, and a fake peer cannot reuse the host path.
**Do this instead:** Pattern 2, symmetric clients with a sequencer.

## Riskiest Boundaries (ranked)

| # | Boundary | Why risky | Containment |
|---|---|---|---|
| 1 | **Premiere object model ↔ `bridge.jsx`** (`getValue`/`setValue` behavior) | `ComponentParam.getValue`/`setValue` "can only work on parameters which are not time-variant" per the docs, so any clip with Motion keyframes (or a stopwatch toggled on) cannot be read or written. `displayName` is localized. Position value format (normalized vs pixels) is unconfirmed. `setValue(value, updateUI)` is documented as taking an integer `updateUI` flag (`1` refreshes UI). | Phase 0 check 6. Demo project with no keyframes and English UI. try/catch each param; mark unreadable params "unsynced" in the UI rather than failing the scan. |
| 2 | **Event reliability** | Event names are confirmed in Adobe's sample panel (`onActiveSequenceStructureChanged`, `onActiveSequenceSelectionChanged`, `onActiveSequenceChanged`, and others). Whether they fire for Motion/Opacity edits is unverified, and the sample panel is the latest version, not 22.3.1. | Pattern 4. The system is correct with zero events; events only cut latency. Phase 0 check 5 decides how much the 1 s timer matters. |
| 3 | **`evalScript` latency and blocking** | ExtendScript runs on Premiere's host thread, so a slow scan can cause UI stutter and delays queued applies. Scan cost for 50 clips is unmeasured. Calls queue; an unhandled error returns a non-JSON string. | Pattern 5 plus adaptive interval. Measure `tick()` duration on the demo project and on a 50-clip dummy sequence during Phase 0 and print it in the panel's debug line forever after. |
| 4 | **Echo and convergence** | The classic way these systems fail: infinite ping-pong, flicker, or lost edits. | Patterns 2 and 3, the two-engine integration test, state hash, Resync button. |
| 5 | **Clip identity** | `nodeId` is undocumented ("Add a description") and its read/write status is not specified in the docs; stability across save/reopen/machines is unknown. | Pattern 6: positional ID in core, `nodeId` optional integrity check. |
| 6 | **Network** | Venue Wi-Fi may block client-to-client traffic; Windows Firewall prompt on first `node` run. | Phone hotspot is the default plan, not the fallback. Test the relay from the second laptop before the build starts. `cloudflared` is plan C; test WebSockets over it. |
| 7 | **Undo stack pollution** | Remote edits land in the local undo stack. Local Ctrl+Z may revert a remote change, which is then seen as a local edit and re-broadcast. | Acceptable for the demo, because it behaves as "undo wins, last writer". Say "don't undo on stage" in the demo script. |

## Build Order (12-hour build, demoable vertical slice early)

Two lanes can run in parallel because the seam between them (the bridge contract and the message set) is fixed up front:
- **Lane P (Premiere-bound):** CEP shell, `bridge.jsx`, `bridge-client.js`, UI. Needs a machine with Premiere.
- **Lane S (Premiere-free):** `sync.js`, `FakeBridge`, `relay.js`, `fake-peer.js`, tests. Needs only Node.

With one person, do the phases in order.

| Phase | Deliverable | Depends on | Demoable output | Rough time |
|---|---|---|---|---|
| **0. Spike / the 6 checks** | `08` §12 checks plus: time a `tick()` on the demo project, confirm `getValue`/`setValue` for Position/Scale/Rotation/Opacity, confirm whether events fire for param edits, confirm `getSelection()`/`getPlayerPosition()` cost. Also fix the bridge contract JSON shapes. | nothing | A panel on both machines that logs `tick()` JSON and a relay round-trip from machine 2. | 1-1.5 h |
| **1. Local loop on one Premiere (Lane P)** | `bridge.jsx` `tick`/`applyOps` with envelope and CAS; `bridge-client.js` queue; panel shows scan JSON; a paste-an-op box applies it. | Phase 0 | "Edit Opacity in Premiere → see the op JSON in the panel. Paste an op → Opacity changes." | 1.5-2 h |
| **1b. Engine + relay (Lane S, parallel with 0-1)** | `sync.js`, `FakeBridge`, `relay.js` with sequencer + op log + approval, `fake-peer.js`, unit and integration tests (concurrent edits converge, no echo, pending rule, CAS retry). | contract only | `node --test` green. `fake-peer.js` can drive a field. | 2.5-3 h |
| **2. First end-to-end slice (the early demo)** | Wire panel ↔ relay ↔ `fake-peer.js` on one machine: fake peer sets Opacity, the real Premiere timeline changes; edit in Premiere, the fake peer's log shows it. Then second real machine replacing the fake peer. One-direction (host → guest) first, then both. | 1, 1b | **Host changes Opacity, guest Premiere updates within about 1 s.** This is the milestone to hit by about hour 5-6. Everything after it is additive. | 1.5 h |
| **3. Session UX + join** | Host/Join/Approve UI, status badge, names/colors, snapshot-then-replay join with diff-apply of differences (make the guest start deliberately different so the join is visible). | 2 | Full connect story from `08` §11 steps 1-3. | 1.5 h |
| **4. Presence + feed** | Fast-tier selection/playhead to peer chips and remote timecode; change feed from commits. | 2 | `08` §11 steps 6-7. | 1 h |
| **5. Hardening** | Pending TTL, hash check and Resync button, adaptive tick interval, watchdog, reconnect via re-join, hotspot rehearsal, full demo-script dry runs on both laptops, record a fallback video. | 3, 4 | Demo-solid core. **This is the gate before any stretch work.** | 2 h, plus reserved buffer |
| **Stretch** | `trim` and `rename` first (field-shaped, same machinery as params); `move` last (needs `nodeId` identity switch and its API check). | 5 | — | only if time remains |

Ordering rationale:
- The pure engine and relay are scheduled first and in parallel because they carry the most logic and have the lowest external risk, while Phase 0 is what could change scope.
- The first real-world end-to-end slice is one field (Opacity) in one direction; widening to Position/Scale/Rotation and to both directions is mechanical once the loop works.
- Presence and feed sit after the edit loop. Presence reuses the fast-tier tick, so it costs little once Phase 1 exists.
- Hardening gets its own phase and a reserved buffer; the overnight timeline makes the late hours the most error-prone.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---|---|---|
| Premiere Pro 22.3.1 ExtendScript API | `evalScript` out, `CSXSEvent` in | Frozen API per `07`; test only on 22.3.1. |
| `ws` (Node) | Relay only; the panel uses the browser-native `WebSocket` | Pin a version compatible with the Node you run the relay on (Node 24 on the dev machine). The panel needs no Node modules. |
| `cloudflared` | Fallback tunnel to the host relay | Confirm WebSocket support before relying on it. |
| Windows Firewall | One-time allow for `node.exe` on Private networks | Hotspot networks may be classified Public; check this on the second laptop. |

### Internal Boundaries

| Boundary | Communication | Notes |
|---|---|---|
| `bridge.jsx` ↔ `bridge-client.js` | `evalScript(string)` → JSON string envelope; `CSXSEvent` payload-free nudges | Fix the shapes in Phase 0. Both `bridge.jsx` and `FakeBridge` must implement them. |
| `bridge-client.js` ↔ `main.js` | Promises | Single in-flight queue lives here only. |
| `main.js` ↔ `sync.js` | Method calls returning effect lists | `sync.js` has no I/O. |
| `main.js` ↔ `relay.js` | JSON over one WebSocket | Message set above. |
| `relay.js` ↔ `fake-peer.js` | Same JSON protocol | `fake-peer.js` imports `sync.js` unchanged. |

## Sources

- `research/live-collab/08-mvp.md` and `05-architecture-and-plan.md`, `07-premiere-pro-22-cep.md` (the architecture under review and its API assumptions). HIGH for what they say, MEDIUM for whether the API assumptions hold.
- Premiere Pro ExtendScript guide, TrackItem: https://ppro-scripting.docsforadobe.dev/item/trackitem/ (read/write `start`, `end`, `inPoint`, `outPoint`, `name`; `nodeId` listed with no description or access). HIGH (official community-maintained docs).
- Premiere Pro ExtendScript guide, ComponentParam: https://ppro-scripting.docsforadobe.dev/sequence/componentparam (`getValue`/`setValue` only for non-time-variant params; `displayName` localized; `setValue(value, updateUI)`). HIGH.
- Adobe CEP PProPanel sample, event registrations and `CSXSEvent` dispatch: https://raw.githubusercontent.com/Adobe-CEP/Samples/master/PProPanel/jsx/PPRO/Premiere.jsx (`app.bind` for `onActiveSequenceStructureChanged`, `onActiveSequenceSelectionChanged`, `onActiveSequenceChanged`, `onActiveSequenceTrackItemAdded/Removed`, `onProjectChanged`; `nodeId` only logged, never used as a key). HIGH for what is registered, nothing there confirms which edits fire which event.
- Adobe Community, listening to timeline changes: https://community.adobe.com/t5/premiere-pro-discussions/listen-to-timeline-changes-via-scripting/m-p/13930998/highlight/true (clip-move detection via structure-changed claimed but not confirmed; nothing on param edits or trims). LOW.
- Adobe Community, JSON parse slowness in ExtendScript: https://community.adobe.com/t5/premiere-pro-discussions/json-parse-extremely-slow-in-extendscript/m-p/13534456 and the thread on `evalScript` not returning on a newer Premiere: https://community.adobe.com/questions-729/critical-premiere-scripting-engine-does-not-respond-to-cep-evalscript-calls-1621640 (anecdotal; informs the watchdog and the small-payload rules). LOW.
- Pattern basis (shadow copy + poll-diff, single sequencer, last-writer-wins per field, optimistic apply with pending mark): general collaborative-editing practice as summarized in `research/live-collab/01` and `05` §5; MEDIUM-HIGH. The convergence argument in Pattern 2 is reasoned directly, not copied from a source.
- Not verified by any source and flagged for Phase 0: that `evalScript` execution blocks Premiere's UI thread (general CEP knowledge, no source confirmed it), the cost of a 50-clip scan, event coverage for param edits, Motion Position value format, and `nodeId` stability.

---
*Architecture research for: live two-user timeline sync, Premiere Pro 22.3.1 CEP*
*Researched: 2026-10-10*
