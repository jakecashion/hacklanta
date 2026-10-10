# Kill test results (Phase 1, ENV-03)

Gate: `setValue` on Scale, Rotation and Opacity must visibly change the Program monitor. If any fails, re-plan before Phase 2.

Machine: ______  Premiere: 22.3.1.2  Date: 2026-10-10

| Field | Wrote | Read back | Program monitor changed? | setValue ms |
|-------|-------|-----------|--------------------------|-------------|
| Motion.Scale | 150 | | | |
| Motion.Rotation | 45 | | | |
| Opacity.Opacity | 50 | | | |

## Unknowns noted

- Rotation above 360 (try Set Rotation 400): read back = ____
- Uniform Scale ON: does Scale write change both axes? ____
- Scan cost for 4 clips (**Scan cost** button): ____ ms
- Changed `.jsx` picked up by **Reload panel**, or Premiere restart needed? ____

## Raw log

```
(paste panel log here)
```
