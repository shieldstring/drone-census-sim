"""Face / person detection helpers. Default census mode detects both."""

from ai_pipeline import config


class FaceDetector:
    """Detect human faces only (YuNet → Haar)."""

    def __init__(self):
        from ai_pipeline.tracker import _build_face_backend

        self.backend, self.mode = _build_face_backend()

    def detect(self, frame):
        return self.backend(frame)


class PersonDetector:
    """Full-body person detector (YOLO class 0 only — never all objects)."""

    PERSON_CLASS_ID = 0

    def __init__(self, model_path=None):
        from ultralytics import YOLO

        self.model = YOLO(model_path or config.YOLO_MODEL)

    def detect(self, frame):
        results = self.model(
            frame,
            classes=[self.PERSON_CLASS_ID],
            conf=config.CONFIDENCE_THRESHOLD,
            verbose=False,
        )
        return results[0]
