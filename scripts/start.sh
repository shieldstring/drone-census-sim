#!/usr/bin/env bash
# start.sh - one-command launcher for the drone census stack on Linux.
#
# Usage:
#   ./scripts/start.sh            # pre-recorded video source (default)
#   ./scripts/start.sh --webcam   # live webcam source
#   ./scripts/start.sh --airsim   # live AirSim simulation source

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"

MODE="video"
for arg in "$@"; do
  case "$arg" in
    --airsim) MODE="airsim" ;;
    --webcam) MODE="webcam" ;;
  esac
done

echo "[start.sh] Mode: $MODE"

ENV_FILE="$ROOT_DIR/scripts/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

AIRSIM_BOOT_WAIT="${AIRSIM_BOOT_WAIT:-30}"

PIDS=()
cleanup() {
  echo "[start.sh] Shutting down..."
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

wait_for_port() {
  local port=$1
  local timeout=${2:-60}
  local elapsed=0
  while ! (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "[start.sh] WARNING: port $port not up after ${timeout}s. Continuing anyway."
      return 1
    fi
  done
  exec 3>&- 2>/dev/null || true
  return 0
}

# ---- Step 1: MongoDB (optional) ----
mkdir -p "$ROOT_DIR/data/db"
if command -v mongod >/dev/null 2>&1; then
  echo "[start.sh] Starting MongoDB..."
  mongod --dbpath "$ROOT_DIR/data/db" > "$LOG_DIR/mongod.log" 2>&1 &
  PIDS+=($!)
  wait_for_port 27017 30 || true
else
  echo "[start.sh] WARNING: mongod not found. Skipping MongoDB (live dashboard still works)."
fi

if [ ! -f "$ROOT_DIR/datasets/DroneCrowd/sample.mp4" ] && [ "$MODE" = "video" ]; then
  echo "[start.sh] ERROR: Missing datasets/DroneCrowd/sample.mp4"
  exit 1
fi

if [ ! -f "$ROOT_DIR/scripts/.env" ] && [ -f "$ROOT_DIR/scripts/.env.example" ]; then
  cp "$ROOT_DIR/scripts/.env.example" "$ROOT_DIR/scripts/.env"
fi
if [ ! -f "$ROOT_DIR/backend/.env" ] && [ -f "$ROOT_DIR/backend/.env.example" ]; then
  cp "$ROOT_DIR/backend/.env.example" "$ROOT_DIR/backend/.env"
fi

# ---- Step 2: Backend ----
echo "[start.sh] Starting backend..."
(cd "$ROOT_DIR/backend" && npm install && npm start) > "$LOG_DIR/backend.log" 2>&1 &
PIDS+=($!)
wait_for_port 8080 60 || true

# ---- Step 3: AirSim (only in --airsim mode) ----
if [ "$MODE" = "airsim" ]; then
  if [ -z "${AIRSIM_BINARY_PATH:-}" ] || [ ! -f "$AIRSIM_BINARY_PATH" ]; then
    echo "[start.sh] No usable AIRSIM_BINARY_PATH found. Running setup_airsim.sh to download it now."
    bash "$ROOT_DIR/scripts/setup_airsim.sh"
    set -a
    source "$ENV_FILE"
    set +a
  fi

  if [ -z "${AIRSIM_BINARY_PATH:-}" ] || [ ! -f "$AIRSIM_BINARY_PATH" ]; then
    echo "[start.sh] AirSim setup did not produce a usable binary. Falling back to video mode."
    MODE="video"
  else
    echo "[start.sh] Launching AirSim from $AIRSIM_BINARY_PATH"
    "$AIRSIM_BINARY_PATH" ${AIRSIM_BINARY_ARGS:-} > "$LOG_DIR/airsim.log" 2>&1 &
    PIDS+=($!)
    echo "[start.sh] Waiting ${AIRSIM_BOOT_WAIT}s for AirSim to finish loading..."
    sleep "$AIRSIM_BOOT_WAIT"
  fi
fi

# ---- Step 4: Frontend ----
echo "[start.sh] Starting frontend..."
(cd "$ROOT_DIR/frontend" && npm install && npm run dev) > "$LOG_DIR/frontend.log" 2>&1 &
PIDS+=($!)
wait_for_port 5173 60 || true

# ---- Step 5: AI pipeline ----
case "$MODE" in
  airsim) SOURCE_ARG="airsim" ;;
  webcam) SOURCE_ARG="webcam:0" ;;
  *) SOURCE_ARG="video:datasets/DroneCrowd/sample.mp4" ;;
esac

echo "[start.sh] Starting AI pipeline (mode: $MODE)..."
VENV_DIR="$ROOT_DIR/.venv"
if [ ! -x "$VENV_DIR/bin/python" ]; then
  echo "[start.sh] Creating project virtual environment at .venv ..."
  python3 -m venv "$VENV_DIR"
fi
(
  cd "$ROOT_DIR"
  "$VENV_DIR/bin/python" -m pip install -r requirements.txt --quiet
  if [ "$MODE" = "airsim" ]; then
    "$VENV_DIR/bin/python" -m pip install -r requirements-airsim.txt --quiet
  fi
  if [ -n "${AIRSIM_HOST:-}" ]; then
    export AIRSIM_HOST
  fi
  "$VENV_DIR/bin/python" -m ai_pipeline.counter --source "$SOURCE_ARG"
) > "$LOG_DIR/ai_pipeline.log" 2>&1 &
PIDS+=($!)

if [ "$MODE" = "airsim" ]; then
  echo "[start.sh] Starting autonomous AirSim survey flight..."
  (
    cd "$ROOT_DIR"
    "$VENV_DIR/bin/python" -m pip install -r requirements-airsim.txt --quiet
    if [ -n "${AIRSIM_HOST:-}" ]; then
      export AIRSIM_HOST
    fi
    sleep 5
    "$VENV_DIR/bin/python" -m simulation.airsim_flight
  ) > "$LOG_DIR/airsim_flight.log" 2>&1 &
  PIDS+=($!)
fi

echo ""
echo "[start.sh] All components launched."
echo "[start.sh] Dashboard:  http://localhost:5173"
echo "[start.sh] Backend:    http://localhost:8080"
echo "[start.sh] Logs:       $LOG_DIR"
if [ "$MODE" = "airsim" ]; then
  echo "[start.sh] AirSim:     Unreal sim + autonomous survey + live camera census"
fi
echo "[start.sh] Press Ctrl+C to stop everything."
echo ""

wait
