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

process.on("uncaughtException", (err) => {
  console.error("[server] uncaughtException:", err.message);
});
process.on("unhandledRejection", (err) => {
  console.error("[server] unhandledRejection:", err && err.message ? err.message : err);
});

const app = express();
app.use(cors());
app.use(express.json({ limit: "2mb" }));
app.use("/api/census", censusRoutes);

const server = http.createServer(app);

// Two WebSocket endpoints sharing one HTTP server:
//   /ai   - the Python AI pipeline pushes count/frame payloads here
//   /dash - the React dashboard subscribes here for live updates
const wssAI = new WebSocketServer({ noServer: true, maxPayload: 8 * 1024 * 1024 });
const wssDash = new WebSocketServer({ noServer: true, maxPayload: 8 * 1024 * 1024 });

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
  ws.on("error", () => dashboardClients.delete(ws));
  ws.on("close", () => dashboardClients.delete(ws));
});

wssAI.on("connection", (ws) => {
  console.log("[server] AI pipeline connected on /ai");

  ws.on("message", (raw) => {
    let payload;
    try {
      payload = JSON.parse(raw.toString());
    } catch (err) {
      return;
    }

    // Relay to every connected dashboard client immediately (include frames).
    let message;
    try {
      message = JSON.stringify(payload);
    } catch (err) {
      console.error("[server] Failed to serialize payload:", err.message);
      return;
    }

    for (const client of dashboardClients) {
      if (client.readyState === client.OPEN) {
        try {
          client.send(message);
        } catch (err) {
          dashboardClients.delete(client);
        }
      }
    }

    // Throttle MongoDB writes; never block the relay on persistence.
    if (mongoose.connection.readyState === 1 && Math.random() < 0.033) {
      ZoneSnapshot.create({
        timestamp: payload.timestamp,
        zone: payload.zone,
        currentFrameCount: payload.current_frame_count,
        uniqueTotal: payload.unique_total,
        altitudeM: payload.altitude_m,
        densityEstimate: payload.density_estimate ?? null,
      }).catch((err) => {
        console.error("[server] Failed to persist snapshot:", err.message);
      });
    }
  });

  ws.on("error", (err) => console.error("[server] AI socket error:", err.message));
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

  server.listen(PORT, "0.0.0.0", () => {
    console.log(`[server] Listening on http://localhost:${PORT}`);
  });
}

start();
