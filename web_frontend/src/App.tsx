import { Navigate, Route, Routes } from "react-router-dom";
import { MatchLayout, TabLayout } from "./components/Layouts";
import { BlockedPeople } from "./screens/BlockedPeople";
import { DevMenu } from "./screens/DevMenu";
import { MapScreen } from "./screens/MapScreen";
import { Meetup, MatchScreen, Sent, SongSearch } from "./screens/MatchFlow";
import { PlaylistScreen } from "./screens/PlaylistScreen";
import { RecommendationDetail } from "./screens/RecommendationDetail";
import { TrackerScreen } from "./screens/TrackerScreen";

export default function App() {
  return (
    <Routes>
      <Route element={<TabLayout />}>
        <Route path="/map" element={<MapScreen />} />
        <Route path="/playlist" element={<PlaylistScreen />} />
        <Route path="/tracker" element={<TrackerScreen />} />
      </Route>

      {/* Pushed screens: no tab bar */}
      <Route path="/playlist/:id" element={<MatchLayout />}>
        <Route index element={<RecommendationDetail />} />
      </Route>
      <Route path="/tracker/blocked" element={<MatchLayout />}>
        <Route index element={<BlockedPeople />} />
      </Route>
      <Route path="/dev" element={<MatchLayout />}>
        <Route index element={<DevMenu />} />
      </Route>

      {/* Match flow (the iOS full-screen cover) */}
      <Route path="/match/:userId" element={<MatchLayout />}>
        <Route index element={<MatchScreen />} />
        <Route path="song" element={<SongSearch />} />
        <Route path="meetup" element={<Meetup />} />
        <Route path="sent" element={<Sent />} />
      </Route>

      <Route path="*" element={<Navigate to="/map" replace />} />
    </Routes>
  );
}
