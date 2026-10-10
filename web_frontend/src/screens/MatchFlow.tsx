import { useEffect, useState } from "react";
import { Navigate, useLocation, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { Check, Handshake, Headphones, ListMusic, MapPinOff, Music, Search, Send } from "lucide-react";
import {
  Button,
  Card,
  CoverArt,
  DecorBlob,
  DecorStar,
  Equalizer,
  GenreChip,
  IconBox,
} from "../components/brut";
import { TopBar } from "../components/Layouts";
import { Modal } from "../components/Modal";
import { SONGS, distanceText, searchSongs, type NearbyUser, type Song } from "../data/mock";
import { useStore } from "../state/store";

/** Resolve :userId to a visible (not blocked) person, or null. */
function useMatchUser(): NearbyUser | null {
  const { userId } = useParams();
  const { visibleUsers } = useStore();
  return visibleUsers.find((u) => u.id === userId) ?? null;
}

/* ------------------------------------------------------------------ match */

export function MatchScreen() {
  const user = useMatchUser();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const outOfRange = params.get("out") === "1";
  if (!user) return <Navigate to="/map" replace />;

  const g = user.sharedGenres;
  const genreLine =
    g.length === 0 ? null : g.length === 1 ? `you both like ${g[0]}` : `you both like ${g[0]} and ${g[1]}`;
  const song = user.nowPlaying;

  return (
    <>
      <TopBar back={false} close />
      <div className="stack content narrow">
        <div className="match-header">
          {/* Kept in the top band beside the rings so they never sit on the headline */}
          <DecorStar color="yellow" size={34} rotation={12} style={{ left: "4%", top: 28 }} />
          <DecorStar color="orange" size={22} rotation={-8} style={{ right: "6%", top: 4 }} />
          <DecorBlob color="light-blue" size={54} style={{ right: "4%", top: 44 }} />
          <DecorStar color="green" size={18} style={{ left: "24%", top: 4 }} />

          <div className="rings" aria-hidden><i /><i /><b /></div>
          <p className="scribble">someone's near you!</p>
          <h1 className="center">{user.name} is {distanceText(user.distanceMeters)}</h1>
          {genreLine && <p className="muted">{genreLine}</p>}
        </div>

        {outOfRange && (
          <Card flat className="orange row gap8 pad12 bold small" style={{ justifyContent: "center" }}>
            <MapPinOff size={18} /> {user.name} moved out of range
          </Card>
        )}

        <Card large className="row gap14 pad16">
          <CoverArt url={song?.artworkURL} size={72} />
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
          {song && <Equalizer />}
        </Card>

        {g.length > 0 && (
          <div className="row gap8 wrap">
            {g.slice(0, 3).map((x) => <GenreChip key={x} text={x} />)}
          </div>
        )}

        <div className="stack tight">
          <Button icon={ListMusic} disabled={outOfRange} onClick={() => navigate(`/match/${user.id}/song`)}>send a song</Button>
          <Button variant="secondary" icon={Handshake} disabled={outOfRange} onClick={() => navigate(`/match/${user.id}/meetup`)}>meet up</Button>
        </div>
        <button type="button" className="link-btn" onClick={() => navigate("/map")}>not now</button>
      </div>
    </>
  );
}

/* ------------------------------------------------------------ song search */

export function SongSearch() {
  const user = useMatchUser();
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Song[]>(SONGS.slice(0, 4));
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<Song | null>(null);
  const trimmed = query.trim();

  // Mock search with a 350 ms debounce. Replace with a backend call later.
  useEffect(() => {
    if (!trimmed) {
      setLoading(false);
      setResults(SONGS.slice(0, 4));
      return;
    }
    setLoading(true);
    const t = setTimeout(() => {
      setResults(searchSongs(trimmed));
      setLoading(false);
    }, 350);
    return () => clearTimeout(t);
  }, [trimmed]);

  if (!user) return <Navigate to="/map" replace />;

  return (
    <>
      <TopBar title={`send to ${user.name}`} />
      <div className="stack content narrow">
        <label className="input">
          <Search size={18} className="muted" aria-hidden />
          <input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="search songs"
            autoCorrect="off"
            spellCheck={false}
            aria-label="search songs"
          />
        </label>

        {loading ? (
          <div className="center pad24"><div className="spinner" style={{ margin: "0 auto" }} /></div>
        ) : trimmed && results.length === 0 ? (
          <div className="center col gap8 pad24" style={{ alignItems: "center" }}>
            <DecorStar color="orange" size={36} rotation={8} style={{ position: "static" }} />
            <h3>no songs found for "{trimmed}"</h3>
            <p className="muted">try a different title or artist.</p>
          </div>
        ) : (
          <>
            <h2>{trimmed ? "results" : `suggested for ${user.name}`}</h2>
            <div className="stack tight">
              {results.map((song) => (
                <button key={song.id} type="button" className="plain-btn" onClick={() => setSelected(song)}>
                  <Card flat className="row gap12 pad12 hoverable">
                    <CoverArt url={song.artworkURL} size={48} />
                    <div className="col grow minw0">
                      <span className="semibold ellipsis">{song.title}</span>
                      <span className="small muted">{song.artist}</span>
                    </div>
                    <span className="send-dot"><Send size={14} strokeWidth={2.5} /></span>
                  </Card>
                </button>
              ))}
            </div>
          </>
        )}
      </div>

      {selected && (
        <ConfirmSong
          song={selected}
          user={user}
          onCancel={() => setSelected(null)}
          onSend={() => navigate(`/match/${user.id}/sent`, {
            replace: true,
            state: { subtitle: `${user.name} will see ${selected.title} in their playlist.` },
          })}
        />
      )}
    </>
  );
}

function ConfirmSong({ song, user, onSend, onCancel }: { song: Song; user: NearbyUser; onSend: () => void; onCancel: () => void }) {
  const [line, setLine] = useState("");
  const limit = 80;
  return (
    <Modal label="confirm song" onClose={onCancel}>
      <div className="stack">
        <div className="row gap14">
          <CoverArt url={song.artworkURL} size={64} />
          <div className="col">
            <h3>{song.title}</h3>
            <span className="muted">{song.artist}</span>
          </div>
        </div>
        <h2>send this song to {user.name}?</h2>
        <div className="col gap8">
          <label htmlFor="line" className="small bold muted">add a short line (optional)</label>
          <div className="input">
            <input
              id="line"
              autoFocus
              value={line}
              maxLength={limit}
              onChange={(e) => setLine(e.target.value)}
              placeholder="this one reminds me of you"
            />
          </div>
          {line.length >= 60 && <span className="xsmall muted">{line.length}/{limit}</span>}
        </div>
        <Button onClick={onSend}>send to {user.name}</Button>
        <button type="button" className="link-btn" onClick={onCancel}>cancel</button>
      </div>
    </Modal>
  );
}

/* ----------------------------------------------------------------- meetup */

const PRESETS = [
  { icon: Music, text: "Your music is fire! wanna talk?" },
  { icon: Headphones, text: "Wanna create a spotify blend?" },
];

export function Meetup() {
  const user = useMatchUser();
  const navigate = useNavigate();
  const [text, setText] = useState("");
  const [preset, setPreset] = useState<string | null>(null);
  const limit = 140;
  if (!user) return <Navigate to="/map" replace />;

  return (
    <>
      <TopBar title="meet up" />
      <div className="stack content narrow">
        <div className="relative">
          <h1>say hi to {user.name}</h1>
          <p className="muted">pick a message or write your own.</p>
          <DecorStar color="yellow" size={26} rotation={12} style={{ right: 4, top: -6 }} />
        </div>

        {PRESETS.map(({ icon, text: t }) => {
          const on = preset === t;
          return (
            <button key={t} type="button" className="plain-btn" onClick={() => { setPreset(t); setText(t); }}>
              {/* Selected card lifts (shadow). Others stay flat. */}
              <Card flat={!on} className="row gap12 pad14 hoverable">
                <IconBox icon={icon} fill={on ? "green" : "light-blue"} size={40} />
                <span className="semibold grow left">{t}</span>
                {on && <Check size={18} strokeWidth={3} />}
              </Card>
            </button>
          );
        })}

        <div className="col gap8">
          <label htmlFor="msg" className="small bold muted">or write your own</label>
          <div className="input">
            <textarea
              id="msg"
              rows={4}
              value={text}
              maxLength={limit}
              placeholder="type a message"
              onChange={(e) => {
                setText(e.target.value);
                if (e.target.value !== preset) setPreset(null);
              }}
            />
          </div>
          <span className="xsmall muted" style={{ textAlign: "right" }}>{text.length}/{limit}</span>
        </div>

        <Button
          icon={Send}
          disabled={!text.trim()}
          onClick={() => navigate(`/match/${user.id}/sent`, {
            replace: true,
            state: { subtitle: `${user.name} will get your message.` },
          })}
        >
          send
        </Button>
      </div>
    </>
  );
}

/* ------------------------------------------------------------------- sent */

export function Sent() {
  const user = useMatchUser();
  const navigate = useNavigate();
  const { state } = useLocation() as { state: { subtitle?: string } | null };
  const [shown, setShown] = useState(false);
  useEffect(() => { const t = setTimeout(() => setShown(true), 30); return () => clearTimeout(t); }, []);
  if (!user) return <Navigate to="/map" replace />;

  return (
    <>
      <TopBar back={false} />
      <div className="stack content narrow sent">
        <div className={`sent-art ${shown ? "shown" : ""}`}>
          <DecorStar color="yellow" size={36} rotation={10} style={{ left: "6%", top: "8%" }} />
          <DecorStar color="orange" size={24} rotation={-12} style={{ right: "8%", top: "2%" }} />
          <DecorBlob color="light-blue" size={50} style={{ right: "10%", bottom: "4%" }} />
          <DecorStar color="red" size={18} style={{ left: "12%", bottom: "6%" }} />
          <span className="sent-check"><Check size={48} strokeWidth={3} /></span>
        </div>
        <h1 className="center">sent to {user.name}</h1>
        <p className="muted center">{state?.subtitle ?? ""}</p>
        <Button onClick={() => navigate("/map")}>done</Button>
      </div>
    </>
  );
}
