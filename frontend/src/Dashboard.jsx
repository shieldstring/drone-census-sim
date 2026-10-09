import { useEffect, useMemo, useState } from "react";
import {
  LineChart,
  Line,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ResponsiveContainer,
  Legend,
} from "recharts";
import useCensusSocket from "./hooks/useCensusSocket";
import VideoFeed from "./VideoFeed";
import HeatMap from "./HeatMap";

const ZONES = ["Zone A", "Zone B", "Zone C", "Zone D"];
const API_BASE = "http://localhost:8080/api/census";

function formatNumber(value) {
  if (value == null || Number.isNaN(Number(value))) return "—";
  return Number(value).toLocaleString();
}

function formatTime(ts) {
  if (!ts) return "—";
  return new Date(ts * 1000).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

export default function Dashboard({ onStatusChange }) {
  const { latest, history, status: liveStatus } = useCensusSocket();
  const [exportMsg, setExportMsg] = useState("");
  const [persistedTotal, setPersistedTotal] = useState(null);

  useEffect(() => {
    onStatusChange?.(liveStatus);
  }, [liveStatus, onStatusChange]);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        const res = await fetch(`${API_BASE}/total`);
        if (!res.ok) return;
        const data = await res.json();
        if (!cancelled) setPersistedTotal(data);
      } catch {
        // backend may be down during first paint
      }
    };
    load();
    const id = setInterval(load, 8000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  const zoneStats = useMemo(() => {
    const stats = {};
    for (const zone of ZONES) {
      stats[zone] = { unique: 0, current: 0, density: null, frames: 0 };
    }
    for (const point of history) {
      if (!stats[point.zone]) continue;
      stats[point.zone].unique = point.unique_total ?? stats[point.zone].unique;
      stats[point.zone].current = point.current_frame_count ?? 0;
      stats[point.zone].frames = point.frame_count ?? stats[point.zone].frames;
      if (point.density_estimate != null) {
        stats[point.zone].density = point.density_estimate;
      }
    }
    return stats;
  }, [history]);

  const censusTotal = useMemo(
    () => ZONES.reduce((sum, zone) => sum + (zoneStats[zone].unique || 0), 0),
    [zoneStats]
  );

  const chartData = history.map((h) => ({
    frame: h.frame_count,
    unique: h.unique_total,
    current: h.current_frame_count,
    density: h.density_estimate ?? null,
  }));

  const zoneBars = ZONES.map((zone) => ({
    zone,
    unique: zoneStats[zone].unique,
    current: zoneStats[zone].current,
  }));

  const densityEnabled = latest?.density_enabled === true;
  const sourceLabel = latest?.source || "video";

  async function exportCensus(format) {
    setExportMsg("");
    const path = format === "csv" ? "export.csv" : "export";
    try {
      const res = await fetch(`${API_BASE}/${path}`);
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        setExportMsg(err.error || "Export unavailable (MongoDB required)");
        return;
      }
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = format === "csv" ? "census_export.csv" : "census_export.json";
      a.click();
      URL.revokeObjectURL(url);
      setExportMsg(`Downloaded ${a.download}`);
    } catch {
      setExportMsg("Could not reach backend export API");
    }
  }

  function downloadLiveSnapshot() {
    const rows = [
      ["zone", "unique_total", "in_frame", "density_estimate", "frames"],
      ...ZONES.map((zone) => [
        zone,
        zoneStats[zone].unique,
        zoneStats[zone].current,
        zoneStats[zone].density ?? "",
        zoneStats[zone].frames,
      ]),
      ["CENSUS_TOTAL", censusTotal, "", "", latest?.frame_count ?? ""],
    ];
    const csv = rows.map((r) => r.join(",")).join("\n");
    const blob = new Blob([csv], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `census_live_${Date.now()}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    setExportMsg(`Downloaded ${a.download}`);
  }

  return (
    <main className="dashboard">
      <section className="toolbar">
        <div className="toolbar-left">
          <span className="hint">
            Source: <strong>{sourceLabel}</strong>
            {" · "}
            Last update: <strong>{formatTime(latest?.timestamp)}</strong>
            {persistedTotal?.persistence === false && " · DB offline (live only)"}
          </span>
        </div>
        <div className="toolbar-right">
          {exportMsg && <span className="hint">{exportMsg}</span>}
          <button type="button" className="btn" onClick={downloadLiveSnapshot}>
            Export live CSV
          </button>
          <button type="button" className="btn" onClick={() => exportCensus("csv")}>
            Export DB CSV
          </button>
          <button type="button" className="btn btn-primary" onClick={() => exportCensus("json")}>
            Export DB JSON
          </button>
        </div>
      </section>

      <section className="metrics" aria-label="Census metrics">
        <article className="metric">
          <span className="metric-label">Census total</span>
          <div className="metric-value">{formatNumber(censusTotal)}</div>
          <div className="metric-sub">Sum of unique IDs across zones</div>
        </article>
        <article className="metric">
          <span className="metric-label">Active zone</span>
          <div className="metric-value">{latest?.zone ?? "Standby"}</div>
          <div className="metric-sub">Survey grid cell in progress</div>
        </article>
        <article className="metric">
          <span className="metric-label">In frame now</span>
          <div className="metric-value">{formatNumber(latest?.current_frame_count)}</div>
          <div className="metric-sub">YOLO detections this frame</div>
        </article>
        <article className="metric">
          <span className="metric-label">Unique tracked</span>
          <div className="metric-value">{formatNumber(latest?.unique_total)}</div>
          <div className="metric-sub">ByteTrack IDs (anti double-count)</div>
        </article>
        <article className="metric">
          <span className="metric-label">Density estimate</span>
          <div className="metric-value">
            {densityEnabled ? formatNumber(latest?.density_estimate) : "Off"}
          </div>
          <div className="metric-sub">
            {densityEnabled ? "CSRNet crowd cross-check" : "Set USE_DENSITY_MAP=true"}
          </div>
        </article>
        <article className="metric">
          <span className="metric-label">Altitude / frames</span>
          <div className="metric-value">
            {latest?.altitude_m ?? "—"}
            <small>m</small>
          </div>
          <div className="metric-sub">{formatNumber(latest?.frame_count)} frames processed</div>
        </article>
      </section>

      <section className="workspace">
        <div className="panel">
          <div className="panel-head">
            <h2 className="panel-title">Annotated aerial feed</h2>
            <span className="panel-note">
              {liveStatus === "live"
                ? "Live YOLO + tracking overlay from the AI pipeline"
                : "Waiting for WebSocket /ai → /dash relay"}
            </span>
          </div>
          <div className="panel-body">
            <VideoFeed
              data={latest}
              zone={latest?.zone}
              altitude={latest?.altitude_m}
            />
          </div>
        </div>

        <div className="panel">
          <div className="panel-head">
            <h2 className="panel-title">Survey zone map</h2>
            <span className="panel-note">
              Geographic coverage — circle size = unique people counted in each zone (not the AI
              density model)
            </span>
          </div>
          <div className="panel-body">
            <HeatMap zoneCounts={Object.fromEntries(ZONES.map((z) => [z, zoneStats[z].unique]))} activeZone={latest?.zone} />
          </div>
        </div>
      </section>

      <section className="lower-grid">
        <div className="panel chart-panel">
          <div className="panel-head">
            <h2 className="panel-title">Count trend</h2>
            <span className="panel-note">Unique IDs, in-frame detections, optional density</span>
          </div>
          <div className="panel-body">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={chartData} margin={{ top: 8, right: 18, left: 0, bottom: 0 }}>
                <CartesianGrid stroke="#e2e8f0" vertical={false} />
                <XAxis dataKey="frame" tick={{ fill: "#64748b", fontSize: 11 }} tickLine={false} />
                <YAxis tick={{ fill: "#64748b", fontSize: 11 }} axisLine={false} tickLine={false} allowDecimals={false} />
                <Tooltip />
                <Legend />
                <Line type="monotone" dataKey="unique" name="Unique total" stroke="#0f766e" strokeWidth={2.2} dot={false} />
                <Line type="monotone" dataKey="current" name="In frame" stroke="#c2410c" strokeWidth={2} dot={false} />
                {densityEnabled && (
                  <Line type="monotone" dataKey="density" name="Density est." stroke="#2563eb" strokeWidth={2} dot={false} connectNulls />
                )}
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="panel chart-panel">
          <div className="panel-head">
            <h2 className="panel-title">Zone comparison</h2>
            <span className="panel-note">Unique vs currently visible per zone</span>
          </div>
          <div className="panel-body">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={zoneBars} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
                <CartesianGrid stroke="#e2e8f0" vertical={false} />
                <XAxis dataKey="zone" tick={{ fill: "#64748b", fontSize: 11 }} tickLine={false} />
                <YAxis tick={{ fill: "#64748b", fontSize: 11 }} axisLine={false} tickLine={false} allowDecimals={false} />
                <Tooltip />
                <Legend />
                <Bar dataKey="unique" name="Unique" fill="#0f766e" radius={[4, 4, 0, 0]} />
                <Bar dataKey="current" name="In frame" fill="#fb923c" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </section>

      <section className="lower-grid">
        <div className="panel">
          <div className="panel-head">
            <h2 className="panel-title">Census report by zone</h2>
            <span className="panel-note">Running totals for this survey session</span>
          </div>
          <div className="panel-body table-wrap">
            <table className="census-table">
              <thead>
                <tr>
                  <th>Zone</th>
                  <th>Unique people</th>
                  <th>In frame</th>
                  <th>Density est.</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {ZONES.map((zone) => (
                  <tr key={zone} className={latest?.zone === zone ? "active" : ""}>
                    <td>{zone}</td>
                    <td className="num">{formatNumber(zoneStats[zone].unique)}</td>
                    <td className="num">{formatNumber(zoneStats[zone].current)}</td>
                    <td className="num">
                      {zoneStats[zone].density != null
                        ? formatNumber(zoneStats[zone].density)
                        : densityEnabled
                          ? "—"
                          : "Off"}
                    </td>
                    <td>{latest?.zone === zone ? "Surveying" : zoneStats[zone].unique ? "Complete" : "Pending"}</td>
                  </tr>
                ))}
                <tr>
                  <td><strong>Total</strong></td>
                  <td className="num"><strong>{formatNumber(censusTotal)}</strong></td>
                  <td className="num">—</td>
                  <td className="num">—</td>
                  <td>{liveStatus === "live" ? "In progress" : "Idle"}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div className="panel">
          <div className="panel-head">
            <h2 className="panel-title">How counting works</h2>
            <span className="panel-note">Detection vs density — two different tools</span>
          </div>
          <div className="panel-body">
            <div className="method-list">
              <div className="method-item">
                <h3>1. YOLO + ByteTrack (primary)</h3>
                <p>
                  Detects people in each aerial frame and assigns persistent IDs so the same person
                  is not counted twice as the drone moves across a zone.
                </p>
                <span className="tag">Always on</span>
              </div>
              <div className="method-item">
                <h3>2. CSRNet density map (optional cross-check)</h3>
                <p>
                  Estimates how many people are in the frame from a crowd density heatmap. Useful in
                  very dense scenes where occlusion makes box detectors under-count. It is not the
                  geographic zone map on the right.
                </p>
                <span className={`tag ${densityEnabled ? "" : "off"}`}>
                  {densityEnabled ? "Enabled" : "Disabled (USE_DENSITY_MAP=false)"}
                </span>
              </div>
              <div className="method-item">
                <h3>3. Zone aggregation</h3>
                <p>
                  The survey path advances through Zone A→D. Unique track IDs are stored per zone and
                  summed into the census total for the mission report / export.
                </p>
                <span className="tag">Zones A–D</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <p className="footer-note">
        Live data streams over WebSocket (<code>/dash</code>). Snapshots persist to MongoDB when
        available. Density map = AI crowd estimate; zone map = geographic survey coverage.
      </p>
    </main>
  );
}
