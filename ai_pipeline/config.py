import os

# Default to the bundled sample video; overridable via --source on the CLI
# or the VIDEO_SOURCE env var. "airsim" switches to the live simulation feed.
VIDEO_SOURCE = os.environ.get("VIDEO_SOURCE", "video:datasets/DroneCrowd/sample.mp4")

# Detection target:
#   both   = faces + full-body persons (default) — never cars / other objects
#   face   = faces only
#   person = full-body person class only
DETECT_MODE = os.environ.get("DETECT_MODE", "both").strip().lower()

YOLO_MODEL = os.environ.get("YOLO_MODEL", "yolov8n.pt")
# Optional dedicated face weights (Ultralytics). If unset, OpenCV YuNet/Haar is used for faces.
FACE_MODEL = os.environ.get("FACE_MODEL", "").strip()
DENSITY_MODEL = os.environ.get("DENSITY_MODEL", "csrnet_weights.pth")

WS_SERVER = os.environ.get("WS_SERVER", "ws://localhost:8080/ai")

CONFIDENCE_THRESHOLD = float(os.environ.get("CONFIDENCE_THRESHOLD", "0.45"))
ALTITUDE_SIMULATION = os.environ.get("ALTITUDE_SIMULATION", "50")

FRAMES_PER_ZONE = int(os.environ.get("FRAMES_PER_ZONE", "150"))
USE_DENSITY_MAP = os.environ.get("USE_DENSITY_MAP", "false").lower() == "true"

GRID_ZONES = ["Zone A", "Zone B", "Zone C", "Zone D"]

# Live annotated-frame streaming to the dashboard
STREAM_VIDEO = os.environ.get("STREAM_VIDEO", "true").lower() == "true"
STREAM_EVERY_N_FRAMES = int(os.environ.get("STREAM_EVERY_N_FRAMES", "2"))
STREAM_MAX_WIDTH = int(os.environ.get("STREAM_MAX_WIDTH", "640"))
STREAM_JPEG_QUALITY = int(os.environ.get("STREAM_JPEG_QUALITY", "60"))

# Ignore tiny false positives (pixels). Raise for high-altitude aerial footage.
MIN_FACE_SIZE = int(os.environ.get("MIN_FACE_SIZE", "20"))

# An ID must be seen this many frames before it counts toward unique_total.
# Stops webcam flicker (1 person) from creating dozens of fake unique IDs.
MIN_HITS_FOR_UNIQUE = int(os.environ.get("MIN_HITS_FOR_UNIQUE", "10"))

# Max centroid jump (pixels) to keep the same track ID between frames.
TRACK_MATCH_DIST_PERSON = float(os.environ.get("TRACK_MATCH_DIST_PERSON", "120"))
TRACK_MATCH_DIST_FACE = float(os.environ.get("TRACK_MATCH_DIST_FACE", "80"))
