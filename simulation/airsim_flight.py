"""
DroneFlightController - drives a simulated multirotor in AirSim across a
grid-survey pattern defined in flight_config.json.

Supports connecting to a remote AirSim instance via the AIRSIM_HOST
environment variable (used on macOS clients, which have no native AirSim
binary, to connect to AirSim running on a separate Windows/Linux machine
on the same network).
"""

import json
import os
import time

import airsim


class DroneFlightController:
    def __init__(self, config_path="simulation/flight_config.json"):
        with open(config_path, "r") as f:
            self.config = json.load(f)

        # Allow overriding the AirSim host for remote connections (e.g. a
        # macOS client pointing at a Windows machine running AirSim).
        host = os.environ.get("AIRSIM_HOST", "127.0.0.1")

        self.client = airsim.MultirotorClient(ip=host)
        self.client.confirmConnection()
        self.client.enableApiControl(True)
        self.client.armDisarm(True)

    def takeoff(self):
        self.client.takeoffAsync().join()

    def fly_grid(self, zone, altitude_m):
        self.client.moveToZAsync(-altitude_m, 3).join()
        for (x, y) in zone["waypoints"]:
            self.client.moveToPositionAsync(x, y, -altitude_m, self.config["speed_mps"]).join()

    def run_survey(self):
        self.takeoff()
        for altitude_m in self.config["altitudes_m"]:
            for zone in self.config["zones"]:
                print(f"[airsim_flight] Surveying {zone['name']} at {altitude_m}m")
                self.fly_grid(zone, altitude_m)
                time.sleep(1)
        self.client.landAsync().join()
        self.client.armDisarm(False)
        self.client.enableApiControl(False)


if __name__ == "__main__":
    controller = DroneFlightController()
    controller.run_survey()
