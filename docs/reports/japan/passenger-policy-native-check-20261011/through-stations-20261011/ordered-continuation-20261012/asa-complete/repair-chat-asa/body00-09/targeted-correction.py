"""Recenter two visually identified Asa bands in saved candidate data only."""
import importlib.util
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("body_fit", HERE / "body-fit.py")
body = importlib.util.module_from_spec(spec)
spec.loader.exec_module(body)

# Actual pixels in original 1024x768 captures. They are the midpoint of the
# own paired/sleepered blue rail band, checked away from text where possible.
GUIDES = {
    0: (3, [(415, 291), (440, 331), (460, 352), (480, 366), (500, 376), (514, 382)]),
    2: (4, [(300, 335), (400, 348), (500, 365), (600, 380), (700, 395), (800, 403), (900, 412)]),
}


def on_source(q, points, chain):
    best = None
    for k, (a, b) in enumerate(zip(points, points[1:])):
        d = b - a
        t = float(np.clip(np.dot(q - a, d) / np.dot(d, d), 0, 1))
        r = a + t * d
        gap = np.linalg.norm(q - r)
        if best is None or gap < best[0]:
            best = (gap, chain[k] + t * (chain[k + 1] - chain[k]), r, d)
    return best


def run():
    data = json.loads((HERE / "body-candidates.json").read_text())
    for i, (view_index, pixels) in GUIDES.items():
        row = data["intervals"][i]
        path = body.views(i)[view_index]
        view = json.loads(path.read_text())
        source = np.array([body.world(p) for p in body.source(i)])
        chain = np.r_[0, np.cumsum(np.linalg.norm(np.diff(source, axis=0), axis=1))]
        guides = []
        for x, y in pixels:
            w = body.world(body.ll([x, y], view))
            _, s, r, d = on_source(w, source, chain)
            normal = np.array([-d[1], d[0]]) / np.linalg.norm(d)
            guides.append({
                "chain": float(s), "coordinate": body.geo(w), "rawPixel": [x, y],
                "offset": float(np.dot(w - r, normal)),
                "capture": str(path.parent.relative_to(body.B)),
                "camera": view["camera"], "mapRect": view["mapRect"],
                "status": "manual-identified-own-paired-rail-midpoint",
                "pixelUncertainty": 2,
            })
        guides.sort(key=lambda g: g["chain"])
        row["targetedOwnBandControls"] = guides
        chains = [g["chain"] for g in guides]
        offsets = [g["offset"] for g in guides]
        for n, control in enumerate(row["controls"]):
            s = control["chain"]
            if i == 0 and s < chains[0]:
                continue
            if i == 2 and not chains[0] <= s <= chains[-1]:
                continue
            idx = max(0, min(np.searchsorted(chain, s, side="right") - 1, len(source) - 2))
            t = (s - chain[idx]) / (chain[idx + 1] - chain[idx])
            r = source[idx] * (1 - t) + source[idx + 1] * t
            d = source[idx + 1] - source[idx]
            normal = np.array([-d[1], d[0]]) / np.linalg.norm(d)
            off = float(np.interp(s, chains, offsets))
            q = r + normal * off
            control["preTargetedCoordinate"] = row["coordinates"][n]
            control["world"] = q.tolist()
            control["offset"] = off
            control["status"] = "interpolated-between-manual-own-band-controls"
            control["capture"] = None
            control.pop("rawPixel", None)
            row["coordinates"][n] = body.geo(q)
    (HERE / "body-candidates.json").write_text(json.dumps(data, ensure_ascii=False, indent=2))
    body.render()


if __name__ == "__main__":
    run()
