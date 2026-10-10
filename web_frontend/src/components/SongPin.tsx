import { CoverArt, Equalizer } from "./brut";
import type { NearbyUser } from "../data/mock";

/**
 * Map pin: album art in a pastel ring with an ink border, a hard shadow and a pointer tail.
 * Green ring when within 100 m, light blue otherwise. The tail tip is the bottom-centre of `.pin`.
 * Rendered to static markup for Leaflet, so keep it free of hooks and event handlers.
 */
export function SongPin({ user, isSelected = false }: { user: NearbyUser; isSelected?: boolean }) {
  const near = user.distanceMeters <= 100;
  return (
    <div className={`pin ${near ? "near" : "far"} ${isSelected ? "selected" : ""}`}>
      <div className="pin-ring">
        <CoverArt url={user.nowPlaying?.artworkURL} size={48} round />
        {user.nowPlaying && (
          <span className="pin-eq">
            <Equalizer />
          </span>
        )}
      </div>
      <svg className="pin-tail" width="14" height="10" viewBox="0 0 14 10" aria-hidden>
        <polygon points="1,0 13,0 7,9" strokeWidth="2" strokeLinejoin="round" />
      </svg>
    </div>
  );
}
