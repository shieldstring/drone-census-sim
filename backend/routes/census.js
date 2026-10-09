const express = require("express");
const mongoose = require("mongoose");
const router = express.Router();
const ZoneSnapshot = require("../models/Zone");

function mongoReady() {
  return mongoose.connection.readyState === 1;
}

router.get("/", async (req, res) => {
  if (!mongoReady()) return res.json([]);
  try {
    const snapshots = await ZoneSnapshot.find().sort({ timestamp: -1 }).limit(100);
    res.json(snapshots);
  } catch (err) {
    res.status(503).json({ error: err.message });
  }
});

router.get("/zones", async (req, res) => {
  if (!mongoReady()) return res.json([]);
  try {
    const zones = await ZoneSnapshot.aggregate([
      { $sort: { timestamp: -1 } },
      { $group: { _id: "$zone", latest: { $first: "$$ROOT" } } },
    ]);
    res.json(zones.map((z) => z.latest));
  } catch (err) {
    res.status(503).json({ error: err.message });
  }
});

router.get("/total", async (req, res) => {
  if (!mongoReady()) return res.json({ total: 0, zoneCount: 0, persistence: false });
  try {
    const zones = await ZoneSnapshot.aggregate([
      { $sort: { timestamp: -1 } },
      { $group: { _id: "$zone", latest: { $first: "$$ROOT" } } },
    ]);
    const total = zones.reduce((sum, z) => sum + (z.latest.uniqueTotal || 0), 0);
    res.json({ total, zoneCount: zones.length });
  } catch (err) {
    res.status(503).json({ error: err.message });
  }
});

router.get("/export", async (req, res) => {
  if (!mongoReady()) return res.status(503).json({ error: "MongoDB not connected" });
  try {
    const snapshots = await ZoneSnapshot.find().sort({ timestamp: 1 });
    res.setHeader("Content-Disposition", "attachment; filename=census_export.json");
    res.json(snapshots);
  } catch (err) {
    res.status(503).json({ error: err.message });
  }
});

router.get("/export.csv", async (req, res) => {
  if (!mongoReady()) return res.status(503).json({ error: "MongoDB not connected" });
  try {
    const snapshots = await ZoneSnapshot.find().sort({ timestamp: 1 }).lean();
    const header = "timestamp,zone,currentFrameCount,uniqueTotal,altitudeM,densityEstimate";
    const rows = snapshots.map((s) =>
      [
        s.timestamp ?? "",
        JSON.stringify(s.zone ?? ""),
        s.currentFrameCount ?? "",
        s.uniqueTotal ?? "",
        s.altitudeM ?? "",
        s.densityEstimate ?? "",
      ].join(",")
    );
    res.setHeader("Content-Type", "text/csv");
    res.setHeader("Content-Disposition", "attachment; filename=census_export.csv");
    res.send([header, ...rows].join("\n"));
  } catch (err) {
    res.status(503).json({ error: err.message });
  }
});

module.exports = router;
