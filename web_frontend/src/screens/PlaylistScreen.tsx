import { Link } from "react-router-dom";
import { ListMusic, Trash2 } from "lucide-react";
import { Button, Card, CoverArt, EmptyState } from "../components/brut";
import { relativeTime, type Recommendation } from "../data/mock";
import { useStore } from "../state/store";

/** The "playlist" tab: songs other people sent to you. */
export function PlaylistScreen() {
  const { recommendations, newCount, markAllRead, deleteRecommendation } = useStore();
  const n = recommendations.length;
  const summary = `${n === 1 ? "1 song" : `${n} songs`}${newCount > 0 ? ` · ${newCount} new` : ""}`;

  return (
    <div className="page with-tabbar">
      <div className="page-head">
        <h1>songs for you</h1>
        {newCount > 0 && (
          <Button variant="ghost" small auto onClick={markAllRead}>mark all read</Button>
        )}
      </div>

      {n === 0 ? (
        <EmptyState
          icon={ListMusic}
          title="no songs yet"
          body="when someone near you sends a song, it shows here."
        />
      ) : (
        <>
          <p className="small bold muted section-label">{summary}</p>
          <ul className="list">
            {recommendations.map((item) => (
              <li key={item.id} className="list-item">
                <RecommendationRow item={item} />
                <button
                  type="button"
                  className="row-delete"
                  aria-label={`Delete ${item.song.title}`}
                  onClick={() => deleteRecommendation(item.id)}
                >
                  <Trash2 size={16} />
                </button>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}

function RecommendationRow({ item }: { item: Recommendation }) {
  return (
    // New songs lift off the page with a shadow. Read songs stay flat.
    <Link to={`/playlist/${item.id}`} className="block">
      <Card flat={!item.isNew} className="row gap12 pad12">
        <CoverArt url={item.song.artworkURL} size={56} />
        <div className="col grow minw0">
          <span className={`ellipsis ${item.isNew ? "bold" : "semibold"}`} style={item.isNew ? { fontSize: "1.0625rem" } : undefined}>
            {item.song.title}
          </span>
          <span className="small muted">{item.song.artist}</span>
          <span className="xsmall muted">from {item.senderName} · {relativeTime(item.receivedAt)}</span>
          {item.note && <span className="xsmall muted ellipsis italic">"{item.note}"</span>}
        </div>
        {item.isNew && <span className="chip green xs">new</span>}
      </Card>
    </Link>
  );
}
