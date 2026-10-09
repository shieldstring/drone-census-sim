import { MapContainer, TileLayer, CircleMarker, Tooltip } from "react-leaflet";

const ZONE_COORDS = {
  "Zone A": [6.4654, 7.5265],
  "Zone B": [6.47, 7.53],
  "Zone C": [6.46, 7.52],
  "Zone D": [6.462, 7.535],
};

export default function HeatMap({ zoneCounts, activeZone }) {
  return (
    <div className="map-shell">
      <MapContainer center={[6.4654, 7.5265]} zoom={14} style={{ height: "100%", width: "100%" }}>
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        {Object.entries(ZONE_COORDS).map(([zone, coords]) => {
          const count = zoneCounts?.[zone] || 0;
          const active = zone === activeZone;
          return (
            <CircleMarker
              key={zone}
              center={coords}
              radius={Math.max(10, Math.min(42, 10 + count / 2))}
              pathOptions={{
                color: active ? "#0f766e" : "#c45c26",
                fillColor: active ? "#14b8a6" : "#ea580c",
                fillOpacity: active ? 0.55 : 0.35,
                weight: active ? 3 : 2,
              }}
            >
              <Tooltip>
                {zone}: {count} unique
              </Tooltip>
            </CircleMarker>
          );
        })}
      </MapContainer>
    </div>
  );
}
