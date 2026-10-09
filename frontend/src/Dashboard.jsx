import { useEffect } from "react";
import {
  LineChart,
  Line,
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

function formatNumber(value) {
  if (value == null || Number.isNaN(value)) return "—";
  return Number(value).toLocaleString();
}

export default function Dashboard({ onStatusChange }) {
  const { latest, history, status: liveStatus } = useCensusSocket();

  useEffect(() => {
    onStatusChange?.(liveStatus);
  }, [liveStatus, onStatusChange]);

  const zoneCounts = {};
  for (const point of history) {
    zoneCounts[point.zone] = point.unique_total;
  }

  const chartData = history.map((h) => ({
    frame: h.frame_count,
    unique: h.unique_total,
    current: h.current_frame_count,
  }));

  return (
    <main className="dashboard">
      <section className="metrics" aria-label="Mission metrics">
        <article className="metric">
          <span className="metric-label">Active zone</span>
          <div className="metric-value">{latest?.zone ?? "Standby"}</div>
        </article>
        <article className="metric">
          <span className="metric-label">People in frame</span>
          <div className="metric-value">{formatNumber(latest?.current_frame_count)}</div>
        </article>
        <article className="metric">
          <span className="metric-label">Unique counted</span>
          <div className="metric-value">{formatNumber(latest?.unique_total)}</div>
        </article>
        <article className="metric">
          <span className="metric-label">Survey altitude</span>
          <div className="metric-value">
            {latest?.altitude_m ?? "—"}
            <small>m</small>
          </div>
        </article>
      </section>

      <section className="workspace">
        <div className="panel">
          <div className="panel-head">
            <h2 className="panel-title">Annotated aerial feed</h2>
            <span className="panel-note">
              {liveStatus === "live" ? "Detection + tracking overlay" : "Feed offline"}
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
            <h2 className="panel-title">Zone density map</h2>
            <span className="panel-note">Survey grid coverage</span>
          </div>
          <div className="panel-body">
            <HeatMap zoneCounts={zoneCounts} activeZone={latest?.zone} />
          </div>
        </div>
      </section>

      <section className="panel chart-panel">
        <div className="panel-head">
          <h2 className="panel-title">Count trend</h2>
          <span className="panel-note">Unique IDs vs people currently visible</span>
        </div>
        <div className="panel-body">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={chartData} margin={{ top: 8, right: 18, left: 0, bottom: 0 }}>
              <CartesianGrid stroke="rgba(16,35,28,0.08)" vertical={false} />
              <XAxis
                dataKey="frame"
                tick={{ fill: "#6b7f75", fontSize: 11 }}
                axisLine={{ stroke: "rgba(16,35,28,0.12)" }}
                tickLine={false}
              />
              <YAxis
                tick={{ fill: "#6b7f75", fontSize: 11 }}
                axisLine={false}
                tickLine={false}
                allowDecimals={false}
              />
              <Tooltip
                contentStyle={{
                  borderRadius: 10,
                  border: "1px solid rgba(16,35,28,0.12)",
                  boxShadow: "0 10px 24px rgba(16,35,28,0.08)",
                }}
              />
              <Legend />
              <Line
                type="monotone"
                dataKey="unique"
                name="Unique total"
                stroke="#0f766e"
                strokeWidth={2.4}
                dot={false}
              />
              <Line
                type="monotone"
                dataKey="current"
                name="In frame"
                stroke="#c45c26"
                strokeWidth={2}
                dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </section>

      <section className="zone-list" aria-label="Zone totals">
        {ZONES.map((zone) => (
          <div className="zone-item" key={zone}>
            <span>{zone}</span>
            <strong>{formatNumber(zoneCounts[zone] || 0)}</strong>
          </div>
        ))}
      </section>

      <p className="footer-note">
        Live relay from the AI pipeline. Counts use persistent track IDs to reduce double-counting
        across the survey path.
      </p>
    </main>
  );
}
