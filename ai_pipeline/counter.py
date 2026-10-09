"""
ZoneCounter - the AI pipeline's orchestrator.

Reads frames from whichever source simulation/camera_stream.get_stream()
resolves (pre-recorded video, webcam, or live AirSim), runs detection +
tracking, optionally cross-checks with CSRNet density estimation, draws
annotated boxes, encodes the annotated frame to base64 for live dashboard
streaming, and pushes a JSON payload per frame over WebSocket to the
Node.js backend's /ai endpoint.
"""

import argparse
import asyncio
import base64
import json
import time

import cv2
import websockets

from ai_pipeline import config
from ai_pipeline.tracker import PersonTracker
from simulation.camera_stream import get_stream

if config.USE_DENSITY_MAP:
    from ai_pipeline.density_map import DensityEstimator


class ZoneCounter:
    def __init__(self, source=None):
        self.source = source or config.VIDEO_SOURCE
        self.stream = get_stream(self.source)
        self.tracker = PersonTracker()
        self.density = DensityEstimator(config.DENSITY_MODEL) if config.USE_DENSITY_MAP else None
        self.zone_index = 0
        self.frame_count = 0
        self.last_density = None

    @staticmethod
    def encode_frame(frame):
        """Downscale + JPEG-encode an annotated frame for WebSocket streaming."""
        h, w = frame.shape[:2]
        if w > config.STREAM_MAX_WIDTH:
            scale = config.STREAM_MAX_WIDTH / w
            frame = cv2.resize(frame, (config.STREAM_MAX_WIDTH, int(h * scale)))
        ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, config.STREAM_JPEG_QUALITY])
        if not ok:
            return None
        return base64.b64encode(buf).decode("ascii")

    def current_zone(self):
        zone = config.GRID_ZONES[self.zone_index % len(config.GRID_ZONES)]
        if self.frame_count and self.frame_count % config.FRAMES_PER_ZONE == 0:
            self.zone_index += 1
        return zone

    async def _connect(self):
        """Retry WebSocket connect so Windows cold-starts do not race the backend."""
        delay = 1.0
        while True:
            try:
                ws = await websockets.connect(config.WS_SERVER, max_size=8 * 1024 * 1024)
                print(f"[counter] Connected to {config.WS_SERVER}, source={self.source}")
                return ws
            except Exception as err:
                print(f"[counter] Waiting for backend at {config.WS_SERVER}: {err}")
                await asyncio.sleep(delay)
                delay = min(delay * 1.5, 10.0)

    async def run(self):
        ws = await self._connect()
        try:
            while True:
                ok, frame = self.stream.read()
                if not ok:
                    await asyncio.sleep(0.05)
                    continue

                self.frame_count += 1
                result = self.tracker.track(frame)
                annotated = result.plot()

                if self.density is not None and self.frame_count % 30 == 0:
                    try:
                        self.last_density = round(self.density.estimate_bgr(frame), 1)
                    except Exception as err:
                        print(f"[counter] Density estimate failed: {err}")

                box_count = 0
                if result.boxes is not None:
                    try:
                        box_count = len(result.boxes)
                    except TypeError:
                        box_count = 0

                source_kind = self.source.split(":", 1)[0] if self.source else "video"
                payload = {
                    "timestamp": time.time(),
                    "zone": self.current_zone(),
                    "frame_count": self.frame_count,
                    "current_frame_count": box_count,
                    "unique_total": self.tracker.total_unique,
                    "altitude_m": config.ALTITUDE_SIMULATION,
                    "density_enabled": self.density is not None,
                    "density_estimate": self.last_density,
                    "source": source_kind,
                    "tracker_mode": getattr(self.tracker, "mode", "yolo"),
                }

                if config.STREAM_VIDEO and self.frame_count % config.STREAM_EVERY_N_FRAMES == 0:
                    frame_b64 = self.encode_frame(annotated)
                    if frame_b64:
                        payload["frame_b64"] = frame_b64

                try:
                    await ws.send(json.dumps(payload))
                except Exception as err:
                    print(f"[counter] WebSocket send failed, reconnecting: {err}")
                    try:
                        await ws.close()
                    except Exception:
                        pass
                    ws = await self._connect()
        finally:
            try:
                await ws.close()
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        default=None,
        help='Override VIDEO_SOURCE, e.g. "video:datasets/DroneCrowd/sample.mp4", "webcam:0", "airsim"',
    )
    args = parser.parse_args()

    counter = ZoneCounter(source=args.source)
    asyncio.run(counter.run())


if __name__ == "__main__":
    main()
