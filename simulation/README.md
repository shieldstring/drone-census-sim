# Flight Simulation (AirSim + Unreal Engine)

AirSim is a free, open-source Microsoft simulator that runs inside Unreal Engine
and exposes a Python API to control drones autonomously. This project uses it so
you can:

- take off and fly survey waypoints from Python (`airsim_flight.py`)
- capture frames from a virtual onboard camera (`camera_stream.AirSimStream`)
- run the same AI census pipeline as with video/webcam — **no real drone needed**

## Important: which Unreal map to use

| Environment | People / crowds? | Size | Notes |
|-------------|------------------|------|--------|
| **CityEnviron** | Yes — vehicles + **pedestrians** | ~2.8 GB (split zip) | **Default** |
| **AirSimNH** | Urban neighborhood (streets/buildings) | ~1.6 GB | Smaller alternative |
| **Blocks** | **No** — empty colored cubes | ~170 MB | Tech demo only — **not** for counting |

`-Airsim` / `setup_airsim.ps1` default to **CityEnviron**. Install [7-Zip](https://www.7-zip.org/) first (split archive).

```powershell
.\scripts\setup_airsim.ps1                  # CityEnviron (default)
.\scripts\setup_airsim.ps1 -EnvName AirSimNH  # smaller urban map
.\scripts\start.ps1 -Airsim
```

In `scripts\.env`:

```
AIRSIM_ENV_NAME=CityEnviron
AIRSIM_BINARY_PATH=C:\...\CityEnviron.exe
AIRSIM_BOOT_WAIT=60
```

Manual downloads: https://github.com/microsoft/AirSim/releases  
(CityEnviron.zip.001 + .002 — extract the `.001` file with 7-Zip.)

## How it fits the stack

```
Unreal + AirSim binary (CityEnviron / AirSimNH)
        │
        ├─ simulation/airsim_flight.py   → takeoff, waypoints, land
        └─ simulation/camera_stream.py   → BGR frames from camera "0"
                    │
                    ▼
           ai_pipeline/counter.py        → detect faces/persons → dashboard
```

## Windows one-command launch

```powershell
.\scripts\start.ps1 -Airsim
```

That will:

1. Auto-download **CityEnviron** (city + pedestrians) on first run if no binary
   is configured (needs 7-Zip; or set `AIRSIM_ENV_NAME=AirSimNH` for a smaller map)
2. Launch the Unreal/AirSim binary
3. Wait for boot (`AIRSIM_BOOT_WAIT`)
4. Start backend + frontend
5. Start autonomous survey flight + AI pipeline (`--source airsim`)

## Manual steps

```powershell
pip install -r requirements-airsim.txt

# Terminal A — fly the census grid
python -m simulation.airsim_flight

# Terminal B — count people from the virtual camera
python -m ai_pipeline.counter --source airsim
```

The launcher always copies `simulation\settings.json` to
`%USERPROFILE%\Documents\AirSim\settings.json` (oblique camera ~55°, 1280×720).

## Detection tips (if counts stay at 0)

Default survey flies at **18–25 m** with an **oblique** camera so YOLO can see people.
Straight-down 50 m+ views look like dots and rarely detect.

1. Confirm `logs\ai_pipeline.log` shows `persons(yolo class0)` — if YOLO failed to load, run:
   `.\.venv\Scripts\pip install ultralytics`
2. Watch the dashboard video: you should see streets/pedestrians, not empty sky/roof.
3. Re-run: `.\scripts\start.ps1 -Airsim` (refreshes AirSim settings + loops the survey).

## Pedestrian density

CityEnviron ships with pedestrians. For denser custom crowds you need Unreal Editor
+ the AirSim plugin and your own NPC-populated level, then set `AIRSIM_BINARY_PATH`
to that packaged `.exe`.

Waypoint layout and altitudes: `flight_config.json` (`loop: true` keeps patrolling).

## Remote AirSim (e.g. Mac → Windows)

On the Windows box run AirSim. On the client set in `scripts/.env`:

```
AIRSIM_HOST=192.168.x.x
```
