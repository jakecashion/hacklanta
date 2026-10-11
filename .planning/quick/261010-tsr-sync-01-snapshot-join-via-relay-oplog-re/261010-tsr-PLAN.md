---
phase: 261010-tsr-sync-01-snapshot-join-via-relay-oplog-re
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - premiere-collab/relay/relay.js
  - premiere-collab/panel/js/sync.js
  - premiere-collab/panel/js/main.js
  - premiere-collab/relay/fake-peer.js
  - premiere-collab/relay/test/relay.test.js
  - premiere-collab/relay/test/sync.test.js
  - premiere-collab/README.md
  - premiere-collab/TEST-PLAN-TWO-LAPTOPS.md
autonomous: true
requirements: [SYNC-01]

estimate:
  tokens: 45000
  raw_tokens: 45000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "A client that connects after edits were committed receives one `catchup` message right after `welcome`, holding the latest committed {rev, op} per (clipId, field) in ascending rev order, and its `rev` equals the relay's current rev"
    - "After a late joiner applies the catch-up, its timeline matches the host's for every logged (clipId, field), and polling it repeatedly sends no ops: relay rev stays still (no echo)"
    - "A client that reconnects gets each (clipId, field) at most once in its catch-up, values it already holds are skipped (not rewritten), and every later live commit reaches it exactly once"
    - "The Premiere panel adds ONE feed line starting `Caught up to rev` per connection; per-op catch-up details go to the log only, not the feed"
    - "The relay does not forward client-sent `catchup`, `commit`, `welcome`, `peers`, `pong` or `error` messages; `cursor` and other unknown types are still forwarded"
    - "`node fake-peer.js` prints the catch-up it receives on connect, so the join can be watched on one laptop"
  artifacts:
    - path: premiere-collab/relay/relay.js
      provides: "collapseLog(log) export, catchup message on connection, server-only type filter"
      contains: "catchup"
    - path: premiere-collab/panel/js/sync.js
      provides: "receiveCatchup(commits) on the PCSync instance"
      contains: "receiveCatchup"
    - path: premiere-collab/panel/js/main.js
      provides: "onCatchup(msg): one batched pc_applyOps call, afterApply per result, one feed summary line"
      contains: "onCatchup"
    - path: premiere-collab/relay/fake-peer.js
      provides: "prints `Caught up to rev N` plus one line per caught-up op"
      contains: "catchup"
    - path: premiere-collab/relay/test/relay.test.js
      provides: "late-join, reconnect-no-duplicate, forged-message, collapseLog and fake-peer smoke tests"
    - path: premiere-collab/relay/test/sync.test.js
      provides: "receiveCatchup unit tests"
  key_links:
    - from: "premiere-collab/relay/relay.js connection handler"
      to: "collapseLog(opLog)"
      via: "ws.send({type:'catchup', rev, commits}) immediately after the welcome send"
      pattern: "type: 'catchup'"
    - from: "premiere-collab/panel/js/main.js sock.onmessage"
      to: "sync.receiveCatchup -> pc_applyOps -> sync.afterApply"
      via: "onCatchup(msg) enqueued on the same serial chain as startSync (onopen) and onCommit"
      pattern: "onCatchup"
    - from: "premiere-collab/panel/js/sync.js receiveCatchup"
      to: "receiveCommit"
      via: "each catch-up entry goes through the live rev/pending rules, then a shadow-epsilon skip"
      pattern: "receiveCatchup"
---

<objective>
SYNC-01 snapshot join, built as a relay opLog replay (approach locked by the user). When a panel connects, the relay sends it one `catchup` message: the latest committed value of each (clipId, field), in rev order. The panel applies it through the same sync engine and `pc_applyOps` path as live commits, so the shadow/no-echo rules hold and relay rev does not move after a join. A guest who clicks Connect after the host has changed Scale, Rotation or Opacity ends up with the host's values (ROADMAP Phase 3 success criterion 1).

Locked constraints from the orchestrator (honor exactly):
- Replay the relay opLog on join through the existing apply path. Collapse to the latest value per (clipId, field) before sending.
- After a join, rev must not climb (no echo). A reconnecting client must not get duplicate ops. The feed shows one catch-up summary line, not one line per replayed op.
- Document this known limit without solving it: edits made before a panel connected (including the host's own edits before the host clicked Connect) are not in the log.
- Laptop 2 is unavailable. Every gate is automated (`node --test` through `npm --prefix premiere-collab/relay test`, `node --check`, grep). Manual Premiere checks appear only in the post-task note in `<verification>`.
- Hackathon: speed over polish. Match the existing code style (2-space indent, single quotes, short comments, arrow functions in panel/relay JS). ES3 rules apply only to `bridge.jsx`, and this plan does not touch it (`pc_applyOps` already takes an array).

Purpose: the guest no longer has to start from a byte-identical, untouched timeline. Joining late or reconnecting after a Wi-Fi drop now catches up (fixes TEST-PLAN 4.1).
Output: relay catch-up message, `PCSync.receiveCatchup`, panel `onCatchup`, fake-peer catch-up print, tests (13 to about 21), README and TEST-PLAN notes.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/ROADMAP.md
@premiere-collab/relay/relay.js
@premiere-collab/panel/js/sync.js
@premiere-collab/panel/js/main.js
@premiere-collab/relay/fake-peer.js
@premiere-collab/relay/test/relay.test.js
@premiere-collab/relay/test/sync.test.js

<interfaces>
Current contracts the executor builds on (from the files above, 2026-10-10):

relay.js
- `start(port, { quiet })` returns `{ wss, rev (getter), opLog }`. `opLog` is an array of `{ rev, op }` and `op` is `{ opId, author, clipId, field, value }`. Only `validOp`-checked ops reach it.
- On 'connection' it sends `{ type: 'welcome', ips, rev }`. Messages: `ping` gets `pong`, `hello` sets the name and broadcasts `peers`, `op` is validated, gets the next rev, is pushed to opLog and broadcast as `{ type: 'commit', rev, op }` to everyone including the sender. Any other type is forwarded to everyone except the sender as `{ ...msg, from }`. This is how `cursor` from cursor.ps1 and fake-cursor.js travels.
- `module.exports = { start }`.

sync.js (UMD; `PCSync` global in the panel, `module.exports` under Node)
- `createSync({ author, epsilon = 0.05, idPrefix })` returns `{ reset(clips), diff(clips) -> ops[], receiveCommit({rev, op}) -> op|null, afterApply(clipId, field, readBack), lastRev, pendingCount, shadowValue(clipId, field), ownsOp(opId) }`.
- `receiveCommit` drops `rev <= lastRev`, sets lastRev, returns null when the key has a pending local op (and clears pending if it is ours), otherwise returns op. The shadow changes only in `afterApply`, from Premiere's read-back.

main.js
- One serial promise chain: `enqueue(fn)`. `sock.onopen` sends hello, then `startSync(name)`, which enqueues scan, `PCSync.createSync`, `sync.reset(clips)`. `onCommit(msg)` enqueues receiveCommit, then `jsx('pc_applyOps(' + JSON.stringify(JSON.stringify([op])) + ')')`, then `afterApply` per ok result, else logs `Apply failed`. `feed(text)` adds a line to the Changes list (max 30) and also logs it. `log(text)` writes to the log only. Helpers: `clipNames`, `FIELD_LABEL`, `fmt`, `showSyncStatus`.
- `onopen` always fires before any `onmessage` on the same socket, so a catch-up job enqueued from onmessage runs after that connection's startSync job.

bridge.jsx
- `pc_applyOps(opsJson)` takes a JSON array of ops and returns `{ ok, results: [{ clipId, field, after, ok } | { clipId, field, ok: false, err }] }`. No change needed.

Tests: `npm --prefix premiere-collab/relay test` runs `node --test test/*.test.js` (13/13 pass on 2026-10-10). relay.test.js has `fakeEditor(url, name)` with a fake timeline that rounds to 0.1, and `setup(t)`, which starts the relay on port 0 and connects Host and Guest together.
</interfaces>
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Tracer - late joiner catches up from the relay opLog, end to end, with no echo</name>
  <files>premiere-collab/relay/relay.js, premiere-collab/panel/js/sync.js, premiere-collab/relay/test/relay.test.js</files>
  <precondition>`npm --prefix premiere-collab/relay test` reports 13 pass, 0 fail before any edit (ws 8.22.0 is installed in premiere-collab/relay/node_modules).</precondition>
  <read_first>premiere-collab/relay/relay.js, premiere-collab/panel/js/sync.js, premiere-collab/relay/test/relay.test.js</read_first>
  <behavior>
    - New test "a late joiner catches up to the host's edits and nothing echoes": start the relay, connect only Host. Host edits Motion.Scale to 150 and polls, waits, edits Motion.Scale to 160 and Motion.Rotation to 45, polls, waits (relay.rev is 3). Then connect Guest with a pristine timeline and await its catch-up. Expect: the catchup message has rev === relay.rev (3) and commits.length === 2 (Scale collapsed to its latest, rev 2 and rev 3 in ascending order). Guest timeline v0:0 is Scale 160, Rotation 45, Opacity 100, the same as Host. guest.sync.lastRev === 3. After 5 rounds of both polling with short waits, relay.rev is still 3 and guest.sync.pendingCount is 0.
    - The 3 existing relay tests still pass. Both editors connect at rev 0 there and get an empty catch-up.
  </behavior>
  <action>
    Before editing: run `git fetch` and `git status -sb` at the repo root. Teammates push to `research`. If behind, `git pull --rebase` first. Read each file right before you write it. Leave the untracked `premiere-collab/docs/` alone, and stage only files listed in this task.

    RED (relay.test.js): extend `fakeEditor(url, name)`. Keep a list of every parsed incoming message on the editor (e.g. `ed.msgs`). Expose a `caughtUp` promise that resolves with the `catchup` message. On a `catchup` message, call `sync.receiveCatchup(msg.commits)`, write each returned op into the fake timeline with `round()`, and call `sync.afterApply` with the stored value. This mirrors what the panel will do in Task 3. Split `setup(t)` so a test can start the relay and get `{ relay, url }` first, then connect editors one at a time (e.g. a `startRelay(t)` helper that registers `relay.wss.close()` in `t.after`). Keep `setup` working for the existing tests on top of it, and close every editor socket in `t.after`. Add the behavior test above. Run it and confirm it fails: no catchup message, and receiveCatchup is not a function.

    GREEN (relay.js), per the locked "replay opLog, collapse to latest per (clip, param)" decision: add a pure `collapseLog(log)`. Walk the entries in order into a Map keyed `clipId + '|' + field`, so later entries overwrite earlier ones. Return the Map values sorted ascending by rev. Each element keeps the `{ rev, op }` shape of a commit. In the 'connection' handler, right after the welcome send, send `{ type: 'catchup', rev, commits: collapseLog(opLog) }` on that socket only. Add one `say` line with the entry count and rev. This needs no lock: the relay is single-threaded, so every later op gets a higher rev and arrives on the same socket after the catch-up. Export `collapseLog` next to `start`. In the header comment, describe the catchup message and the known limits: edits made in a panel before it connected never enter the log, and restarting the relay clears it.

    GREEN (sync.js): add `receiveCatchup(commits)`. Copy the array, sort the copy ascending by rev, and pass each entry through the existing `receiveCommit`, so the rev guard and pending rule are exactly the live rules. Return the array of ops to apply. Add it to the returned object. Add one line to the header rule list that says catch-up entries follow the same rules as live commits. Leave `receiveCommit`, `diff` and `reset` unchanged. Run the tests, then commit as `feat(sync): late joiner catches up from relay opLog (SYNC-01)`.
  </action>
  <verify>
    <automated>npm --prefix premiere-collab/relay test</automated>
  </verify>
  <done>The test run shows 14 pass and 0 fail, including the late-joiner test. relay.js sends `catchup` after `welcome` and exports `collapseLog`. sync.js exports `receiveCatchup` on the instance. Task committed.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Catch-up hardening - reconnect without duplicates, skip values already held, drop forged server messages</name>
  <files>premiere-collab/relay/relay.js, premiere-collab/panel/js/sync.js, premiere-collab/relay/test/relay.test.js, premiere-collab/relay/test/sync.test.js</files>
  <read_first>premiere-collab/relay/relay.js, premiere-collab/panel/js/sync.js, premiere-collab/relay/test/relay.test.js, premiere-collab/relay/test/sync.test.js</read_first>
  <behavior>
    - sync.test "catch-up applies in rev order even if sent out of order": reset baseline v0:0 at 100/0/100. receiveCatchup with [rev 3 Rotation 45, rev 1 Scale 150] returns 2 ops, Scale first, and lastRev is 3.
    - sync.test "catch-up skips values the timeline already has": baseline Scale 150. receiveCatchup with [rev 4 Scale 150.02] returns [] (within epsilon 0.05), and lastRev is still 4.
    - sync.test "live commits after a catch-up": after a catch-up up to rev 5, receiveCommit rev 5 returns null and rev 6 returns its op.
    - relay.test "collapseLog keeps the latest value per clip field": the log [rev1 v0:0 Scale 150, rev2 v0:0 Rotation 10, rev3 v0:0 Scale 160, rev4 v0:1 Scale 90] gives revs [2, 3, 4], and the v0:0 Scale entry has value 160.
    - relay.test "a reconnecting guest gets each field once and live commits exactly once": Host edits Scale to 150, then 160. Guest joins and catches up, then its socket closes. Host edits Opacity to 30. A new Guest editor reuses the first guest's timeline object, standing in for the same Premiere after a reconnect. Its catch-up has 2 commits (one per key), it applies only Opacity (Scale 160 is already held, so the apply counter is 1), and its timeline matches Host. Host then edits Rotation to 90. The new guest receives exactly one commit message with that rev and applies it. After 5 polling rounds, relay.rev is unchanged.
    - relay.test "relay drops client-sent server messages": with Host and Guest connected, Host sends a forged `{type:'catchup', rev:99, commits:[...Scale 5...]}` and a forged `{type:'commit', rev:99, op:{...}}`, then `{type:'cursor', x:1, y:1}`. Guest receives the cursor (with `from`), receives no catchup or commit message with rev 99, and its timeline Scale is still 100.
  </behavior>
  <action>
    Run `git fetch` and `git status -sb` again, and Read each file right before you edit it.

    RED: add the 3 sync.test cases (use the existing `clip()` helper) and the 3 relay.test cases above. In relay.test.js, import `collapseLog` from `../relay.js`. Let `fakeEditor` take an optional third argument, a starting timeline object (default: the pristine v0:0 at 100/0/100). Count the ops it actually writes (e.g. `ed.applied`) on both the catch-up path and the live commit path. Run them. The skip test and the forged-message test fail, and the others may already pass.

    GREEN (sync.js): in `receiveCatchup`, after `receiveCommit` returns an op, drop it when `shadowValue` for that key is a number within `epsilon` of `op.value`. The timeline already holds it, so nothing needs writing and no Premiere setValue is spent. lastRev still advances, because receiveCommit already set it. Leave the live `receiveCommit` path unchanged.

    GREEN (relay.js): add a `SERVER_ONLY` set holding welcome, catchup, commit, peers, pong and error. In the message handler, put a branch before the generic forward that returns silently when `msg.type` is in that set. This mitigates T-tsr-01: a forged catch-up or commit from any socket must never reach other panels' apply path. Keep `cursor` and any other unknown type forwarded as before. Run the tests, then commit as `fix(sync): catch-up skips held values, relay drops forged server messages`.
  </action>
  <verify>
    <automated>npm --prefix premiere-collab/relay test</automated>
  </verify>
  <done>The test run shows 20 pass and 0 fail. A reconnecting client gets one entry per key and each later commit once. Values it already holds are not reapplied. Forged catchup and commit messages are not forwarded, and cursor still is. Task committed.</done>
</task>

<task type="auto">
  <name>Task 3: Panel onCatchup (one feed line), fake-peer catch-up print, docs</name>
  <files>premiere-collab/panel/js/main.js, premiere-collab/relay/fake-peer.js, premiere-collab/relay/test/relay.test.js, premiere-collab/README.md, premiere-collab/TEST-PLAN-TWO-LAPTOPS.md</files>
  <read_first>premiere-collab/panel/js/main.js, premiere-collab/relay/fake-peer.js, premiere-collab/relay/test/relay.test.js, premiere-collab/README.md, premiere-collab/TEST-PLAN-TWO-LAPTOPS.md</read_first>
  <action>
    Run `git fetch` and `git status -sb` again, and Read each file right before you edit it.

    main.js: add `onCatchup(msg)` next to `onCommit`, with one `enqueue` job. If `!sync`, return. Take `total` = the length of `msg.commits || []` and `toApply = sync.receiveCatchup(msg.commits || [])`. For each op in toApply, call `log()` (log only, not feed) with a detail line in the onCommit wording, prefixed `Catch-up:`: author, clip name from `clipNames`, field label from `FIELD_LABEL`, `fmt(value)`. If toApply is not empty, make ONE batched `pc_applyOps` call with the whole array, using the same double `JSON.stringify` as onCommit. If `!res.ok`, log `Catch-up apply error`. Return if `sync` went null during the await. For each result, call `sync.afterApply` and count it applied when ok, and otherwise log `Apply failed` and count it failed. Then call `feed()` exactly once. The text starts `Caught up to rev ${msg.rev}:`. With total 0 it reads `nothing to catch up`. Otherwise it gives the applied count, the already-held count (`total - toApply.length`), the failed count only if above 0, and the distinct authors. End with `showSyncStatus()`. In `sock.onmessage`, add a `catchup` branch that calls `onCatchup(msg)`. Add a phrase about the Phase 3 catch-up on connect to the header comment. Do not touch `onCommit`, `startSync` or the poll loop. The catch-up depends on startSync's job (enqueued in onopen) running first on the same serial chain.

    fake-peer.js: handle `catchup`. Print `Caught up to rev ${msg.rev}: ${msg.commits.length} change(s)` and then one line per entry, in the same format as the commit print. Add a header-comment line saying that a fake-peer started after edits prints the catch-up it received.

    relay.test.js: add a test "fake-peer.js prints the catch-up on connect". Start the relay and connect a fake editor that commits Scale 150 (rev 1). Spawn `process.execPath` with the fake-peer.js path (`path.join(__dirname, '..', 'fake-peer.js')`) and the relay url. Collect stdout until it contains both `Caught up to rev 1` and `Motion.Scale = 150`, and fail after 3 s. Kill the child in `t.after`. Its first op is only sent after 4 s, so it never edits during the test.

    README.md (Live sync section): replace the sentence "Connecting does not copy the host's timeline yet (Phase 3); both laptops must start from the same project." with a short "Joining late / reconnecting" paragraph. The relay keeps every commit. A panel that connects gets one catch-up holding the latest value of each clip field, applied like a live edit with no echo, plus one feed line `Caught up to rev N`. List the known limits (documented, not solved, per the locked decision). Edits made before a panel connected, including the host's own edits before the host clicks Connect, are not in the log, so start the relay and connect the host before editing. Restarting the relay clears the log. A reconnecting laptop's offline edits are never sent, and they are overwritten for fields already in the log. Open the sequence before clicking Connect, because with no active sequence the catch-up apply fails and is logged. Add the one-laptop check: `node relay.js`, then `node fake-peer.js`, wait about 10 s, then click Connect in Premiere.

    TEST-PLAN-TWO-LAPTOPS.md: update the "no join snapshot yet" sentences in section 0 and in the Connection loss intro to describe the catch-up. Both laptops still start from the clean project, because clips match by V1 position and pre-connect edits are not logged. Change 4.1 Expected to: G's Hero jumps to Scale 80 on Connect and G's feed shows one `Caught up to rev N` line. Change 4.2 Expected to: known limit, H never gets 15, and G keeps 15 unless Rotation was edited earlier in the session. Run the checks, then commit as `feat(panel): apply relay catch-up on connect with one feed line (SYNC-01)`.
  </action>
  <verify>
    <automated>npm --prefix premiere-collab/relay test && node --check premiere-collab/panel/js/main.js && grep -c "onCatchup" premiere-collab/panel/js/main.js && grep -c "Caught up to rev" premiere-collab/panel/js/main.js premiere-collab/relay/fake-peer.js premiere-collab/README.md</automated>
  </verify>
  <done>The test run shows 21 pass and 0 fail, including the fake-peer smoke test. main.js parses, routes `catchup` to `onCatchup`, applies the batch in one `pc_applyOps` call, and writes one feed line per connection. fake-peer prints the catch-up. README and TEST-PLAN describe the catch-up and its known limits. Task committed.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| client -> relay | Any socket on the LAN or Tailscale network can connect to TCP 8080 and send JSON. No auth (by design: no session code, no Approve). |
| relay -> panel | Panels apply `commit` and now `catchup` payloads to the Premiere timeline through `pc_applyOps`. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-tsr-01 | Spoofing/Tampering | relay.js generic forward branch | medium | mitigate | Task 2: a `SERVER_ONLY` type set (welcome, catchup, commit, peers, pong, error) is dropped when a client sends it, so a forged catch-up or commit never reaches another panel's apply path. Covered by the "relay drops client-sent server messages" test. |
| T-tsr-02 | Tampering | catch-up payload contents | low | mitigate | The catch-up is built only from `opLog`, and only ops that passed `validOp` (clip id regex, 3-field allowlist, finite number) are stored there. The panel applies it through the same `pc_applyOps` and shadow rules as live commits. |
| T-tsr-03 | Denial of Service | catch-up size / echo storm | low | mitigate | `collapseLog` bounds the payload to clips x 3 fields. The shadow is set from read-back via `afterApply`, and held values are skipped, so a join cannot start an op loop. Asserted by the "rev stays still" checks in Tasks 1 and 2. |
| T-tsr-04 | Information Disclosure | catch-up sent to every new socket | low | accept | It carries the same data (clip ids, values, author names) that live commits already broadcast to every connected socket. Demo-only, private network. |
| T-tsr-05 | Denial of Service | unbounded `opLog` growth in relay memory | low | accept | One demo session produces at most a few thousand small entries, and restarting the relay clears it. |
| T-tsr-SC | Tampering | npm/pip/cargo installs | high | accept | This plan installs no packages. It uses only `ws` 8.22.0 (already pinned) and Node built-ins (`node:test`, `child_process`, `path`). |
</threat_model>

<verification>
Automated gates (all from the repo root):
- `npm --prefix premiere-collab/relay test` reports 21 tests, 21 pass, 0 fail. That is the 13 existing tests, 1 from Task 1, 6 from Task 2 and 1 from Task 3.
- `node --check premiere-collab/panel/js/main.js` passes.
- `git log --oneline -3` shows the three task commits on `research`, and `git status -sb` shows nothing staged from `premiere-collab/docs/`.

Post-task manual note (NOT a gate; laptop 2 is unavailable):
- One laptop with Premiere: run `node relay.js` in premiere-collab/relay, then `node fake-peer.js`, and wait about 10 s (2 to 3 edits to v0:0). Open the demo project and Sequence 01, type `localhost` in the panel and click Connect. Expected: Hero (v0:0) jumps to fake-peer's latest values, the Changes feed shows one `Caught up to rev N` line, and the relay window shows no rev authored by the panel's name over the next 10 s.
- Two laptops, later: TEST-PLAN-TWO-LAPTOPS.md 4.1 (G disconnects, H sets Scale 80, G connects and catches up to 80).
</verification>

<success_criteria>
- SYNC-01: a panel connecting after edits ends up with the latest committed value of every logged (clipId, field), matched by `v{track}:{clip}`, with no session code or Approve step.
- No echo after a join (rev still), no duplicate ops on reconnect, and one feed summary line per connection.
- Known limit (pre-connect edits are not logged) is documented in README.md and TEST-PLAN-TWO-LAPTOPS.md.
- 21/21 tests pass.
</success_criteria>

<output>
Create `.planning/quick/261010-tsr-sync-01-snapshot-join-via-relay-oplog-re/261010-tsr-SUMMARY.md` when done
</output>
