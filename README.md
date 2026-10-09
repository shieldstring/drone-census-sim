# Drone-Based Population Census - Simulation

A fully software-simulated drone census system: no physical drone or hardware
required. Pre-recorded video, a webcam, or **Flight Simulation (AirSim +
Unreal Engine)** all feed the same AI pipeline through one abstraction layer.

AirSim is a free, open-source Microsoft simulator that runs inside Unreal
Engine and exposes a Python API to control drones autonomously — takeoff,
waypoints, and frames from a virtual onboard camera. Unreal environments
(cities, neighborhoods, open areas) can be loaded directly; pedestrian NPC
characters are the population to be counted. Details: `simulation/README.md`.

## Architecture

```
simulation/      AirSim flight control + frame-source abstraction
ai_pipeline/      YOLOv8 detection, ByteTrack tracking, optional CSRNet density check, zone aggregation
backend/          Node.js/Express + WebSocket relay + MongoDB persistence
frontend/         React + Vite dashboard (live video, Leaflet heatmap, Recharts)
datasets/         Sample/validation footage
scripts/          One-command launchers and AirSim auto-setup
```

Data flow: `simulation/camera_stream.py` yields frames -> `ai_pipeline/counter.py`
runs detection + tracking, draws annotations, and sends a JSON payload (counts,
zone, GPS-style zone label, and a base64 JPEG of the annotated frame) over
WebSocket to `backend/server.js` on `/ai` -> the backend relays it live to every
dashboard client on `/dash` and throttles writes to MongoDB (~1 in 30 payloads)
-> `frontend/src/Dashboard.jsx` renders the live feed, heatmap, and running chart.

## Running it

The one-command launchers in `scripts/` start everything (MongoDB, backend,
frontend, AI pipeline, and optionally AirSim) in the right order and tear it
all down together on Ctrl+C.

**Linux / WSL:**
```bash
./scripts/start.sh            # default: pre-recorded video
./scripts/start.sh --webcam   # live webcam
./scripts/start.sh --airsim   # live AirSim simulation (auto-downloads the environment on first run)
```

**Windows:**
```powershell
.\RUN.bat
.\scripts\start.ps1
.\scripts\start.ps1 -Webcam
.\scripts\start.ps1 -Airsim
```
Double-click `RUN.bat`, or follow `CLIENT_QUICKSTART.md`. A demo video is
bundled at `datasets/DroneCrowd/sample.mp4`.

**macOS:** AirSim has no native macOS build. Run `./scripts/setup_mac.sh` first
to install prerequisites, and optionally `./scripts/setup_mac.sh --remote-host <ip>`
to point this machine at AirSim running live on a separate Windows/Linux box on
the same network. Then use `./scripts/start.sh` as above (video/webcam modes
work locally either way).

Once running, open the dashboard at http://localhost:5173.

For a non-technical, Windows-specific walkthrough intended for an end client,
see `CLIENT_QUICKSTART.md`.

## Manual setup (without the launcher scripts)

```bash
# 1. MongoDB (optional - live dashboard works without it)
mongod --dbpath ./data/db

# 2. Backend
cd backend && npm install && npm start

# 3. Frontend
cd frontend && npm install && npm run dev

# 4. AI pipeline (use a project venv; Python 3.10-3.12 recommended)
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
python -m ai_pipeline.counter --source "video:datasets/DroneCrowd/sample.mp4"
# Optional AirSim extras: pip install -r requirements-airsim.txt
```

## Configuration

`ai_pipeline/config.py` reads these environment variables (all optional):

| Variable | Default | Purpose |
|---|---|---|
| `VIDEO_SOURCE` | `video:datasets/DroneCrowd/sample.mp4` | Frame source string: `video:<path>`, `webcam:<index>`, or `airsim` |
| `WS_SERVER` | `ws://localhost:8080/ai` | Backend WebSocket endpoint the AI pipeline sends to |
| `CONFIDENCE_THRESHOLD` | `0.35` | YOLOv8 detection confidence cutoff |
| `USE_DENSITY_MAP` | `false` | Enable the optional CSRNet density cross-check |
| `STREAM_VIDEO` | `true` | Whether to stream annotated frames to the dashboard |
| `AIRSIM_HOST` | `127.0.0.1` | Set to a remote machine's IP to connect to AirSim running elsewhere (used by macOS clients) |

`scripts/.env` (copy from `scripts/.env.example`) configures the AirSim binary
path/args/boot-wait and `AIRSIM_HOST`, read by the launcher scripts.

## AirSim environment auto-download

`scripts/setup_airsim.sh` / `scripts/setup_airsim.ps1` resolve the latest
matching release from `microsoft/AirSim`'s GitHub releases, download the
prebuilt "Blocks" environment (a few GB), extract it, and write
`AIRSIM_BINARY_PATH` into `scripts/.env`. The launcher scripts call this
automatically the first time `--airsim` / `-Airsim` is used if no binary path
is already configured.
