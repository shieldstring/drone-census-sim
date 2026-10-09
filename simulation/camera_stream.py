"""
Frame-source abstraction. get_stream(source) returns an iterator-like
object yielding BGR numpy frames, regardless of whether the underlying
source is a pre-recorded video file, a webcam, or a live AirSim camera.

This lets ai_pipeline/counter.py stay identical no matter which layer
is supplying frames.
"""

import os

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
    def __init__(self, image_type=0):
        import airsim

        host = os.environ.get("AIRSIM_HOST", "127.0.0.1")
        self.client = airsim.MultirotorClient(ip=host)
        self.client.confirmConnection()
        self.image_type = image_type

    def read(self):
        import numpy as np

        resp = self.client.simGetImage("0", self.image_type)
        if resp is None:
            return False, None
        arr = cv2.imdecode(np.frombuffer(resp, np.uint8), cv2.IMREAD_COLOR)
        return True, arr

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
