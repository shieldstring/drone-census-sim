"""
Make the vendored AirSim Python client importable without pip-installing
the broken PyPI "airsim" package.

Puts <repo>/third_party on sys.path so `import airsim` resolves to
third_party/airsim/.
"""

from __future__ import annotations

import sys
from pathlib import Path


def ensure_airsim_path() -> Path:
    root = Path(__file__).resolve().parents[1]
    third_party = root / "third_party"
    tp = str(third_party)
    if tp not in sys.path:
        sys.path.insert(0, tp)
    return third_party


def import_airsim():
    ensure_airsim_path()
    import airsim  # noqa: WPS433 - intentional late import after path fix

    return airsim
