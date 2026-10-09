"""
Lightweight demo feeder — no OpenCV / torch required.

Uses ffmpeg (system binary) to pull JPEG frames from the sample video and
pushes them to the backend /ai WebSocket so the dashboard shows a live feed
while full AI deps install.

Usage:
  python3 -m ai_pipeline.demo_stream
  python3 -m ai_pipeline.demo_stream --source datasets/DroneCrowd/sample.mp4
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import shutil
import subprocess
import time
from pathlib import Path

import websockets

from ai_pipeline import config

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_VIDEO = ROOT / "datasets" / "DroneCrowd" / "sample.mp4"
ZONES = config.GRID_ZONES
FRAMES_PER_ZONE = config.FRAMES_PER_ZONE


def require_ffmpeg():
    if not shutil.which("ffmpeg"):
        raise SystemExit(
            "ffmpeg not found on PATH. Install it, or wait for the full AI pipeline "
            "(pip install -r requirements.txt) and run: python -m ai_pipeline.counter"
        )


async def connect():
    delay = 1.0
    while True:
        try:
            ws = await websockets.connect(config.WS_SERVER, max_size=8 * 1024 * 1024)
            print(f"[demo_stream] Connected to {config.WS_SERVER}")
            return ws
        except Exception as err:
            print(f"[demo_stream] Waiting for backend: {err}")
            await asyncio.sleep(delay)
            delay = min(delay * 1.5, 8.0)


def start_ffmpeg(video_path: Path):
    # Loop the file forever so the demo does not stop
    return subprocess.Popen(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-stream_loop",
            "-1",
            "-i",
            str(video_path),
            "-vf",
            f"fps=5,scale={config.STREAM_MAX_WIDTH}:-2",
            "-q:v",
            "8",
            "-f",
            "image2pipe",
            "-vcodec",
            "mjpeg",
            "-",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def read_jpeg(proc: subprocess.Popen) -> bytes | None:
    """Read one MJPEG frame from ffmpeg stdout (SOI..EOI markers)."""
    stdout = proc.stdout
    if stdout is None:
        return None

    # Find SOI
    while True:
        b = stdout.read(1)
        if not b:
            return None
        if b == b"\xff":
            b2 = stdout.read(1)
            if not b2:
                return None
            if b2 == b"\xd8":
                buf = bytearray(b"\xff\xd8")
                break

    while True:
        b = stdout.read(1)
        if not b:
            return None
        buf.append(b[0])
        if len(buf) >= 2 and buf[-2] == 0xFF and buf[-1] == 0xD9:
            return bytes(buf)


async def run(video_path: Path):
    require_ffmpeg()
    if not video_path.exists():
        raise SystemExit(f"Video not found: {video_path}")

    proc = start_ffmpeg(video_path)
    ws = await connect()
    frame_count = 0
    unique_total = 0
    zone_index = 0

    print(f"[demo_stream] Streaming {video_path} (ffmpeg demo mode — install ultralytics for full YOLO)")

    try:
        while True:
            jpeg = await asyncio.to_thread(read_jpeg, proc)
            if jpeg is None:
                if proc.poll() is not None:
                    print("[demo_stream] ffmpeg exited; restarting")
                    proc = start_ffmpeg(video_path)
                    continue
                await asyncio.sleep(0.05)
                continue

            frame_count += 1
            if frame_count % FRAMES_PER_ZONE == 0:
                zone_index += 1
            zone = ZONES[zone_index % len(ZONES)]

            # Synthetic rising count for dashboard demo when no detector is present
            in_frame = 8 + (frame_count % 17)
            unique_total = max(unique_total, unique_total + max(0, (frame_count % 11) - 7))
            if frame_count % 5 == 0:
                unique_total += 1

            payload = {
                "timestamp": time.time(),
                "zone": zone,
                "frame_count": frame_count,
                "current_frame_count": in_frame,
                "unique_total": unique_total,
                "altitude_m": config.ALTITUDE_SIMULATION,
                "density_enabled": False,
                "density_estimate": None,
                "source": "video",
                "tracker_mode": "demo_ffmpeg",
                "frame_b64": base64.b64encode(jpeg).decode("ascii"),
            }

            try:
                await ws.send(json.dumps(payload))
            except Exception as err:
                print(f"[demo_stream] send failed, reconnecting: {err}")
                try:
                    await ws.close()
                except Exception:
                    pass
                ws = await connect()

            await asyncio.sleep(0.05)
    finally:
        proc.kill()
        try:
            await ws.close()
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        default=str(DEFAULT_VIDEO),
        help="Path to an mp4 file (not the video: prefix)",
    )
    args = parser.parse_args()
    path = Path(args.source)
    if str(path).startswith("video:"):
        path = Path(str(path).split(":", 1)[1])
    asyncio.run(run(path))


if __name__ == "__main__":
    main()
