"""
CSRNet-based crowd density estimator, used as an optional cross-check
against the tracker's unique-ID count in very dense zones where occlusion
may cause YOLO/ByteTrack to under-count.

Disabled by default (config.USE_DENSITY_MAP) since it adds a second,
heavier model to the pipeline.
"""

import torch
import torch.nn as nn
from torchvision import models


class CSRNet(nn.Module):
    def __init__(self):
        super().__init__()
        vgg = models.vgg16(weights=None)
        self.frontend = nn.Sequential(*list(vgg.features.children())[:23])

        self.backend = nn.Sequential(
            nn.Conv2d(512, 512, 3, padding=2, dilation=2), nn.ReLU(inplace=True),
            nn.Conv2d(512, 512, 3, padding=2, dilation=2), nn.ReLU(inplace=True),
            nn.Conv2d(512, 512, 3, padding=2, dilation=2), nn.ReLU(inplace=True),
            nn.Conv2d(512, 256, 3, padding=2, dilation=2), nn.ReLU(inplace=True),
            nn.Conv2d(256, 128, 3, padding=2, dilation=2), nn.ReLU(inplace=True),
            nn.Conv2d(128, 64, 3, padding=2, dilation=2), nn.ReLU(inplace=True),
        )
        self.output_layer = nn.Conv2d(64, 1, 1)

    def forward(self, x):
        x = self.frontend(x)
        x = self.backend(x)
        x = self.output_layer(x)
        return x


class DensityEstimator:
    def __init__(self, weights_path):
        self.model = CSRNet()
        try:
            state = torch.load(weights_path, map_location="cpu")
            self.model.load_state_dict(state)
        except FileNotFoundError:
            print(f"[density_map] No weights at {weights_path} - using random init (demo only)")
        self.model.eval()

    def estimate(self, frame_tensor):
        with torch.no_grad():
            density_map = self.model(frame_tensor)
        return float(density_map.sum().item())

    def estimate_bgr(self, frame_bgr):
        """Run density estimation on an OpenCV BGR frame; returns approximate head count."""
        import cv2
        import numpy as np

        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        h, w = rgb.shape[:2]
        # Keep inference bounded for live survey streaming
        max_side = 640
        if max(h, w) > max_side:
            scale = max_side / max(h, w)
            rgb = cv2.resize(rgb, (int(w * scale), int(h * scale)))
        tensor = torch.from_numpy(rgb.transpose(2, 0, 1)).float().unsqueeze(0) / 255.0
        return self.estimate(tensor)
