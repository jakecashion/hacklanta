# Kill test results (Phase 1, ENV-03)

Gate: `setValue` on Scale, Rotation and Opacity must visibly change the Program monitor. If any fails, re-plan before Phase 2.

**Result: PASS.** All three fields moved the Program monitor (confirmed by eye) and read back exactly.

Machine: dev laptop (DESKTOP-TATE7J0)  Premiere: 22.3.1  Date: 2026-10-10

| Field | Wrote | Read back | Program monitor changed? | setValue ms |
|-------|-------|-----------|--------------------------|-------------|
| Motion.Scale | 150 | 150 | Yes | 5 |
| Motion.Rotation | 45 | 45 | Yes | 3 |
| Opacity.Opacity | 50 | 50 | Yes | 6 |

Reset (100 / 0 / 100) also read back exactly, 4-6 ms per write. `timeVarying` is false on all three.

## Unknowns noted

- Rotation above 360 (Set Rotation 400): not captured in the log
- Uniform Scale ON: does a Scale write change both axes? Not checked separately; Scale 150 visibly resized the image
- Scan cost (**Scan cost** button): not captured; the demo sequence has 1 clip so far (spec wants 4)
- Changed `.jsx` picked up by **Reload panel**, or Premiere restart needed? **Reload panel is enough.** A marker field added to `pc_ping` showed up after Reload
- Param lookup: matchNames `AE.ADBE Motion` / `AE.ADBE Opacity` and English displayNames found as expected
- `nodeId` is present (`000f4242`)
- Demo media: Premiere's bundled tutorial clip `A001_C037_0921FG_001.mp4` under `C:\Users\Public\Documents\Adobe\Premiere Pro\22.0\Tutorial\Going Home project\Footage\`

## Raw log

```
[6:04:20 PM] pc_resetClip  Scale 150->100 (6 ms), Rotation 45->0 (4 ms), Opacity 50->100 (6 ms), all ok, timeVarying false
[6:04:14 PM] pc_killTest   Scale 100->150 (5 ms), Rotation 0->45 (3 ms), Opacity 100->50 (6 ms), all ok, timeVarying false
[6:04:11 PM] pc_listClips  Sequence 01, track 0, 1 clip: v0:0 "A001_C037_0921FG_001.mp4" nodeId 000f4242 selected
                           p: Motion.Scale 100, Motion.Rotation 0, Opacity.Opacity 100
                           AE.ADBE Opacity: Opacity, Blend Mode, Blend Mode
                           AE.ADBE Motion: Position, Scale, Scale Width, Uniform Scale, Rotation, Anchor Point, Anti-flicker Filter
[6:04:10 PM] pc_ping       version 22.3.1, project demo.prproj, sequence Sequence 01, reloadTest "edited-1755"
```

(Full JSON log condensed; the panel writes it to `panel/panel-log.txt`.)
