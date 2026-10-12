"""
Census tracker — faces, persons, or both.

Default DETECT_MODE=both:
  - draws face boxes and full-body person boxes
  - never detects cars / bags / other COCO classes
  - unique people IDs: a face inside a person box shares that person's ID
    (no double-count); orphan faces still get an ID

Modes: both | face | person
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from urllib.request import urlretrieve

import cv2
import numpy as np

from ai_pipeline import config

YUNET_URL = (
    "https://github.com/opencv/opencv_zoo/raw/main/models/"
    "face_detection_yunet/face_detection_yunet_2023mar.onnx"
)
YUNET_NAME = "face_detection_yunet_2023mar.onnx"

COLOR_FACE = (15, 118, 110)      # teal
COLOR_PERSON = (194, 65, 12)     # orange (BGR-ish via OpenCV: need BGR)
COLOR_FACE_BGR = (110, 118, 15)
COLOR_PERSON_BGR = (12, 65, 194)


@dataclass
class SimpleBoxes:
    xyxy: np.ndarray
    id: np.ndarray | None = None
    conf: np.ndarray | None = None

    def __len__(self):
        return 0 if self.xyxy is None else len(self.xyxy)


@dataclass
class SimpleResult:
    boxes: SimpleBoxes
    annotated: np.ndarray
    faces_in_frame: int = 0
    persons_in_frame: int = 0
    extras: dict = field(default_factory=dict)

    def plot(self):
        return self.annotated


def _models_dir() -> Path:
    d = Path(__file__).resolve().parent / "models"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _ensure_yunet() -> Path | None:
    path = _models_dir() / YUNET_NAME
    if path.exists() and path.stat().st_size > 1000:
        return path
    try:
        print(f"[tracker] Downloading YuNet face model -> {path.name}")
        urlretrieve(YUNET_URL, path)
        return path
    except Exception as err:
        print(f"[tracker] YuNet download failed ({err}); will use Haar cascades")
        return None


def _build_face_backend():
    yunet_path = _ensure_yunet()
    if yunet_path is not None and hasattr(cv2, "FaceDetectorYN_create"):
        try:
            detector = cv2.FaceDetectorYN_create(
                str(yunet_path),
                "",
                (320, 320),
                float(config.CONFIDENCE_THRESHOLD),
                0.3,
                5000,
            )

            def detect_yunet(frame):
                h, w = frame.shape[:2]
                detector.setInputSize((w, h))
                _, faces = detector.detect(frame)
                boxes, scores = [], []
                if faces is None:
                    return np.zeros((0, 4), np.float32), np.zeros((0,), np.float32)
                for face in faces:
                    x, y, bw, bh = face[:4]
                    score = float(face[-1])
                    if bw < config.MIN_FACE_SIZE or bh < config.MIN_FACE_SIZE:
                        continue
                    if score < config.CONFIDENCE_THRESHOLD:
                        continue
                    boxes.append([x, y, x + bw, y + bh])
                    scores.append(score)
                if not boxes:
                    return np.zeros((0, 4), np.float32), np.zeros((0,), np.float32)
                return np.array(boxes, np.float32), np.array(scores, np.float32)

            print("[tracker] Face detector: OpenCV YuNet")
            return detect_yunet, "yunet"
        except Exception as err:
            print(f"[tracker] YuNet init failed ({err})")

    cascade_path = Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml"
    cascade = cv2.CascadeClassifier(str(cascade_path))

    def detect_haar(frame):
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.equalizeHist(gray)
        rects = cascade.detectMultiScale(
            gray,
            scaleFactor=1.1,
            minNeighbors=5,
            minSize=(config.MIN_FACE_SIZE, config.MIN_FACE_SIZE),
            flags=cv2.CASCADE_SCALE_IMAGE,
        )
        boxes, scores = [], []
        for x, y, bw, bh in rects:
            boxes.append([float(x), float(y), float(x + bw), float(y + bh)])
            scores.append(1.0)
        if not boxes:
            return np.zeros((0, 4), np.float32), np.zeros((0,), np.float32)
        return np.array(boxes, np.float32), np.array(scores, np.float32)

    print("[tracker] Face detector: OpenCV Haar")
    return detect_haar, "haar"


def _try_yolo(model_path):
    try:
        from ultralytics import YOLO

        return YOLO(model_path)
    except Exception as err:
        print(f"[tracker] YOLO unavailable ({err})")
        return None


def _face_in_person(face_box, person_box, min_overlap=0.4):
    """True if face center is inside person box, or IoU-ish containment is high."""
    fx1, fy1, fx2, fy2 = face_box
    px1, py1, px2, py2 = person_box
    cx, cy = (fx1 + fx2) / 2.0, (fy1 + fy2) / 2.0
    if px1 <= cx <= px2 and py1 <= cy <= py2:
        return True
    # intersection over face area
    ix1, iy1 = max(fx1, px1), max(fy1, py1)
    ix2, iy2 = min(fx2, px2), min(fy2, py2)
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
    face_area = max(1.0, (fx2 - fx1) * (fy2 - fy1))
    return (iw * ih) / face_area >= min_overlap


def _draw_box(img, box, label, color):
    x1, y1, x2, y2 = [int(v) for v in box]
    cv2.rectangle(img, (x1, y1), (x2, y2), color, 2)
    cv2.putText(
        img,
        label,
        (x1, max(16, y1 - 6)),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        color,
        2,
        cv2.LINE_AA,
    )


class PersonTracker:
    PERSON_CLASS_ID = 0

    def __init__(self, model_path=None):
        self._seen_ids = set()
        self._next_id = 1
        self._prev_person_centroids = {}
        self._prev_orphan_face_centroids = {}

        raw = config.DETECT_MODE if config.DETECT_MODE in ("face", "person", "both") else "both"
        self.detect_mode = raw
        self.model = None
        self._face_detect = None
        self._face_backend_name = None
        self.mode = raw

        want_faces = raw in ("face", "both")
        want_persons = raw in ("person", "both")

        if want_faces:
            if config.FACE_MODEL:
                face_model = _try_yolo(config.FACE_MODEL)
                if face_model is not None:
                    self._face_yolo = face_model
                    self._face_backend_name = "face_yolo"
                else:
                    self._face_yolo = None
                    self._face_detect, self._face_backend_name = _build_face_backend()
            else:
                self._face_yolo = None
                self._face_detect, self._face_backend_name = _build_face_backend()
        else:
            self._face_yolo = None

        if want_persons:
            self.model = _try_yolo(model_path or config.YOLO_MODEL)
            if self.model is None and raw == "person":
                print("[tracker] YOLO missing; falling back to faces only")
                self.detect_mode = "face"
                if self._face_detect is None and self._face_yolo is None:
                    self._face_detect, self._face_backend_name = _build_face_backend()

        parts = []
        if self.detect_mode in ("face", "both"):
            parts.append(f"faces({self._face_backend_name})")
        if self.detect_mode in ("person", "both") and self.model is not None:
            parts.append("persons(yolo class0)")
        self.mode = "+".join(parts) if parts else "none"
        print(f"[tracker] DETECT_MODE={self.detect_mode} -> {self.mode}")

    def track(self, frame):
        face_boxes = np.zeros((0, 4), np.float32)
        face_scores = np.zeros((0,), np.float32)
        person_boxes = np.zeros((0, 4), np.float32)
        person_scores = np.zeros((0,), np.float32)

        if self.detect_mode in ("face", "both"):
            face_boxes, face_scores = self._detect_faces(frame)

        if self.detect_mode in ("person", "both") and self.model is not None:
            person_boxes, person_scores = self._detect_persons(frame)

        # Assign IDs: persons first, then orphan faces
        person_ids = self._match_ids(person_boxes, self._prev_person_centroids, thresh=90.0)
        if person_ids is not None:
            for tid in person_ids.tolist():
                self._seen_ids.add(int(tid))

        orphan_faces = []
        orphan_scores = []
        face_labels = []  # (box, score, id_or_None, linked_person_id_or_None)

        for i, fbox in enumerate(face_boxes):
            score = float(face_scores[i]) if i < len(face_scores) else 1.0
            linked = None
            if person_ids is not None and len(person_boxes):
                for j, pbox in enumerate(person_boxes):
                    if _face_in_person(fbox, pbox):
                        linked = int(person_ids[j])
                        break
            if linked is not None:
                face_labels.append((fbox, score, linked, True))
            else:
                orphan_faces.append(fbox)
                orphan_scores.append(score)

        orphan_arr = (
            np.array(orphan_faces, np.float32)
            if orphan_faces
            else np.zeros((0, 4), np.float32)
        )
        orphan_ids = self._match_ids(orphan_arr, self._prev_orphan_face_centroids, thresh=55.0)
        if orphan_ids is not None:
            for tid in orphan_ids.tolist():
                self._seen_ids.add(int(tid))
            for i, fbox in enumerate(orphan_arr):
                face_labels.append((fbox, orphan_scores[i], int(orphan_ids[i]), False))

        annotated = frame.copy()
        if person_ids is not None:
            for i, pbox in enumerate(person_boxes):
                conf = f" {person_scores[i]:.2f}" if i < len(person_scores) else ""
                _draw_box(annotated, pbox, f"person #{int(person_ids[i])}{conf}", COLOR_PERSON_BGR)
        for fbox, score, tid, linked in face_labels:
            tag = "face" if not linked else "face"
            _draw_box(annotated, fbox, f"{tag} #{tid} {score:.2f}", COLOR_FACE_BGR)

        # People in this frame = persons + orphan faces (linked faces already counted as persons)
        people_boxes = []
        people_ids = []
        if person_ids is not None:
            for i, pbox in enumerate(person_boxes):
                people_boxes.append(pbox)
                people_ids.append(int(person_ids[i]))
        if orphan_ids is not None:
            for i, fbox in enumerate(orphan_arr):
                people_boxes.append(fbox)
                people_ids.append(int(orphan_ids[i]))

        if people_boxes:
            xyxy = np.array(people_boxes, np.float32)
            ids = np.array(people_ids, np.int32)
        else:
            xyxy = np.zeros((0, 4), np.float32)
            ids = None

        return SimpleResult(
            boxes=SimpleBoxes(xyxy=xyxy, id=ids),
            annotated=annotated,
            faces_in_frame=len(face_boxes),
            persons_in_frame=len(person_boxes),
        )

    def _detect_faces(self, frame):
        if self._face_yolo is not None:
            results = self._face_yolo.predict(
                frame, conf=config.CONFIDENCE_THRESHOLD, verbose=False
            )
            r0 = results[0]
            if r0.boxes is None or len(r0.boxes) == 0:
                return np.zeros((0, 4), np.float32), np.zeros((0,), np.float32)
            xyxy = r0.boxes.xyxy.cpu().numpy()
            confs = r0.boxes.conf.cpu().numpy()
            keep = [
                i
                for i, (x1, y1, x2, y2) in enumerate(xyxy)
                if (x2 - x1) >= config.MIN_FACE_SIZE and (y2 - y1) >= config.MIN_FACE_SIZE
            ]
            if not keep:
                return np.zeros((0, 4), np.float32), np.zeros((0,), np.float32)
            return xyxy[keep], confs[keep]
        return self._face_detect(frame)

    def _detect_persons(self, frame):
        results = self.model.predict(
            frame,
            classes=[self.PERSON_CLASS_ID],
            conf=config.CONFIDENCE_THRESHOLD,
            verbose=False,
        )
        r0 = results[0]
        if r0.boxes is None or len(r0.boxes) == 0:
            return np.zeros((0, 4), np.float32), np.zeros((0,), np.float32)
        return r0.boxes.xyxy.cpu().numpy(), r0.boxes.conf.cpu().numpy()

    def _match_ids(self, boxes: np.ndarray, store: dict, thresh: float = 80.0):
        if len(boxes) == 0:
            store.clear()
            return None

        centroids = [((x1 + x2) / 2.0, (y1 + y2) / 2.0) for x1, y1, x2, y2 in boxes]
        assigned = {}
        used_prev = set()
        for i, (cx, cy) in enumerate(centroids):
            best_id = None
            best_dist = thresh
            for pid, (px, py) in store.items():
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

        store.clear()
        store.update({assigned[i]: centroids[i] for i in range(len(centroids))})
        return np.array([assigned[i] for i in range(len(centroids))], dtype=np.int32)

    @property
    def total_unique(self):
        return len(self._seen_ids)

    def reset(self):
        self._seen_ids.clear()
        self._prev_person_centroids.clear()
        self._prev_orphan_face_centroids.clear()
        self._next_id = 1


FaceTracker = PersonTracker
