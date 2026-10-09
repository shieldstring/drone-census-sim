from ultralytics import YOLO

from ai_pipeline import config


class PersonDetector:
    """Thin wrapper around a YOLOv8 model restricted to the 'person' class."""

    PERSON_CLASS_ID = 0

    def __init__(self, model_path=None):
        self.model = YOLO(model_path or config.YOLO_MODEL)

    def detect(self, frame):
        results = self.model(
            frame,
            classes=[self.PERSON_CLASS_ID],
            conf=config.CONFIDENCE_THRESHOLD,
            verbose=False,
        )
        return results[0]
