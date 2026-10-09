require("dotenv").config();
const express = require("express");
const cors = require("cors");
const http = require("http");
const { WebSocketServer } = require("ws");
const mongoose = require("mongoose");

const ZoneSnapshot = require("./models/Zone");
const censusRoutes = require("./routes/census");

const PORT = process.env.PORT || 8080;
const MONGO_URI = process.env.MONGO_URI || "mongodb://localhost:27017/drone_census";

const app = express();
app.use(cors());
app.use(express.json());
app.use("/api/census", censusRoutes);

const server = http.createServer(app);

// Two WebSocket endpoints sharing one HTTP server:
//   /ai   - the Python AI pipeline pushes count/frame payloads here
//   /dash - the React dashboard subscribes here for live updates
const wssAI = new WebSocketServer({ noServer: true });
const wssDash = new WebSocketServer({ noServer: true });

const dashboardClients = new Set();

server.on("upgrade", (req, socket, head) => {
  if (req.url === "/ai") {
    wssAI.handleUpgrade(req, socket, head, (ws) => wssAI.emit("connection", ws, req));
  } else if (req.url === "/dash") {
    wssDash.handleUpgrade(req, socket, head, (ws) => wssDash.emit("connection", ws, req));
  } else {
    socket.destroy();
  }
});

wssDash.on("connection", (ws) => {
  dashboardClients.add(ws);
  ws.on("close", () => dashboardClients.delete(ws));
});

wssAI.on("connection", (ws) => {
  console.log("[server] AI pipeline connected on /ai");

  ws.on("message", async (raw) => {
    let payload;
    try {
      payload = JSON.parse(raw.toString());
    } catch (err) {
      return;
    }

    // Relay to every connected dashboard client immediately.
    const message = JSON.stringify(payload);
    for (const client of dashboardClients) {
      if (client.readyState === client.OPEN) client.send(message);
    }

    // Throttle MongoDB writes to ~1-in-30 payloads to bound write volume
    // while still keeping a representative time series.
    if (Math.random() < 0.033) {
      try {
        await ZoneSnapshot.create({
          timestamp: payload.timestamp,
          zone: payload.zone,
          currentFrameCount: payload.current_frame_count,
          uniqueTotal: payload.unique_total,
          altitudeM: payload.altitude_m,
          densityEstimate: payload.density_estimate ?? null,
        });
      } catch (err) {
        console.error("[server] Failed to persist snapshot:", err.message);
      }
    }
  });

  ws.on("close", () => console.log("[server] AI pipeline disconnected"));
});

async function start() {
  try {
    await mongoose.connect(MONGO_URI, {
      serverSelectionTimeoutMS: 3000,
    });
    console.log("[server] Connected to MongoDB");
  } catch (err) {
    console.error("[server] MongoDB connection failed:", err.message);
    console.error("[server] Continuing without persistence - live WebSocket relay still works.");
  }

  server.listen(PORT, () => {
    console.log(`[server] Listening on http://localhost:${PORT}`);
  });
}

start();
