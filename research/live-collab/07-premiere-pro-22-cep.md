# 07 — Premiere Pro 22.3.1: CEP + ExtendScript plan

Date: 2026-10-10. Written in ASD-STE100 Simplified Technical English.

## 1. Facts

- Both machines have Premiere Pro **v22.3.1.2**.
- UXP plugins need Premiere 25.6 or later. **UXP does not work on 22.3.1.** Do not use `06-premiere-pro-uxp.md` for the build. Keep it for a later port.
- Use a **CEP panel** (HTML + JavaScript + Node.js) and **ExtendScript** (`.jsx`) for the build.
- The ExtendScript API is frozen. Adobe made no changes after 23.0. Everything we need is in 22.3.1.

## 2. Setup

1. On both machines, enable debug mode for CEP 11 (Premiere 15.4 and later use CSXS.11):
   - Windows: in `regedit`, go to `HKEY_CURRENT_USER\Software\Adobe\CSXS.11`. Add a string value `PlayerDebugMode` = `1`.
   - macOS: run `defaults write ~/Library/Preferences/com.adobe.CSXS.11.plist PlayerDebugMode 1`.
2. Put the panel folder in the CEP extensions folder:
   - Windows: `%APPDATA%\Adobe\CEP\extensions\`
   - macOS: `~/Library/Application Support/Adobe/CEP/extensions/`
3. In `CSXS/manifest.xml`, set host `PPRO` and enable Node.js (`--enable-nodejs`, `--mixed-context`).
4. CEP 11 uses Node.js 15.9. Use only node modules that work with Node 15.
5. Start from Adobe's sample panel: https://github.com/Adobe-CEP/Samples/tree/master/PProPanel
6. Restart Premiere. Open the panel from Window > Extensions.

### Tools

Do not use the UXP Developer Tool (UDT). UDT is for UXP plugins only. Use these tools:

| Task | Tool | How |
|---|---|---|
| Load the panel | Debug mode + extensions folder | Do steps 1–2 above. Use a symlink to the repo folder. Then you do not copy after each change. |
| Debug panel JS | Chrome DevTools | Add a `.debug` file to the panel root (see below). Open `http://localhost:8088` in Chrome. |
| Debug `.jsx` | VS Code + Adobe "ExtendScript Debugger" extension | Install the extension. Select Premiere Pro as the target. Do not use ExtendScript Toolkit. It is 32-bit and does not run on new macOS. |
| Reload panel JS | Premiere | Close the panel. Open it again. |
| Reload `.jsx` | Premiere | Load the `.jsx` again from the panel. If the change does not apply, restart Premiere. |
| Sign and package | `ZXPSignCmd` | Not necessary for the hackathon. Debug mode loads unsigned panels. |

Symlink commands:

- Windows (Command Prompt as administrator): `mklink /D "%APPDATA%\Adobe\CEP\extensions\<panel>" "<repo>\<panel>"`
- macOS: `ln -s "<repo>/<panel>" ~/Library/Application\ Support/Adobe/CEP/extensions/<panel>`

`.debug` file (put it in the panel root, next to `CSXS/`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ExtensionList>
  <Extension Id="<extension id from manifest.xml>">
    <HostList>
      <Host Name="PPRO" Port="8088"/>
    </HostList>
  </Extension>
</ExtensionList>
```

Install on each machine: Premiere 22.3.1, VS Code with the ExtendScript Debugger extension, and Chrome.

## 3. Parts

| Part | Runs in | Does |
|---|---|---|
| Panel JS | CEP (Node.js) | WebSocket to relay, sync engine, UI |
| Bridge `.jsx` | ExtendScript (ES3) | Reads and writes the timeline |
| Link | `csInterface.evalScript()` (JS to JSX) | Calls a `.jsx` function. Gets a string back. Send JSON strings. |
| Events back | `CSXSEvent` (JSX to JS) | Sends Premiere events to the panel |

Note: ExtendScript is ES3. There is no `JSON` object. Add `json2.js` to the `.jsx` side.

## 4. API to use (ExtendScript)

| Need | API |
|---|---|
| Active sequence | `app.project.activeSequence` |
| Sequence ID | `Sequence.sequenceID` |
| Clips | `seq.videoTracks[i].clips[j]` (`TrackItem`) |
| **Clip ID** | `TrackItem.nodeId` (string). Adobe's sample uses it in events. |
| Move a clip | Set `TrackItem.start` and `TrackItem.end` (read/write). Or `TrackItem.move(time)`. |
| Trim a clip | Set `TrackItem.inPoint` and `TrackItem.outPoint` (read/write) |
| Effect value | `TrackItem.components[i].properties[k]` (`ComponentParam`): `getValue()`, `setValue(v, true)` |
| Keyframes | `ComponentParam`: `setTimeVarying()`, `addKey()`, `setValueAtKey()` |
| Selection | `seq.getSelection()`, `TrackItem.isSelected()`, `TrackItem.setSelected()` |
| Playhead | `seq.getPlayerPosition()`, `seq.setPlayerPosition(ticks)` |
| Add a clip | `seq.insertClip()`, `seq.overwriteClip()` |
| Remove a clip | `TrackItem.remove()` |
| Rename | `TrackItem.name` |
| Export (render badge) | `app.encoder` (fixed on Mac in 22 and later) |
| Message in Premiere | `app.setSDKEventMessage(text, "info")` |

Events (`app.bind(name, fn)`). Adobe's sample panel uses these:

| Event | Use |
|---|---|
| `onActiveSequenceSelectionChanged` | Presence: send my selection |
| `onActiveSequenceStructureChanged` | Something changed. Compare snapshot. |
| `onActiveSequenceTrackItemAdded` | Clip added (gives track, trackItem) |
| `onActiveSequenceTrackItemRemoved` | Clip removed (gives track, trackItem) |
| `onActiveSequenceChanged` | Other sequence is active |
| `onProjectChanged` | Project changed |

## 5. How sync works

1. **Snapshot.** In `.jsx`, read the active sequence: each clip `nodeId`, track, `start`, `end`, `inPoint`, `outPoint`, `name`, Motion (Position, Scale, Rotation) and Opacity values. Return JSON.
2. **Find local edits.** On `onActiveSequenceStructureChanged`, on `onActiveSequenceSelectionChanged`, and on a 1 Hz timer: get a new snapshot. Compare it to the old one. Send each difference as an `op`.
3. **Send presence.** On `onActiveSequenceSelectionChanged`, send the selected `nodeId`s. Send the playhead at 2–5 Hz. Do not log presence.
4. **Host order.** Use the rules in `05` §5. The host gives each op a `rev`. The last writer wins per property. Use a soft lock per clip.
5. **Apply remote ops.** Call a `.jsx` function with `evalScript`. Find the clip by `nodeId`. Set the value.
6. **Prevent echo.** Before you apply a remote op, write the new value into the snapshot. Then the next compare does not send it again. Ignore events while an apply runs.

Op kinds for the MVP:

| Op | Fields |
|---|---|
| `move` | nodeId, start, end |
| `trim` | nodeId, inPoint, outPoint |
| `setParam` | nodeId, component matchName, param displayName, value |
| `addKey` | nodeId, component, param, time, value |
| `rename` | nodeId, name |

Do not sync these in the MVP: add or remove clips, transitions, audio, titles, nested sequences.

Use ticks (string) for all times. `Time.ticks` is exact. Seconds can round.

## 6. Changes from the AE plan (`05`)

| AE plan | Premiere 22.3.1 plan |
|---|---|
| Poll all changes at 4 Hz | Events tell us when to compare. Timer at 1 Hz only as backup. |
| Tag in `Layer.comment` | Use `TrackItem.nodeId` |
| Property path by `matchName` | Component `matchName` + param `displayName` |
| `beginUndoGroup` | No undo group API found. Each set can be its own undo step. |
| `aerender` | `app.encoder` |
| Everything else | Same: CEP, relay, WSS, host authority, invite code |

## 7. Risks

| Risk | Action |
|---|---|
| `nodeId` is not documented ("Add a description"). It can change after save or reopen. | Do test 3 in §8. If it changes, map IDs on join from the snapshot. |
| No undo group. One remote op can make many undo steps. | Set as few values as possible per op. Tell users in the demo. |
| `onActiveSequenceStructureChanged` can fire often or not on every edit | Keep the 1 Hz timer as backup |
| Large snapshot is slow in ES3 | Read only the active sequence. Cap at about 50 clips. |
| Media must be at the same path on both machines | Use one demo project. Copy the media folder to the same path on both. |
| Old version has known bugs. No fixes will come. | Test on 22.3.1 only. Do not test on a newer version. |
| `evalScript` calls wait in a queue | Send one batch per call. Do not call in a tight loop. |

## 8. First-hour tests

Stop and plan again if a test fails.

1. Load the sample panel (PProPanel) on both machines. Make sure it opens.
2. From the panel, open a `wss` connection to the relay. Send and receive one message.
3. Read `nodeId` of one clip. Save, close, and open the project. Read it again. Make sure it is the same.
4. Open the same project on machine B. Make sure the clip has the same `nodeId` on both machines.
5. Set `TrackItem.start` and `end` from a `.jsx` call. Make sure the clip moves.
6. Bind `onActiveSequenceStructureChanged`. Move a clip by hand. Make sure the event fires.
7. On two machines, move a clip on A. Make sure it moves on B and does not echo back.

Note: test 4 is the most important. If `nodeId` is different on each machine, use a tag in the clip name (for example `Hero [cu:a1b2]`).

## 9. Not verified

- What `nodeId` is, and if it is stable across save and across machines.
- If `onActiveSequenceStructureChanged` fires for a move, a trim, and an effect change.
- If all events in §4 exist in 22.3.1. The sample panel is the latest version.
- If Premiere has an undo group for scripts.
- If setting `start` changes `end` too, or if we must set both.
- The `.debug` file format, port 8088, and the VS Code ExtendScript Debugger support for Premiere 22.3.1. These come from general CEP knowledge, not from a source we read. First-hour test 1 checks the panel load.

## 10. Sources

- ExtendScript guide (source): https://github.com/docsforadobe/premiere-scripting-guide (TrackItem, Sequence, ComponentParam, Project, application, changelog)
- ExtendScript guide (site): https://ppro-scripting.docsforadobe.dev/
- Adobe sample panel, events and `nodeId` use: https://github.com/Adobe-CEP/Samples/blob/master/PProPanel/jsx/PPRO/Premiere.jsx
- CEP 11, Node 15.9, and CSXS.11 debug mode (forum): https://community.adobe.com/t5/premiere-pro-discussions/missing-com-adobe-csxs-lt-version-gt-plist-files/m-p/12217898/highlight/true
- UXP minimum version 25.6: see `06-premiere-pro-uxp.md`
