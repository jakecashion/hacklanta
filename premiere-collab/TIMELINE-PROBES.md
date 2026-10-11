# Timeline probe results (Phase 3, ENV-06)

Gate: record these results before you build rename, move or trim sync.

Machine: dev laptop (host)  Premiere: 22.3.1  Date: 2026-10-10

Sequence: 23.976 fps. One frame is 10,594,584,000 ticks (`sequence.timebase`). The demo clip is 8 frames long.

**Status: partly done.** Two probes are still open. See "Open probes".

## How the probes ran

1. A script cloned `Sequence 01` to a new sequence, `PROBE (delete me)`. The demo sequence did not change.
2. The script added test clips to V1 of the probe sequence.
3. The script ran ExtendScript in Premiere through the Tandem panel debug port (`localhost:8088`, CDP `Runtime.evaluate`).
4. Each write and each read-back ran in a different `evalScript` call.
5. To see what Premiere plays, the script exported frames with `qe` `exportFramePNG`. Then it compared each frame with the source frames, pixel by pixel. All matches had a difference of 0.0.
6. The user did the hand edits (drag, trim, rename, Scale) in Premiere.

The project was not saved.

## Results

### 1. Clip identity (`nodeId`)

| Test | Result |
|------|--------|
| Scripted move, trim, in/out writes, rename | `nodeId` does not change |
| Hand drag, hand trim, hand rename | `nodeId` does not change (`000f4246`) |
| Premiere restart, same file, not saved | Same `nodeId` (`000f4242` before and after) |
| Clips added during the session | They get new values from a counter (`000f4244`, `000f4245`, ...) |
| Cloned sequence | The cloned clip gets a new `nodeId` |

`nodeId` looks like a counter that Premiere sets when it loads the project.

Do not use `nodeId` as the shared clip ID until the guest probe is done.

### 2. Move

| Write | Result |
|-------|--------|
| `trackItem.start = time` | No effect. No error. |
| `trackItem.move(delta)` | Moves the clip by `delta` seconds. A `Time` object and a plain number both work. A negative delta works. |

`move()` does not round to frames. `move(0.5)` put the clip between two frames. Send moves as ticks or whole frames.

### 3. Trim, in and out

Premiere stores `start`, `end`, `inPoint` and `outPoint` as separate values. A script write changes only one value.

| Write | What Premiere plays (source frames 0-7) |
|-------|------------------------------------------|
| `inPoint = 3` only | 3 4 5 6 7, then 3 black frames. The clip length stays 8. |
| `end = start + 4` only | 0 1 2 3. Then the clip ends. `outPoint` stays 8. |
| `end = start + 16` (past the media) | 0 to 7, then 8 black frames. |
| `outPoint = 4` only | 0 to 7. No change. |
| `end = start + 5` and `outPoint = 5` | 0 1 2 3 4 |

Rules:

1. The clip length on the timeline comes from `start` and `end` only.
2. The picture starts at `inPoint`. It moves forward one source frame for each timeline frame.
3. When the media ends, Premiere shows black. It does not freeze the last frame.
4. `outPoint` does not change what Premiere plays.
5. A hand trim keeps `outPoint` equal to `inPoint` + clip length. Do the same when you apply a trim.

To trim the tail, set `end` and `outPoint`.

To trim the head, you cannot set `start`. Do these steps:

1. Add `d` to `inPoint`.
2. Call `move(+d)`.
3. Set `end` back to its old value.
4. Set `outPoint` to `inPoint` + clip length.

### 4. No validation

Premiere accepts these writes with no error:

- `inPoint` larger than `outPoint` (span -3 frames).
- `end` past the end of the media (black frames).
- `end` across the next clip. Two clips then overlap on the same track. A hand edit cannot make this state.

Before you apply a move or trim op, do these checks:

1. Make sure that `inPoint` is 0 or more.
2. Make sure that `inPoint` + clip length is not more than the media length.
3. Make sure that the clip does not overlap the clip before or after it on the track.

If a check fails, do not apply the op. Write a line in the feed.

### 5. Rename

`trackItem.name = "..."` renames the clip on the timeline. The project item name does not change.

### 6. Events

All seven `app.bind` calls returned `true`.

| Edit | Events that fired |
|------|-------------------|
| Select a clip | `onActiveSequenceSelectionChanged` |
| Hand drag | `onActiveSequenceTrackItemRemoved`, `onActiveSequenceTrackItemAdded` (two pairs), then `onActiveSequenceChanged`, `onProjectChanged` |
| Hand trim | `onActiveSequenceChanged`, `onProjectChanged` |
| Hand rename | `onActiveSequenceChanged`, `onProjectChanged` |
| Scale in Effect Controls | `onActiveSequenceChanged`, `onProjectChanged` |
| Scripted `end` write or rename | `onActiveSequenceChanged` (4 to 5 times); rename also `onProjectChanged` |

- `onActiveSequenceStructureChanged` did not fire for any edit.
- No event tells which clip changed or what changed.
- A drag fires "removed" and "added", but the clip keeps its `nodeId`.

Decision: keep the 1 s scan to find edits. You can also start a scan when `onActiveSequenceChanged` fires. Do not make sync depend on events.

## Design input for Steps 2-5

- Rename op: `{clipId, field: "name", value: string}`. The relay and `sync.js` must accept a string value.
- Timing op: one op per clip with `{start, end, inPoint}` in ticks. Set `outPoint` from them.
- Apply order: `move(newStart - start)`, then `end`, then `inPoint`, then `outPoint`.
- Do the validation checks in section 4 before you apply.

## Open probes

1. **Save and reopen.** Do clips that you add in a session keep their `nodeId` after a save and reopen? Delete the probe sequence first. Do not save it in `demo.prproj`.
2. **Guest laptop.** Open the same `demo.prproj` on the guest. Read the `nodeId` of V1 clip 0 (`pc_listClips`). If it is `000f4242`, `nodeId` can be the shared clip ID. If it is different, keep `v{track}:{clip}` on the wire and map it to `nodeId` on each laptop.

## Clean up

Delete the `PROBE (delete me)` sequence before you save the project.
