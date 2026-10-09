"""
Person tracking for the census pipeline.

Uses Ultralytics YOLO + ByteTrack when available. Falls back to OpenCV HOG
person detection if ultralytics/torch are not installed (common on first
Windows setup or constrained machines).
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from ai_pipeline import config


@dataclass
class SimpleBoxes:
    """Minimal stand-in for Ultralytics Boxes so counter.py can share one path."""

    xyxy: np.ndarray
    id: np.ndarray | None = None

    def __len__(self):
        return 0 if self.xyxy is None else len(self.xyxy)


@dataclass
class SimpleResult:
    boxes: SimpleBoxes
    annotated: np.ndarray

    def plot(self):
        return self.annotated


def _try_yolo(model_path):
    try:
        from ultralytics import YOLO

        return YOLO(model_path)
    except Exception as err:
        print(f"[tracker] YOLO unavailable ({err}); using OpenCV HOG fallback")
        return None


class PersonTracker:
    """
    Primary: Ultralytics ByteTrack for persistent IDs.
    Fallback: OpenCV HOG + centroid matching for a demo feed without torch.
    """

    PERSON_CLASS_ID = 0

    def __init__(self, model_path=None):
        self._seen_ids = set()
        self._next_id = 1
        self._prev_centroids = {}  # id -> (x, y)
        self.model = _try_yolo(model_path or config.YOLO_MODEL)
        self.mode = "yolo" if self.model is not None else "hog"

        if self.mode == "hog":
            self.hog = cv2.HOGDescriptor()
            self.hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())
            print("[tracker] OpenCV HOG person detector ready (demo fallback)")

    def track(self, frame):
        if self.mode == "yolo":
            return self._track_yolo(frame)
        return self._track_hog(frame)

    def _track_yolo(self, frame):
        results = self.model.track(
            frame,
            classes=[self.PERSON_CLASS_ID],
            conf=config.CONFIDENCE_THRESHOLD,
            persist=True,
            tracker="bytetrack.yaml",
            verbose=False,
        )
        result = results[0]
        if result.boxes is not None and result.boxes.id is not None:
            for tid in result.boxes.id.tolist():
                self._seen_ids.add(int(tid))
        return result

    def _track_hog(self, frame):
        # HOG works better on upright people; rescale tall aerial frames a bit
        h, w = frame.shape[:2]
        scale = 1.0
        work = frame
        if max(h, w) > 960:
            scale = 960 / max(h, w)
            work = cv2.resize(frame, (int(w * scale), int(h * scale)))

        rects, weights = self.hog.detectMultiScale(
            work,
            winStride=(8, 8),
            padding=(8, 8),
            scale=1.05,
        )

        boxes = []
        for (x, y, bw, bh), weight in zip(rects, weights):
            if weight < 0.3:
                continue
            x1 = int(x / scale)
            y1 = int(y / scale)
            x2 = int((x + bw) / scale)
            y2 = int((y + bh) / scale)
            boxes.append([x1, y1, x2, y2])

        boxes = np.array(boxes, dtype=np.float32) if boxes else np.zeros((0, 4), dtype=np.float32)
        ids = self._match_ids(boxes)

        annotated = frame.copy()
        for i, (x1, y1, x2, y2) in enumerate(boxes.astype(int)):
            tid = int(ids[i]) if ids is not None else i + 1
            cv2.rectangle(annotated, (x1, y1), (x2, y2), (15, 118, 110), 2)
            cv2.putText(
                annotated,
                f"ID {tid}",
                (x1, max(16, y1 - 6)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (15, 118, 110),
                2,
                cv2.LINE_AA,
            )

        if ids is not None:
            for tid in ids.tolist():
                self._seen_ids.add(int(tid))

        return SimpleResult(
            boxes=SimpleBoxes(xyxy=boxes, id=ids),
            annotated=annotated,
        )

    def _match_ids(self, boxes: np.ndarray):
        if len(boxes) == 0:
            self._prev_centroids = {}
            return None

        centroids = []
        for x1, y1, x2, y2 in boxes:
            centroids.append(((x1 + x2) / 2.0, (y1 + y2) / 2.0))

        assigned = {}
        used_prev = set()
        for i, (cx, cy) in enumerate(centroids):
            best_id = None
            best_dist = 80.0  # pixels
            for pid, (px, py) in self._prev_centroids.items():
                if pid in used_prev:
                    continue
                dist = ((cx - px) ** 2 + (cy - py) ** 2) ** 0.5
                if dist < best_dist:
                    best_dist = dist
                    best_id = pid
            if best_id is not None:
                assigned[i] = best_id
                used_prev.add(best_id)
            else:
                assigned[i] = self._next_id
                self._next_id += 1

        self._prev_centroids = {
            assigned[i]: centroids[i] for i in range(len(centroids))
        }
        return np.array([assigned[i] for i in range(len(centroids))], dtype=np.int32)

    @property
    def total_unique(self):
        return len(self._seen_ids)

    def reset(self):
        self._seen_ids.clear()
        self._prev_centroids.clear()
        self._next_id = 1
