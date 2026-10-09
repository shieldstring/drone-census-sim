import { useEffect, useState } from "react";
import Dashboard from "./Dashboard";

function useClock() {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);
  return now;
}

export default function App() {
  const now = useClock();
  const [linkStatus, setLinkStatus] = useState("connecting");

  const statusLabel =
    linkStatus === "live" ? "Live" : linkStatus === "offline" ? "Offline" : "Connecting";

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="brand-block">
          <h1 className="brand">Aether Census</h1>
          <p className="brand-sub">
            Drone population census — detect, track, zone-aggregate, density cross-check
          </p>
        </div>

        <div className="mission-meta">
          <div className={`status-chip ${linkStatus}`}>
            <span className="status-dot" />
            {statusLabel}
          </div>
          <div className="status-chip">
            {now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
          </div>
        </div>
      </header>

      <Dashboard onStatusChange={setLinkStatus} />
    </div>
  );
}
