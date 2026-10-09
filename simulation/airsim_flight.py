"""
Flight Simulation — AirSim + Unreal Engine

AirSim (Microsoft, open-source) runs inside Unreal Engine and exposes a Python
API to control drones autonomously. This module:

  - connects to a local or remote AirSim instance (AIRSIM_HOST)
  - takes off, flies a grid survey from flight_config.json
  - leaves the virtual onboard camera streaming for ai_pipeline/counter.py

No physical drone is required. Load Unreal environments (Blocks, cities,
neighborhoods) in AirSim; place pedestrian NPCs as the population to count.

Usage:
  python -m simulation.airsim_flight
  python -m simulation.airsim_flight --config simulation/flight_config.json
"""

from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path

import airsim


class DroneFlightController:
    def __init__(self, config_path="simulation/flight_config.json"):
        config_path = Path(config_path)
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

        host = os.environ.get("AIRSIM_HOST", "127.0.0.1")
        print(f"[airsim_flight] Connecting to AirSim at {host} ...")
        self.client = airsim.MultirotorClient(ip=host)
        self.client.confirmConnection()
        self.client.enableApiControl(True)
        self.client.armDisarm(True)
        self._configure_camera()
        print("[airsim_flight] Connected — API control enabled")

    def _configure_camera(self):
        """Point camera 0 downward for aerial census framing."""
        cam = self.config.get("camera", {})
        pitch_deg = float(cam.get("pitch_deg", -90))
        # AirSim uses NED; pitch negative looks down
        orientation = airsim.to_quaternion(pitch_deg * 3.14159 / 180.0, 0, 0)
        try:
            self.client.simSetCameraPose(
                "0",
                airsim.Pose(airsim.Vector3r(0.0, 0.0, 0.0), orientation),
            )
        except Exception as err:
            print(f"[airsim_flight] Camera pose note: {err}")

    def takeoff(self, altitude_m=None):
        print("[airsim_flight] Takeoff...")
        self.client.takeoffAsync().join()
        if altitude_m:
            # NED: negative Z is up
            self.client.moveToZAsync(-float(altitude_m), 3).join()
            print(f"[airsim_flight] Climb to {altitude_m} m AGL")

    def fly_grid(self, zone, altitude_m):
        name = zone.get("name", "zone")
        speed = float(self.config.get("speed_mps", 5))
        self.client.moveToZAsync(-float(altitude_m), 3).join()
        for i, (x, y) in enumerate(zone["waypoints"]):
            print(f"[airsim_flight] {name} waypoint {i + 1}/{len(zone['waypoints'])} -> ({x}, {y}) @ {altitude_m}m")
            self.client.moveToPositionAsync(float(x), float(y), -float(altitude_m), speed).join()
            # brief hover so the AI pipeline can sample the zone
            time.sleep(float(self.config.get("hover_s", 1.0)))

    def run_survey(self):
        altitudes = self.config.get("altitudes_m") or [50]
        zones = self.config.get("zones") or []
        self.takeoff(altitude_m=altitudes[0])

        for altitude_m in altitudes:
            for zone in zones:
                print(f"[airsim_flight] Surveying {zone['name']} at {altitude_m} m")
                self.fly_grid(zone, altitude_m)

        print("[airsim_flight] Survey complete — landing")
        self.client.landAsync().join()
        self.client.armDisarm(False)
        self.client.enableApiControl(False)
        print("[airsim_flight] Disarmed / API control released")


def main():
    parser = argparse.ArgumentParser(description="Autonomous AirSim census survey flight")
    parser.add_argument(
        "--config",
        default="simulation/flight_config.json",
        help="Path to flight_config.json",
    )
    args = parser.parse_args()

    controller = DroneFlightController(config_path=args.config)
    controller.run_survey()


if __name__ == "__main__":
    main()
