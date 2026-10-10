import { Hand } from "lucide-react";
import { Button, Card, EmptyState, IconBox } from "../components/brut";
import { TopBar } from "../components/Layouts";
import { relativeTime } from "../data/mock";
import { useStore } from "../state/store";

/** People the user blocked. Opened from the tracker tab. */
export function BlockedPeople() {
  const { blocked, unblock } = useStore();
  return (
    <div className="page">
      <TopBar title="blocked people" />
      {blocked.length === 0 ? (
        <EmptyState
          icon={Hand}
          iconFill="light-blue"
          starColor="green"
          title="no one blocked"
          body="you can block someone from a song they sent you."
        />
      ) : (
        <div className="stack content narrow">
          <p className="muted">they do not show on your map, send you alerts or send you songs.</p>
          {blocked.map((p) => (
            <Card key={p.id} flat className="row gap12 pad12">
              <IconBox icon={Hand} fill="orange" size={44} />
              <div className="col grow">
                <h3>{p.name}</h3>
                <span className="xsmall muted">blocked {relativeTime(p.blockedAt)}</span>
              </div>
              <Button variant="ghost" auto small onClick={() => unblock(p.id)}>unblock</Button>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
