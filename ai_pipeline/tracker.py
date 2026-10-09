from ultralytics import YOLO

from ai_pipeline import config


class PersonTracker:
    """
    Wraps Ultralytics' built-in ByteTrack (model.track) to assign persistent
    IDs to detected people across frames, preventing double-counting as the
    drone moves over the same zone.
    """

    PERSON_CLASS_ID = 0

    def __init__(self, model_path=None):
        self.model = YOLO(model_path or config.YOLO_MODEL)
        self._seen_ids = set()

    def track(self, frame):
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

    @property
    def total_unique(self):
        return len(self._seen_ids)

    def reset(self):
        self._seen_ids.clear()
