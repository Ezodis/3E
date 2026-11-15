"""Recognize monster portraits, not their HP pool. All references are local.

The atlas manifest records Riot's Monster_Epic tags and the source of each HUD
portrait. Unknown/occluded portraits return None; callers must not guess damage.
"""
from functools import lru_cache
from pathlib import Path
import json

import cv2
import numpy as np
from PIL import Image

_ROOT = Path(__file__).resolve().parent
_BOX = (214, 28, 308, 110)


@lru_cache(maxsize=1)
def _references():
    with Image.open(_ROOT / "lol_monsters.png") as image:
        atlas = image.convert("RGB")
    entries = json.loads((_ROOT / "lol_monsters.json").read_text())["entries"]
    references = []
    for entry in entries:
        portrait = atlas.crop(entry["box"])
        for size in (86, 90, 94):
            # Inner face only: ignore the circular frame and level badge.
            art = np.array(portrait.resize((size, size), Image.Resampling.LANCZOS))
            patch = art[int(size*.2):int(size*.7), int(size*.2):int(size*.8)].copy()
            references.append((entry["name"], entry["epic"], patch))
    return references


@lru_cache(maxsize=128)
def _classify(pixels):
    roi = np.frombuffer(pixels, np.uint8).reshape((82, 94, 3))
    scores = {}
    for name, epic, patch in _references():
        score = float(cv2.minMaxLoc(cv2.matchTemplate(roi, patch, cv2.TM_CCOEFF_NORMED))[1])
        key = (name, epic)
        scores[key] = max(scores.get(key, -1), score)
    best = max(scores, key=scores.get)
    opposite = max((s for k, s in scores.items() if k[1] != best[1]), default=-1)
    if scores[best] >= .84 and scores[best] - opposite >= .08:
        return best
    return None


def identify_monster(frame, scale):
    box = tuple(round(v * scale) for v in _BOX)
    roi = frame.crop(box).convert("RGB").resize((94, 82), Image.Resampling.LANCZOS)
    return _classify(roi.tobytes())
