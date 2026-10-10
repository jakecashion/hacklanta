import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { Check, Ellipsis, Hand, ListPlus, Reply, SquareArrowOutUpRight } from "lucide-react";
import { Button, Card, CoverArt, DecorBlob, DecorStar, GenreChip } from "../components/brut";
import { TopBar } from "../components/Layouts";
import { Modal } from "../components/Modal";
import { SELF_ID, relativeTime, type Song } from "../data/mock";
import { useStore } from "../state/store";

/** Mock songs have no Spotify link yet. Search for the song instead. */
const spotifySearchURL = (song: Song) =>
  `https://open.spotify.com/search/${encodeURIComponent(`${song.title} ${song.artist}`)}`;

export function RecommendationDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { recommendations, markRead, block, users } = useStore();
  const item = recommendations.find((r) => r.id === id);

  const [queued, setQueued] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [confirmBlock, setConfirmBlock] = useState(false);

  useEffect(() => {
    if (id) markRead(id);
  }, [id, markRead]);

  const canBlock = item && item.senderId !== SELF_ID;
  const sender = item && users.find((u) => u.id === item.senderId);

  return (
    <div className="page">
      <TopBar
        right={
          canBlock && (
            <div className="menu-anchor">
              <button type="button" className="nav-btn" aria-label="More" onClick={() => setMenuOpen((o) => !o)}>
                <Ellipsis size={22} strokeWidth={2.5} />
              </button>
              {menuOpen && (
                <div className="card menu">
                  <button
                    type="button"
                    className="menu-item danger"
                    onClick={() => { setMenuOpen(false); setConfirmBlock(true); }}
                  >
                    <Hand size={16} /> block {item.senderName}
                  </button>
                </div>
              )}
            </div>
          )
        }
      />

      {!item ? (
        <p className="muted center pad24">this song is not in your playlist.</p>
      ) : (
        <div className="stack content narrow">
          <div className="hero">
            <DecorStar color="yellow" size={34} rotation={12} style={{ left: "6%", top: 0 }} />
            <DecorStar color="orange" size={22} rotation={-10} style={{ right: "8%", top: -6 }} />
            <DecorBlob color="light-blue" size={50} style={{ right: "6%", bottom: 10 }} />
            <span className="cover-shadow"><CoverArt url={item.song.artworkURL} size={200} /></span>
          </div>

          <div className="center col gap4">
            <h1 style={{ fontSize: "1.75rem" }}>{item.song.title}</h1>
            <p className="muted" style={{ fontSize: "1.125rem" }}>{item.song.artist}</p>
          </div>

          <Card large className="col gap8 pad16">
            <div><GenreChip text="sent by" fill="orange" /></div>
            <h3>{item.senderName} · {relativeTime(item.receivedAt)}</h3>
            {item.note && <p className="italic">"{item.note}"</p>}
            {item.sharedGenres.length > 0 && (
              <div className="row gap8 wrap">
                {item.sharedGenres.slice(0, 3).map((g) => <GenreChip key={g} text={g} />)}
              </div>
            )}
          </Card>

          <Button icon={SquareArrowOutUpRight} onClick={() => window.open(spotifySearchURL(item.song), "_blank", "noopener")}>
            open in spotify
          </Button>
          {/* UI only for now. TODO: add the track to the Spotify queue (needs Spotify sign-in). */}
          <Button
            variant={queued ? "green" : "secondary"}
            icon={queued ? Check : ListPlus}
            disabled={queued}
            onClick={() => setQueued(true)}
          >
            {queued ? "added to queue" : "add to queue"}
          </Button>
          {sender && (
            <Button variant="ghost" icon={Reply} onClick={() => navigate(`/match/${sender.id}/song`)}>
              send a song back
            </Button>
          )}
        </div>
      )}

      {confirmBlock && item && (
        <Modal label={`block ${item.senderName}?`} onClose={() => setConfirmBlock(false)}>
          <div className="stack">
            <h2>block {item.senderName}?</h2>
            <p className="muted">they leave your map, you get no alerts from them, and their songs are removed.</p>
            <Button
              onClick={() => {
                block(item.senderId, item.senderName);
                navigate("/playlist", { replace: true });
              }}
            >
              block
            </Button>
            <button type="button" className="link-btn" onClick={() => setConfirmBlock(false)}>cancel</button>
          </div>
        </Modal>
      )}
    </div>
  );
}
