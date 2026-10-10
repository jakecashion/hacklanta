import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { CircleMarker, MapContainer, Marker, TileLayer, ZoomControl, useMapEvents } from "react-leaflet";
import L from "leaflet";
import { renderToStaticMarkup } from "react-dom/server";
import { Wrench } from "lucide-react";
import { IconBox } from "../components/brut";
import { NearbyUserCard } from "../components/NearbyUserCard";
import { SongPin } from "../components/SongPin";
import { DEFAULT_CENTER, type NearbyUser } from "../data/mock";
import { useStore } from "../state/store";

function pinIcon(user: NearbyUser, isSelected: boolean) {
  return L.divIcon({
    className: "pin-wrap",
    html: renderToStaticMarkup(<SongPin user={user} isSelected={isSelected} />),
    iconSize: [0, 0],
    iconAnchor: [0, 0],
  });
}

function ClearOnMapClick({ onClear }: { onClear: () => void }) {
  useMapEvents({ click: onClear });
  return null;
}

export function MapScreen() {
  const navigate = useNavigate();
  const { visibleUsers } = useStore();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const selected = visibleUsers.find((u) => u.id === selectedId) ?? null;

  const icons = useMemo(
    () => new Map(visibleUsers.map((u) => [u.id, pinIcon(u, u.id === selectedId)])),
    [visibleUsers, selectedId],
  );

  const pill =
    visibleUsers.length === 0
      ? "no one near you yet"
      : visibleUsers.length === 1
        ? "1 person near you"
        : `${visibleUsers.length} people near you`;

  return (
    <div className="map-screen">
      <MapContainer center={DEFAULT_CENTER} zoom={16} zoomControl={false} className="map">
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <ZoomControl position="topright" />
        <ClearOnMapClick onClear={() => setSelectedId(null)} />
        <CircleMarker
          center={DEFAULT_CENTER}
          radius={9}
          pathOptions={{ color: "#010101", weight: 2, fillColor: "#28b1e6", fillOpacity: 1 }}
        />
        {visibleUsers.map((u) => (
          <Marker
            key={u.id}
            position={[u.lat, u.lng]}
            icon={icons.get(u.id)!}
            zIndexOffset={u.id === selectedId ? 1000 : 0}
            eventHandlers={{ click: () => setSelectedId(u.id) }}
          />
        ))}
      </MapContainer>

      <div className="map-overlay top-left">
        <IconBox icon={Wrench} fill="yellow" size={44} label="Dev menu" onClick={() => navigate("/dev")} />
      </div>

      <div className="map-overlay top-center">
        <span className="pill-note">{pill}</span>
      </div>

      {selected && (
        <div className="sheet">
          <NearbyUserCard
            user={selected}
            onClose={() => setSelectedId(null)}
            onRecommend={() => navigate(`/match/${selected.id}/song`)}
            onMeetUp={() => navigate(`/match/${selected.id}/meetup`)}
          />
        </div>
      )}
    </div>
  );
}
