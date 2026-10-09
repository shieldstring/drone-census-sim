#!/usr/bin/env bash
# setup_airsim.sh - downloads a prebuilt AirSim Unreal environment
# (default: "Blocks") from the microsoft/AirSim GitHub releases for Linux,
# extracts it, and writes AIRSIM_BINARY_PATH into scripts/.env.

set -euo pipefail

ENV_NAME="${1:-Blocks}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_DIR="$ROOT_DIR/airsim_env"
mkdir -p "$DOWNLOAD_DIR"

echo "[setup_airsim.sh] Looking up latest AirSim Linux release..."

RELEASES_JSON="$(curl -s "https://api.github.com/repos/microsoft/AirSim/releases")"

ASSET_URL="$(echo "$RELEASES_JSON" | python3 -c "
import json, sys
releases = json.load(sys.stdin)
env_name = '$ENV_NAME'
for release in releases:
    for asset in release.get('assets', []):
        name = asset['name']
        if name.startswith(env_name) and name.endswith('.zip') and 'windows' not in name.lower():
            print(asset['browser_download_url'])
            sys.exit(0)
")"

if [ -z "$ASSET_URL" ]; then
  echo "[setup_airsim.sh] Could not find a Linux build of '$ENV_NAME' in AirSim releases."
  echo "[setup_airsim.sh] Visit https://github.com/microsoft/AirSim/releases and download one manually,"
  echo "[setup_airsim.sh] then set AIRSIM_BINARY_PATH in scripts/.env to the extracted .sh path."
  exit 1
fi

ZIP_PATH="$DOWNLOAD_DIR/${ENV_NAME}.zip"
echo "[setup_airsim.sh] Downloading $ASSET_URL (this may take a few minutes)..."
curl -L -o "$ZIP_PATH" "$ASSET_URL"

echo "[setup_airsim.sh] Extracting..."
unzip -o -q "$ZIP_PATH" -d "$DOWNLOAD_DIR"

BINARY="$(find "$DOWNLOAD_DIR" -maxdepth 4 -iname "*.sh" -perm -u+x | head -n1)"
if [ -z "$BINARY" ]; then
  BINARY="$(find "$DOWNLOAD_DIR" -maxdepth 4 -iname "*.sh" | head -n1)"
fi

if [ -z "$BINARY" ]; then
  echo "[setup_airsim.sh] Extraction completed but no usable .sh launcher was found under $DOWNLOAD_DIR."
  exit 1
fi

chmod +x "$BINARY"
echo "[setup_airsim.sh] AirSim binary ready at $BINARY"

ENV_FILE="$ROOT_DIR/scripts/.env"
touch "$ENV_FILE"
grep -v "^AIRSIM_BINARY_PATH=" "$ENV_FILE" > "$ENV_FILE.tmp" || true
mv "$ENV_FILE.tmp" "$ENV_FILE"
echo "AIRSIM_BINARY_PATH=$BINARY" >> "$ENV_FILE"

echo "[setup_airsim.sh] Wrote AIRSIM_BINARY_PATH to scripts/.env"
