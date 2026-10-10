# 06 — Premiere Pro version: plugin SDK and plan changes

Date: 2026-10-10. Written in ASD-STE100 Simplified Technical English.

## 1. Decision

- We start with Premiere Pro. We do After Effects (AE) after.
- The architecture in `05-architecture-and-plan.md` stays the same: relay server, host is the authority, ops over WSS.
- This file gives only the changes for Premiere Pro.

## 2. Which plugin type to use

Use a **UXP plugin**. Do not use the other types.

| Type | What it does | Use it? |
|---|---|---|
| UXP plugin (JavaScript) | Panel. Reads and edits the project and timeline. GA since Premiere 25.6. | **Yes** |
| UXP Hybrid plugin (UXP + C++ `.uxpaddon`) | Adds native C++ code. Premiere 26.2+. | Only if speed is a problem |
| C++ SDK | Importers, exporters, effects, transitions, transmitters, control surfaces. | **No.** It cannot edit the timeline. |
| CEP + ExtendScript | Old panel type. Adobe stops new CEP submissions Dec 2027. CEP is off by default Dec 2028. | No |

## 3. Setup

1. Install Premiere Pro 25.6 or later on both machines. Use the same version on both.
2. Install the UXP Developer Tool (UDT) 2.2 or later.
3. In Premiere, enable developer mode (Preferences > Plugins).
4. Use manifest v5.
5. Put the relay domain in `manifest.json`:

```json
"requiredPermissions": {
  "network": { "domains": ["wss://<relay-domain>"] }
}
```

Note: UXP blocks all domains that are not in this list. macOS blocks `http://`. Use `https://` and `wss://`.

## 4. API to use

Get the API with `const ppro = require("premierepro");`.

| Need | API |
|---|---|
| Make an edit | `project.executeTransaction(cb, undoString)`. Add actions to the `CompoundAction` in `cb`. |
| Read with no changes during the read | `project.lockedAccess(cb)` |
| Move or trim a clip | `VideoClipTrackItem`: `createMoveAction`, `createSetStartAction`, `createSetEndAction`, `createSetInPointAction`, `createSetOutPointAction` |
| Add or remove a clip | `SequenceEditor`: `createInsertProjectItemAction`, `createOverwriteItemAction`, `createRemoveItemsAction` |
| Set an effect value or keyframe | `ComponentParam`: `createSetValueAction`, `createAddKeyframeAction` |
| Rename a clip | `createSetNameAction` |
| Selection | `sequence.getSelection()`, `sequence.setSelection()` |
| Playhead | `sequence.getPlayerPosition()`, `sequence.setPlayerPosition()` |
| Events | `EventManager.addEventListener(target, name, handler)` |
| Export (render badge) | `EncoderManager`, then event `EVENT_EXPORT_MEDIA_COMPLETE` |
| Network | `WebSocket` (global, no `require`) |

Available events:

- `SequenceEvent`: `ACTIVATED`, `CLOSED`, `SELECTION_CHANGED`.
- `ProjectEvent`: `EVENT_ACTIVATED`, `EVENT_DIRTY`, `EVENT_OPENED`.
- `OperationCompleteEvent`: `EVENT_EXPORT_MEDIA_COMPLETE`, `EVENT_IMPORT_MEDIA_COMPLETE`, and others.

## 5. IDs

- A sequence has a stable `guid`.
- A project item has `getId()`.
- **A clip on the timeline has no ID.** We did not find one in the docs.
- Make a clip ID from: sequence `guid` + track index + project item ID + start time.
- If that fails, write a tag in the clip name with `createSetNameAction`, for example `Hero [cu:a1b2]`.

## 6. How sync works in Premiere

1. **Presence.** Listen for `SELECTION_CHANGED`. Send the selected clip IDs and playhead. Do not poll for selection.
2. **Find local edits.** There is no "clip changed" event. `EVENT_DIRTY` fires only when the dirty state changes. Do this:
   - Keep a snapshot of the active sequence: tracks, clips, start, end, in, out, Motion and Opacity values.
   - Compare a new snapshot to the old snapshot on `SELECTION_CHANGED`, on `EVENT_DIRTY`, and on a slow timer (1–2 Hz).
   - Send each difference as an `op`.
3. **Apply remote ops.** Apply each op in one `executeTransaction`. Use the author in the undo string, for example `"Sam: move Hero"`. Then each remote edit is one undo step.
4. **Prevent echo.** Before you apply a remote op, update the snapshot with the new value. Then the next compare does not send it again.
5. **Host order and locks.** Use the same rules as `05` §5: the host gives each op a `rev`, last writer wins per property, soft lock per clip.

Op kinds for the MVP:

| Op | Fields |
|---|---|
| `move` | clipId, newStart |
| `trim` | clipId, start, end, in, out |
| `setParam` | clipId, component matchName, param, value |
| `addKeyframe` | clipId, component, param, time, value |
| `rename` | clipId, name |

Do not sync these in the MVP: add or remove clips, transitions, audio, titles, nested sequences.

## 7. Changes from the AE plan (`05`)

| AE plan | Premiere plan |
|---|---|
| CEP panel + ExtendScript bridge | One UXP plugin. No bridge. |
| `PlayerDebugMode` for unsigned panels | UDT and developer mode |
| Poll at 4 Hz for all changes | Event for selection. Compare on events and a slow timer for edits. |
| `beginUndoGroup` | `executeTransaction` with an undo string |
| Tag in `Layer.comment` | Clip ID from position, or tag in clip name |
| `aerender` for the render badge | `EncoderManager` + `EVENT_EXPORT_MEDIA_COMPLETE` |
| Any relay URL | Relay domain must be in the manifest. A random Cloudflare quick tunnel name needs `https://*.trycloudflare.com`. |

## 8. Risks

| Risk | Action |
|---|---|
| UI can freeze during many timeline actions. One forum report (Apr 2026, no answer) says edits show only at the end of a loop and Premiere can crash. | Apply one small transaction per op. Test this first. |
| No clip ID | Do test 4 in §9. Use the name tag if it fails. |
| Different Premiere versions change API behavior. Example: `setSelection` is synchronous from 26.3. | Use the same version on both machines. |
| Media must be at the same path on both machines | Use a demo project with media in one shared folder. Use the same folder path on both. |
| No AI in the core | Same as `05` §3. |

## 9. First-hour tests

Stop and plan again if a test fails.

1. Load a UXP panel with UDT. Open a `wss` connection to the relay. Send and receive one message.
2. Move a clip with `createMoveAction` in `executeTransaction`. Make sure undo shows one step.
3. Apply 20 ops in a row. Make sure the UI does not freeze.
4. Make a clip ID. Move, trim, and rename the clip. Make sure the ID still finds the clip.
5. Listen for `SELECTION_CHANGED`. Make sure it fires when you click a clip.
6. On two machines, move a clip on one. Make sure it moves on the other and does not echo back.

## 10. Not verified

- **ExtendScript end date.** A forum user said ExtendScript ends September 2026. Adobe says ExtendScripts "are not affected". Do not use the September 2026 date.
- **ExtendScript events and `nodeId`.** We think ExtendScript has `onActiveSequenceStructureChanged` and a clip `nodeId`. We did not find these in the docs. They are a possible fallback.
- **Migration guide.** The Adobe ExtendScript to UXP migration guide is empty ("Stuff goes here...").
- **Clip ID.** We did not find an ID on `VideoClipTrackItem`. A newer API can add one. Check the changelog.

## 11. Sources

- Premiere UXP docs (source on GitHub): https://github.com/AdobeDocs/uxp-premiere-pro (EventManager, Project, Sequence, SequenceEditor, ComponentParam, Guid, constants, network recipe, changelog 26.5, hybrid plugins)
- UXP API reference: https://developer.adobe.com/premiere-pro/uxp/ppro-reference/
- UXP samples: https://github.com/AdobeDocs/uxp-premiere-pro-samples
- Adobe blog, UXP and CEP dates (Sept 2026): https://blog.developer.adobe.com/en/publish/2026/09/investing-in-the-future-of-creative-cloud-extensibility-uxp-comes-to-our-flagship-applications
- C++ SDK plugin types: https://ppro-plugins.docsforadobe.dev/intro/premiere-pro-plugin-types/
- Forum, UI freeze: https://community.adobe.com/questions-729/uxp-api-freezing-premiere-pro-ui-during-timeline-operations-1559410
- Forum, ExtendScript to UXP: https://community.adobe.com/questions-729/extendscript-to-uxp-for-premiere-pro-1553924
- ExtendScript guide: https://ppro-scripting.docsforadobe.dev/application/application/
- Example UXP project: https://github.com/CaYatur/PremiereProMCP
