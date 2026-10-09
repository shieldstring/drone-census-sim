# Flight Simulation (AirSim + Unreal Engine)

AirSim is a free, open-source Microsoft simulator that runs inside Unreal Engine
and exposes a Python API to control drones autonomously. This project uses it so
you can:

- take off and fly survey waypoints from Python (`airsim_flight.py`)
- capture frames from a virtual onboard camera (`camera_stream.AirSimStream`)
- run the same AI census pipeline as with video/webcam — **no real drone needed**

Unreal environments (Blocks, cities, neighborhoods, open areas) load in AirSim.
Pedestrian NPC characters in those maps are the “population” to be counted.

## How it fits the stack

```
Unreal + AirSim binary
        │
        ├─ simulation/airsim_flight.py   → takeoff, waypoints, land
        └─ simulation/camera_stream.py   → BGR frames from camera "0"
                    │
                    ▼
           ai_pipeline/counter.py        → detect / track / stream to dashboard
```

## Windows one-command launch

```powershell
.\scripts\start.ps1 -Airsim
```

That will:

1. Auto-download a prebuilt AirSim “Blocks” environment on first run (several GB)
2. Launch the Unreal/AirSim binary
3. Wait for boot (`AIRSIM_BOOT_WAIT` in `scripts/.env`)
4. Start backend + frontend
5. Start autonomous survey flight + AI pipeline (`--source airsim`)

## Manual steps

```powershell
# 1. Start AirSim / Unreal (or use setup_airsim.ps1)
# 2. Optional: copy simulation\settings.json to Documents\AirSim\settings.json

pip install -r requirements-airsim.txt

# Terminal A — fly the census grid
python -m simulation.airsim_flight

# Terminal B — count people from the virtual camera
python -m ai_pipeline.counter --source airsim
```

## Pedestrian NPCs (population)

The default **Blocks** environment is a simple test map. For denser “population”:

- Use a City / neighborhood Unreal map with pedestrian NPCs, or
- Place AirSim/Unreal pedestrian characters in your level, then point
  `AIRSIM_BINARY_PATH` at that packaged `.exe`

Waypoint layout and altitudes are edited in `flight_config.json`.

## Remote AirSim (e.g. Mac → Windows)

On the Windows box run AirSim. On the client set in `scripts/.env`:

```
AIRSIM_HOST=192.168.x.x
```

Then run the flight + counter scripts on the client; they connect over the network.
