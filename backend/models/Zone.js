const mongoose = require("mongoose");

const ZoneSnapshotSchema = new mongoose.Schema({
  timestamp: { type: Number, required: true },
  zone: { type: String, required: true },
  currentFrameCount: { type: Number, required: true },
  uniqueTotal: { type: Number, required: true },
  altitudeM: { type: String },
  densityEstimate: { type: Number, default: null },
});

module.exports = mongoose.model("ZoneSnapshot", ZoneSnapshotSchema);
