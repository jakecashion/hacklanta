import { ListMusic, Handshake, X } from "lucide-react";
import { Button, CoverArt, GenreChip } from "./brut";
import { distanceText, type NearbyUser } from "../data/mock";

/** Card shown when the user taps a pin. A bottom sheet on phones, a side panel on desktop. */
export function NearbyUserCard({
  user,
  onRecommend,
  onMeetUp,
  onClose,
}: {
  user: NearbyUser;
  onRecommend: () => void;
  onMeetUp: () => void;
  onClose: () => void;
}) {
  const song = user.nowPlaying;
  return (
    <div className="card lg user-card">
      <button type="button" className="close-btn" onClick={onClose} aria-label="Close">
        <X size={16} strokeWidth={3} />
      </button>

      <div className="row gap14">
        <CoverArt url={song?.artworkURL} size={64} />
        <div className="col gap4 grow">
          {song ? (
            <>
              <div><GenreChip text="now playing" fill="green" /></div>
              <h3 className="clamp2">{song.title}</h3>
              <p className="small muted">{song.artist}</p>
            </>
          ) : (
            <p className="muted">not playing music right now</p>
          )}
        </div>
      </div>

      <div className="row gap8 wrap">
        <span className="small bold">{user.name} · {distanceText(user.distanceMeters)}</span>
        {user.sharedGenres.slice(0, 2).map((g) => (
          <GenreChip key={g} text={g} />
        ))}
      </div>

      <div className="row gap8">
        <Button icon={ListMusic} onClick={onRecommend}>send a song</Button>
        <Button variant="secondary" icon={Handshake} onClick={onMeetUp}>meet up</Button>
      </div>
    </div>
  );
}
