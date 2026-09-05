#!/usr/bin/env python3
"""Structural and cross-platform preflight for JTM `compact-v1` rail packages.

This does not claim surveyed-track correctness. It checks the contracts the
packages actually hold today, and emits review candidates for the defect
classes that earlier Japan/Taiwan/Hong Kong/Macao audits kept finding by hand.

Format notes this relies on (verified against the packages and
`app/scripts/railway/lib/na_build.py::segments_for`):

* `stations[i] = [id, name, lon, lat, roma, romaSource, (tzIndex)]`
* `segments[i] = [km, continuesFromPrevious, coordinates]`
* `continuesFromPrevious == 1` means the row DROPS the vertex it shares with
  the previous row, so a segment's real polyline is
  `[previous_row_last_vertex] + coordinates`. Reading the row on its own
  under-measures the interval and mis-locates its first endpoint, which is why
  every geometric check below reconstructs the chain first.
* `km` is the interval length of that reconstructed polyline, so a geometry
  edit that is not reflected in `km` (or the reverse) is a real inconsistency.
* Station anchors coincide EXACTLY with interval endpoints in every shipped
  package, so an anchor gap of more than a few metres is a regression rather
  than a tolerance.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

EARTH_RADIUS_M = 6_371_008.8

# Review thresholds. These are calibrated against the shipped packages to keep
# hard findings sparse. Warning-level geometry findings are review triggers,
# not proof of a defect, and a repository may intentionally retain a named
# warning baseline while evidence is gathered.
ANCHOR_GAP_WARN_M = 5.0
ANCHOR_GAP_ERROR_M = 50.0
LENGTH_MISMATCH_WARN = 0.02
LENGTH_MISMATCH_ERROR = 0.10
LENGTH_MISMATCH_FLOOR_M = 20.0
CHORD_MIN_M = 250.0
SPARSE_MIN_M = 1_000.0
SPARSE_VERTICES_PER_KM = 1.5
SPARSE_RATIO = 1.002
VERTEX_JUMP_M = 2_000.0
DETOUR_RATIO = 3.0
DETOUR_MIN_M = 2_000.0
REVERSAL_DEGREES = 150.0
REVERSAL_MIN_EDGE_M = 40.0
OUTLIER_FACTOR = 3.0
OUTLIER_FLOOR_M = 50_000.0
OVERLAP_STEP_M = 25.0
OVERLAP_CELL_M = 30.0
OVERLAP_MIN_ALONG_M = 750.0
OVERLAP_ANGLE_DEG = 30.0
OVERLAP_WARN = 0.10
OVERLAP_WARN_M = 1_500.0
RETRACE_STATION_SHARE = 0.8
RETRACE_LINE_SHARE = 0.25
RETRACE_NEAR_M = 40.0

# STRAIGHT_INTERVAL — chord-deviation review class ------------------------
#
# `na_geo.densify()` (app/scripts/railway/lib/na_geo.py, bands in
# lib/na_profile.py) subdivides every edge COLLINEARLY to <= max_edge_m by
# band (street 120 / metro 160 / commuter 220 / regional 350 / longhaul
# 600 m). A station-to-station straight line therefore ships as a chain of
# short straight pieces: STRAIGHT_CHORD only fires on a bare 2-point
# interval, and SPARSE_GEOMETRY only on low vertex density — a densified
# straight interval can carry a dozen healthily-spaced vertices and still
# be perfectly straight, so both read zero on it. Collinear subdivision
# cannot hide only one thing: the maximum perpendicular deviation of the
# interval's INTERIOR vertices from the chord between its two station
# endpoints. A straight line densified into N pieces has interior vertices
# that all sit exactly ON that chord; a curve's do not.
#
# STRAIGHT_INTERVAL_CHORD_MIN_M = 1,500 m. The coarsest densify band
# (longhaul) caps a sub-edge at 600 m, so any chord under about 1,200 m
# could in principle BE a single un-subdivided densify edge with no
# interior vertex to measure at all — that case proves nothing, it is just
# how the densifier writes any edge, straight or not. 1,500 m sits
# comfortably above 2x that ceiling, so a finding always spans at least two
# densified sub-edges: it is evidence about the interval's own recorded
# shape, not an artifact of how finely one edge happened to be cut.
#
# STRAIGHT_INTERVAL_DEVIATION_MAX_M = 25 m. A chord of length L drawn along
# a constant-radius curve of radius R sags by L^2/(8R) at its midpoint. At
# the threshold chord (1,500 m) a 25 m sag corresponds to R = 1500^2 /
# (8*25) ~= 11.25 km — far broader than a turnout or station-throat curve,
# and broader than most mainline curve radii. Below this deviation the
# interval reads, at any zoom a renderer draws it at, as dead straight;
# above it, real curvature is visible. 25 m is also well clear of
# coordinate rounding and GPS jitter in the shipped packages (compare
# `check_anchor`'s 5 m WARN floor).
#
# Sensitivity (measured against the shipped packages, 2026-09-02):
#   chord>1,000 m dev<25 m -> US 344 intervals/114 lines/882 km   CA 47/22/153 km
#   chord>1,500 m dev<25 m -> US 242 intervals/81 lines/753 km    CA 34/15/137 km  <- chosen
#   chord>2,000 m dev<25 m -> US 145 intervals/59 lines/587 km    CA 27/12/125 km
#   chord>1,500 m dev<15 m -> US 213 intervals/77 lines/664 km    CA 34/15/137 km
#   chord>1,500 m dev<40 m -> US 279 intervals/87 lines/883 km    CA 42/16/163 km
# Every CA count is identical at dev<15/25 m — CA's straight intervals sit
# at 0.06-0.10 m deviation, nowhere near either knob, which is itself
# evidence that they are dead-straight synthetic chords rather than gentle
# real curves sitting just inside a threshold. Neither knob shows a cliff:
# the count moves smoothly as each one moves, so no pair is "obviously
# correct" — 1,500 m / 25 m was chosen mid-way through a smooth trade-off,
# not at an edge where a small change in the source data would flip many
# findings at once.
#
# This class is a REVIEW CANDIDATE, never an automatic verdict: a real
# dead-straight high-speed viaduct or a prairie mainline draws exactly the
# same signature as a synthetic straight line copied station-to-station.
# The jp/tw/hk/kr packages (surveyed, not densified) DO trigger it —
# JR Hokkaido's flat-plain lines, TRA's Chianan-plain running, MTR's West
# Rail viaduct, and KTX/Airport Railroad express track are all genuinely
# straight over multi-km chords — which is the expected true-positive case
# this class exists to distinguish from densified filler, not a bug in the
# detector. See STRAIGHT_INTERVAL's entry in `result()["limitations"]`.
STRAIGHT_INTERVAL_CHORD_MIN_M = 1_500.0
STRAIGHT_INTERVAL_DEVIATION_MAX_M = 25.0


def haversine(a: list[float], b: list[float]) -> float:
    lon1, lat1 = math.radians(a[0]), math.radians(a[1])
    lon2, lat2 = math.radians(b[0]), math.radians(b[1])
    dlon, dlat = lon2 - lon1, lat2 - lat1
    value = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(value)))


def deflection_degrees(a: list[float], b: list[float], c: list[float]) -> float:
    """Turn angle at `b`: 0 is straight ahead, 180 is a full reversal."""
    scale = math.cos(math.radians((a[1] + c[1]) / 2))
    ux, uy = (b[0] - a[0]) * scale, b[1] - a[1]
    wx, wy = (c[0] - b[0]) * scale, c[1] - b[1]
    nu, nw = math.hypot(ux, uy), math.hypot(wx, wy)
    if nu == 0 or nw == 0:
        return 0.0
    cosine = max(-1.0, min(1.0, (ux * wx + uy * wy) / (nu * nw)))
    return math.degrees(math.acos(cosine))


def finite_coordinate(value: Any) -> bool:
    return (
        isinstance(value, list)
        and len(value) >= 2
        and all(isinstance(item, (int, float)) and math.isfinite(item) for item in value[:2])
        and -180 <= value[0] <= 180
        and -90 <= value[1] <= 90
    )


def orient_path_to_anchors(
    path: list[list[float]], start: list[float] | None, end: list[float] | None
) -> list[list[float]]:
    """Return an interval in station order without changing its geometry.

    `compact-v1` permits a self-contained interval to be digitised in either
    direction.  Whole-line checks must orient each interval before assigning
    along-line distance; otherwise two adjacent, oppositely digitised intervals
    manufacture an artificial out-and-back between them.
    """
    if not start or not end or len(path) < 2:
        return path
    forward = max(haversine(path[0], start), haversine(path[-1], end))
    reverse = max(haversine(path[-1], start), haversine(path[0], end))
    return list(reversed(path)) if reverse < forward else path


def point_to_segment_distance_m(point: list[float], a: list[float], b: list[float]) -> float:
    """Local equirectangular point-to-segment distance in metres."""
    latitude = math.radians(point[1])
    x_scale = 111_320.0 * max(0.2, math.cos(latitude))
    y_scale = 110_540.0
    ax, ay = (a[0] - point[0]) * x_scale, (a[1] - point[1]) * y_scale
    bx, by = (b[0] - point[0]) * x_scale, (b[1] - point[1]) * y_scale
    dx, dy = bx - ax, by - ay
    denominator = dx * dx + dy * dy
    if denominator <= 0:
        return math.hypot(ax, ay)
    ratio = max(0.0, min(1.0, -(ax * dx + ay * dy) / denominator))
    return math.hypot(ax + ratio * dx, ay + ratio * dy)


def point_to_polyline_distance_m(point: list[float], path: list[list[float]]) -> float:
    if len(path) < 2:
        return math.inf
    return min(point_to_segment_distance_m(point, a, b) for a, b in zip(path, path[1:]))


def find_repo(start: Path) -> Path:
    """The packages are the one thing every JTM checkout has.

    `ios/` is not required: the repositories were split, and the web repository
    that still owns the Japan/Taiwan/Hong Kong/Macao/Korea builders has no iOS
    tree at all. Demanding both refused to run in exactly the checkout where a
    railway rebuild happens.
    """
    current = start.resolve()
    for candidate in (current, *current.parents):
        if (candidate / "app/public/rail").is_dir():
            return candidate
    raise SystemExit(f"no app/public/rail above {start} — is this a JTM checkout?")


def discover_countries(repo: Path) -> list[str]:
    names = sorted(path.stem.split("-")[0] for path in (repo / "app/public/rail").glob("??-2025.json"))
    return names


class Audit:
    def __init__(self, repo: Path) -> None:
        self.repo = repo
        self.issues: list[dict[str, Any]] = []
        self.packages: dict[str, dict[str, Any]] = {}
        # STRAIGHT_INTERVAL per-line rollup: country -> line_id -> {count,
        # chordKm, worst, markedByPackage, smoothingProfile}. The per-package
        # `tally` Counter only holds a package-wide total, which cannot answer
        # "which lines, how bad, worst interval" — the ledger this feeds
        # needs the per-line breakdown, so it is kept here rather than
        # recomputed from `issues` after the fact.
        self.straight_lines: dict[str, dict[str, dict[str, Any]]] = {}

    # ------------------------------------------------------------------ util

    def issue(self, severity: str, code: str, message: str, **context: Any) -> None:
        self.issues.append({"severity": severity, "code": code, "message": message, **context})

    def require_file(self, path: Path, country: str, code: str) -> bool:
        if path.is_file():
            return True
        self.issue("ERROR", code, f"missing {path.relative_to(self.repo)}", country=country)
        return False

    # --------------------------------------------------------------- package

    def audit_package(self, country: str) -> None:
        rail_dir = self.repo / "app/public/rail"
        package_path = rail_dir / f"{country}-2025.json"
        if not self.require_file(package_path, country, "MISSING_PACKAGE"):
            return

        try:
            package = json.loads(package_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            self.issue("ERROR", "INVALID_JSON", str(error), country=country)
            return

        for key, expected in (("format", "compact-v1"), ("crs", "WGS84"), ("country", country.upper())):
            if package.get(key) != expected:
                self.issue(
                    "ERROR",
                    "PACKAGE_HEADER",
                    f"{key} is {package.get(key)!r}, expected {expected!r}",
                    country=country,
                )

        lines = package.get("lines")
        if not isinstance(lines, list) or not lines:
            self.issue("ERROR", "EMPTY_LINES", "package has no lines", country=country)
            return

        for line_id, count in Counter(
            line.get("id") for line in lines if isinstance(line, dict)
        ).items():
            if line_id and count > 1:
                self.issue(
                    "ERROR", "DUPLICATE_LINE_ID", f"duplicate line id {line_id}", country=country, line=line_id
                )

        tally = Counter()
        for index, line in enumerate(lines):
            self.audit_line(country, index, line, tally)

        self.packages[country] = {
            "version": package.get("version"),
            "generatedAt": package.get("generatedAt"),
            "lines": len(lines),
            "stationRows": tally["stations"],
            "segments": tally["segments"],
            "vertices": tally["vertices"],
            "extraSegments": tally["extraSegments"],
            "straightChords": tally["chords"],
            "straightIntervals": tally["straightIntervals"],
            "straightIntervalKm": round(tally["straightIntervalKm"], 1),
            "reversalCandidates": tally["reversals"],
            "detours": tally["detours"],
            "selfOverlap": tally["selfOverlap"],
            "lengthMismatches": tally["lengthMismatch"],
            "geometrySources": dict(sorted(Counter(
                str(line.get("geometrySource", "<unspecified>"))
                for line in lines if isinstance(line, dict)
            ).items())),
        }

        self.require_file(rail_dir / f"{country}-2025.sources.md", country, "MISSING_SOURCE_NOTES")
        suffix = "" if country == "jp" else f"-{country}"
        for family in ("stations", "rail-sections", "station-readings"):
            code = f"MISSING_{family.upper().replace('-', '_')}"
            self.require_file(self.repo / f"app/data/{family}{suffix}.json", country, code)
        self.require_file(self.repo / f"app/data/train-store{suffix}.json", country, "MISSING_SAMPLE_STORE")

    def audit_line(self, country: str, index: int, line: Any, tally: Counter) -> None:
        if not isinstance(line, dict):
            self.issue("ERROR", "INVALID_LINE", f"line {index} is not an object", country=country)
            return
        line_id = line.get("id") or f"line[{index}]"
        stations, segments = line.get("stations"), line.get("segments")

        if not isinstance(stations, list) or len(stations) < 2:
            self.issue("ERROR", "INVALID_STATIONS", "line needs at least two stations", country=country, line=line_id)
            return
        # A loop line may close back onto its first station, hence the two
        # accepted counts.
        if not isinstance(segments, list) or len(segments) not in {len(stations) - 1, len(stations)}:
            count = len(segments) if isinstance(segments, list) else "invalid"
            self.issue(
                "ERROR", "SEGMENT_COUNT", f"{count} segments for {len(stations)} stations",
                country=country, line=line_id,
            )
            return

        tally["stations"] += len(stations)
        tally["segments"] += len(segments)

        anchors: list[list[float] | None] = []
        station_names: list[str] = []
        local_ids: list[str] = []
        for station_index, station in enumerate(stations):
            if not isinstance(station, list) or len(station) < 4:
                self.issue(
                    "ERROR", "INVALID_STATION_ROW", f"station {station_index} has an invalid compact row",
                    country=country, line=line_id,
                )
                anchors.append(None)
                station_names.append("?")
                continue
            local_ids.append(str(station[0]))
            station_names.append(str(station[1]) if len(station) > 1 else "?")
            point = [station[2], station[3]]
            if finite_coordinate(point):
                anchors.append(point)
            else:
                self.issue(
                    "ERROR", "INVALID_STATION_COORDINATE", f"station {station_index} coordinate is invalid",
                    country=country, line=line_id,
                )
                anchors.append(None)

        for station_id, count in Counter(local_ids).items():
            if count > 1:
                self.issue(
                    "ERROR", "DUPLICATE_STATION_IN_LINE",
                    f"station id {station_id} occurs {count} times", country=country, line=line_id,
                )

        # The NA builders leave a `straightIntervals` marker (interval
        # ordinals + the tolerance they were confirmed under) on lines whose
        # straightness was already investigated. It only exists for NA
        # (18 US / 6 CA lines) — cross-referencing it tells us how much of
        # what STRAIGHT_INTERVAL finds was already known versus new.
        straight_marker = line.get("straightIntervals")
        marked_intervals: set[int] = set()
        if isinstance(straight_marker, dict) and isinstance(straight_marker.get("intervals"), list):
            marked_intervals = {value for value in straight_marker["intervals"] if isinstance(value, int)}
        smoothing_profile = line.get("smoothingProfile")

        paths = self.audit_geometry(
            country, line_id, anchors, segments, tally,
            station_names=station_names, marked_intervals=marked_intervals, smoothing_profile=smoothing_profile,
        )
        self.check_self_overlap(country, line_id, paths, tally)
        self.audit_extra_segments(country, line_id, line, len(stations), tally)

    def audit_geometry(
        self, country: str, line_id: str, anchors: list[list[float] | None], segments: list[Any], tally: Counter,
        *, station_names: list[str] | None = None, marked_intervals: set[int] | None = None,
        smoothing_profile: Any = None,
    ) -> list[list[list[float]]]:
        station_names = station_names or []
        marked_intervals = marked_intervals or set()
        previous_end: list[float] | None = None
        centroids: list[tuple[list[float], int, str]] = []
        paths: list[list[list[float]]] = []
        line_total = sum(
            row[0] for row in segments
            if isinstance(row, list) and row and isinstance(row[0], (int, float))
        ) * 1000.0

        for ordinal, segment in enumerate(segments):
            if not isinstance(segment, list) or len(segment) < 3:
                self.issue(
                    "ERROR", "INVALID_SEGMENT_ROW", f"segment {ordinal} has an invalid compact row",
                    country=country, line=line_id,
                )
                previous_end = None
                continue

            declared_km, marker, coordinates = segment[0], segment[1], segment[2]
            if marker not in (0, 1):
                self.issue(
                    "ERROR", "INVALID_CONTINUATION_MARKER",
                    f"segment {ordinal} continuesFromPrevious is {marker!r}", country=country, line=line_id,
                )
            if not isinstance(coordinates, list) or len(coordinates) < 1 or not all(
                finite_coordinate(point) for point in coordinates
            ):
                self.issue(
                    "ERROR", "INVALID_SEGMENT_GEOMETRY", f"segment {ordinal} has invalid coordinates",
                    country=country, line=line_id,
                )
                previous_end = None
                continue

            # Reconstruct the chain: a continuing row omits its shared vertex.
            if marker == 1 and previous_end is not None:
                path = [previous_end, *coordinates]
            else:
                path = list(coordinates)
                if marker == 1:
                    self.issue(
                        "WARNING", "ORPHAN_CONTINUATION",
                        f"segment {ordinal} continues from a previous row that has no usable geometry",
                        country=country, line=line_id,
                    )
            previous_end = coordinates[-1]
            tally["vertices"] += len(coordinates)

            if len(path) < 2:
                self.issue(
                    "ERROR", "EMPTY_SEGMENT", f"segment {ordinal} has no drawable geometry",
                    country=country, line=line_id,
                )
                continue

            walked = sum(haversine(a, b) for a, b in zip(path, path[1:]))
            direct = haversine(path[0], path[-1])
            centroids.append((path[len(path) // 2], ordinal, line_id))
            start = anchors[ordinal] if ordinal < len(anchors) else None
            end = anchors[(ordinal + 1) % len(anchors)] if anchors else None
            path = orient_path_to_anchors(path, start, end)
            paths.append(path)
            self.check_retrace(country, line_id, ordinal, path, walked, line_total, anchors)

            self.check_anchor(country, line_id, ordinal, path, anchors)
            self.check_declared_length(country, line_id, ordinal, declared_km, walked, tally)
            self.check_chord(country, line_id, ordinal, path, walked, direct, tally)
            self.check_straight_interval(
                country, line_id, ordinal, path, start, end, station_names, marked_intervals,
                smoothing_profile, tally,
            )
            self.check_detour(country, line_id, ordinal, walked, direct, tally)
            self.check_vertex_jumps(country, line_id, ordinal, path)
            self.check_reversal(country, line_id, ordinal, path, tally)

        self.check_outliers(country, line_id, centroids)
        return paths

    def check_anchor(
        self, country: str, line_id: str, ordinal: int, path: list[list[float]], anchors: list[list[float] | None]
    ) -> None:
        start = anchors[ordinal] if ordinal < len(anchors) else None
        end = anchors[(ordinal + 1) % len(anchors)] if anchors else None
        if not start or not end:
            return
        forward = max(haversine(path[0], start), haversine(path[-1], end))
        reverse = max(haversine(path[-1], start), haversine(path[0], end))
        gap = min(forward, reverse)
        if gap > ANCHOR_GAP_ERROR_M:
            self.issue(
                "ERROR", "ANCHOR_OFF_LINE",
                f"segment {ordinal} ends {gap:.0f} m from its station anchor",
                country=country, line=line_id,
            )
        elif gap > ANCHOR_GAP_WARN_M:
            self.issue(
                "WARNING", "ANCHOR_DRIFT",
                f"segment {ordinal} ends {gap:.1f} m from its station anchor",
                country=country, line=line_id,
            )

    def check_declared_length(
        self, country: str, line_id: str, ordinal: int, declared_km: Any, walked: float, tally: Counter
    ) -> None:
        if not isinstance(declared_km, (int, float)) or declared_km <= 0:
            return
        declared = declared_km * 1000.0
        difference = abs(walked - declared)
        if difference < LENGTH_MISMATCH_FLOOR_M:
            return
        ratio = difference / declared
        if ratio > LENGTH_MISMATCH_ERROR:
            tally["lengthMismatch"] += 1
            self.issue(
                "ERROR", "LENGTH_DISAGREES",
                f"segment {ordinal} declares {declared / 1000:.3f} km but its geometry walks {walked / 1000:.3f} km",
                country=country, line=line_id,
            )
        elif ratio > LENGTH_MISMATCH_WARN:
            tally["lengthMismatch"] += 1
            self.issue(
                "WARNING", "LENGTH_DRIFT",
                f"segment {ordinal} declares {declared / 1000:.3f} km, geometry walks {walked / 1000:.3f} km",
                country=country, line=line_id,
            )

    def check_chord(
        self, country: str, line_id: str, ordinal: int, path: list[list[float]],
        walked: float, direct: float, tally: Counter,
    ) -> None:
        if len(path) == 2 and walked >= CHORD_MIN_M:
            tally["chords"] += 1
            self.issue(
                "WARNING", "STRAIGHT_CHORD",
                f"segment {ordinal} is a single {walked / 1000:.2f} km straight line between two stations",
                country=country, line=line_id,
            )
            return
        if walked < SPARSE_MIN_M or direct <= 0:
            return
        density = (len(path) - 1) / (walked / 1000.0)
        if density < SPARSE_VERTICES_PER_KM and walked / direct < SPARSE_RATIO:
            tally["chords"] += 1
            self.issue(
                "WARNING", "SPARSE_GEOMETRY",
                f"segment {ordinal} draws {walked / 1000:.2f} km with {len(path)} vertices and no measurable curvature",
                country=country, line=line_id,
            )

    def check_straight_interval(
        self, country: str, line_id: str, ordinal: int, path: list[list[float]],
        start: list[float] | None, end: list[float] | None, station_names: list[str],
        marked_intervals: set[int], smoothing_profile: Any, tally: Counter,
    ) -> None:
        """Chord-deviation review class — see the STRAIGHT_INTERVAL_* constants.

        STRAIGHT_CHORD only fires on a bare 2-point interval, which is
        exactly the shape `na_geo.densify()` never leaves behind: every edge
        it touches is cut to <= max_edge_m, so a real station-to-station
        straight line ships as several short straight pieces and both
        STRAIGHT_CHORD and SPARSE_GEOMETRY read zero on it (the piece count
        keeps density healthy). The only signal collinear subdivision cannot
        hide is how far the interval's own interior vertices sit off the
        straight line between its two station anchors.
        """
        if len(path) < 3:
            return  # a 2-point interval is STRAIGHT_CHORD's case, not this one
        chord_a = start or path[0]
        chord_b = end or path[-1]
        chord_len = haversine(chord_a, chord_b)
        if chord_len < STRAIGHT_INTERVAL_CHORD_MIN_M:
            return
        max_deviation = max(point_to_segment_distance_m(vertex, chord_a, chord_b) for vertex in path[1:-1])
        if max_deviation >= STRAIGHT_INTERVAL_DEVIATION_MAX_M:
            return

        tally["straightIntervals"] += 1
        tally["straightIntervalKm"] += chord_len / 1000.0
        name_a = station_names[ordinal] if ordinal < len(station_names) else "?"
        name_b = station_names[(ordinal + 1) % len(station_names)] if station_names else "?"
        already_marked = ordinal in marked_intervals

        line_entry = self.straight_lines.setdefault(country, {}).setdefault(
            line_id,
            {"count": 0, "chordKm": 0.0, "worst": None, "markedByPackage": False, "smoothingProfile": smoothing_profile},
        )
        line_entry["count"] += 1
        line_entry["chordKm"] += chord_len / 1000.0
        if already_marked:
            line_entry["markedByPackage"] = True
        worst = line_entry["worst"]
        if worst is None or chord_len > worst["chordM"]:
            line_entry["worst"] = {
                "ordinal": ordinal, "chordM": chord_len, "deviationM": max_deviation,
                "stationA": name_a, "stationB": name_b,
            }

        self.issue(
            "WARNING", "STRAIGHT_INTERVAL",
            f"segment {ordinal} ({name_a} -> {name_b}) is a {chord_len / 1000:.2f} km chord with "
            f"{max_deviation:.1f} m max interior deviation from it -- densified into pieces but not curved"
            + (" [already carries the package's straightIntervals marker]" if already_marked else ""),
            country=country, line=line_id,
        )

    def check_detour(
        self, country: str, line_id: str, ordinal: int, walked: float, direct: float, tally: Counter
    ) -> None:
        """One interval walking far further than the distance between its two
        stations.

        This is the shape the CTA Brown Line took when the builder projected each
        station onto an operator's round-trip shape independently: two adjacent
        stations picked opposite passes, and a 410 m interval was drawn as
        32.6 km. Real switchbacks and street loops also land here, so it is a
        review candidate — but every one of them has to be explained.
        """
        if walked < DETOUR_MIN_M or direct <= 50:
            return
        ratio = walked / direct
        if ratio >= DETOUR_RATIO:
            tally["detours"] += 1
            self.issue(
                "WARNING", "DETOUR_RATIO",
                f"segment {ordinal} walks {walked / 1000:.1f} km between stations {direct / 1000:.1f} km apart "
                f"({ratio:.1f}x)",
                country=country, line=line_id,
            )

    def check_retrace(
        self, country: str, line_id: str, ordinal: int, path: list[list[float]],
        walked: float, line_total: float, anchors: list[list[float] | None],
    ) -> None:
        """One interval carrying a whole extra lap of its own line.

        The Atlanta Streetcar's Peachtree Center → Carnegie Way hop is 264 m
        apart and drawn as 3.93 km, passing within 23 m of all twelve of the
        line's stations — a second lap of a loop whose other eleven intervals
        already sum to the real 3.93 km. Nothing legitimate looks like this: an
        interval does not pass by nearly every station on its own line.
        """
        stations = [point for point in anchors if point]
        if len(stations) < 5 or len(path) < 2 or line_total <= 0:
            return
        if walked < line_total * RETRACE_LINE_SHARE:
            return
        near = sum(
            1 for station in stations
            if point_to_polyline_distance_m(station, path) < RETRACE_NEAR_M
        )
        if near >= len(stations) * RETRACE_STATION_SHARE:
            self.issue(
                "ERROR", "INTERVAL_RETRACES_LINE",
                f"segment {ordinal} walks {walked / 1000:.2f} km and passes within {RETRACE_NEAR_M:.0f} m of "
                f"{near}/{len(stations)} of the line's own stations — an extra lap, not an interval",
                country=country, line=line_id,
            )

    def check_self_overlap(
        self, country: str, line_id: str, paths: list[list[list[float]]], tally: Counter
    ) -> None:
        """How much of a line is drawn on top of itself.

        Alaska's Aurora Winter lay on itself for 72.8% of its length after the
        builder copied two wrong station coordinates out of an official GTFS.
        Proximity alone cannot find that: 井川線, 黒部峡谷, Alishan's spirals and
        street trams all run close to themselves honestly. Two extra conditions
        make the difference — the two passes must be roughly parallel or
        antiparallel, and they must be far apart ALONG the line. A horseshoe
        curve fails both; a line drawn twice fails neither.
        """
        if sum(len(path) for path in paths) < 3:
            return
        samples: list[tuple[list[float], float, float, float]] = []
        along = 0.0
        for path in paths:
            for a, b in zip(path, path[1:]):
                span = haversine(a, b)
                if span <= 0:
                    continue
                bearing = math.degrees(
                    math.atan2(
                        (b[0] - a[0]) * math.cos(math.radians((a[1] + b[1]) / 2)),
                        b[1] - a[1],
                    )
                ) % 180
                steps = max(1, math.ceil(span / OVERLAP_STEP_M))
                weight = span / steps
                for step in range(steps):
                    ratio = step / steps
                    samples.append((
                        [a[0] + (b[0] - a[0]) * ratio, a[1] + (b[1] - a[1]) * ratio],
                        along + span * ratio,
                        bearing,
                        weight,
                    ))
                along += span
        if len(samples) < 20:
            return

        minimum_cosine = min(max(0.2, math.cos(math.radians(sample[0][1]))) for sample in samples)
        cell_lon = OVERLAP_CELL_M / (111_320 * minimum_cosine)
        cell_lat = OVERLAP_CELL_M / 110_540
        grid: dict[tuple[int, int], list[int]] = {}
        for index, (point, _, _, _) in enumerate(samples):
            grid.setdefault((int(point[0] / cell_lon), int(point[1] / cell_lat)), []).append(index)

        overlapped_m = 0.0
        for index, (point, distance, bearing, weight) in enumerate(samples):
            cx, cy = int(point[0] / cell_lon), int(point[1] / cell_lat)
            if any(
                other != index
                and abs(distance - samples[other][1]) >= OVERLAP_MIN_ALONG_M
                and min(
                    abs(bearing - samples[other][2]), 180 - abs(bearing - samples[other][2])
                ) <= OVERLAP_ANGLE_DEG
                and haversine(point, samples[other][0]) <= OVERLAP_CELL_M
                for dx in (-1, 0, 1)
                for dy in (-1, 0, 1)
                for other in grid.get((cx + dx, cy + dy), ())
            ):
                overlapped_m += weight

        share = overlapped_m / along if along else 0.0
        # Share alone dilutes a local defect on a long line: a 4 km out-and-back
        # on the 宜蘭線 is 4% and would pass. Absolute length catches that half.
        if share >= OVERLAP_WARN or overlapped_m >= OVERLAP_WARN_M:
            tally["selfOverlap"] += 1
            self.issue(
                "WARNING", "SELF_OVERLAP",
                f"{overlapped_m / 1000:.1f} km ({share * 100:.0f}%) of this line is drawn on top of itself, "
                f"parallel and far apart along the line",
                country=country, line=line_id,
            )

    def check_vertex_jumps(self, country: str, line_id: str, ordinal: int, path: list[list[float]]) -> None:
        longest = max(haversine(a, b) for a, b in zip(path, path[1:]))
        if longest >= VERTEX_JUMP_M:
            self.issue(
                "WARNING", "VERTEX_JUMP",
                f"segment {ordinal} contains a single {longest / 1000:.2f} km edge with no intermediate survey point",
                country=country, line=line_id,
            )

    def check_reversal(
        self, country: str, line_id: str, ordinal: int, path: list[list[float]], tally: Counter
    ) -> None:
        for index in range(1, len(path) - 1):
            before = haversine(path[index - 1], path[index])
            after = haversine(path[index], path[index + 1])
            if before < REVERSAL_MIN_EDGE_M or after < REVERSAL_MIN_EDGE_M:
                continue
            angle = deflection_degrees(path[index - 1], path[index], path[index + 1])
            if angle >= REVERSAL_DEGREES:
                tally["reversals"] += 1
                self.issue(
                    "WARNING", "REVERSAL_CANDIDATE",
                    f"segment {ordinal} turns {angle:.0f}° at vertex {index}; confirm a real switchback before smoothing",
                    country=country, line=line_id,
                )
                return

    def check_outliers(self, country: str, line_id: str, centroids: list[tuple[list[float], int, str]]) -> None:
        """A rotated or concatenated station order shows up as one interval that
        teleports away from its own line.

        Distance from the line's centre alone is not the test: an intercity line
        legitimately ends hundreds of kilometres from its middle. What is not
        legitimate is a GAP — one interval far outside the run of every other,
        which is what a rotated order or a stray coordinate produces.
        """
        if len(centroids) < 4:
            return
        points = [point for point, _, _ in centroids]
        lon = sorted(point[0] for point in points)
        lat = sorted(point[1] for point in points)
        median = [lon[len(lon) // 2], lat[len(lat) // 2]]
        distances = sorted((haversine(point, median), ordinal) for point, ordinal, _ in centroids)
        furthest, ordinal = distances[-1]
        runner_up = distances[-2][0]
        if furthest > OUTLIER_FLOOR_M and furthest > runner_up * OUTLIER_FACTOR:
            self.issue(
                "WARNING", "GEOGRAPHIC_OUTLIER",
                f"segment {ordinal} sits {furthest / 1000:.0f} km from the line's centre while "
                f"every other interval stays within {runner_up / 1000:.0f} km",
                country=country, line=line_id,
            )

    def audit_extra_segments(
        self, country: str, line_id: str, line: dict[str, Any], station_count: int, tally: Counter
    ) -> None:
        extras = line.get("extraSegments")
        if not extras:
            return
        if not isinstance(extras, list):
            self.issue("ERROR", "INVALID_EXTRA_SEGMENTS", "extraSegments is not a list", country=country, line=line_id)
            return
        tally["extraSegments"] += len(extras)
        for position, extra in enumerate(extras):
            if not isinstance(extra, dict):
                self.issue(
                    "ERROR", "INVALID_EXTRA_SEGMENTS", f"extraSegments[{position}] is not an object",
                    country=country, line=line_id,
                )
                continue
            for key in ("from", "to"):
                value = extra.get(key)
                if not isinstance(value, int) or not 0 <= value < station_count:
                    self.issue(
                        "ERROR", "EXTRA_SEGMENT_INDEX",
                        f"extraSegments[{position}].{key} is {value!r}, outside the station list",
                        country=country, line=line_id,
                    )
            # extraSegments exist because a distinct-station order cannot
            # express direction-specific physical track. An entry without
            # evidence is an invented edge.
            if not extra.get("evidence"):
                self.issue(
                    "WARNING", "EXTRA_SEGMENT_UNSOURCED",
                    f"extraSegments[{position}] carries no evidence string",
                    country=country, line=line_id,
                )

    # -------------------------------------------------------- cross-platform

    def audit_cross_platform(self, countries: list[str]) -> None:
        paths = {
            "js": self.repo / "app/public/railmap-style.js",
            "swift": self.repo / "ios/RailMap/RailStyle.swift",
            "renderer": self.repo / "ios/RailMap/RailMapView.swift",
            "copy": self.repo / "ios/copy-rail-packages.sh",
            "regions": self.repo / "ios/RailMap/RegionCatalog.swift",
            "datum": self.repo / "ios/RailMap/AppleMapDatum.swift",
        }
        # A web-only checkout is a valid subject, not a broken one. Say what
        # went unchecked rather than reporting six missing files as defects.
        if not (self.repo / "ios").is_dir():
            self.issue(
                "INFO", "WEB_ONLY_CHECKOUT",
                "no ios/ here, so the simplify-tolerance, datum-boundary, region and bundle "
                "contracts were NOT checked; run those against the iOS checkout",
            )
            return
        missing = [path for path in paths.values() if not path.is_file()]
        for path in missing:
            self.issue("ERROR", "MISSING_CROSS_PLATFORM_FILE", f"missing {path.relative_to(self.repo)}")
        if missing:
            return

        js_text = paths["js"].read_text(encoding="utf-8")
        swift_text = paths["swift"].read_text(encoding="utf-8")
        renderer_text = paths["renderer"].read_text(encoding="utf-8")
        js_match = re.search(r"SEGMENT_SIMPLIFY_TOLERANCE_PX\s*=\s*([0-9.]+)", js_text)
        swift_match = re.search(r"simplifyTolerance:\s*Double\s*=\s*([0-9.]+)", swift_text)
        if not js_match or not swift_match:
            self.issue("ERROR", "SIMPLIFY_CONTRACT_MISSING", "could not read the Web/Swift simplification constants")
        elif js_match.group(1) != swift_match.group(1):
            self.issue(
                "ERROR", "SIMPLIFY_CONTRACT_MISMATCH",
                f"Web simplifies at {js_match.group(1)} px but iOS at {swift_match.group(1)} px",
            )
        # Equal declarations are not enough — the 2026-08-24 regression lived in
        # the renderer, below every parity fixture.
        if "* RailStyle.simplifyTolerance" not in renderer_text:
            self.issue(
                "ERROR", "SIMPLIFY_RENDERER_DETACHED",
                "RailMapView no longer derives its epsilon from RailStyle.simplifyTolerance",
            )

        copy_text = paths["copy"].read_text(encoding="utf-8")
        region_text = paths["regions"].read_text(encoding="utf-8")
        for country in countries:
            if not re.search(rf"case {re.escape(country)}\b", region_text):
                self.issue("ERROR", "IOS_REGION_MISSING", f"RegionCatalog has no case {country}", country=country)
            if not re.search(rf"\b{re.escape(country)}\b", copy_text):
                self.issue("ERROR", "IOS_COPY_MISSING", f"copy-rail-packages.sh does not mention {country}", country=country)

        for country in discover_countries(self.repo):
            if country not in countries:
                self.issue(
                    "INFO", "PACKAGE_NOT_AUDITED",
                    f"{country}-2025.json exists but was outside this run's --countries scope",
                    country=country,
                )

        datum_text = paths["datum"].read_text(encoding="utf-8")
        datum_match = re.search(r"gcj02Countries[^=]*=\s*\[([^]]*)\]", datum_text)
        if datum_match:
            scope = re.findall(r'"([a-z]{2})"', datum_match.group(1))
            self.issue(
                "INFO", "APPLE_DATUM_SCOPE",
                f"MapKit display correction covers {', '.join(scope) or 'nothing'}; "
                f"every other region is presented in canonical WGS84",
            )

    # -------------------------------------------------------------- reporting

    def result(self) -> dict[str, Any]:
        counts = Counter(issue["severity"] for issue in self.issues)
        return {
            "repo": str(self.repo),
            "packages": self.packages,
            "counts": {level: counts.get(level, 0) for level in ("ERROR", "WARNING", "INFO")},
            "codes": dict(Counter(issue["code"] for issue in self.issues)),
            "issues": self.issues,
            "straightIntervalsByLine": self.straight_lines,
            "limitations": [
                "Structural preflight only: it cannot prove official inventory completeness, "
                "correct topology, surveyed alignment, or what either client actually draws.",
                "STRAIGHT_CHORD, SPARSE_GEOMETRY, VERTEX_JUMP, DETOUR_RATIO, SELF_OVERLAP and REVERSAL_CANDIDATE are "
                "review candidates. Real switchbacks and street loops (Alishan, 木次線 出雲坂根, 영동선) "
                "legitimately trigger DETOUR_RATIO and REVERSAL_CANDIDATE.",
                "STRAIGHT_INTERVAL is also a review candidate, not a defect verdict, and it cannot see "
                "what it is being asked to distinguish: a real dead-straight viaduct or prairie mainline "
                "produces the exact same near-zero-deviation signature as a synthetic straight line copied "
                "station-to-station. It only reads the geometry that shipped -- it has no track elevation, "
                "no source provenance, and cannot tell 'never curved' from 'curve not recorded'. The "
                "jp/tw/hk/kr packages (surveyed, not collinearly densified) do trigger it -- JR Hokkaido's "
                "flat-plain running, TRA's Chianan-plain line, MTR's West Rail viaduct, and KTX/Airport "
                "Railroad express track all carry genuinely straight multi-km chords -- which is the correct "
                "true-positive behaviour this class exists to surface, confirming it is not NA-only wiring, "
                "not a bug specific to `na_geo.densify()`'s output shape, and every finding still needs a "
                "human to look at the actual railway before being called broken.",
                "A clean run is not a PASS for a repair; it only means the contracts this file can "
                "read are intact.",
            ],
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="repository path or a child directory")
    parser.add_argument("--countries", default="", help="comma-separated package codes (default: every package found)")
    parser.add_argument("--json", type=Path, help="write the full report here, or '-' for JSON on stdout")
    parser.add_argument("--limit", type=int, default=25, help="issues printed per severity in text mode")
    parser.add_argument("--strict", action="store_true", help="exit non-zero when review warnings remain")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = find_repo(args.repo)
    countries = [item.strip().lower() for item in args.countries.split(",") if item.strip()]
    if not countries:
        countries = discover_countries(repo)
        if not countries:
            raise SystemExit(f"no packages found under {repo / 'app/public/rail'}")

    audit = Audit(repo)
    for country in countries:
        audit.audit_package(country)
    audit.audit_cross_platform(countries)
    result = audit.result()

    if args.json == Path("-"):
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"JTM package preflight: {repo}")
        for country, summary in result["packages"].items():
            print(
                f"  {country}: v{summary['version']} | {summary['lines']} lines | "
                f"{summary['stationRows']} station rows | {summary['segments']} intervals | "
                f"{summary['vertices']} vertices | {summary['extraSegments']} extra segments"
            )
            print(
                f"      review candidates: {summary['straightChords']} straight/sparse intervals, "
                f"{summary['detours']} detours, {summary['selfOverlap']} self-overlapping lines, "
                f"{summary['reversalCandidates']} reversals, {summary['lengthMismatches']} length disagreements"
            )
            by_line = result["straightIntervalsByLine"].get(country, {})
            if by_line:
                print(
                    f"      STRAIGHT_INTERVAL (chord-deviation, densify()-proof): "
                    f"{summary['straightIntervals']} intervals across {len(by_line)} lines, "
                    f"{summary['straightIntervalKm']:.0f} km total"
                )
                worst_lines = sorted(by_line.items(), key=lambda item: -item[1]["chordKm"])[:5]
                for worst_line_id, entry in worst_lines:
                    worst = entry["worst"] or {}
                    marked = "marked" if entry["markedByPackage"] else "UNMARKED"
                    print(
                        f"        {worst_line_id} [{entry['smoothingProfile']}, {marked}]: "
                        f"{entry['count']} intervals, {entry['chordKm']:.1f} km; worst "
                        f"{worst.get('chordM', 0) / 1000:.2f} km @ {worst.get('deviationM', 0):.1f} m dev "
                        f"({worst.get('stationA')} -> {worst.get('stationB')})"
                    )
                if len(by_line) > 5:
                    print(f"        … {len(by_line) - 5} more lines (use --json for the full per-line ledger)")
        counts = result["counts"]
        print(f"  findings: {counts['ERROR']} errors, {counts['WARNING']} warnings, {counts['INFO']} info")
        for level in ("ERROR", "WARNING", "INFO"):
            issues = [issue for issue in result["issues"] if issue["severity"] == level]
            for issue in issues[: args.limit]:
                subject = "/".join(value for value in (issue.get("country"), issue.get("line")) if value)
                prefix = f" [{subject}]" if subject else ""
                print(f"  {level} {issue['code']}{prefix}: {issue['message']}")
            if len(issues) > args.limit:
                print(f"  … {len(issues) - args.limit} more {level} findings (use --json for the full list)")
        for limitation in result["limitations"]:
            print(f"  limitation: {limitation}")
        if args.json:
            args.json.parent.mkdir(parents=True, exist_ok=True)
            args.json.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if result["counts"]["ERROR"]:
        return 1
    if args.strict and result["counts"]["WARNING"]:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
