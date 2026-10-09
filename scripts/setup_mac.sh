#!/usr/bin/env bash
# setup_mac.sh - prerequisite installer for macOS.
#
# AirSim has no native macOS binary, so this script installs everything
# except AirSim itself, and (optionally) configures this machine to connect
# to AirSim running on a separate Windows or Linux machine on the network.
#
# Usage:
#   ./scripts/setup_mac.sh
#   ./scripts/setup_mac.sh --remote-host 192.168.1.50

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_HOST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --remote-host)
      REMOTE_HOST="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if ! command -v brew >/dev/null 2>&1; then
  echo "[setup_mac.sh] Homebrew not found. Install it from https://brew.sh first."
  exit 1
fi

echo "[setup_mac.sh] Installing node, python3, mongodb-community..."
brew install node python3
brew tap mongodb/brew
brew install mongodb-community

echo "[setup_mac.sh] Installing Python dependencies..."
pip3 install -r "$ROOT_DIR/requirements.txt"

echo ""
echo "[setup_mac.sh] NOTE: AirSim does not ship a macOS build."
echo "[setup_mac.sh] To use the live simulation source on this Mac, run AirSim on a"
echo "[setup_mac.sh] separate Windows or Linux machine on the same network, then point"
echo "[setup_mac.sh] this machine at it with --remote-host <that machine's IP>."
echo "[setup_mac.sh] Without that, use the default pre-recorded video source instead."

if [ -n "$REMOTE_HOST" ]; then
  ENV_FILE="$ROOT_DIR/scripts/.env"
  touch "$ENV_FILE"
  grep -v "^AIRSIM_HOST=" "$ENV_FILE" > "$ENV_FILE.tmp" || true
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  echo "AIRSIM_HOST=$REMOTE_HOST" >> "$ENV_FILE"
  echo ""
  echo "[setup_mac.sh] Wrote AIRSIM_HOST=$REMOTE_HOST to scripts/.env"
  echo "[setup_mac.sh] Make sure AirSim on $REMOTE_HOST is running and reachable on this network,"
  echo "[setup_mac.sh] and that its settings.json allows connections from other machines."
fi

echo ""
echo "[setup_mac.sh] Done. Run ./scripts/start.sh to launch the stack."
