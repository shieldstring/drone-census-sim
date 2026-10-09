# Drone Census - Quickstart (Windows)

This guide gets the full system running on a Windows machine with one command.
No physical drone is required.

## 1. Prerequisites (one-time install)

Install these using the default installer options:

1. **Node.js (LTS)** - https://nodejs.org
2. **Python 3.10, 3.11, or 3.12** - https://www.python.org/downloads/
   - Prefer 3.11 or 3.12 (avoid 3.13+ for easiest AI package installs)
   - On the install screen, check **Add python.exe to PATH**
3. **MongoDB Community Server** (optional but recommended) - https://www.mongodb.com/try/download/community
   - If you skip MongoDB, the live dashboard still works; only saved history is disabled.

After installing, **close and reopen** any open terminal windows so they pick up the new PATH.

## 2. Unzip the project

Right-click the zip you were sent and choose **Extract All...**.
Pick a simple destination like `C:\drone-census-sim` (avoid deeply nested folders or OneDrive-synced paths).

Confirm these exist after extract:

- `RUN.bat` (double-click launcher)
- `datasets\DroneCrowd\sample.mp4` (bundled demo video)
- `scripts\start.ps1`

## 3. Allow PowerShell scripts (one-time)

Windows blocks downloaded scripts by default. Open PowerShell **as Administrator**
(right-click Start -> Terminal (Admin) or Windows PowerShell (Admin)) and run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Type `Y` and press Enter if asked. You only need this once per machine.

## 4. Run it

**Easiest:** double-click `RUN.bat` in the project folder.

Or from PowerShell:

```powershell
cd C:\drone-census-sim
.\scripts\start.ps1
```

First launch downloads Python AI packages and Node modules (can take several minutes).
Later launches are much faster.

Other modes:

```powershell
.\scripts\start.ps1 -Webcam
.\scripts\start.ps1 -Airsim
```

`-Airsim` starts **Flight Simulation (AirSim + Unreal Engine)**:
downloads a prebuilt Unreal/AirSim environment on first run, flies an
autonomous survey (takeoff → waypoints → land), and streams the virtual
onboard camera into the same AI census pipeline. Pedestrian NPCs in the
Unreal map are the population being counted. See `simulation/README.md`.

First AirSim download is several GB and can take a while.

## 5. Open the dashboard

When the terminal shows `All components launched`, open:

```
http://localhost:5173
```

You should see the live annotated video feed, zone heatmap, and running count.

## 6. Stop everything

Focus the window running the launcher and press `Ctrl+C`.
That shuts down every component it started.

## Troubleshooting

**"running scripts is disabled on this system"** - redo step 3 in an Administrator PowerShell window.

**Cascading red parse errors in PowerShell** - the `.ps1` file was corrupted in transit. Re-extract a fresh copy of the zip (do not edit the script by hand in email/chat).

**Python not found** - reinstall Python 3.10+ and check **Add python.exe to PATH**, then reopen PowerShell.

**MongoDB / mongod not found** - normal if you did not install a local MongoDB. Live video still works. For saved history either install MongoDB Community, or set `MONGO_URI` in `backend\.env` to a MongoDB Atlas `mongodb+srv://...` URI (no local mongod needed).

**Aerial feed blinking** - fixed in the latest package: the UI now keeps the last frame between updates. Copy the updated `frontend` folder (or re-extract the zip), stop with Ctrl+C, then run `.\scripts\start.ps1` again and hard-refresh the browser (Ctrl+F5).

**Port already in use** - something else is using 8080, 5173, or 27017. Stop the previous run with Ctrl+C first.

**Nothing in the browser** - wait 10-20 seconds after launch for the first frontend build, then refresh.

**Blank video / "Waiting for live feed"** - check `logs\ai_pipeline.log`. The first AI run downloads the YOLOv8 model weights automatically.
