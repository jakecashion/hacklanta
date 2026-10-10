# Pitfalls Research

**Domain:** Live two-machine timeline sync as a CEP 11 + ExtendScript (ES3) panel in Premiere Pro 22.3.1.2 on Windows, with a Node `ws` relay over venue Wi-Fi (hackathon demo, ~12 h build)
**Researched:** 2026-10-10
**Confidence:** MEDIUM-LOW overall. API signatures and the sample panel were read from the Adobe-maintained docs repo and `Adobe-CEP/Samples`. Runtime behaviour of `nodeId`, events, `setValue` units and `start`/`end` setters is NOT documented and is unverified on 22.3.1. Every item tagged "verify" must be settled by the Phase 1 probes before design is locked.

Confidence tags used below: **[DOC]** stated in the Adobe scripting docs or sample code; **[COMMUNITY]** reported in Adobe forum threads, not confirmed; **[EXPERIENCE]** common CEP/networking knowledge, not re-verified here; **[UNKNOWN]** must be tested in Phase 1.

Phase numbers: 1 setup + API checks, 2 relay + connect, 3 join snapshot + Motion/Opacity sync, 4 presence, 5 stretch (move/trim/rename/feed), 6 demo rehearsal.

---

## Critical Pitfalls

### Pitfall 1: Stale-snapshot race causes ping-pong "phantom edits"

**What goes wrong:**
A remote value is applied, the shadow is updated, but a `snapshot()` call that was issued BEFORE the apply resolves AFTER it. Compared against the new shadow, the old Premiere value looks like a fresh local edit. The panel sends it as an op, the other machine applies it, and the two machines flip-flop the same field forever. The `applying = true` flag in `08` §8.6 does not stop this: `app.bind` events and `evalScript` callbacks are delivered asynchronously, often after the flag is already cleared.

**Why it happens:**
`evalScript` is async on the JS side, but the 1 Hz timer, the structure/selection events and the remote-apply path all issue calls independently. Nothing orders the results against the shadow update.

**How to avoid:**
- One bridge queue with ONE `evalScript` in flight at a time (mutex). Timer ticks and events coalesce into a single "snapshot wanted" flag; they never stack.
- Tag every snapshot with the sequence number at which it was issued. When a remote apply finishes, bump the number and DROP any snapshot result issued earlier.
- Make `applyOps()` return a fresh snapshot of the touched clips in the same `evalScript` call, and set the shadow from that read-back (see Pitfall 2). Never set it from the values you sent.
- Treat the diff itself as the idempotent guard. The flag is only an optimisation. After an apply, also suppress event-triggered snapshots for about 500 ms (a quiet window), not just while the call runs.
- Add a loop breaker: if the same `(clipId, field)` produces more than 5 ops in 2 s, freeze that field and log a warning in the panel.

**Warning signs:**
Value jitters on both machines with nothing touched. Rev counter climbs while both editors are idle. Two panels' change feeds fill with identical entries.

**Phase to address:** Phase 3 (design the queue before writing sync). Re-verify in Phase 6. Confidence: HIGH that the race exists (it follows from the architecture); the fix is standard.

---

### Pitfall 2: Sent value is not the value Premiere stores (rounding and float drift)

**What goes wrong:**
You set `start`/`end` or a Motion value, read it back, and it differs: times snap to frame boundaries, Scale/Opacity come back as float32 approximations (for example `99.99999` for `100`), Position comes back as `0.5000001`. `08` §8.6 says "the shadow has the new values". If the shadow holds the sent value, the next compare finds a difference, emits an op, and the loop never settles.

**Why it happens:**
Premiere quantises times to the sequence frame rate and stores params as floats. `Time.seconds` is a double and can round. `Time.ticks` is exact as a string, but an off-grid tick value you send is snapped by Premiere. [DOC for ticks=string and 254016000000 ticks/s; COMMUNITY/EXPERIENCE for snapping]

**How to avoid:**
- After every apply, re-read the field from Premiere and store THAT in the shadow.
- Compare numbers with an epsilon (for example `1e-4` for Position, `0.01` for Scale/Rotation/Opacity). Compare times as exact tick strings but only after both sides were read back from Premiere.
- Quantise outgoing times to the frame (`ticksPerFrame` from `seq.timebase`) before sending.
- Keep time handling in strings. Do not `parseInt` ticks without care: JS numbers are safe to about 9e15 ticks (about 10 h) so `Number()` is fine for the demo, but never do arithmetic in ExtendScript floats on long timelines.

**Warning signs:**
One tiny constant diff in the log after an apply. An op that "changes" a field to a value that prints identical.

**Phase to address:** Phase 1 (probe: write `0.3`, read back) and Phase 3 (shadow design). Confidence: MEDIUM.

---

### Pitfall 3: Motion Position units, parameter lookup by index, Uniform Scale, keyframes

**What goes wrong:**
- You send Position in pixels. [COMMUNITY] reports that `getValue()` on Motion Position returns RELATIVE values (for example `[0.5, 0.5]`, relative to the sequence frame) and that passing pixels gave `[32000, 32767]`, i.e. a clamped/saturated value. `08` §6.3 already assumes normalized values; it must still be proven.
- You find Motion/Opacity by `components[1]`/`components[0]`. The sample code's own comment says `0 = clip, 1 = Opacity` while community code treats `components[1]` as Motion, so order is not trustworthy. [DOC sample comment; COMMUNITY]
- You find params by `displayName`. [DOC] `ComponentParam.displayName` is localized and read-only; there is no `matchName` on params. A laptop with Premiere set to another language breaks every lookup.
- You set `Scale` while `Uniform Scale` is off. `Scale` is then ignored (the UI uses `Scale Width`/`Scale Height`) [EXPERIENCE].
- A param has keyframes (stopwatch on). [DOC] `getValue`/`setValue` "can only work on parameters which are not time-variant". The call returns a wrong value or throws, and one such clip can break the whole snapshot.
- Rotation: values beyond 360 degrees may be stored as turns plus degrees [UNKNOWN].

**Why it happens:**
The API is untyped, undocumented on units, and was frozen at 23.0 ("no further changes", changelog). Samples only demo Gaussian Blur and Repeat Edge Pixels.

**How to avoid:**
- Phase 1 probe: dump every component of one clip as `index : matchName : displayName`, and every property as `index : displayName : typeof getValue() : value`. Save the dump in the repo as ground truth.
- Look up the component by `component.matchName` (`AE.ADBE Motion`, `AE.ADBE Opacity`; confirm in the dump). Look up the param by `displayName` ONLY after the dump proves the English names on both machines. Check Premiere's language on both laptops. Resolve once per clip, cache the indices, and verify the name still matches before each write.
- Test `setValue([x, y], true)` with normalized pairs, then with pixels, and note how Program monitor moves. Log the sequence frame size next to the result.
- Snapshot `Uniform Scale` too. In the demo project, keep Uniform Scale ON and set Scale only.
- Call `isTimeVarying()` before reading/writing. If true, mark the field `unsupported`, skip it and show a badge. Never throw. The demo project must have zero keyframes.
- Test Rotation at `0`, `45`, `-45`, `400`.

**Warning signs:**
Clip jumps to a corner or off-screen on the other machine. `getValue()` returns `0`, `undefined`, or an object instead of a number or array. Snapshot returns `"EvalScript error."`.

**Phase to address:** Phase 1 (probes) and Phase 3 (param table). Confidence: MEDIUM-LOW on units until probed.

---

### Pitfall 4: TrackItem `start`/`end`/`inPoint`/`outPoint`/`move()` are not what the plan assumes

**What goes wrong:**
- `TrackItem.move()` takes a DELTA, not an absolute time. [DOC] "shifting it by a number of seconds"; the parameter is oddly named `newInPoint`. It was added in 15.4. Passing an absolute time moves the clip far off the timeline. It is a `Time` in seconds, so it rounds, and negative deltas are untested [UNKNOWN].
- `inPoint`/`outPoint` are SOURCE-relative; `start`/`end` are SEQUENCE-relative (and "NOT the sequence zero point"). [DOC] Mixing them gives wrong trims.
- Setting `start` may shift the clip or may trim the head, and setting `end` may trim the tail or fail if it precedes `start`. `07` §9 lists this as unverified. Order of the two writes can matter when moving right vs left [UNKNOWN].
- A single human trim changes several of `start`/`end`/`inPoint`/`outPoint` at once. A naive field-by-field diff emits `move` and `trim` ops for ONE edit; applying them in sequence fights itself.
- Moving a clip onto a neighbour on the same track may overwrite it, shift it, or error. That is a structural change that destroys another clip's `nodeId`.
- Ripple/gap behaviour: moving a clip can leave other clips untouched, but a razor or ripple delete by hand shifts everything and invalidates the index map.

**How to avoid:**
- Scope: keep move/trim in stretch (Phase 5). Core is Motion/Opacity only.
- Phase 1 probe: for one clip with free space on both sides, run (a) `start = X` alone, read `start/end/duration/inPoint/outPoint`; (b) `end = Y` alone; (c) `move(delta)`; (d) `inPoint`/`outPoint` writes. Record exactly which fields change. Pick ONE mechanism and write it in the plan.
- Model timing as one composite op `{start, end, inPoint, outPoint}` per clip per diff. Apply by restoring the whole tuple, in an order the probe proved safe.
- In the demo project leave gaps between clips and clamp remote moves to stay inside the gap, so no overwrite can happen.

**Warning signs:**
Clip duration changes after a "move". A neighbour disappears. Two ops (`move` and `trim`) appear for one drag in the feed.

**Phase to address:** Phase 1 (probe 4 of `08` §12) and Phase 5. Confidence: MEDIUM (docs for `move`, `inPoint`, `outPoint` read directly); effects of setters UNKNOWN.

---

### Pitfall 5: `nodeId` is undocumented, and the guest index-mapping can silently misalign

**What goes wrong:**
- `TrackItem.nodeId` has "*Add a description*" in the docs; type String only. It may change after save/reopen, undo, razor, or when the sequence is re-activated. [DOC; stability UNKNOWN] If it changes mid-session, every op targets a dead ID.
- The host's `nodeId` is meaningless on the guest, so the join map is by `(trackIndex, clipIndex)`. If the two project files differ by even one clip (host edited the timeline after copying, or the guest has unsaved changes), indexes misalign. The guest then writes the host's Hero values into Logo, with no error.
- QE DOM indexes differ from DOM indexes (QE `getItemAt` counts transitions and gaps). Mixing them yields off-by-N clips. [EXPERIENCE]

**How to avoid:**
- Phase 1 probe (checks 3 and 4): read `nodeId`; move, trim, set a param, save, close, reopen, read again. Also log it before and after `app.project.activeSequence` is re-fetched.
- Build the map from a content fingerprint, not just index: for every clip compare `(track, name, start, end, inPoint, outPoint)` and require an exact match. On any mismatch, REFUSE the join with a visible list ("Track V1 clip 2: host 'Card' vs guest 'Logo'"). Fail loudly; never guess.
- Also compare `sequence.name` and clip counts, and show both on the Join screen.
- If `nodeId` proves unstable, fall back to a clip-name tag (`Hero [cu:a1b2]`) as `08` §12 says, but check that renaming through the API does not itself trigger events or rename loops.
- Do not use QE for anything in the core path.

**Warning signs:**
`nodeId` string differs between two reads in one session. Join "succeeds" but a clip on the guest looks wrong.

**Phase to address:** Phase 1 (probe) and Phase 3 (map + fingerprint). Confidence: HIGH that this needs a test; outcome UNKNOWN.

---

### Pitfall 6: Event handlers are not a reliable change detector, and they stack up on panel reload

**What goes wrong:**
- `onActiveSequenceStructureChanged` is a structure event. It most likely does NOT fire for Motion/Opacity value changes, and may not fire for a plain move or trim [UNKNOWN; the sample only logs "Something in X changed"]. If you rely on it, param edits are never noticed.
- For selection the sample binds `onActiveSequenceSelectionChanged`, while forum threads name the event `onSequenceSelectionChanged` [COMMUNITY]. Which exists in 22.3.1 is not proven. `app.bind` returns a success flag; the sample ignores it.
- `app.bind` handlers live in the shared ExtendScript engine. Closing and reopening the panel re-runs your `.jsx` and binds AGAIN. You get 2, 3, 4... handlers, each dispatching a `CSXSEvent`, so event storms and double snapshots.
- Events are bound in ExtendScript, not panel JS. The handler must create a `CSXSEvent` (via `PlugPlugExternalObject.dll` on Windows) to reach the panel. The panel must have called `addEventListener` for that type first, or events are lost. The sample creates a new `ExternalObject` on every event. [DOC sample]
- The event argument sets differ per event (`TrackItemAdded` gives track and trackItem; structure change gives none).

**How to avoid:**
- Design as if events do not exist: the 1 Hz poll is the primary detector, events only make it faster. Do not let any requirement depend on an event firing.
- Phase 1 probe: bind candidate events (`onActiveSequenceStructureChanged`, `onActiveSequenceSelectionChanged`, `onSequenceSelectionChanged`, `onActiveSequenceChanged`) and log the `app.bind` return values. Drag a clip, trim, edit Scale in Effect Controls, select, deselect. Record which fire.
- Guard binding with `$.global.__collabBound` so a reload does not rebind. Create the `ExternalObject` once and cache it.
- For selection presence, polling `seq.getSelection()` at 2 to 4 Hz is a valid fallback if the event does not exist.

**Warning signs:**
Param edit on A never shows on B until 1 s later (poll) or never. Event counter increases by 2 per action after a panel reload.

**Phase to address:** Phase 1 (check 5) and Phase 2/3 (queue). Confidence: MEDIUM-LOW.

---

### Pitfall 7: `evalScript` blocks Premiere, queues without a timeout, and mangles strings

**What goes wrong:**
- ExtendScript runs on Premiere's main thread. A long snapshot freezes the UI (playback stutter, dragging lag). A modal dialog or a busy app (import, render, relink) stalls `evalScript` with no timeout; your queue backs up.
- The return value is ALWAYS a string. `undefined` returns the string `"undefined"`; a thrown error returns `"EvalScript error."` with no detail; an object returns `"[object Object]"`; booleans return `"true"`/`"false"`. `JSON.parse("undefined")` throws in the panel and kills the loop.
- Building the call as `evalScript("applyOps('" + json + "')")` breaks on a single quote in a clip name (`Sam's clip`), a backslash (Windows paths), or a newline. It is also an injection hole (Pitfall 9).
- Non-ASCII characters in names may be mangled across the bridge [EXPERIENCE].
- `.jsx` is cached by the ExtendScript engine: edits do not apply until re-evaluated or Premiere restarts (`07` §2).

**How to avoid:**
- Every exported bridge function wraps its body in `try/catch` and returns a JSON string `{"ok":true,"data":...}` or `{"ok":false,"err":"...","line":N}`. The panel wrapper checks for `"EvalScript error."`, `"undefined"` and empty strings before `JSON.parse`.
- Pass arguments as a doubly-encoded literal: `JSON.stringify(JSON.stringify(payload))`, or `encodeURIComponent` + `decodeURIComponent` in `.jsx`. Never string-concatenate user data into script text.
- Single in-flight call, a 5 s watchdog (if no callback, mark the bridge "busy", stop polling, show a badge), and coalesced ticks (Pitfall 1).
- During development, use `$.evalFile(path)` from a "Reload JSX" button; restart Premiere if needed. Build paths with `csInterface.getSystemPath(SystemPath.EXTENSION)` and forward slashes.
- One batch per call, not one call per field (`07` §7).

**Warning signs:**
Panel logs `Unexpected token u in JSON`. Premiere stutters at exactly 1 Hz. Calls never return after an unrelated dialog appears.

**Phase to address:** Phase 1 (bridge wrapper) and Phase 3. Confidence: HIGH for string-only returns and "EvalScript error."; MEDIUM for the rest.

---

### Pitfall 8: ES3 traps in `bridge.jsx`

**What goes wrong:**
ExtendScript is ES3 plus a few extras. `JSON`, `Array.prototype.map/forEach/filter/indexOf/reduce`, `Object.keys`, `String.prototype.trim`, `let`/`const`, arrow functions, template strings, default params and `Date.now` are missing or unreliable. Reserved words as property names (`.class`, `.default`) and trailing commas can cause syntax errors. A parse error in the `.jsx` shows up only as `"EvalScript error."` for EVERY call, with no line number. `console.log` does not exist (`$.writeln` goes to the ESTK/VS Code debugger console).

**How to avoid:**
- Include `json2.js` first and test `JSON.stringify` in the first probe. Write plain `for` loops and a tiny `indexOf` helper.
- Keep `bridge.jsx` small and free of modern syntax; lint it with a ES3 parser (for example `eslint --parser-options ecmaVersion:3`, or just run `node --check` plus a regex grep for `=>`, `let `, `const `).
- Add a `ping()` function returning `"pong"` and call it when the panel loads, so a parse failure is caught immediately.
- Log with a `$._collab.log(msg)` that dispatches a `CSXSEvent` to a panel debug console (works with no ESTK).
- Keep `sync.js` (pure, modern JS, `node --test`) separate from `bridge.jsx` (ES3); never share code between them.

**Warning signs:**
`ping()` returns `"EvalScript error."`. Everything worked until you added one helper.

**Phase to address:** Phase 1. Confidence: HIGH.

---

### Pitfall 9: Remote ops are an eval-injection and clip-corruption path

**What goes wrong:**
The relay is reachable by anyone on the venue Wi-Fi. ExtendScript can read and write files and run shell commands (`File`, `Folder`, `system.callSystem`). If any string from a peer (name, clipId, param) is concatenated into `evalScript` text, a hostile or buggy message executes arbitrary code on the host laptop. Even without malice, an op with a bad value (`NaN`, string for Position, huge Scale) can wreck the timeline.

**How to avoid:**
- Pass data through the doubly-encoded literal (Pitfall 7) and parse it inside `.jsx`; never build code from it.
- Validate on the HOST before apply: kind in allow list; `clipId` in the known clip set; field in the param allow list; value `typeof number`/array of two finite numbers within sane ranges (Opacity 0 to 100, Scale 1 to 1000, Position 0 to 1 plus a margin, Rotation -3600 to 3600); names length-capped.
- Relay: bind on all interfaces is needed, so require the 6-character room code AND host approval (already planned), rate-limit connections per IP, ignore messages from unapproved sockets, cap message size (`ws` `maxPayload`, for example 1 MB) and room count. Do not accept `create` from guests.
- Use a code alphabet without look-alike characters, and shut the room after a failed-join cap.

**Warning signs:**
Panel logs ops from unknown author IDs. A clip's value goes to `NaN` or `0`.

**Phase to address:** Phase 2 (relay limits) and Phase 3 (validation). Confidence: HIGH.

---

### Pitfall 10: Panel does not appear in Window > Extensions (CEP load failures)

**What goes wrong:**
No panel entry, or a blank panel. Silent causes, in order of likelihood:
1. `PlayerDebugMode` set under the wrong `CSXS.N` key, or with the wrong type. It must be a STRING (`REG_SZ`) `"1"` under `HKCU\Software\Adobe\CSXS.11`. The dev machine has the key but no value yet. A `REG_DWORD` is a common mistake. [EXPERIENCE; `07` §2 says string]
2. Folder is nested one level too deep (`extensions\repo-main\panel\CSXS\manifest.xml`). The manifest must be at `%APPDATA%\Adobe\CEP\extensions\<name>\CSXS\manifest.xml`. The folder `%APPDATA%\Adobe\CEP\extensions` does not exist on the dev machine yet.
3. Malformed `manifest.xml`: one bad character, unclosed tag or wrong `Extension Id` hides the panel with no error. Version attributes copied from the sample are unsafe: the Adobe sample uses `RequiredRuntime Name="CSXS" Version="6.0"` and `Host Name="PPRO" Version="9.0"`, which is old but works. Copying a newer manifest requiring `CSXS 12` will not load on CEP 11.
4. Premiere not fully restarted after the registry edit.
5. `mklink /D` fails without admin or Developer Mode, or the link points at a wrong folder.
6. `.debug` file saved as `.debug.txt` by Windows tools. Its `Extension Id` must match the manifest. Port `8088` may collide.
7. `--enable-nodejs --mixed-context` flags added but not needed. The sample manifest enables no Node; the panel only needs the browser `WebSocket` (`08` §4). Extra flags add failure modes.

**How to avoid:**
- Start from the working `PProPanel` sample; change only the IDs, then rebuild up to the real panel one file at a time. Prove the empty panel loads on BOTH laptops first.
- Set the debug key for `CSXS.10`, `.11` and `.12` as insurance (`reg add HKCU\Software\Adobe\CSXS.11 /v PlayerDebugMode /t REG_SZ /d 1 /f`). Commit a `setup.ps1` that does registry + folder + link, and runs the same on both laptops.
- Validate the manifest as XML before each load (`node -e "require('fs').readFileSync(...)"` plus an XML linter).
- Check the Premiere version is 22.3.1.2 on both, and `Window > Extensions` lists the panel. If it doesn't, look for CEP logs under `%TEMP%` or `%APPDATA%\Adobe\CEP\logs` (exact file name for CEP 11 unverified).
- Do not enable Node in the manifest unless something needs it.

**Warning signs:**
Menu entry missing after restart. Blank white panel (page path wrong). DevTools at `http://localhost:8088` does not connect.

**Phase to address:** Phase 1 (check 1) on both machines. Confidence: MEDIUM (`07` plus sample); the log location is LOW.

---

### Pitfall 11: Windows Firewall, network profile, and venue Wi-Fi client isolation

**What goes wrong:**
- The first run of `node relay.js` raises a Windows Defender Firewall prompt that can hide behind full-screen Premiere or be dismissed. Inbound is then blocked silently, and the guest times out.
- The rule from `08` §9 allows Node only on Private networks. Venue Wi-Fi and phone hotspots are usually classified Public by Windows, so the rule does not apply.
- Many venue Wi-Fi networks isolate clients (AP/client isolation), run a captive portal, or throttle peer-to-peer traffic. `ping` between the laptops fails. This is the biggest unknown in `08` §14.
- `ipconfig` lists several IPv4 addresses (WSL/Hyper-V `vEthernet`, VirtualBox, VPN). Typing the wrong one fails.
- A corporate VPN or WARP client on either laptop reroutes LAN traffic.
- DHCP lease changes after sleep. The IP typed during rehearsal is now wrong.
- Wi-Fi power saving kills idle sockets when the panel is quiet.

**How to avoid:**
- Pre-create the rule from an admin shell the night before: `netsh advfirewall firewall add rule name="collab-relay" dir=in action=allow protocol=TCP localport=8080 profile=any` (or set the Wi-Fi to Private). Verify with `Test-NetConnection <hostIP> -Port 8080` from the guest.
- Relay prints every non-internal IPv4 on start (`os.networkInterfaces()`), labels the Wi-Fi one, and shows it in the host panel. Guests never run `ipconfig`.
- Test peer reachability at the venue the first minute you arrive. Order of fallbacks: venue Wi-Fi, phone hotspot (host connects too; a hotspot carries LAN traffic without using data), then a laptop-to-laptop Ethernet cable or Windows Mobile Hotspot, then `cloudflared` (Pitfall 12). Decide the order in advance and rehearse switching in under 2 minutes.
- Bind the relay explicitly to `0.0.0.0` and have the host panel connect to `ws://127.0.0.1:8080` (not `localhost`; on Node 17+ `localhost` can resolve to `::1`).
- Add a ping/pong heartbeat every 15 s on both sides; disable Wi-Fi power saving on the adapter; keep both laptops on AC and awake (no sleep, no screen saver).
- Put an explicit "Check connection" button in the guest panel that reports the specific failure: DNS / refused / timeout.

**Warning signs:**
Guest connects from the host laptop's own browser but not from the other laptop. `Test-NetConnection` shows `TcpTestSucceeded: False`. `ping` times out.

**Phase to address:** Phase 2 (check 2), with a venue re-test in Phase 6. Confidence: HIGH for the firewall/profile mechanics; client isolation depends on the venue.

---

### Pitfall 12: `cloudflared` WebSocket tunnel as fallback has its own failure modes

**What goes wrong:**
- Quick tunnels (`trycloudflare.com`) have "no uptime guarantee", a 200 in-flight-request limit (429 beyond it), and no SSE support. [DOC, Cloudflare] The page does not say whether WebSockets work, so test it.
- `cloudflared` connects OUT on port 7844 (UDP for QUIC, TCP for `http2`). [DOC, Cloudflare firewall page] Venue networks that block this make the tunnel fail to start, exactly when you need the fallback. Protocol selection flags are not covered on the pages fetched; check `cloudflared tunnel --help` for `--protocol`.
- The hostname changes on every run. Guests must type a new `wss://xyz.trycloudflare.com` each time, but the panel UI in `08` §9 is built around "host IP". An IP-only input field cannot accept it.
- Latency rises (extra hop to a Cloudflare edge and back), which erodes the 1 to 2 second target. Idle WebSockets may be closed by intermediaries, so heartbeats matter [EXPERIENCE].
- The tunnel exposes the relay to the public internet. Anyone with the URL can try codes.
- `cloudflared` pointed at `http://localhost:8080` works only if the relay answers plain HTTP upgrade requests there. It does not need TLS on the origin.

**How to avoid:**
- The panel's connect field accepts a full URL (`ws://ip:8080` or `wss://host`) and defaults `ws://` when only an IP is typed.
- Install `cloudflared.exe` on the host laptop before the event. Run the tunnel once on home Wi-Fi AND once on a phone hotspot, with a real two-machine edit test. Note the exact command in a README.
- Treat it as plan C. Plan B is the phone hotspot, which is more reliable for a LAN demo. Do not build anything tunnel-specific beyond the URL input.
- Keep approval and room code mandatory (Pitfall 9).

**Warning signs:**
`cloudflared` prints connection retries and no URL. WebSocket opens then closes after about 100 s.

**Phase to address:** Phase 2 (smoke test) and Phase 6. Confidence: MEDIUM (ports/limits from Cloudflare docs); WebSocket behaviour must be tested.

---

### Pitfall 13: Project and media differ between machines (relink, locale, modal dialogs)

**What goes wrong:**
- Absolute media paths: `C:\collab-demo\` must exist and be identical on both laptops, with identical file names and sizes. A different drive, a case difference, or a Dropbox/OneDrive copy can break links. A "Link Media" dialog on open is MODAL and stalls `evalScript`.
- The host copied the project file but then edited the timeline in memory without saving. The guest's copy differs. Index mapping misaligns (Pitfall 5).
- Projects opened from a synced/shared folder may be locked (`.prlock`), or Premiere may offer to "save as" on first change.
- The guest has a newer media cache state: first open conforms audio and builds peak files and index. Run once on both before the demo.
- Different sequence settings (frame rate, resolution) would make normalized Position look the same but pixel previews differ. Different Premiere language breaks displayName lookups (Pitfall 3).
- Heavy media (4K H.264/H.265) makes playback and `setValue` redraw slow, so "within 1 to 2 s" looks broken even if sync is instant.
- Premiere's auto-save and "project modified" prompts add dialogs on close.

**How to avoid:**
- Use 1080p, short, intra-frame or lightly compressed clips (or stills/solid colours) in the demo project, no third-party effects, no keyframes, Uniform Scale ON, gaps between clips.
- Copy `C:\collab-demo\` with a script (`robocopy`) and verify with file hashes on both. Open the project once on each laptop to build caches, save, and snapshot a pristine copy (`C:\collab-demo-pristine\`) to restore between rehearsals.
- Open the project on both machines, check there is NO dialog, and put the demo sequence in an open, active timeline panel. The join pre-check compares clip fingerprints (Pitfall 5) and sequence name.
- Both laptops: same Premiere version, same language, same workspace, project and media on the local C: drive, not a synced folder.

**Warning signs:**
Offline-media red clips. A dialog sits on top while the panel says "Waiting". Guest snapshot count differs from the host.

**Phase to address:** Phase 1 (build the demo project and copy script) and Phase 6. Confidence: HIGH for generic Premiere behaviour.

---

### Pitfall 14: No undo group, so remote edits pollute the local Undo stack

**What goes wrong:**
There is no `beginUndoGroup`-style API in the Premiere DOM (`07` §6; none found, unconfirmed). Each remote `setValue` becomes its own undo step, or none at all. A local Ctrl+Z may undo a REMOTE change, which looks like a new local edit and is sent back as an op. If undo is not recorded at all (some scripted changes bypass the history), the project shows no dirty state.

**How to avoid:**
- Design the sync as state-based (diff of shadow vs actual), so an undo is just another edit and converges naturally. This is a benefit of the architecture; keep it.
- Do not call `app.project.save()` automatically.
- Phase 1 probe: apply a remote-style `setValue`, then Ctrl+Z, and observe. Write the observed behaviour in the demo notes.
- Demo script: do not press Ctrl+Z during the pitch; if asked, say undo is out of scope for the MVP (`PROJECT.md`: "One undo step per remote edit" is out of scope).

**Warning signs:**
Pressing Undo moves a value back on the other machine too. Undo history shows dozens of entries after one drag.

**Phase to address:** Phase 1 (probe) and Phase 6 (demo script). Confidence: MEDIUM-LOW.

---

### Pitfall 15: Lost, rejected or stale commits leave fields stuck "pending", and nothing recovers from a drop

**What goes wrong:**
In `08` §8, a field marked pending is never updated by remote commits until its own commit returns. If the host rejects the op (clip missing, validation failure), drops the message, or the socket dies, the pending mark stays forever and that field silently stops syncing. After a Wi-Fi blip the relay forgets the room; `08` §3.2 puts reconnect out of scope, so one dropped socket ends the demo. Presence messages can also arrive late and show a stale playhead.

**How to avoid:**
- Add a `reject {opId, reason}` message from host to author, and a pending TTL (about 3 s). On expiry, clear the mark and resync that clip from the host.
- Heartbeats and a visible badge ("Connection lost") (Pitfall 11). Even without full reconnect, offer a one-click "Rejoin" that reuses the same room code and sends a fresh snapshot, rather than restarting everything. This is a stretch of Phase 2, but cheap and high value for a live demo.
- Have the host broadcast a full snapshot hash every 5 s, and have the guest resync on mismatch (cheap repair for any bug).
- `rev` is assigned only by the host panel. If the host panel reloads, `rev` restarts at 0, so guests must rejoin and take a fresh snapshot. State this in the demo notes rather than building persistence.
- Relay should not echo a message back to its sender (or the sender must ignore its own `opId`).
- Presence is lossy by design: always overwrite, never queue; drop stale ones by timestamp.

**Warning signs:**
One field stops updating while others work. Guest feed shows a rev gap.

**Phase to address:** Phase 2 (protocol) and Phase 3. Confidence: HIGH.

---

## Moderate Pitfalls

### Pitfall 16: Snapshot cost, polling vs playback, and drag storms

**What goes wrong:**
Each property read is an ExtendScript call into Premiere. 50 clips x (name, 4 times, 5 params) x 1 Hz can take hundreds of milliseconds, and runs on the UI thread. During playback or while the user drags a value in Effect Controls, either the snapshot stutters playback or intermediate values flood the relay.

**Prevention:**
- Measure in Phase 1 with `$.hiresTimer` for a 4-clip and a 50-clip sequence. Demo has 4 clips; do not over-engineer, but keep the scalar loop short: resolve component/param indices once per clip and cache them.
- Poll cheaply: read only the selected clips fully each tick, and the rest every 3 to 5 s. Skip polling while the bridge is busy.
- Debounce outgoing param ops per field by about 100 to 150 ms, send the last value only, and rate-limit remote apply to about 10 per second per field.
- Combine presence and snapshot in one call: `getPlayerPosition()` and `getSelection()` are cheap when batched. Send the playhead only if it changed.

**Phase to address:** Phase 1 (measure) and Phase 3. Confidence: MEDIUM.

---

### Pitfall 17: Remote selection must not be applied to the local timeline

**What goes wrong:**
Calling `setSelected()` on the other user's selected clips steals the local selection and may change which clip Effect Controls shows, which the diff then reads as an edit target. Calling `setPlayerPosition()` for remote playheads moves the local playhead during a demo.

**Prevention:**
Presence is display-only in the panel (colored chips with clip names and a timecode). Never call `setSelected` or `setPlayerPosition` from a remote message. Highlighting in the timeline is out of scope.

**Phase to address:** Phase 4. Confidence: HIGH.

---

### Pitfall 18: Panel visibility, throttled timers and DevTools masking bugs

**What goes wrong:**
A CEP panel that is hidden behind another tab in the same panel group, or a window that is minimised, may have its timers and rendering throttled or suspended. A closed panel kills the WebSocket. Having Chrome DevTools open on port 8088 changes timing and can mask or cause problems. Reloading the panel does not reset ExtendScript globals (stale handlers, stale `$._collab` state).

**Prevention:**
- Dock the panel in its own visible frame for the demo and keep it visible. Test it docked and floating.
- Make the panel idempotent on load: read the current state, check `$.global` flags, and rebind safely (Pitfall 6).
- Close DevTools during the final rehearsal.
- Do the final rehearsal on the exact build, with panels at the exact arrangement.

**Phase to address:** Phase 6. Confidence: MEDIUM-LOW.

---

### Pitfall 19: `activeSequence` is null or the wrong sequence

**What goes wrong:**
`app.project.activeSequence` is `null` when no project is open, no timeline is active, or a different panel is focused in some states. Every bridge call then throws. A second sequence (even a nested one) in the project makes the host and guest disagree about which is active, and the diff targets the wrong clips.

**Prevention:**
Guard every bridge function for null project/sequence and return a typed `{ok:false, err:"no-active-sequence"}`. Show the sequence name in both panels. Demo project contains exactly one sequence. Require both panels to report the same sequence name and clip count before enabling Join.

**Phase to address:** Phase 1 and Phase 3. Confidence: MEDIUM.

---

### Pitfall 20: Panel-side WebSocket and dev-environment details

**What goes wrong:**
- CEP 11 embeds an older Chromium (about v88) [EXPERIENCE]. Modern syntax in `main.js` (optional chaining, newer APIs) may not run. Test in the panel, not in desktop Chrome.
- `node --test` and the `ws` relay run on Node 24 on the dev machine, but CEP 11's Node is 15.9 if you enable Node in the panel. Do not import `ws` into the panel; use the built-in `WebSocket`.
- Mixed-content: panel pages load from `file://`, so `ws://` is allowed; `wss://` needs a valid cert, which Cloudflare provides.
- Port clash: another process on `8080` (Docker, dev servers). Make it configurable and fall back to the next free port.

**Prevention:**
Develop `main.js` in plain ES2017 or earlier, test in DevTools at `localhost:8088`. Keep `sync.js` dependency-free and CommonJS/UMD so it loads both in the panel and under `node --test`. Make the relay port an environment variable.

**Phase to address:** Phase 1 and 2. Confidence: MEDIUM.

---

## Minor Pitfalls

### Pitfall 21: Windows-specific tooling snags
`mklink /D` needs an elevated shell. VS Code ExtendScript Debugger support for Premiere 22.3.1 is unverified (`07` §9). If it fails, use `$.writeln`-to-CSXSEvent logging (Pitfall 8). Do not use ExtendScript Toolkit. Antivirus can quarantine `cloudflared.exe`; install and run it ahead of time. A Windows Update restart during the event can wipe the session; pause updates the day before.

### Pitfall 22: Display changes crash or rearrange Premiere
Plugging in a projector or changing scaling while Premiere is open can reset the workspace or crash it. Connect the display and set the layout first, then open Premiere and the panel.

### Pitfall 23: Clip name tags change names the user sees
If `nodeId` fails and the fallback tags names (`Hero [cu:a1b2]`), the pitch screen shows the tag. Hide the tag in the panel UI and keep the original name for display, or only use the tag in an internal check.

### Pitfall 24: Rotation and Position drift on repeated applies
Repeated apply of the same normalised value can accumulate quantisation if your code reads, adds a delta, and writes. Always send absolute values, never deltas (move() is the sole exception, Pitfall 4).

### Pitfall 25: Effect Controls display may not refresh
After a scripted `setValue(v, true)` the Program monitor may update but the open Effect Controls panel can show stale numbers until the clip is reselected [COMMUNITY/EXPERIENCE]. Do the demo with Effect Controls closed on the receiving side, or watch the Program monitor only (matches `08` §11 step 5).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Field-by-field diff for move and trim | Simple diff code | Duplicate and conflicting ops for one edit (Pitfall 4) | Never; use one composite timing op |
| Index-only clip map | No fingerprint code | Silent wrong-clip writes (Pitfall 5) | Never; fingerprint is about 20 lines |
| `applying` flag as the only echo guard | Looks sufficient | Ping-pong through async events (Pitfall 1) | Never; add seq tags + read-back |
| String-concatenating args into `evalScript` | Fast to write | Breaks on quotes and paths; injection (Pitfall 9) | Never |
| Hard-coded `components[1]`/`properties[0]` | No lookup code | Wrong component per clip/locale (Pitfall 3) | Never; resolve by matchName/displayName and cache |
| 1 Hz poll only, no events | Works for all edit types | 1 s latency floor | Fine for MVP (events are an optimisation) |
| No reconnect | Smaller protocol | One blip ends the demo | Acceptable only if the Rejoin button exists |
| Skipping validation on host | Less code | Remote code or NaN into the timeline | Never on a shared Wi-Fi |
| Hard-coded IP/port in the panel | Less UI | Fails on any network change | Only in the first smoke test |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `evalScript` | Treat return as typed; call in a loop | Return JSON strings, check `"EvalScript error."`, one in flight, watchdog |
| `CSXSEvent` | Dispatch before the panel listens; new `ExternalObject` per event | Register listener on load; create the object once; guard rebind |
| `app.bind` | Assume event coverage | Poll as primary, events as hint; log return of `bind` |
| `ComponentParam` | Pixels for Position; lookup by index; skip Uniform Scale; ignore keyframes | Normalized values proven by probe; lookup by matchName/displayName cached; `isTimeVarying()` guard |
| `Time` | Seconds, `parseFloat` | `Time.ticks` strings, set via `new Time()` and `.ticks`, quantise to frame |
| `ws` relay | Echo to sender, no heartbeat, unlimited payload | Skip sender, ping/pong, `maxPayload`, approval gate |
| Windows Firewall | Rely on the prompt; Private-only rule | Pre-create rule with `profile=any`; verify with `Test-NetConnection` |
| `cloudflared` | Assume it works on venue Wi-Fi | Test beforehand on a hotspot; 7844 outbound; URL input accepts `wss://` |
| CEP load | Edit registry on one key, nested folder | Set CSXS.10/.11/.12; scripted setup; empty-panel load test first |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full re-snapshot every second with property reads | Premiere stutters at 1 Hz | Cache indices; read selected clips fully, others slowly | About 30+ clips or on slow laptops |
| Queue backlog from timer + events | Latency grows over minutes | Single in-flight call; coalesce; watchdog | After any slow call |
| Un-debounced slider drags | Relay floods, guest lags | Debounce about 100 to 150 ms; send last value | Any continuous drag |
| Presence via separate calls at 4 Hz | Extra main-thread calls | Batch with snapshot; send on change | During playback |
| Heavy media | Redraw lag looks like sync lag | 1080p light codecs for the demo | Any 4K/long-GOP clip |
| Venue Wi-Fi congestion | Random 1 to 5 s delays | Hotspot; wired option; keep messages small | Hundreds of devices |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Interpolating peer data into `evalScript` | Remote code execution on host (ExtendScript has file and shell access) | Doubly-encoded literal; parse in `.jsx` |
| No value or clip validation | Corrupted timeline, `NaN` | Allow lists and numeric ranges on host |
| Open relay on shared Wi-Fi | Strangers join or flood | Room code + host approval, payload cap, per-IP rate limit |
| Public quick-tunnel URL | Anyone with URL can try codes | Short-lived tunnel; approval required |
| Panel loads remote content | CEP has file access | Panel loads only local files |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent failure on join (wrong IP, firewall) | Presenter stuck on stage | Specific error text and "Check connection" button |
| No sync indicator | Judges cannot tell it works | Visible badge, rev counter, last-applied toast per edit |
| Feed shows raw ids | Confusing story | Show clip names and user names with their colors |
| Judges edit during the pitch and trigger an unsupported edit | Demo derails | Keep the demo script tight; the panel shows "unsupported change" instead of silently failing |
| Presenter presses Ctrl+Z | Unplanned behaviour | Avoid in script (Pitfall 14) |

## "Looks Done But Isn't" Checklist

- [ ] **Panel load:** Often works on the dev laptop only. Verify on BOTH laptops after a full Premiere restart.
- [ ] **Join:** Often works only with the host IP seen in the room. Verify from the guest on the venue network and on the hotspot.
- [ ] **Param sync:** Often tested in one direction. Verify host-to-guest AND guest-to-host for each of Position, Scale, Rotation, Opacity.
- [ ] **No echo:** Often hides behind small values. Verify with both machines idle for 60 s, and rev counter stays constant.
- [ ] **Simultaneous edits:** Often untested. Edit the same field on both machines at once; both converge to the same value.
- [ ] **Different fields, same clip:** Edit Scale on A and Opacity on B simultaneously; both apply.
- [ ] **Panel reload:** Often rebinding duplicates handlers. Close and reopen the panel 3 times, then check the event count per action.
- [ ] **Premiere restart:** Restart one machine and rejoin; join pre-check passes.
- [ ] **Cold start:** Fresh boot, fresh Premiere, relay start, join, edit, in under 2 minutes.
- [ ] **Fallbacks:** Hotspot and tunnel each tested with a real edit, not just a connection.
- [ ] **Locale and keyframes:** Both machines in English; demo clips have no keyframes.
- [ ] **Pristine reset:** Restoring `C:\collab-demo-pristine\` returns to the demo start state in under 1 minute.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Echo/ping-pong (1) | LOW | Pause sync button; host sends fresh snapshot; guest rejoin |
| Wrong units (3) | LOW | Fix the conversion in the param table; rerun probe |
| `nodeId` unstable (5) | MEDIUM | Switch to name-tag fallback; re-fingerprint on join |
| Events silent (6) | LOW | Already covered by the 1 Hz poll; lower the interval to 500 ms if needed |
| Panel will not load (10) | MEDIUM | Reset registry keys with `setup.ps1`; load the stock PProPanel to isolate manifest vs environment |
| No peer connectivity (11) | MEDIUM | Hotspot; then wired; then tunnel |
| Tunnel blocked (12) | MEDIUM | Switch to hotspot; if all fail, run host and `fake-peer.js` on one laptop |
| Project mismatch (13) | LOW | Restore `C:\collab-demo-pristine\` on both; reopen; rejoin |
| Premiere crash during demo | MEDIUM | Autosave on; reopen the pristine project; rejoin (rehearse this) |
| Everything fails on stage | LOW | Pre-recorded 60 s screen video of a successful two-machine session, plus single-laptop `fake-peer.js` demo as a live fallback |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 Stale snapshot race | Phase 3 | Two idle machines for 60 s: rev constant; simultaneous edits converge |
| 2 Rounding drift | Phase 1 probe, Phase 3 | Write-then-read probe; shadow from read-back; no residual diff |
| 3 Motion/Opacity units and lookup | Phase 1, Phase 3 | Component/param dump committed; four params round-trip on both machines |
| 4 Timing setters | Phase 1, Phase 5 | Probe table of which fields each setter changes |
| 5 nodeId and map | Phase 1, Phase 3 | Save/reopen probe; join refuses a deliberately mismatched project |
| 6 Events and rebind | Phase 1, Phase 2/3 | Event table recorded; no duplicate events after 3 panel reloads |
| 7 evalScript handling | Phase 1 | Wrapper unit-tested with `undefined`, error and quote-containing inputs |
| 8 ES3 | Phase 1 | `ping()` and `JSON.stringify` work; lint step in place |
| 9 Injection and validation | Phase 2, Phase 3 | Fuzz test: malformed ops rejected; no code executes |
| 10 Panel load | Phase 1 | Empty panel visible on both laptops after restart |
| 11 Firewall and Wi-Fi | Phase 2, Phase 6 | Guest connects from the other laptop on venue Wi-Fi and hotspot |
| 12 Tunnel | Phase 2, Phase 6 | Real edit over `wss://` tunnel on a hotspot |
| 13 Project differences | Phase 1, Phase 6 | Hash check and join pre-check pass on both machines |
| 14 Undo | Phase 1, Phase 6 | Observed behaviour written into the demo notes |
| 15 Stuck pending and reconnect | Phase 2, Phase 3 | Kill the socket mid-edit; Rejoin restores the state |
| 16 Performance | Phase 1, Phase 3 | `$.hiresTimer` numbers recorded; no visible stutter |
| 17 Remote selection | Phase 4 | Remote selection never moves the local selection |
| 18 Panel visibility | Phase 6 | Full rehearsal with the final layout |
| 19 Null/wrong sequence | Phase 1, Phase 3 | Each bridge function tested with no project open |
| 20 Panel Chromium and ports | Phase 1, Phase 2 | `main.js` runs in the panel; configurable port |

## Phase-1 Probe List (settle the unknowns before design lock)

| # | Probe | Settles |
|---|-------|---------|
| P1 | Empty PProPanel-derived panel loads on both laptops; `ping()` returns `pong`; `JSON.stringify` works | 8, 10 |
| P2 | Dump all components and params of one clip (index, matchName, displayName, typeof value, value, `isTimeVarying`) | 3, 19 |
| P3 | `setValue` normalized vs pixel Position; Scale with Uniform on and off; Rotation 45, -45, 400; Opacity 0 to 100; read back each | 2, 3 |
| P4 | `nodeId` across move, trim, param edit, save/close/reopen, and re-fetching `activeSequence` | 5 |
| P5 | `start`/`end` alone, `move(delta)`, `inPoint`/`outPoint`: which fields change; overlap behaviour | 4 |
| P6 | Bind four candidate events; log `app.bind` return values; test with drag, trim, Effect Controls edit, selection | 6 |
| P7 | Remote-style `setValue` then Ctrl+Z | 14 |
| P8 | `$.hiresTimer` snapshot cost for 4 and 50 clips | 16 |
| P9 | `Test-NetConnection` from the second laptop to the relay; hotspot; `cloudflared` WebSocket round trip | 11, 12 |

## Sources

- Premiere ExtendScript docs (Adobe-maintained, `docsforadobe/premiere-scripting-guide`): `docs/item/trackitem.md` (start/end/inPoint/outPoint read-write; `nodeId` "Add a description"; `move()` shifts by seconds, added in 15.4), `docs/sequence/componentparam.md` (`getValue`/`setValue` only for non time-variant params; `displayName` localized; `setValue(value, updateUI)`), `docs/other/time.md` (254016000000 ticks per second; `ticks` is a String), `docs/introduction/changelog.md` (no ExtendScript changes after 23.0). Read directly. Confidence: MEDIUM-LOW per the confidence seam (single-source fetch).
- Adobe sample panel: `Adobe-CEP/Samples/PProPanel` (`jsx/PPRO/Premiere.jsx`: event binds, `CSXSEvent` via `PlugPlugExternalObject.dll`, `nodeId` in event logs, component order comment; `CSXS/manifest.xml`: CSXS 6.0 runtime, no Node flags). Read directly.
- Adobe Community threads (unconfirmed): Position reads as relative values such as `[0.5, 0.5]`; pixel `setValue` yields `[32000, 32767]`; "scale to frame size" cannot be read; event names `onActiveSequenceStructureChanged` vs `onSequenceSelectionChanged`; events are bound in ExtendScript and passed to the panel by CSXS events. Search results: https://community.adobe.com/t5/premiere-pro-discussions/how-to-find-out-if-a-clip-was-quot-scaled-to-frame-size-quot-in-a-cep-extension/m-p/11808662 and related threads. Confidence: LOW to MEDIUM (verified only by cross-reading two searches).
- Cloudflare docs: Quick Tunnels page (no uptime guarantee, 200 concurrent requests, no SSE, hostname changes per run) and Tunnel with firewall page (outbound port 7844, TCP for `http2`, UDP for `quic`). Read directly. Confidence: MEDIUM.
- Project research: `research/live-collab/07-premiere-pro-22-cep.md` and `08-mvp.md` (risks, checks, sync rules).
- Common CEP/Windows knowledge not re-verified here: `PlayerDebugMode` as `REG_SZ` per `CSXS.N` key, Windows firewall profile behaviour, CEP Chromium version, undo-stack behaviour. Marked [EXPERIENCE] or LOW above.

---
*Pitfalls research for: Premiere Pro 22.3.1 CEP/ExtendScript live-collab panel with a Node ws relay on venue Wi-Fi*
*Researched: 2026-10-10*
