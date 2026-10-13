"""
Frame-source abstraction. get_stream(source) returns an iterator-like
object yielding BGR numpy frames, regardless of whether the underlying
source is a pre-recorded video file, a webcam, or a live AirSim camera.

This lets ai_pipeline/counter.py stay identical no matter which layer
is supplying frames.
"""

import os
import time

import cv2


class VideoFileStream:
    def __init__(self, path):
        self.cap = cv2.VideoCapture(path)
        if not self.cap.isOpened():
            raise FileNotFoundError(f"Could not open video source: {path}")

    def read(self):
        ok, frame = self.cap.read()
        if not ok:
            # loop the file so a demo / client run doesn't just stop
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            ok, frame = self.cap.read()
        return ok, frame

    def release(self):
        self.cap.release()


class WebcamStream(VideoFileStream):
    def __init__(self, index=0):
        self.cap = cv2.VideoCapture(index)
        if not self.cap.isOpened():
            raise RuntimeError(f"Could not open webcam index {index}")


class AirSimStream:
    """
    Live frames from AirSim's virtual onboard camera (Unreal Engine).
    Pair with simulation.airsim_flight for autonomous survey while this
    stream feeds ai_pipeline.counter — no physical drone required.
    """

    def __init__(self, image_type=0, camera_name="0"):
        import airsim

        host = os.environ.get("AIRSIM_HOST", "127.0.0.1")
        print(f"[camera_stream] AirSim camera connect -> {host}")
        self.client = airsim.MultirotorClient(ip=host)
        self.client.confirmConnection()
        self.image_type = image_type
        self.camera_name = camera_name
        self._empty_streak = 0
        self._ok_frames = 0
        # Warm up: first few simGetImage calls can return empty while UE boots.
        for _ in range(10):
            ok, frame = self.read()
            if ok and frame is not None:
                h, w = frame.shape[:2]
                print(f"[camera_stream] AirSim frame OK ({w}x{h})")
                break
            time.sleep(0.3)
        else:
            print("[camera_stream] WARNING: no AirSim frames yet — is the sim running?")

    def read(self):
        import airsim
        import numpy as np

        try:
            responses = self.client.simGetImages(
                [
                    airsim.ImageRequest(
                        self.camera_name,
                        self.image_type,
                        pixels_as_float=False,
                        compress=True,
                    )
                ]
            )
        except Exception as err:
            print(f"[camera_stream] simGetImages failed: {err}")
            return False, None

        if not responses:
            self._empty_streak += 1
            return False, None

        resp = responses[0]
        raw = resp.image_data_uint8
        if raw is None or len(raw) == 0:
            # Fallback: uncompressed scene request
            try:
                responses = self.client.simGetImages(
                    [
                        airsim.ImageRequest(
                            self.camera_name,
                            self.image_type,
                            pixels_as_float=False,
                            compress=False,
                        )
                    ]
                )
                resp = responses[0] if responses else None
            except Exception:
                resp = None
            if resp is None or not resp.image_data_uint8:
                self._empty_streak += 1
                if self._empty_streak in (1, 30, 150):
                    print("[camera_stream] Empty AirSim image — waiting for camera...")
                return False, None
            # Uncompressed BGRA
            h, w = resp.height, resp.width
            if h <= 0 or w <= 0:
                return False, None
            arr = np.frombuffer(resp.image_data_uint8, dtype=np.uint8)
            # AirSim uncompressed Scene images are typically BGRA.
            try:
                frame = cv2.cvtColor(arr.reshape(h, w, 4), cv2.COLOR_BGRA2BGR)
            except ValueError:
                try:
                    frame = arr.reshape(h, w, 3).copy()
                except ValueError:
                    return False, None
        else:
            frame = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
            if frame is None:
                self._empty_streak += 1
                return False, None

        self._empty_streak = 0
        self._ok_frames += 1
        if self._ok_frames == 1:
            h, w = frame.shape[:2]
            print(f"[camera_stream] Streaming AirSim camera ({w}x{h})")
        return True, frame

    def release(self):
        pass


def get_stream(source: str):
    """
    source: "video:<path>" | "webcam:<index>" | "airsim"
    """
    if source.startswith("video:"):
        return VideoFileStream(source.split(":", 1)[1])
    if source.startswith("webcam:"):
        idx = int(source.split(":", 1)[1]) if ":" in source else 0
        return WebcamStream(idx)
    if source == "airsim":
        return AirSimStream()
    raise ValueError(f"Unknown stream source: {source}")
