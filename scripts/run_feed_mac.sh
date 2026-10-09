#!/usr/bin/env bash
# Detached start of backend + frontend + demo aerial feed (macOS/Linux).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/logs"
mkdir -p "$LOG"

pkill -f "$ROOT/backend/server.js" 2>/dev/null || true
pkill -f "ai_pipeline.demo_stream" 2>/dev/null || true
pkill -f "ai_pipeline.counter" 2>/dev/null || true
sleep 1

cd "$ROOT/backend"
nohup node server.js >> "$LOG/backend.log" 2>&1 &
echo $! > "$LOG/backend.pid"

cd "$ROOT/frontend"
nohup npm run dev -- --host --port 5173 >> "$LOG/frontend.log" 2>&1 &
echo $! > "$LOG/frontend.pid"

sleep 3
cd "$ROOT"
# Prefer full YOLO counter if deps exist; otherwise ffmpeg demo feeder
if python3 -c "import ultralytics, cv2, websockets" 2>/dev/null; then
  nohup python3 -u -m ai_pipeline.counter --source "video:datasets/DroneCrowd/sample.mp4" >> "$LOG/ai_pipeline.log" 2>&1 &
else
  nohup python3 -u -m ai_pipeline.demo_stream >> "$LOG/ai_pipeline.log" 2>&1 &
fi
echo $! > "$LOG/ai_pipeline.pid"

echo "Started. Dashboard: http://localhost:5173"
echo "PIDs: backend=$(cat "$LOG/backend.pid") frontend=$(cat "$LOG/frontend.pid") ai=$(cat "$LOG/ai_pipeline.pid")"
