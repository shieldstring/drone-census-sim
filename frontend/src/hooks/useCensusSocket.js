import { useEffect, useRef, useState } from "react";

export default function useCensusSocket(url = "ws://localhost:8080/dash") {
  const [latest, setLatest] = useState(null);
  const [history, setHistory] = useState([]);
  const [status, setStatus] = useState("connecting");
  const wsRef = useRef(null);

  useEffect(() => {
    let closed = false;
    let retryTimer;
    let ws;

    const connect = () => {
      if (closed) return;
      setStatus((prev) => (prev === "live" ? prev : "connecting"));
      ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        if (!closed) setStatus("live");
      };

      ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        setLatest(data);
        setHistory((prev) => [...prev.slice(-199), data]);
        setStatus("live");
      };

      ws.onerror = () => {
        if (!closed) setStatus("offline");
      };

      ws.onclose = () => {
        if (closed) return;
        setStatus("offline");
        retryTimer = setTimeout(connect, 2000);
      };
    };

    connect();

    return () => {
      closed = true;
      clearTimeout(retryTimer);
      if (ws) ws.close();
    };
  }, [url]);

  return { latest, history, status };
}
