#!/usr/bin/env python3
"""Offline heuristic classifier for dark-mode Apple Maps transit captures.

This module deliberately does not claim semantic image understanding.  It looks
for the visual shape Apple Maps commonly uses for transit: a long, narrow,
bright, saturated stroke.  Optional accessibility/OCR evidence can strengthen a
station match or identify a bus route that has the same visual treatment.
"""

from __future__ import annotations

import argparse
from collections import deque
import colorsys
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import re
import shutil
from typing import Any, Iterable, Optional, Union

import numpy as np

try:
    from PIL import Image, UnidentifiedImageError
except ImportError:  # Give callers a useful error instead of hiding the dependency.
    Image = None  # type: ignore[assignment]
    UnidentifiedImageError = OSError  # type: ignore[assignment,misc]


IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff"}
_BUS_WORDS = re.compile(
    r"\b(?:bus|bus stop|brt|rapidbus|metrobus|express bus|bus route)\b",
    re.IGNORECASE,
)
_RAIL_WORDS = re.compile(
    r"\b(?:railway station|train station|subway station|metro station|"
    r"light rail|streetcar|tram|commuter rail|rail station|lrt|subway|metro)\b",
    re.IGNORECASE,
)
_NUMBERED_ROUTE = re.compile(r"^\s*\d{2,4}\s+\S+")


def _clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def _flatten_strings(value: Any) -> list[str]:
    strings: list[str] = []
    if isinstance(value, str):
        if value.strip():
            strings.append(value.strip())
    elif isinstance(value, dict):
        for child in value.values():
            strings.extend(_flatten_strings(child))
    elif isinstance(value, (list, tuple, set)):
        for child in value:
            strings.extend(_flatten_strings(child))
    return strings


def _strings_for_keys(value: Any, wanted: set[str]) -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = str(key).lower().replace("-", "_")
            if normalized in wanted:
                found.extend(_flatten_strings(child))
            found.extend(_strings_for_keys(child, wanted))
    elif isinstance(value, (list, tuple)):
        for child in value:
            found.extend(_strings_for_keys(child, wanted))
    return found


def _normalized_text(text: str) -> str:
    return " ".join(re.sub(r"[^\w]+", " ", text.lower()).split())


def _matched_observed_names(names: Iterable[str], observed: Iterable[str]) -> list[str]:
    """Match a complete label or an AX ``name, description`` prefix.

    Deliberately avoid unconstrained substrings: a station called ``York`` must
    not match a nearby ``Yorkville`` business or neighborhood.
    """
    observed_values = list(observed)
    matches: list[str] = []
    for name in names:
        target = _normalized_text(name)
        if len(target) < 3:
            continue
        raw_target = name.strip().casefold()
        for text in observed_values:
            raw_text = text.strip().casefold()
            if _normalized_text(text) == target or raw_text.startswith(raw_target + ","):
                matches.append(name)
                break
    return matches


def _evidence_adjustment(evidence: Any) -> tuple[float, list[str], bool]:
    """Return (score adjustment, reasons, conflicting bus/rail evidence)."""
    if not evidence:
        return 0.0, [], False

    all_strings = _flatten_strings(evidence)
    visible_strings = _strings_for_keys(
        evidence,
        {
            "visible_text",
            "ocr",
            "ocr_text",
            "ax_descriptions",
            "ax_elements",
            "elements",
            "descriptions",
            "accessibility",
        },
    )
    if not visible_strings:
        # A simple list/string is presumed to be observed evidence.  A structured
        # dict containing only catalog metadata is not.
        if not isinstance(evidence, dict):
            visible_strings = all_strings

    visible_blob = " \n ".join(visible_strings)
    adjustment = 0.0
    reasons: list[str] = []
    saw_bus = bool(_BUS_WORDS.search(visible_blob))
    saw_rail = bool(_RAIL_WORDS.search(visible_blob))

    route_names = _strings_for_keys(
        evidence, {"route", "route_name", "route_names", "transit_routes"}
    )
    explicit_bus_route = any(
        _NUMBERED_ROUTE.search(route) and "line" not in route.lower()
        for route in route_names
    )
    if explicit_bus_route:
        saw_bus = True

    excluded_names = _strings_for_keys(
        evidence,
        {"excluded_route_names", "bus_route_names", "excluded_routes"},
    )
    matched_excluded = _matched_observed_names(excluded_names, visible_strings)
    if matched_excluded:
        saw_bus = True
        adjustment -= 0.52
        reasons.append(f"visible text matches excluded route {matched_excluded[0]!r}")
    elif explicit_bus_route:
        adjustment -= 0.43
        reasons.append("structured evidence identifies a numbered bus route")
    elif saw_bus:
        # A dense view may contain bus stops and rail at the same time.  Treat a
        # generic mention as a review flag, not as proof that the colored stroke
        # itself is a bus route.
        adjustment -= 0.01
        reasons.append("accessibility/OCR evidence mentions bus service but not a matched route")

    station_names = _strings_for_keys(
        evidence,
        {"rail_station_names", "station_names", "known_rail_stations"},
    )
    matched_stations = _matched_observed_names(station_names, visible_strings)
    if matched_stations:
        saw_rail = True
        adjustment += 0.24
        reasons.append(f"visible text matches rail station {matched_stations[0]!r}")
    elif saw_rail:
        adjustment += 0.16
        reasons.append("accessibility/OCR evidence describes rail transit")

    return adjustment, reasons, saw_bus and saw_rail


def _load_rgb(path: Path) -> tuple[np.ndarray, tuple[int, int]]:
    if Image is None:
        raise RuntimeError("Pillow is required; install the project's requirements")
    try:
        with Image.open(path) as source:
            source.load()
            original_size = source.size
            image = source.convert("RGB")
            # Apple Maps can render transit routes only one or two physical
            # pixels wide.  Resampling a full-screen capture blended those
            # strokes into the dark basemap and split them into short fragments.
            # Analyze the captured pixels directly so their connectivity and
            # saturation survive.
            return np.asarray(image, dtype=np.uint8), original_size
    except (OSError, UnidentifiedImageError, ValueError) as error:
        raise ValueError(f"cannot decode image {path}: {error}") from error


def _saturated_bright_mask(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    unit = rgb.astype(np.float32) / 255.0
    maximum = unit.max(axis=2)
    minimum = unit.min(axis=2)
    saturation = (maximum - minimum) / np.maximum(maximum, 1e-6)

    # Dark-mode map polygons can be saturated but are generally dim.  Transit
    # strokes retain both high saturation and value.
    mask = (saturation >= 0.42) & (maximum >= 0.53)
    return mask, saturation, maximum


def _component_stats(
    mask: np.ndarray,
    rgb: np.ndarray,
    saturation: np.ndarray,
    value: np.ndarray,
) -> list[dict[str, Any]]:
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    minimum_area = max(7, round(height * width * 0.000008))
    components: list[dict[str, Any]] = []

    for start_y, start_x in zip(*np.nonzero(mask & ~visited)):
        if visited[start_y, start_x]:
            continue
        queue: deque[tuple[int, int]] = deque([(int(start_y), int(start_x))])
        visited[start_y, start_x] = True
        xs: list[int] = []
        ys: list[int] = []
        while queue:
            y, x = queue.popleft()
            xs.append(x)
            ys.append(y)
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    if mask[next_y, next_x] and not visited[next_y, next_x]:
                        visited[next_y, next_x] = True
                        queue.append((next_y, next_x))

        area = len(xs)
        if area < minimum_area:
            continue
        x0, x1 = min(xs), max(xs)
        y0, y1 = min(ys), max(ys)
        box_width, box_height = x1 - x0 + 1, y1 - y0 + 1
        major_span, minor_span = max(box_width, box_height), min(box_width, box_height)
        span_ratio = max(box_width / width, box_height / height)
        thickness = area / max(major_span, 1)
        fill_ratio = area / (box_width * box_height)

        coordinates = np.column_stack((xs, ys)).astype(np.float32)
        if area >= 3:
            covariance = np.cov(coordinates, rowvar=False)
            eigenvalues = np.linalg.eigvalsh(covariance)
            elongation = math.sqrt(
                float(eigenvalues[-1] + 0.5) / float(eigenvalues[0] + 0.5)
            )
        else:
            elongation = 1.0

        edge_touches = sum((x0 == 0, x1 == width - 1, y0 == 0, y1 == height - 1))
        indices = (np.asarray(ys), np.asarray(xs))
        mean_rgb = np.rint(rgb[indices].mean(axis=0)).astype(int).tolist()

        # Shape score.  Long span and PCA elongation are positive; thick filled
        # shapes are parks, water, shields, and icons rather than route strokes.
        span_score = _clamp((span_ratio - 0.11) / 0.34)
        elongation_score = _clamp((elongation - 2.4) / 7.0)
        thin_score = _clamp((0.26 - minor_span / max(major_span, 1)) / 0.20)
        thickness_score = _clamp((15.0 - thickness) / 11.0)
        continuity_score = _clamp((fill_ratio - 0.10) / 0.36)
        edge_bonus = 0.05 if edge_touches else 0.0
        line_score = _clamp(
            0.36 * span_score
            + 0.25 * elongation_score
            + 0.19 * thin_score
            + 0.12 * thickness_score
            + 0.08 * continuity_score
            + edge_bonus
        )
        # A bent route can occupy a broad bounding box while remaining a thin
        # one-dimensional component; high PCA elongation is the better signal in
        # that case.  Filled polygons have both high thickness and low elongation.
        if (
            thickness < 0.75
            or thickness > 18
            or (
                minor_span / max(major_span, 1) > 0.34
                and elongation < 5.0
            )
        ):
            line_score *= 0.45

        # A route that only clips a corner of the capture can have a modest
        # overall span even though it is unmistakably a sparse, elongated
        # colored stroke.  This covers the Riverfront edge of the Nashville
        # capture without admitting short labels or edge-to-edge UI overlays.
        if (
            span_ratio >= 0.10
            and fill_ratio <= 0.035
            and 0.75 <= thickness <= 8.0
            and elongation >= 10.0
            and edge_touches <= 1
        ):
            sparse_stroke_score = 0.62 + 0.12 * _clamp((span_ratio - 0.10) / 0.30)
            line_score = max(line_score, sparse_stroke_score)

        components.append(
            {
                "score": round(line_score, 4),
                "area": area,
                "bbox": [x0, y0, box_width, box_height],
                "span_ratio": round(span_ratio, 4),
                "thickness": round(thickness, 3),
                "elongation": round(elongation, 3),
                "fill_ratio": round(fill_ratio, 4),
                "edge_touches": edge_touches,
                "mean_rgb": mean_rgb,
                "mean_saturation": round(float(saturation[indices].mean()), 4),
                "mean_value": round(float(value[indices].mean()), 4),
            }
        )

    components.sort(key=lambda item: (item["score"], item["area"]), reverse=True)
    return components


def _fragmented_stroke_evidence(
    components: list[dict[str, Any]], image_shape: tuple[int, int]
) -> Optional[dict[str, Any]]:
    """Combine separated pieces of the same thin transit-colored stroke.

    Station symbols and labels can interrupt a rendered route.  Requiring two
    or more sparse components with nearly identical hue avoids promoting a
    single colored road, map boundary, or label.
    """
    height, width = image_shape
    minimum_area = max(30, round(height * width * 0.00003))
    candidates: list[tuple[float, dict[str, Any]]] = []
    for component in components:
        if not (
            component["area"] >= minimum_area
            and component["span_ratio"] >= 0.04
            and component["fill_ratio"] <= 0.10
            and 0.75 <= component["thickness"] <= 8.0
            and component["edge_touches"] <= 1
            and component["mean_saturation"] >= 0.50
            and component["mean_value"] >= 0.53
        ):
            continue
        red, green, blue = (channel / 255.0 for channel in component["mean_rgb"])
        hue = colorsys.rgb_to_hsv(red, green, blue)[0] * 360.0
        candidates.append((hue, component))

    best: Optional[dict[str, Any]] = None
    for anchor_hue, _ in candidates:
        matching = [
            component
            for hue, component in candidates
            if min(abs(hue - anchor_hue), 360.0 - abs(hue - anchor_hue)) <= 9.0
        ]
        if len(matching) < 2:
            continue
        total_span = sum(component["span_ratio"] for component in matching)
        if total_span < 0.26:
            continue
        score = min(0.78, 0.60 + 0.40 * (total_span - 0.26))
        evidence = {
            "score": round(score, 4),
            "component_count": len(matching),
            "total_span_ratio": round(total_span, 4),
            "mean_hue_degrees": round(anchor_hue, 1),
        }
        if best is None or evidence["score"] > best["score"]:
            best = evidence
    return best


def classify_image(path: Union[str, Path], evidence: Any = None) -> dict[str, Any]:
    """Classify one image as ``rail`` or ``no_rail``.

    ``evidence`` may contain OCR/accessibility strings.  Recognized structured
    keys include ``visible_text``, ``rail_station_names``, ``route_names``, and
    ``excluded_route_names``.  Decode errors raise ``ValueError`` so a sorting
    caller can leave the source file untouched.
    """
    source = Path(path)
    rgb, original_size = _load_rgb(source)
    mask, saturation, value = _saturated_bright_mask(rgb)
    components = _component_stats(mask, rgb, saturation, value)
    strongest_component = components[0]["score"] if components else 0.0
    fragmented_stroke = _fragmented_stroke_evidence(components, mask.shape)
    fragmented_strength = fragmented_stroke["score"] if fragmented_stroke else 0.0
    strongest = max(strongest_component, fragmented_strength)
    strong_count = sum(component["score"] >= 0.60 for component in components)

    # Convert the geometric score into a conservative rail likelihood.  A clear
    # component can cross the decision line on pixels alone; metadata only nudges
    # or vetoes that result.
    rail_likelihood = 0.10 + 0.80 * strongest + min(0.08, max(0, strong_count - 1) * 0.025)
    evidence_delta, evidence_reasons, evidence_conflict = _evidence_adjustment(evidence)
    rail_likelihood = _clamp(rail_likelihood + evidence_delta)
    label = "rail" if rail_likelihood >= 0.58 else "no_rail"
    confidence = rail_likelihood if label == "rail" else 1.0 - rail_likelihood

    reasons: list[str] = []
    if fragmented_strength > strongest_component:
        reasons.append(
            "found multiple matching transit-colored stroke fragments "
            f"(combined span {fragmented_stroke['total_span_ratio']:.0%})"
        )
    elif strongest >= 0.60:
        top = components[0]
        reasons.append(
            "found a long thin saturated stroke "
            f"(span {top['span_ratio']:.0%}, thickness {top['thickness']:.1f}px)"
        )
    elif strongest >= 0.42:
        reasons.append("found a possible transit-colored stroke, but its geometry is weak")
    else:
        reasons.append("no convincing long thin saturated transit stroke was found")
    reasons.extend(evidence_reasons)

    needs_review = (
        label == "no_rail"
        or 0.30 <= rail_likelihood <= 0.74
        or evidence_conflict
        or (evidence_delta < 0 and strongest >= 0.60)
    )
    if needs_review:
        if label == "no_rail" and evidence_delta >= 0:
            reasons.append(
                "negative image-only results cannot prove rail is absent; manual review is recommended"
            )
        else:
            reasons.append("heuristic evidence is uncertain or conflicting; manual review is recommended")

    return {
        "label": label,
        "confidence": round(float(confidence), 4),
        "needs_review": bool(needs_review),
        "reasons": reasons,
        "rail_likelihood": round(float(rail_likelihood), 4),
        "image_size": list(original_size),
        "analyzed_size": [int(rgb.shape[1]), int(rgb.shape[0])],
        "saturated_pixel_fraction": round(float(mask.mean()), 6),
        "line_candidates": components[:5],
        "fragmented_stroke": fragmented_stroke,
        "method": "dark-map saturated-stroke heuristic v2 (native resolution)",
    }


def _unique_destination(directory: Path, name: str) -> Path:
    candidate = directory / name
    if not candidate.exists():
        return candidate
    path = Path(name)
    counter = 1
    while True:
        candidate = directory / f"{path.stem}-{counter}{path.suffix}"
        if not candidate.exists():
            return candidate
        counter += 1


def _evidence_for_file(evidence: Any, path: Path) -> Any:
    if not isinstance(evidence, dict):
        return evidence
    files = evidence.get("files")
    if isinstance(files, dict):
        return files.get(path.name, files.get(str(path), evidence.get("default")))
    if path.name in evidence:
        return evidence[path.name]
    return evidence


def sort_directory(
    directory: Union[str, Path],
    *,
    evidence: Any = None,
    audit_path: Optional[Union[str, Path]] = None,
    dry_run: bool = False,
) -> dict[str, int]:
    """Classify immediate image children and move successful ones by label."""
    source = Path(directory)
    if not source.is_dir():
        raise ValueError(f"not a directory: {source}")
    audit = Path(audit_path) if audit_path else source / "classification-audit.jsonl"
    candidates = sorted(
        path
        for path in source.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
    )
    counts = {"rail": 0, "no_rail": 0, "failed": 0}
    records: list[dict[str, Any]] = []

    for path in candidates:
        record: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "input": str(path),
        }
        try:
            result = classify_image(path, _evidence_for_file(evidence, path))
            destination_directory = source / result["label"]
            destination = _unique_destination(destination_directory, path.name)
            if not dry_run:
                destination_directory.mkdir(parents=True, exist_ok=True)
                shutil.move(str(path), str(destination))
            record.update(
                {
                    "status": "dry_run" if dry_run else "moved",
                    "output": str(destination),
                    "result": result,
                }
            )
            counts[result["label"]] += 1
        except Exception as error:  # Per-file failure must not abort or move input.
            record.update(
                {
                    "status": "error",
                    "error": f"{type(error).__name__}: {error}",
                }
            )
            counts["failed"] += 1
        records.append(record)

    audit.parent.mkdir(parents=True, exist_ok=True)
    with audit.open("a", encoding="utf-8") as stream:
        for record in records:
            stream.write(json.dumps(record, sort_keys=True) + "\n")
    return counts


def _load_evidence(path: Optional[str]) -> Any:
    if not path:
        return None
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream)


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", help="directory whose immediate image files will be sorted")
    parser.add_argument("--evidence", help="optional JSON evidence file")
    parser.add_argument("--audit", help="JSONL audit path (default: DIRECTORY/classification-audit.jsonl)")
    parser.add_argument("--dry-run", action="store_true", help="classify and audit without moving files")
    args = parser.parse_args(list(argv) if argv is not None else None)
    counts = sort_directory(
        args.directory,
        evidence=_load_evidence(args.evidence),
        audit_path=args.audit,
        dry_run=args.dry_run,
    )
    print(json.dumps(counts, sort_keys=True))
    return 0 if counts["failed"] == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
