import { useState } from "react";
import { Link } from "react-router-dom";
import { ChevronRight, Hand, Navigation } from "lucide-react";
import { Button, Card, GenreChip, IconBox } from "../components/brut";
import { useStore } from "../state/store";

// Design-only tracker: the toggle is local state and the fixes are placeholders.
// Real tracking (navigator.geolocation, foreground only) comes with the backend wiring.
const MOCK_FIXES = [
  { lat: 33.753102, lng: -84.385811, acc: 8, ago: 4 },
  { lat: 33.753087, lng: -84.385794, acc: 10, ago: 34 },
  { lat: 33.753061, lng: -84.385776, acc: 9, ago: 64 },
];

export function TrackerScreen() {
  const { blocked } = useStore();
  const [tracking, setTracking] = useState(false);

  return (
    <div className="page with-tabbar">
      <div className="page-head"><h1>tracker</h1></div>
      <div className="stack">
        <Card large className="col gap14 pad20">
          <div className="row gap12">
            <IconBox icon={Navigation} fill={tracking ? "green" : "light-blue"} size={44} />
            <h2>{tracking ? "tracking is on" : "tracking is off"}</h2>
          </div>
          <div className="row between">
            <span className="muted">authorization</span>
            <GenreChip text="when in use" fill="surface" />
          </div>
          <div className="row between">
            <span className="muted">fixes recorded</span>
            <GenreChip text={tracking ? String(MOCK_FIXES.length) : "0"} fill="surface" />
          </div>
        </Card>

        <Button variant={tracking ? "ghost" : "primary"} onClick={() => setTracking((t) => !t)}>
          {tracking ? "stop tracking" : "start tracking"}
        </Button>

        <Link to="/tracker/blocked" className="block">
          <Card flat className="row gap12 pad12">
            <IconBox icon={Hand} fill="orange" size={40} />
            <h3 className="grow">blocked people</h3>
            <GenreChip text={String(blocked.length)} fill="surface" />
            <ChevronRight size={18} strokeWidth={3} />
          </Card>
        </Link>

        <h2>recent</h2>
        {!tracking && <p className="muted">no location fixes yet.</p>}
        {tracking &&
          MOCK_FIXES.map((f) => (
            <Card key={f.ago} flat className="col pad14">
              <span className="mono">{f.lat.toFixed(6)}, {f.lng.toFixed(6)}</span>
              <span className="xsmall muted">{f.ago} s ago · ±{f.acc}m</span>
            </Card>
          ))}
      </div>
    </div>
  );
}
