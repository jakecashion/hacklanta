# 08 — MVP plan: two-machine live session in Premiere Pro 22.3.1

Date: 2026-10-10. Written in ASD-STE100 Simplified Technical English.

Status: **plan only.** Do not build until the team agrees.

Read first: `07-premiere-pro-22-cep.md` (API, setup, tools).

## 1. Goal

- Two Windows machines join one session in Premiere Pro 22.3.1.2.
- **Both machines can edit the same timeline.**
- Each machine shows the edits, selection, and playhead of the other machine.

## 2. Facts for this plan

| Item | Value |
|---|---|
| Machines | 2, both Windows |
| Premiere | 22.3.1.2 on both |
| Panel type | CEP 11 + ExtendScript |
| Relay | Node.js, runs on the host laptop |
| Network | Same Wi-Fi or a phone hotspot |
| Code location (later) | `premiere-collab/` on branch `research` |

## 3. MVP scope

### 3.1 In the MVP

1. The host starts a session. The panel shows a 6-character code.
2. The guest types the host IP and the code. The guest clicks **Join**.
3. The host clicks **Approve**.
4. The status badge shows: Not connected → Waiting → Connected.
5. The panel shows the names and colors of both users.
6. On join, the guest timeline changes to match the host timeline.
7. Both users can do these edits on video clips in the active sequence:
   - Move a clip on the same track.
   - Trim a clip (in point, out point).
   - Change Motion: Position, Scale, Rotation.
   - Change Opacity.
   - Rename a clip.
8. The other machine shows each edit in 1–2 seconds.
9. Each panel shows the clips that the other user selected, and the playhead time of the other user.
10. Each panel shows a change feed. Example: `Sam moved Hero (rev 12)`.

### 3.2 Not in the MVP

- Add or remove clips.
- Move a clip to a different track.
- Audio, transitions, titles, nested sequences.
- Effects other than Motion and Opacity.
- Keyframes.
- More than one sequence.
- Locks.
- One undo step for each remote edit.
- Reconnect without a new join.
- More than 2 users.
- Render badge.

## 4. Architecture

```
Host laptop (Windows)                                 Guest laptop (Windows)
Premiere ⇄ bridge.jsx ⇄ panel (host role)             panel (guest role) ⇄ bridge.jsx ⇄ Premiere
                          │ ws://localhost:8080                │ ws://<host IP>:8080
                          └─────────► relay.js (Node) ◄────────┘
                                      runs on host laptop
```

- The **host panel** is the authority. It gives each edit a number (`rev`).
- The **relay** only moves messages. It does not read edits.
- The panel uses the `WebSocket` that is in CEP. The panel does not need Node modules.

## 5. Parts (files to make later)

All files go in `premiere-collab/`.

| File | Job |
|---|---|
| `relay/relay.js`, `relay/package.json` | Rooms by code. Messages `create`, `join`, `approve`. Then sends each message to the host or to all. About 100 lines. Uses `ws`. |
| `relay/fake-peer.js` | Joins as a guest and sends test edits. One person can test with one Premiere. |
| `panel/CSXS/manifest.xml` | CEP 11 manifest. Host `PPRO`. Copy from the Adobe `PProPanel` sample. |
| `panel/.debug` | Debug port 8088 (see 07 §2 Tools). |
| `panel/js/CSInterface.js` | Copy from Adobe CEP-Resources, CEP 11. |
| `panel/js/sync.js` | Sync engine. No Premiere calls. Node can test it. |
| `panel/js/main.js`, `panel/index.html` | UI, WebSocket, timers, `evalScript` calls. |
| `panel/jsx/json2.js` | JSON for ExtendScript (ES3). |
| `panel/jsx/bridge.jsx` | `snapshot()`, `presence()`, `applyOps(json)`, `bindEvents()`. |
| `test/sync.test.js` | Tests for `sync.js`. Run with `node --test`. |

## 6. Data model

### 6.1 Clip ID

- Use the **host `nodeId`** as the clip ID in all messages.
- On join, the guest makes a map: host `nodeId` → local `nodeId`.
- The guest makes the map by track index and clip index. Both machines open the same project file, so the indexes are the same at join.
- Result: `nodeId` can be different on each machine. It must only stay the same on one machine during the session.

### 6.2 Time

- Use `Time.ticks` (string) for all times.
- Compare times as strings. Do not use seconds. Seconds can round.

### 6.3 Snapshot

One clip in a snapshot:

```json
{
  "id": "<nodeId>", "ti": 0, "ci": 2, "name": "Hero",
  "start": "<ticks>", "end": "<ticks>", "inPoint": "<ticks>", "outPoint": "<ticks>",
  "p": {
    "Motion.Position": [0.5, 0.5],
    "Motion.Scale": 100,
    "Motion.Rotation": 0,
    "Opacity.Opacity": 100
  }
}
```

## 7. Messages

All messages are JSON on one WebSocket.

| Type | From → To | Fields |
|---|---|---|
| `create` / `created` | host → relay → host | name → code |
| `join` | guest → relay | code, name, color |
| `join_request` | relay → host | name, color |
| `approve` | host → relay | guest id |
| `joined` | relay → guest | — |
| `snapshot` | host → guest | rev, clips |
| `op` | guest → host | opId, author, kind, clipId, values |
| `commit` | host → all | rev, op |
| `presence` | each → all | user, selected clip IDs, playhead ticks |

Op kinds: `move`, `trim`, `param`, `rename`.

Presence: send 4 times each second. Do not keep presence in the log.

## 8. Sync rules

Each machine keeps a **shadow**. The shadow is the last known state of the timeline.

1. **Find local edits.**
   - `bindEvents()` binds `onActiveSequenceStructureChanged` and `onActiveSequenceSelectionChanged`. Each event sends a `CSXSEvent` to the panel.
   - On each event, and each 1 second, the panel calls `snapshot()`.
   - The panel compares the snapshot to the shadow. Each difference becomes one op.
2. **Host makes an edit.**
   - The edit is already on the host timeline.
   - The host gives the op the next `rev`.
   - The host updates the shadow.
   - The host sends `commit` to all.
3. **Guest makes an edit.**
   - The edit stays on the guest timeline.
   - The guest updates the shadow.
   - The guest marks the field as **pending**. A field is `(clipId, field name)`.
   - The guest sends `op` to the host.
4. **Host gets an op.**
   - The host checks that the kind is in the allow list.
   - The host checks that the clip exists.
   - The host gives the op the next `rev`.
   - The host applies the op with `applyOps()`.
   - The host updates the shadow.
   - The host sends `commit` to all.
5. **A machine gets a commit.**
   - If the commit is its own pending op: clear the pending mark.
   - If the field is pending on this machine: do not apply. The local op comes later in host order, so it wins.
   - Else: apply with `applyOps()`. Update the shadow.
6. **Stop echo.**
   - Set `applying = true` during `applyOps()`.
   - Ignore events while `applying` is true.
   - The shadow has the new values. The next compare finds no difference. Nothing goes back.
7. **Conflict.** The last edit in host order wins for each field. The MVP has no locks.
8. **Join.**
   - The host sends `snapshot`.
   - The guest makes the clip ID map (§6.1).
   - The guest compares the host snapshot to its own timeline.
   - The guest applies each difference.
   - The guest sets the shadow to the host snapshot.

## 9. Network setup (Windows)

1. Connect both laptops to the same Wi-Fi. If the guest cannot connect, use a phone hotspot.
2. On the host, start the relay: `node relay/relay.js`.
3. When Windows Firewall asks, allow Node.js on **Private networks**.
4. On the host, run `ipconfig`. Find the IPv4 address.
5. On the guest, type `ws://<host IPv4>:8080` in the panel.
6. Fallback: on the host, run `cloudflared tunnel --url http://localhost:8080`. On the guest, use the `wss://...trycloudflare.com` address. Test WebSockets on the tunnel before the demo.

## 10. Demo project

1. Make a small project: one sequence, 4 video clips on V1. Names: Hero, Logo, Card, BG.
2. Use only Motion and Opacity. Do not use third-party effects.
3. Put the project and media in `C:\collab-demo\` on the host.
4. Copy `C:\collab-demo\` to the same path on the guest.
5. Do not change the project on one machine before the join.

## 11. Demo script

1. Host: start the relay. Open `C:\collab-demo\demo.prproj`. Click **Host**. Read the code.
2. Guest: open the same project. Type the host IP and code. Click **Join**.
3. Host: click **Approve**. Both panels show **Connected**.
4. Guest: move Hero. The host timeline shows the move.
5. Host: change Hero Scale. The guest Program monitor shows the change.
6. Both: select a clip. Each panel shows the selection of the other user.
7. Show the change feed with the names of the users.

## 12. Checks before the build

Do these checks first. They use the tests in 07 §8. Stop and plan again if a check fails.

| # | Check | If it fails |
|---|---|---|
| 1 | The panel loads on both machines with `PlayerDebugMode`. | Fix the manifest or registry. |
| 2 | The guest panel connects to `ws://<host IP>:8080`. | Use the hotspot. Then the tunnel. |
| 3 | `nodeId` stays the same for a clip after a move and a trim. | Use a tag in the clip name, for example `Hero [cu:a1b2]`. |
| 4 | Setting `start` and `end` (or `move()`) moves a clip. Setting `inPoint` and `outPoint` trims it. | Remove `move` or `trim` from the MVP. |
| 5 | `onActiveSequenceStructureChanged` fires for a move, a trim, and a Motion change. | Use the 1 second timer only. |
| 6 | `ComponentParam.setValue` on Motion and Opacity updates the Program monitor. | Remove `param` from the MVP. |

## 13. Tests (after the build)

1. `node --test test/`:
   - Host and guest engines get the same state after edits at the same time.
   - Edits on the same field and on different clips.
   - No echo loop.
   - The pending rule in §8 step 5 works.
2. One machine: Premiere with the panel as host. `fake-peer.js` as guest. The test edits show on the timeline.
3. Two machines: do the demo script (§11) on the venue Wi-Fi. Then do it on the hotspot.

## 14. Not known yet

- If `nodeId` stays the same during a session (check 3).
- If the events fire for all edit kinds (check 5).
- If the venue Wi-Fi lets two laptops connect to each other (check 2).
- The ExtendScript speed for a snapshot of about 50 clips at 1 time each second.
