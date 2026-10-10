# web_frontend

Web port of the LocationTracker iOS app's design. UI only: everything runs on mock data in `src/data/mock.ts` and an in-memory store in `src/state/store.tsx`. Nothing calls the backend yet.

Vite + React + TypeScript, react-router, Leaflet (OpenStreetMap tiles), lucide icons.

```
npm install
npm run dev      # http://localhost:5173
npm run build    # typecheck + production build
```

## Where things are

| Path | Ported from |
|---|---|
| `src/theme.css` | `Theme.swift` and `DESIGN.md`: colour tokens, card/button/chip/input/icon-box primitives, press-down buttons |
| `src/components/brut.tsx` | `Theme.swift` components: `GenreChip`, `IconBox`, `CoverArt`, `Equalizer`, `DecorStar`, `DecorBlob` |
| `src/components/SongPin.tsx`, `NearbyUserCard.tsx` | `SongPin.swift`, `NearbyUserCard.swift` |
| `src/screens/MapScreen.tsx` | `NearbyMapView.swift` |
| `src/screens/PlaylistScreen.tsx`, `RecommendationDetail.tsx` | `RecommendationsView.swift`, `RecommendationDetailView.swift` |
| `src/screens/MatchFlow.tsx` | `MatchView.swift`, `SongSearchView.swift`, `MeetupView.swift`, `SentView.swift` |
| `src/screens/TrackerScreen.tsx`, `BlockedPeople.tsx` | `TrackerView` in `ContentView.swift`, `BlockedPeopleView.swift` |
| `src/screens/DevMenu.tsx` | `DevMenuView.swift` (mock-state tools only; no notifications) |

## Routes

`/map`, `/playlist`, `/playlist/:id`, `/tracker`, `/tracker/blocked`, `/dev`, `/match/:userId` (+ `/song`, `/meetup`, `/sent`). Add `?out=1` to a match URL to see the out-of-range state.

## Differences from iOS

- Layout is responsive: bottom sheet and bottom tab bar on phones, a side panel for the selected person on desktop (>= 900px).
- The decorative star has a wider waist than `FourPointStar` so its fill shows under the outline at web sizes.
- Font is DM Sans (per `DESIGN.md`) instead of the iOS rounded system font. Handwritten callouts use Caveat instead of Bradley Hand.
- The tracker is a visual stub. Browsers can't track location in the background.
- Not ported yet: the "cannot search now" error state and notification tools.
