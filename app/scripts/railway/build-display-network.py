#!/usr/bin/env python3
"""Build the iOS map's continuous display network from the canonical packages.

The compact-v1 packages remain the source of truth.  This derivative contains
only map-display geometry and station records, with the reviewed shared
corridors and screen-space lanes already applied — the two rules the Web
renderer applies at runtime in `rail-network.js` and which the native app has
no second implementation of.

The native-only St Clair West schematic below is an explicit presentation
exception: the user requested a straight 512 and a separate on-line platform,
while keeping the Line 1 platform and the canonical survey unchanged.

Geometry is NOT cut up.  One blob per region holds every line's display parts
whole as an independently decodable JSON chunk per line (manifest.json records
each line's byte range), so a railway crossing the viewport is one continuous
stroke rather than a run of pieces that happen to abut.  What keeps a national
network off the GPU is the renderer's own viewport cull (`NetworkLOD` plus the
per-interval rect test in `RailMapView`), which is a question about what is on
screen rather than about which square of Web Mercator it fell in, or which
chunk of the region blob it happened to be written into.

Each manifest line also carries `dependsOn`, the sorted list of other line
ids in the same region whose chunks its own display parts `follows` (so a
client that wants to draw one line correctly knows which other chunks to
fetch alongside it).

Usage:
    python3 app/scripts/railway/build-display-network.py \
        --rail-dir app/public/rail \
        --output app/data/raw/na-rail/display-network
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import shutil
import sys
import time
import warnings
from collections import defaultdict
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "lib"))

import display_identity  # noqa: E402
import na_geo  # noqa: E402


FORMAT = "jtm-display-network-v2"

# Overview chunks (spec: size-aware loading) trade precision for bytes at app
# zoom <= 7, where the renderer's own decimation already exceeds this
# tolerance. A region whose full-chunk blob is at or under this many bytes
# loads as one batch ("whole"); a bigger one gets overview chunks appended
# so a national/continental camera can decode a fraction of the geometry.
DEFAULT_SMALL_REGION_MAX_BYTES = 1_500_000
OVERVIEW_SIMPLIFY_TOLERANCE_M = 50.0
OVERVIEW_STATION_MAX_ZOOM = 6

OVERVIEW_QUALIFYING_OPERATORS = {"Amtrak", "Via Rail Canada"}


def line_qualifies_for_overview(entry: dict) -> bool:
    return (
        entry.get("rank", 0) == 0
        or entry.get("minZoomMapLibre", 0) <= 6
        or entry.get("operator") in OVERVIEW_QUALIFYING_OPERATORS
    )


def build_overview_fragment(fragment: dict) -> tuple[dict, int]:
    """The overview variant of one full-chunk fragment (spec A3): parts are
    Douglas-Peucker simplified at ``OVERVIEW_SIMPLIFY_TOLERANCE_M``,
    lane/follow geometry is dropped (sub-pixel at the app zooms overview
    chunks are drawn at), and metre-keyed rows are rescaled by the ratio
    between this fragment's simplified and original total length.
    """
    overview = dict(fragment)
    new_parts = []
    vertex_count = 0
    for part in fragment["parts"]:
        if len(part) < 3:
            simplified = [list(p) for p in part]
        else:
            simplified = na_geo.simplify(part, OVERVIEW_SIMPLIFY_TOLERANCE_M)
        new_parts.append(simplified)
        vertex_count += len(simplified)
    overview["parts"] = new_parts
    overview.pop("laneRows", None)
    overview.pop("follows", None)
    overview.pop("lane", None)
    if "totalMetres" in fragment:
        old_total = fragment["totalMetres"]
        new_total = round(sum(na_geo.line_length(part) for part in new_parts), 1)
        overview["totalMetres"] = new_total
        rescale = (new_total / old_total) if old_total > 0 else 0.0
        if "withheld" in fragment:
            overview["withheld"] = [
                [
                    min(max(0.0, round(span[0] * rescale, 1)), new_total),
                    min(max(0.0, round(span[1] * rescale, 1)), new_total),
                ]
                for span in fragment["withheld"]
            ]
        if "familyWindows" in fragment:
            overview["familyWindows"] = [
                [
                    min(max(0.0, round(window[0] * rescale, 1)), new_total),
                    min(max(0.0, round(window[1] * rescale, 1)), new_total),
                    window[2], window[3],
                ]
                for window in fragment["familyWindows"]
            ]
    return overview, vertex_count
STATIONS_FORMAT = "jtm-display-stations-v2"
REPORT_FORMAT = "jtm-display-network-report-v2"
SHARED_CORRIDOR_FORMAT = "jtm-shared-corridors-v1"
DISPLAY_LANES_FORMAT = "jtm-display-lanes-v1"
NA_RENDER_GROUPS_FORMAT = "jtm-na-render-groups-v2"
# v1 used `groups`; v2 renamed it `families` (adds `networkId`/`mode` per
# family, and a structured `colorSource` citation). Read for one release so a
# checkout mid-migration does not fail closed.
NA_RENDER_GROUPS_FORMAT_DEPRECATED = "jtm-na-render-groups-v1"
# Same v2 document schema as na-render-groups.json (scope / policy / evidence
# / byLineId / families-with-networkId-and-mode), a different reviewed
# policy: see jp-render-groups.json's own `policy.why`. Held in its own file
# and its own format string so neither review can inherit the other's
# default by accident — matches build-display-lanes.mjs's RENDER_GROUP_FORMATS.
JP_RENDER_GROUPS_FORMAT = "jtm-jp-render-groups-v2"
RENDER_GROUP_POLICY_FORMATS = frozenset({
    NA_RENDER_GROUPS_FORMAT, NA_RENDER_GROUPS_FORMAT_DEPRECATED, JP_RENDER_GROUPS_FORMAT,
})
# One entry per reviewed render-group policy file. Each doc claims the
# regions it governs in its own `scope` (build-display-lanes.mjs reads the
# same two files the same way); a region absent from every policy's `scope`
# simply never gets a family palette, the same tolerance the single-file
# reader always had.
RENDER_GROUP_POLICY_FILENAMES = ("na-render-groups.json", "jp-render-groups.json")
REGIONS = ("jp", "tw", "hk", "mo", "kr", "us", "ca")
# Regions whose railways the native map draws as ONE continuous stroke per
# chain of intervals, with the screen-space lane offset and corner rounding
# baked into the geometry on device (RailCore ContinuousStroke, the port of
# rail-stroke.js). Their fragments carry the reviewed lane rows in metres and
# each platform carries the vertex it sits on, instead of the geometry being
# cut into per-lane pieces here. Must agree with rail-network.js's
# CONTINUOUS_STROKE_COUNTRIES.
CONTINUOUS_STROKE_REGIONS = frozenset({"us", "ca", "jp"})
# Slot 8 of a `partsByRegion` row (build-display-lanes.mjs): that display
# part's withheld spans, measured by rail-network.js on the part's own final
# vertices. Read rather than re-derived — see `web_withheld_spans`.
WITHHELD_SPANS_SLOT = 8
EPSILON = 1e-12
# rail-network.js's lane ramp, to the constant. A lane change is a drift, not a
# step: the ramp is long enough to be a shallow diagonal, and each step across
# it is a quarter of a lane — under a pixel at the scales lanes draw at, so the
# fragments either side of a step land on the same ink.
LANE_RAMP_METRES_PER_LANE = 300.0
LANE_RAMP_MAX_METRES = 900.0
LANE_RAMP_QUANTUM = 0.25
LANE_PLATEAU_MIN_METRES = 60.0


def decoded_intervals(line: dict) -> list[list[list[float]]]:
    stations = line.get("stations") or []
    if not stations:
        return []
    intervals = []
    previous = None
    for index, row in enumerate(line.get("segments") or []):
        coordinates = [list(point) for point in row[2]]
        if row[1]:
            coordinates.insert(0, previous or (coordinates[0] if coordinates else [0, 0]))
        if not coordinates:
            intervals.append([])
            continue
        start = stations[index % len(stations)]
        end = stations[(index + 1) % len(stations)]
        coordinates[0] = [start[2], start[3]]
        coordinates[-1] = [end[2], end[3]]
        previous = coordinates[-1]
        intervals.append(coordinates)
    return intervals


def length_min_zoom(km: float) -> int:
    if km >= 150:
        return 3
    if km >= 70:
        return 4
    if km >= 30:
        return 5
    if km >= 12:
        return 6
    return 7


def wide_min_zoom(km: float) -> int:
    if km >= 300:
        return 3
    if km >= 120:
        return 4
    if km >= 50:
        return 5
    if km >= 20:
        return 6
    return 7


def station_density_min_zoom(line: dict, line_min: int) -> int:
    """Port of Visibility.stationMinZoomByLineId."""
    count = len(line.get("stations") or [])
    km = sum(float(row[0]) for row in line.get("segments") or [])
    if count < 2 or km <= 0:
        return line_min
    spacing = km / (count - 1)
    station_lod_k = (22.0 * 40075.017) / (256.0 * math.cos(math.radians(35.0)))
    # JavaScript Math.round: ties go toward +infinity, unlike Python's bankers rounding.
    density = math.floor(math.log2(station_lod_k / spacing) + 0.5)
    return min(14, max(line_min, density))


def utf16_key(value: str) -> bytes:
    return value.encode("utf-16-be", "surrogatepass")


def equirectangular_metres(a: dict, b: dict) -> float:
    lat = math.radians((a["lat"] + b["lat"]) / 2)
    dx = math.radians(b["lon"] - a["lon"]) * math.cos(lat)
    dy = math.radians(b["lat"] - a["lat"])
    return math.hypot(dx, dy) * 6_371_008.8


def label_winners(stations: list[dict]) -> set[str]:
    by_group: dict[str, dict] = {}
    for station in stations:
        group = station["stationCode"] or f"solo:{station['id']}"
        held = by_group.get(group)
        if held is None or (station["lodMinZoomMapLibre"], utf16_key(station["id"])) < (
            held["lodMinZoomMapLibre"], utf16_key(held["id"])
        ):
            by_group[group] = station
    elected = sorted(
        by_group.values(),
        key=lambda item: (item["lodMinZoomMapLibre"], utf16_key(item["id"])),
    )
    accepted: list[dict] = []
    winners: set[str] = set()
    for station in elected:
        duplicate = any(
            utf16_key(other["name"]) == utf16_key(station["name"])
            and equirectangular_metres(other, station) <= 600.0
            for other in accepted
        )
        if not duplicate:
            accepted.append(station)
            winners.add(station["id"])
    return winners


def compact_json(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def line_length_metres(points: list[list[float]]) -> float:
    return sum(
        equirectangular_metres(
            {"lon": first[0], "lat": first[1]},
            {"lon": second[0], "lat": second[1]},
        )
        for first, second in zip(points, points[1:])
    )


def lane_measure_metres(first: list[float], second: list[float]) -> float:
    """rail-network.js's equirectangular metre: 111320 on BOTH axes.

    A lane row is a pair of measures along a stroke that each renderer
    re-measures for itself, so every ruler that reads one has to be the same
    ruler. The general-purpose metre above is a haversine radius and reads
    0.1125% shorter everywhere, which on a long line walks a lane boundary
    hundreds of metres away from where the Web map puts it.
    """
    lat = math.radians((first[1] + second[1]) / 2)
    return math.hypot(
        (second[0] - first[0]) * 111320.0 * math.cos(lat),
        (second[1] - first[1]) * 111320.0,
    )


def lane_measure_length(points: list[list[float]]) -> float:
    return sum(
        lane_measure_metres(first, second)
        for first, second in zip(points, points[1:])
    )


def lane_plateaus(rows: list[list], total: float) -> list[list[float]]:
    """The stretches a part holds one lane over, in order and touching."""
    plateaus: list[list[float]] = []
    cursor = 0.0
    for row in sorted(rows, key=lambda row: float(row[2])):
        start = max(cursor, min(float(row[2]), total))
        end = max(start, min(float(row[3]), total))
        if start > cursor:
            plateaus.append([cursor, start, 0.0])
        if end > start:
            plateaus.append([start, end, float(row[4])])
        cursor = end
    if cursor < total:
        plateaus.append([cursor, total, 0.0])
    return coalesce_lane_plateaus(plateaus)


def coalesce_lane_plateaus(plateaus: list[list[float]]) -> list[list[float]]:
    """Absorb stretches too short to be evidence, then join what now agrees.

    Rows are measured to a tenth of a metre against a part length recomputed
    downstream, so a row covering a whole part still ends short of it. Left
    alone that remainder is a plateau, and a plateau is a lane change.
    """
    held = [list(plateau) for plateau in plateaus]
    while len(held) >= 2:
        at = -1
        for index, plateau in enumerate(held):
            span = plateau[1] - plateau[0]
            if span >= LANE_PLATEAU_MIN_METRES:
                continue
            if at < 0 or span < held[at][1] - held[at][0]:
                at = index
        if at < 0:
            break
        previous = held[at - 1] if at else None
        following = held[at + 1] if at + 1 < len(held) else None
        if previous is not None and (
            following is None
            or previous[1] - previous[0] >= following[1] - following[0]
        ):
            previous[1] = held[at][1]
        else:
            following[0] = held[at][0]
        held.pop(at)
    result: list[list[float]] = []
    for plateau in held:
        if result and result[-1][2] == plateau[2]:
            result[-1][1] = plateau[1]
        else:
            result.append(list(plateau))
    return result


def lane_ramp_room(before: list[float], after: list[float]) -> float:
    """Length a change between two plateaus may borrow — half from each side."""
    delta = abs(after[2] - before[2])
    if not delta:
        return 0.0
    return min(
        LANE_RAMP_MAX_METRES,
        LANE_RAMP_METRES_PER_LANE * delta,
        (before[1] - before[0]) / 1.5,
        (after[1] - after[0]) / 1.5,
    )


def lane_ramp_steps(
    before: list[float], after: list[float], room: float,
) -> list[tuple[float, float, float]]:
    delta = after[2] - before[2]
    if not delta or room <= 1:
        return []
    steps = max(1, round(abs(delta) / LANE_RAMP_QUANTUM))
    start = before[1] - room / 2
    return [
        (
            start + (step * room) / steps,
            start + ((step + 1) * room) / steps,
            before[2] + (delta * (step + 1)) / steps,
        )
        for step in range(steps)
    ]


def ramped_lane_rows(rows: list[list], total: float) -> list[tuple[float, float, float]]:
    """The whole part's lane profile: plateaus trimmed back for their ramps."""
    plateaus = lane_plateaus(rows, total)
    if len(plateaus) < 2:
        return [(plateau[0], plateau[1], plateau[2]) for plateau in plateaus]
    result: list[tuple[float, float, float]] = []
    for index, plateau in enumerate(plateaus):
        previous = plateaus[index - 1] if index else None
        following = plateaus[index + 1] if index + 1 < len(plateaus) else None
        head = lane_ramp_room(previous, plateau) if previous is not None else 0.0
        tail = lane_ramp_room(plateau, following) if following is not None else 0.0
        start = plateau[0] + head / 2
        end = plateau[1] - tail / 2
        if end > start:
            result.append((start, end, plateau[2]))
        if following is not None:
            result.extend(lane_ramp_steps(plateau, following, tail))
    # A ramp ends ON the lane it was heading for, so its last step and the
    # plateau it runs into are one stretch.
    joined: list[tuple[float, float, float]] = []
    for start, end, lane in result:
        if joined and joined[-1][2] == lane:
            joined[-1] = (joined[-1][0], end, lane)
        else:
            joined.append((start, end, lane))
    return joined


def split_intervals_by_lane(
    intervals: list[list[list[float]]], rows: list[list],
) -> list[tuple[float, list[list[float]]]]:
    """Split ordered interval geometry wherever its screen-space lane changes.

    Lane rows use the cumulative measure of display part 0. Current reviewed
    data has 99% of its rows on that main part; nonzero part rows are retained
    in the Web renderer and deliberately not guessed onto native tile branches.
    """
    total = sum(lane_measure_length(interval) for interval in intervals)
    profile = ramped_lane_rows([row for row in rows if int(row[1]) == 0], total)
    if not profile:
        return [(0.0, interval) for interval in intervals if len(interval) >= 2]
    boundaries = sorted({
        max(0.0, min(total, value))
        for start, end, _ in profile for value in (start, end)
    })

    profile_start, profile_end = profile[0][0], profile[-1][1]

    def lane_at(measure: float) -> float:
        # The profile covers the part end to end, so anything outside it is
        # float drift in the running measure — a metre of accumulated rounding
        # at the far end of a transcontinental line. Reading that as lane zero
        # left a stub fragment on the centreline after the stroke had already
        # been drawn in its lane.
        held = min(max(measure, profile_start), profile_end)
        return next((lane for start, end, lane in profile
                     if start <= held <= end), 0.0)

    pieces: list[tuple[float, list[list[float]]]] = []
    measure = 0.0
    for interval in intervals:
        current_lane = None
        current: list[list[float]] = []
        for first, second in zip(interval, interval[1:]):
            length = lane_measure_metres(first, second)
            if length <= EPSILON:
                continue
            cuts = [measure]
            cuts.extend(value for value in boundaries if measure < value < measure + length)
            cuts.append(measure + length)
            for start, end in zip(cuts, cuts[1:]):
                lane = lane_at((start + end) / 2)
                start_ratio = (start - measure) / length
                end_ratio = (end - measure) / length
                a = [
                    first[0] + (second[0] - first[0]) * start_ratio,
                    first[1] + (second[1] - first[1]) * start_ratio,
                ]
                b = [
                    first[0] + (second[0] - first[0]) * end_ratio,
                    first[1] + (second[1] - first[1]) * end_ratio,
                ]
                if current_lane != lane:
                    if len(current) >= 2:
                        pieces.append((float(current_lane), current))
                    current_lane, current = lane, [a, b]
                else:
                    append_distinct(current, [a, b])
            measure += length
        if len(current) >= 2:
            pieces.append((float(current_lane), current))
    return pieces


def merged_withheld_spans(spans: list[list[float]]) -> list[list[float]]:
    """Collapse touching `[from, to]` spans into one, in metre order.

    Two intervals the alignment gate withheld back to back produce two spans
    that share an exact boundary (the shared station anchor); merging them is
    what keeps the dashed overlay one run rather than two abutting ones, the
    same shape rail-network.js's own vertex-tagging produces on the web.
    """
    if not spans:
        return spans
    merged = [list(spans[0])]
    for low, high in spans[1:]:
        if abs(low - merged[-1][1]) <= EPSILON:
            merged[-1][1] = high
        else:
            merged.append([low, high])
    return merged


def continuous_chains(
    intervals: list[list[list[float]]], withheld: set[int],
) -> list[dict]:
    """Group intervals into chains drawn as one uninterrupted stroke.

    A blocked interval (`withheld`) no longer splits the chain: the geometry
    is real, only held back from the official-alignment comparison, so it is
    drawn through like any other interval and its own span is recorded in
    `withheld` — metres in the CHAIN's own measure space, the same ruler
    `laneRows`/`totalMetres` use — for the renderer to dash instead of cut.
    This is the same choice rail-network.js's `displayPartsForLine` makes for
    the web (see `bridgeBlockedIntervals` there); the two must keep matching
    part-for-part or a chain here and its web display part would disagree
    about how many pieces one railway is.

    Only a geometrically empty interval (`len(interval) < 2`, meaning there is
    nothing at all to draw) still breaks the chain — the one splitter this
    function ever had besides the alignment gate, and untouched here.
    """
    chains: list[dict] = []
    measure = 0.0
    current: dict | None = None
    for index, interval in enumerate(intervals):
        length = lane_measure_length(interval)
        if len(interval) < 2:
            if current is not None:
                chains.append(current)
                current = None
            measure += length
            continue
        if current is None:
            current = {
                "firstInterval": index, "startMetres": measure,
                "parts": [], "polyline": [], "anchorIndexByStation": {},
                "withheld": [], "withheldIntervals": set(),
            }
            current["anchorIndexByStation"][index] = 0
            current["polyline"].extend(list(point) for point in interval)
        else:
            current["polyline"].extend(list(point) for point in interval[1:])
        interval_start = measure
        current["parts"].append(interval)
        current["anchorIndexByStation"][index + 1] = len(current["polyline"]) - 1
        measure += length
        current["endMetres"] = measure
        if index in withheld:
            current["withheld"].append([
                round(interval_start - current["startMetres"], 1),
                round(measure - current["startMetres"], 1),
            ])
            current["withheldIntervals"].add(index)
    if current is not None:
        chains.append(current)
    # The web's display part index this chain corresponds to: bridging means
    # the alignment gate no longer opens a new part on its own, so a chain's
    # position in this list IS its web part index (the only other splitter,
    # a geometrically empty interval, still numbers its chains the same way
    # the web's own `flush()` does — sequentially, in order).
    for index, chain in enumerate(chains):
        chain["partIndex"] = index
        chain["withheld"] = merged_withheld_spans(chain["withheld"])
    return chains


def chain_from_interval_range(
    intervals: list[list[list[float]]], first: int, last: int, withheld: set[int],
) -> dict:
    """One chain built from a KNOWN, contiguous range of raw intervals.

    This is the reconstruction for a `partsByRegion` "plain" row (see
    `chains_from_parts_rows`): the web's displayPartsForLine reduced that
    part to nothing more than intervals `first..last` concatenated in order,
    so redoing exactly that concatenation here — the same
    continuesFromPrevious rule `continuous_chains` uses, just scoped to a
    known range instead of discovered by scanning for empty intervals —
    reproduces the same chain, measured on this module's own ruler.

    The `withheld` spans it accumulates are the FALLBACK measure, kept for a
    display-lanes.json that predates the row's slot 8, and the record of
    WHICH intervals this part places (`withheldIntervals`) for the caller's
    coverage check. They are measured over the raw intervals, which are the
    geometry before grooming and station-approach rebuilding shorten it, so
    where slot 8 is present the caller replaces them with the web's own —
    see `web_withheld_spans`.
    """
    chain: dict = {
        "firstInterval": first, "startMetres": 0.0,
        "parts": [], "polyline": [], "anchorIndexByStation": {},
        "withheld": [], "withheldIntervals": set(),
    }
    measure = 0.0
    for index in range(first, last + 1):
        interval = intervals[index]
        length = lane_measure_length(interval)
        if index == first:
            chain["anchorIndexByStation"][index] = 0
            chain["polyline"].extend(list(point) for point in interval)
        else:
            chain["polyline"].extend(list(point) for point in interval[1:])
        interval_start = measure
        chain["parts"].append(interval)
        chain["anchorIndexByStation"][index + 1] = len(chain["polyline"]) - 1
        measure += length
        chain["endMetres"] = measure
        if index in withheld:
            chain["withheld"].append([round(interval_start, 1), round(measure, 1)])
            chain["withheldIntervals"].add(index)
    chain["withheld"] = merged_withheld_spans(chain["withheld"])
    return chain


def anchor_indices_for_polyline(
    stations: list[list], polyline: list[list[float]],
) -> dict[int, int]:
    """Station index -> polyline vertex index, by exact coordinate match.

    Used only for a fallback (embedded-geometry) chain, where there is no
    interval index to derive `anchorIndexByStation` from directly. A vertex
    that matches more than one station is left out rather than guessed — the
    station simply gets no `slot` from this chain, the same graceful gap the
    caller already tolerates for a chain that never reaches a given station
    at all (and which the caller's own fail-closed fallback — nearest vertex
    within 1 m, across every chain the line has — closes for real).

    A station matched by more than one VERTEX is normally the same gap, with
    one deliberate exception: a closed loop's embedded polyline repeats its
    first vertex as its last (the wrap seam), so the loop's seam station
    matches both index 0 and the final index. That is not ambiguity, just
    the loop closing on itself, so the seam station is anchored to the
    chain's own start.
    """
    by_key: dict[tuple[float, float], list[int]] = defaultdict(list)
    for vertex_index, point in enumerate(polyline):
        by_key[(point[0], point[1])].append(vertex_index)
    last_vertex = len(polyline) - 1
    out: dict[int, int] = {}
    for station_index, row in enumerate(stations):
        matches = by_key.get((row[2], row[3]))
        if not matches:
            continue
        if len(matches) == 1:
            out[station_index] = matches[0]
        elif set(matches) == {0, last_vertex}:
            out[station_index] = 0
    return out


def withheld_spans_for_embedded(
    polyline: list[list[float]], anchors: dict[int, int], withheld: set[int],
) -> tuple[list[list[float]], set[int]]:
    """The blocked intervals this embedded part carries, as metre spans.

    A fallback row has no raw-interval range to accumulate against (that is
    what made it a fallback), so the spans are read off the part's OWN
    vertices instead: interval `i` runs station `i` to station `i + 1`, both
    of which `anchor_indices_for_polyline` has already located in this
    polyline, so the stretch between those two vertices IS that interval as
    this part finally draws it.

    rail-network.js reaches the same spans from the other side — it tags the
    VERTICES a blocked interval contributed (`currentWithheldKeys`) and runs
    `withheldSpansForPart` over them — and the two agree to well under the
    0.1 m this rounds to on every shipped line that has both (pinned by the
    `withheld` case in display-parts.json). That agreement is why this stayed
    a re-derivation while the plain path's did not: both measure the part's
    final vertices, so both get the web's answer. Where the row carries slot
    8 the web's answer is used directly regardless (`web_withheld_spans`) and
    what this still supplies alone is `placed` — which intervals the part
    reaches, for the caller's coverage check. Vertex tagging is the more
    general of the two: it also survives a retrace laying an interval down
    twice, an excursion copying it into a branch, and grooming splitting one
    run into two. None of those occur on any shipped package today, and the
    caller fails the build rather than guessing if one ever does — see the
    coverage check where chains are built.

    Returns the spans and the interval indices actually placed, so that
    caller can tell "this part does not reach that interval" (ordinary, for
    a line the web cut into several parts) from "nothing placed it at all"
    (a silent release, which is the bug this function exists to close).
    """
    if not withheld:
        return [], set()
    measures = [0.0]
    for first, second in zip(polyline, polyline[1:]):
        measures.append(measures[-1] + lane_measure_metres(first, second))
    last_vertex = len(polyline) - 1
    closed = last_vertex > 0 and polyline[0] == polyline[last_vertex]
    spans: list[list[float]] = []
    placed: set[int] = set()
    for index in sorted(withheld):
        start_vertex, end_vertex = anchors.get(index), anchors.get(index + 1)
        if start_vertex is None or end_vertex is None:
            continue
        # A closed loop's seam station is anchored to the chain's START (see
        # `anchor_indices_for_polyline`), so the interval that ENDS on the
        # seam would otherwise read backwards over the whole ring.
        if closed and end_vertex == 0 and start_vertex > 0:
            end_vertex = last_vertex
        low, high = sorted((start_vertex, end_vertex))
        if low == high:
            continue
        spans.append([round(measures[low], 1), round(measures[high], 1)])
        placed.add(index)
    return merged_withheld_spans(sorted(spans)), placed


def chain_from_embedded_coordinates(
    coordinates: list[list[float]], stations: list[list], withheld: set[int],
) -> dict:
    """One chain built directly from a `partsByRegion` fallback row's own
    embedded vertex coordinates — the part's true, final geometry, copied
    out of rail-network.js's displayPartsForLine rather than re-derived from
    raw intervals (which a branch lead-in, a retrace's partial interval, or
    a loop's wrap seam cannot faithfully give). Measured on this module's
    own ruler, same as every other chain.

    Its blocked intervals are located on those same vertices rather than
    dropped: a fallback row used to hand back an empty `withheld`, which
    drew a stretch the alignment gate had REFUSED to confirm as a solid
    line — the map asserting surveyed track it does not have, and the one
    failure mode a dashed overlay exists to prevent.
    """
    polyline = [list(point) for point in coordinates]
    anchors = anchor_indices_for_polyline(stations, polyline)
    spans, placed = withheld_spans_for_embedded(polyline, anchors, withheld)
    return {
        "firstInterval": None, "startMetres": 0.0, "endMetres": lane_measure_length(polyline),
        "parts": [polyline], "polyline": polyline,
        "anchorIndexByStation": anchors,
        "withheld": spans, "withheldIntervals": placed,
    }


def web_withheld_spans(row: list) -> list[list[float]] | None:
    """A `partsByRegion` row's withheld spans, as rail-network.js measured them.

    The web is the authority on where a dashed span starts and ends, and it
    is the only side that can be: `withheldSpansForPart` measures on the
    part's FINAL vertices, after grooming and station-approach rebuilding
    have already changed the geometry's length. Both re-derivations in this
    module measure something else. `chain_from_embedded_coordinates` gets
    the same answer anyway, because a fallback row hands it those very
    vertices — the two agree to 0.0 m on every shipped part. But
    `chain_from_interval_range` accumulates RAW interval lengths, which are
    the lengths BEFORE grooming, and on the shipped packages that put eight
    parts' dash edges up to 647 m from the web's (us|amtrak-silver-meteor
    part 0). Reading the spans closes both paths at once, the same way
    `strokeExcludedByRegion`, `reversedLoopParts` and
    `releasedIntervalsByRegion` are read here rather than re-derived.

    Returns None — not `[]` — for a row that predates the slot, so a stale
    display-lanes.json falls back to re-deriving (loudly) instead of
    silently releasing every dashed span in the region.
    """
    if len(row) <= WITHHELD_SPANS_SLOT:
        return None
    spans = row[WITHHELD_SPANS_SLOT]
    if spans is None:
        return None
    # Rounded and merged on arrival, so a span coming from the web is the
    # same shape on disk as one this module still derives for itself: the
    # web tags vertices and does not merge, and a survives-grooming vertex
    # in the middle of a withheld run splits one span into two abutting ones
    # there (see `merged_withheld_spans`).
    return merged_withheld_spans(
        sorted([round(float(low), 1), round(float(high), 1)]
               for low, high in spans))


def chains_from_parts_rows(
    rows: list[list], intervals: list[list[list[float]]], stations: list[list],
    withheld: set[int], line_id: str, region: str,
) -> list[dict]:
    """Build one line's chains from its `partsByRegion` rows — one native
    chain per web display part, in partIndex order, guaranteeing the two
    always agree on how many parts the line has (see the file the rows come
    from, build-display-lanes.mjs, for the encoding). A row's own partIndex
    must already run 0..N-1 with no gaps (checked by the caller before this
    is called); a malformed interval range inside a "plain" row is treated
    as data corruption, not a hint to guess from, and raises.
    """
    chains: list[dict] = []
    for row in rows:
        part_index = int(row[1])
        first_interval, last_interval = int(row[2]), int(row[3])
        if first_interval < 0:
            if len(row) < 8 or not row[7]:
                raise RuntimeError(
                    f"{region}|{line_id}: partsByRegion part {part_index} "
                    f"(kind={row[6] if len(row) > 6 else '?'!r}) carries no "
                    "embedded geometry to build its chain from")
            chain = chain_from_embedded_coordinates(row[7], stations, withheld)
        else:
            if last_interval < first_interval or last_interval >= len(intervals):
                raise RuntimeError(
                    f"{region}|{line_id}: partsByRegion part {part_index} names "
                    f"interval range [{first_interval}, {last_interval}] outside "
                    f"its {len(intervals)} intervals")
            chain = chain_from_interval_range(intervals, first_interval, last_interval, withheld)
        chain["partIndex"] = part_index
        # The web's own measure of this part's dashed spans wins where the
        # row carries it. What is NOT taken from the row is which raw
        # intervals the part places: that stays this module's own answer,
        # because it is what the fail-closed coverage check below reads, and
        # a metre span cannot be turned back into an interval index. The two
        # must therefore at least agree on WHETHER this part draws blocked
        # track — if they don't, one of them would draw dashed exactly where
        # the other draws solid, and neither answer is safe to prefer.
        spans = web_withheld_spans(row)
        chain["webWithheldSpans"] = spans is not None
        if spans is not None:
            if bool(spans) != bool(chain["withheld"]):
                raise RuntimeError(
                    f"{region}|{line_id}: partsByRegion part {part_index} and this "
                    f"module disagree about whether the alignment gate blocked any "
                    f"track this part draws (display-lanes.json: {len(spans)} span(s), "
                    f"rebuilt here: {len(chain['withheld'])}). One of them would draw "
                    "dashed exactly where the other draws solid, so the disagreement "
                    "itself is the thing to fix — a display-lanes.json built against "
                    "a different revision of this region's package is the usual cause")
            chain["withheld"] = spans
        chains.append(chain)
    # Fail closed on a released withheld interval. A blocked interval the
    # alignment gate held back must reach the renderer as a dashed span on
    # SOME part of this line; a part that does not carry it is ordinary (the
    # web cut this line in several places and the interval lives on one of
    # them), but no part carrying it at all means the flag was silently
    # dropped and that stretch would draw as a solid, confident line over
    # track nobody confirmed. Drawing it dashed is honest; drawing it solid
    # is a false claim, so this raises rather than shipping the picture.
    placed: set[int] = set()
    for chain in chains:
        placed |= chain.get("withheldIntervals") or set()
    unplaced = sorted(index for index in withheld if index < len(intervals))
    unplaced = [index for index in unplaced if index not in placed]
    if unplaced:
        raise RuntimeError(
            f"{region}|{line_id}: display-blocked interval(s) {unplaced!r} are "
            f"carried by none of this line's {len(chains)} display part(s), so "
            "the alignment gate's verdict would be lost and the stretch would "
            "draw solid. A part built from embedded geometry places them by "
            "station anchor (see `withheld_spans_for_embedded`); one that "
            "cannot means this line's parts and its station list disagree")
    return chains


def chain_follow_rows(
    follows: list[list], chain: dict, chains_by_line: dict[str, list[dict]],
    region: str, line_id: str = "?",
) -> list[list]:
    """The follow rows of this chain's web display part, clipped to the chain.

    A follow names the canonical PART and measures along it (reversed when
    the two are digitised against each other). Rows are measured from their
    part's own start, and a part is a chain here (see `continuous_chains` /
    `chains_from_parts_rows`), so the canonical part index names the
    canonical chain directly and its measures need no re-basing.

    A follow whose canonical chain does not exist used to be silently
    dropped — the same shape of bug `chains_from_parts_rows` exists to close
    for a line's OWN parts, just on the canonical side instead. Every
    canonical line's chains are built before any follow is resolved (see the
    caller), so a genuine gap here means the canonical line's own chain list
    disagrees with what this row expects, and that is exactly the kind of
    silent mismatch worth raising loudly over rather than quietly drawing
    one railway a lane short.
    """
    total = chain.get("endMetres", chain["startMetres"]) - chain["startMetres"]
    out: list[list] = []
    for row in follows:
        if int(row[1]) != chain.get("partIndex", 0):
            continue
        low = max(0.0, float(row[2]))
        high = min(total, float(row[3]))
        if high - low <= EPSILON:
            continue
        span = float(row[3]) - float(row[2])
        if span <= EPSILON:
            continue
        canon_from = float(row[6]) + (low - float(row[2])) / span * (float(row[7]) - float(row[6]))
        canon_to = float(row[6]) + (high - float(row[2])) / span * (float(row[7]) - float(row[6]))
        canon_chains = chains_by_line.get(str(row[4]), [])
        canon_index = int(row[5])
        if (
            canon_index < 0
            or canon_index >= len(canon_chains)
            or canon_chains[canon_index].get("partIndex", 0) != canon_index
        ):
            raise RuntimeError(
                f"{region}|{line_id}: follow row {row!r} names canonical "
                f"{row[4]!r} partIndex {canon_index}, which has no matching "
                f"chain (canonical line has {len(canon_chains)} chains)")
        out.append([
            round(low, 1), round(high, 1),
            f"{region}|{row[4]}", canon_index,
            round(canon_from, 1), round(canon_to, 1),
        ])
    return out


def chain_lane_rows(rows: list[list], chain: dict) -> list[list[float]]:
    """The reviewed lane rows of this chain's web display part, clipped to it.

    Rows are keyed by the web's display part and measured from that part's
    start. A line without withheld intervals is one part, and only part 0
    is honoured; a line the alignment gate split is split at the same
    intervals here, so part k is chain k and its rows are already relative
    to the chain.
    """
    total = chain.get("endMetres", chain["startMetres"]) - chain["startMetres"]
    out: list[list[float]] = []
    for row in rows:
        if int(row[1]) != chain.get("partIndex", 0):
            continue
        low = max(0.0, float(row[2]))
        high = min(total, float(row[3]))
        if high - low <= EPSILON:
            continue
        out.append([round(low, 1), round(high, 1), float(row[4])])
    return out


def chain_family_windows(
    rows: list[list], chain: dict, group_colors: dict[str, dict],
    region: str, line_id: str,
) -> list[list]:
    """The family-collapse windows of this chain's web display part, clipped
    to it — mirrors `chain_lane_rows`/`chain_follow_rows`.

    Rows are `[lineId, partIndex, fromMetres, toMetres, role, groupId]`
    (`familyWindowsByRegion`, the web agent's `display-lanes.json`). `role`
    0 is the landlord: this chain draws the shared family stroke over the
    window, in the family colour. `role` 1 is the tenant: this chain's own
    stroke is withheld over the window (it is still built whole, for rides
    and playback — only what the network overlay DRAWS there changes). A
    window naming a group `na-render-groups.json` gives no colour is a real
    disagreement between the reviewed policy and the lane artefact, not
    something to silently draw in the wrong colour, so it raises — the same
    fail-closed rule `chains_from_parts_rows`'s orphan-partIndex check uses.
    """
    total = chain.get("endMetres", chain["startMetres"]) - chain["startMetres"]
    out: list[list] = []
    for row in rows:
        if int(row[1]) != chain.get("partIndex", 0):
            continue
        low = max(0.0, float(row[2]))
        high = min(total, float(row[3]))
        if high - low <= EPSILON:
            continue
        role = int(row[4])
        if role not in (0, 1):
            raise RuntimeError(
                f"{region}|{line_id}: family window row {row!r} has role "
                f"{role!r}, expected 0 (landlord) or 1 (tenant)")
        group_id = str(row[5])
        if group_id not in group_colors:
            raise RuntimeError(
                f"{region}|{line_id}: family window row {row!r} names group "
                f"{group_id!r} with no colour in na-render-groups.json")
        out.append([round(low, 1), round(high, 1), role, group_id])
    return out


def point_segment_projection(
    point: list[float], first: list[float], second: list[float],
) -> tuple[float, float]:
    latitude = math.radians((first[1] + second[1] + point[1]) / 3)
    scale = max(0.01, math.cos(latitude))
    dx = (second[0] - first[0]) * scale
    dy = second[1] - first[1]
    px = (point[0] - first[0]) * scale
    py = point[1] - first[1]
    denominator = dx * dx + dy * dy
    ratio = min(1.0, max(0.0, (px * dx + py * dy) / denominator)) \
        if denominator > EPSILON else 0.0
    projected = [
        first[0] + (second[0] - first[0]) * ratio,
        first[1] + (second[1] - first[1]) * ratio,
    ]
    distance = equirectangular_metres(
        {"lon": point[0], "lat": point[1]},
        {"lon": projected[0], "lat": projected[1]})
    return distance, ratio


def station_lane(
    point: list[float], pieces: list[tuple[float, list[list[float]]]],
) -> tuple[float, float] | None:
    best = None
    for lane, coordinates in pieces:
        if not lane:
            continue
        for first, second in zip(coordinates, coordinates[1:]):
            distance, _ = point_segment_projection(point, first, second)
            if best is None or distance < best[0]:
                latitude = math.radians((first[1] + second[1]) / 2)
                east = (second[0] - first[0]) * math.cos(latitude)
                north = second[1] - first[1]
                bearing = (math.degrees(math.atan2(east, north)) + 360) % 360
                best = (distance, lane, bearing)
    if best is None or best[0] > 200:
        return None
    return best[1], best[2]


def append_distinct(points: list[list[float]], additions: list[list[float]]) -> None:
    for point in additions:
        if not points or points[-1] != point:
            points.append(list(point))


def closest_vertex(
    points: list[list[float]], wanted: list[float], maximum_metres: float,
) -> int:
    distances = [
        equirectangular_metres(
            {"lon": point[0], "lat": point[1]},
            {"lon": wanted[0], "lat": wanted[1]},
        )
        for point in points
    ]
    index = min(range(len(points)), key=distances.__getitem__)
    if distances[index] > maximum_metres:
        raise RuntimeError(
            f"reviewed shared-corridor cut moved {distances[index]:.1f} m "
            f"(limit {maximum_metres:.1f} m)")
    return index


def station_row(line: dict, station_code: str) -> list:
    rows = [row for row in line.get("stations") or [] if row[0] == station_code]
    if len(rows) != 1:
        raise RuntimeError(
            f"{line['id']}: shared corridor expected one station "
            f"{station_code!r}, found {len(rows)}")
    return rows[0]


def interval_for_station_pair(
    line: dict, station_codes: list[str], required: bool = True,
) -> tuple[int, bool] | None:
    """Return the unique interval and whether it runs in registry order."""
    wanted = tuple(station_codes)
    matches = []
    stations = line.get("stations") or []
    interval_count = len(line.get("segments") or [])
    for index in range(interval_count):
        pair = (stations[index][0], stations[(index + 1) % len(stations)][0])
        if pair == wanted:
            matches.append((index, True))
        elif pair == tuple(reversed(wanted)):
            matches.append((index, False))
    if not matches and not required:
        return None
    if len(matches) != 1:
        raise RuntimeError(
            f"{line['id']}: reviewed shared interval {wanted!r} "
            f"matched {len(matches)} package intervals")
    return matches[0]


def set_station_point(
    line: dict, intervals: list[list[list[float]]], station_code: str,
    point: list[float],
) -> bool:
    """Move one display station and every adjacent display-interval endpoint."""
    row = station_row(line, station_code)
    changed = row[2:4] != point
    row[2], row[3] = point
    station_index = next(
        index for index, candidate in enumerate(line["stations"])
        if candidate[0] == station_code)
    if station_index < len(intervals) and intervals[station_index]:
        intervals[station_index][0] = list(point)
    incoming = station_index - 1
    if station_index == 0 and len(intervals) == len(line["stations"]):
        incoming = len(intervals) - 1
    if incoming >= 0 and incoming < len(intervals) and intervals[incoming]:
        intervals[incoming][-1] = list(point)
    return changed


def terminal_path(
    points: list[list[float]], side: str, cut_index: int,
) -> list[list[float]]:
    if side == "start":
        return [list(point) for point in points[:cut_index + 1]]
    if side == "end":
        return [list(point) for point in reversed(points[cut_index:])]
    raise RuntimeError(f"shared corridor side must be 'start' or 'end', got {side!r}")


def straighten_st_clair_west_display(
    region: str, package: dict, intervals_by_line: dict,
    follow_rows: list[list],
) -> None:
    """User-requested native schematic: 512 goes straight through St Clair West.

    This is a display choice, not a correction to surveyed track. Keep the
    canonical package (including the streetcar station loop) and Line 1 intact.
    The streetcar platform alone moves onto the Tweedsmuir–Bathurst chord.
    Followers of 512 need the shortened display ruler, including its western
    branch; otherwise a remote branch would follow the wrong stretch of track.
    """
    if region != "ca":
        return
    line_id = "ttc-512"
    line = next((line for line in package["lines"] if line["id"] == line_id), None)
    if line is None:
        return
    codes = [row[0] for row in line["stations"]]
    station_code = "ca-official-st-clair-west"
    index = codes.index(station_code)
    if codes[index - 1:index + 2] != [
        "ca-official-st-clair-ave-west-at-tweedsmuir-ave", station_code,
        "ca-official-st-clair-ave-west-at-bathurst-st",
    ]:
        raise RuntimeError("ttc-512: St Clair West display neighbours changed")
    intervals = intervals_by_line[line_id]
    a, b = intervals[index - 1][0], intervals[index][-1]
    station = line["stations"][index][2:4]
    # Local metric projection; longitude degrees are shorter at this latitude.
    longitude_scale = math.cos(math.radians((a[1] + b[1]) / 2))
    dx, dy = (b[0] - a[0]) * longitude_scale, b[1] - a[1]
    fraction = (((station[0] - a[0]) * longitude_scale * dx
                 + (station[1] - a[1]) * dy) / (dx * dx + dy * dy))
    if not 0 < fraction < 1:
        raise RuntimeError("ttc-512: St Clair West no longer projects inside its display span")
    projected = [a[0] + fraction * (b[0] - a[0]), a[1] + fraction * (b[1] - a[1])]
    before = sum(line_length_metres(part) for part in intervals[:index - 1])
    old_station = before + line_length_metres(intervals[index - 1])
    old_end = old_station + line_length_metres(intervals[index])
    intervals[index - 1] = [list(a), projected]
    intervals[index] = [projected, list(b)]
    set_station_point(line, intervals, station_code, projected)
    new_station = before + line_length_metres(intervals[index - 1])
    new_end = new_station + line_length_metres(intervals[index])

    def remap(measure: float) -> float:
        if measure <= before:
            return measure
        if measure < old_station:
            return before + (measure - before) * (new_station - before) / (old_station - before)
        if measure < old_end:
            return new_station + (measure - old_station) * (new_end - new_station) / (old_end - old_station)
        return measure + new_end - old_end

    for row in follow_rows:
        if row[0] == line_id and row[1] == 0:
            row[2], row[3] = remap(float(row[2])), remap(float(row[3]))
        if row[4] == line_id and row[5] == 0:
            row[6], row[7] = remap(float(row[6])), remap(float(row[7]))


def apply_shared_corridors(
    region: str, package: dict, intervals_by_line: dict, corridors: list[dict],
    released_intervals: set[tuple[str, int]] | None = None,
) -> dict:
    """Apply only reviewed station-to-junction display sharing.

    The compact package remains untouched on disk and continues to own routing
    and statistics.  Each reviewed corridor chooses one existing canonical
    display arm; named members may reuse that arm only up to their individually
    reviewed cut vertices.  There is deliberately no proximity search for
    candidate lines here.
    """
    totals = {
        "groups": 0, "arms": 0, "mergedStations": 0,
        "snappedMetres": 0.0, "releasedIntervals": 0,
        "unresolvedGroups": 0,
    }
    released_intervals = released_intervals if released_intervals is not None else set()
    lines = {line["id"]: line for line in package.get("lines") or []}
    comparison = (((package.get("geometrySource") or {})
                   .get("officialGeometryComparison") or {})
                  .get("byLine") or {})
    blocked_by_line = {
        line_id: set((comparison.get(line_id) or {})
                     .get("displayBlockedIntervals") or [])
        for line_id in lines
    }
    for corridor in corridors:
        if corridor.get("region") != region:
            continue
        corridor_id = corridor.get("id") or "unnamed-shared-corridor"
        evidence = corridor.get("evidence") or []
        evidence_types = {row.get("type") for row in evidence if row.get("type")}
        if len(evidence_types) < 2:
            raise RuntimeError(
                f"{corridor_id}: shared corridor needs at least two distinct "
                "reviewed source types")
        shared_intervals = list(corridor.get("intervals") or [])
        if corridor.get("stationPairs"):
            line_pool = corridor.get("lineIds") or []
            priority = corridor.get("canonicalLinePriority") or line_pool
            for station_codes in corridor["stationPairs"]:
                matches = {
                    line_id: interval_for_station_pair(
                        lines[line_id], station_codes, required=False)
                    for line_id in line_pool if line_id in lines
                }
                matches = {
                    line_id: match for line_id, match in matches.items()
                    if match is not None
                }
                serving = list(matches)
                canonical_id = next(
                    (line_id for line_id in priority
                     if line_id in matches and
                     matches[line_id][0] not in blocked_by_line[line_id]), None)
                if canonical_id is None:
                    totals["unresolvedGroups"] += 1
                    continue
                shared_intervals.append({
                    "stationCodes": station_codes,
                    "canonicalLineId": canonical_id,
                    "lineIds": serving,
                })
        if shared_intervals:
            expected_kind = corridor.get("kind")
            maximum_station = float(
                corridor.get("maxStationSeparationMeters", 120.0))
            station_anchors: dict[str, list[float]] = {}
            for reviewed_interval in shared_intervals:
                station_codes = reviewed_interval.get("stationCodes") or []
                line_ids = reviewed_interval.get("lineIds") or []
                if len(station_codes) != 2 or station_codes[0] == station_codes[1]:
                    raise RuntimeError(
                        f"{corridor_id}: a shared interval needs two station codes")
                if len(line_ids) < 2 or len(line_ids) != len(set(line_ids)):
                    raise RuntimeError(
                        f"{corridor_id}: a shared interval needs distinct member lines")
                canonical_id = reviewed_interval.get("canonicalLineId")
                if canonical_id not in line_ids:
                    raise RuntimeError(
                        f"{corridor_id}: interval canonical line is not a member")
                for line_id in line_ids:
                    line = lines.get(line_id)
                    if line is None:
                        raise RuntimeError(
                            f"{corridor_id}: missing line {line_id!r}")
                    if "kind" in corridor and line.get("kind") != expected_kind:
                        raise RuntimeError(
                            f"{corridor_id}: {line_id} is {line.get('kind')!r}, "
                            f"not reviewed kind {expected_kind!r}")

                canonical_line = lines[canonical_id]
                canonical_index, canonical_forward = interval_for_station_pair(
                    canonical_line, station_codes)
                if canonical_index in blocked_by_line[canonical_id]:
                    raise RuntimeError(
                        f"{corridor_id}: canonical shared interval is display-blocked")
                canonical_interval = intervals_by_line[canonical_id][canonical_index]
                canonical_path = [list(point) for point in (
                    canonical_interval if canonical_forward
                    else reversed(canonical_interval))]
                if len(canonical_path) < 2:
                    raise RuntimeError(
                        f"{corridor_id}: canonical shared interval is empty")

                for station_code, path_point in zip(
                        station_codes, (canonical_path[0], canonical_path[-1])):
                    anchor = station_anchors.setdefault(
                        station_code, list(path_point))
                    if equirectangular_metres(
                        {"lon": anchor[0], "lat": anchor[1]},
                        {"lon": path_point[0], "lat": path_point[1]},
                    ) > maximum_station:
                        raise RuntimeError(
                            f"{corridor_id}: canonical station {station_code!r} "
                            "is inconsistent across reviewed intervals")

                for line_id in line_ids:
                    line = lines[line_id]
                    interval_index, forward = interval_for_station_pair(
                        line, station_codes)
                    old_interval = intervals_by_line[line_id][interval_index]
                    old_oriented = (old_interval if forward
                                    else list(reversed(old_interval)))
                    for endpoint, anchor in zip(
                            (old_oriented[0], old_oriented[-1]),
                            (station_anchors[station_codes[0]],
                             station_anchors[station_codes[1]])):
                        gap = equirectangular_metres(
                            {"lon": endpoint[0], "lat": endpoint[1]},
                            {"lon": anchor[0], "lat": anchor[1]})
                        if gap > maximum_station:
                            raise RuntimeError(
                                f"{corridor_id}: {line_id} station is {gap:.1f} m "
                                "from the reviewed shared interval")
                    replacement = [list(point) for point in (
                        canonical_path if forward else reversed(canonical_path))]
                    intervals_by_line[line_id][interval_index] = replacement
                    # Releasing the alignment gate's verdict here is
                    # DELIBERATE, and is the only place other than the
                    # reviewed release table where that may happen. The line
                    # just had this interval's geometry REPLACED by the
                    # canonical arm's, and the canonical arm cannot itself be
                    # blocked (raised on, above), so what will be drawn over
                    # these metres is geometry that passed the gate. The
                    # verdict belonged to geometry that is no longer on
                    # screen. Nothing else may drop the flag: a withheld
                    # interval that draws dashed is honest, one that draws
                    # solid claims surveyed track nobody confirmed — see the
                    # fail-closed check in `chains_from_parts_rows`.
                    if (interval_index in blocked_by_line[line_id] and
                            (line_id, interval_index) not in released_intervals):
                        released_intervals.add((line_id, interval_index))
                        totals["releasedIntervals"] += 1
                    if line_id != canonical_id:
                        totals["snappedMetres"] += line_length_metres(old_interval)
                    if corridor.get("mergeStation", True):
                        for station_code in station_codes:
                            if set_station_point(
                                    line, intervals_by_line[line_id], station_code,
                                    station_anchors[station_code]):
                                totals["mergedStations"] += 1
                totals["groups"] += 1
                totals["arms"] += len(line_ids)
            continue
        if corridor.get("stationPairs"):
            continue
        members = corridor.get("members") or []
        if len(members) < 2:
            raise RuntimeError(f"{corridor_id}: shared corridor needs at least two arms")
        member_ids = [member.get("lineId") for member in members]
        if len(member_ids) != len(set(member_ids)):
            raise RuntimeError(f"{corridor_id}: a line is listed more than once")
        canonical_id = corridor.get("canonicalLineId")
        if canonical_id not in set(member_ids):
            raise RuntimeError(f"{corridor_id}: canonical line is not a member")

        expected_kind = corridor.get("kind")
        member_lines = []
        for member in members:
            line_id = member.get("lineId")
            line = lines.get(line_id)
            if line is None:
                raise RuntimeError(f"{corridor_id}: missing line {line_id!r}")
            if "kind" in corridor and line.get("kind") != expected_kind:
                raise RuntimeError(
                    f"{corridor_id}: {line_id} is {line.get('kind')!r}, "
                    f"not reviewed kind {expected_kind!r}")
            member_lines.append((member, line))

        canonical_member, canonical_line = next(
            pair for pair in member_lines if pair[0]["lineId"] == canonical_id)
        canonical_interval_index = int(canonical_member["intervalIndex"])
        if canonical_interval_index in blocked_by_line[canonical_id]:
            raise RuntimeError(
                f"{corridor_id}: canonical shared interval is display-blocked")
        canonical_interval = intervals_by_line[canonical_id][canonical_interval_index]
        canonical_cut = closest_vertex(
            canonical_interval, canonical_member["cut"],
            float(canonical_member.get("maxCutSearchMeters", 5.0)))
        canonical_path = terminal_path(
            canonical_interval, canonical_member["side"], canonical_cut)
        if len(canonical_path) < 2:
            raise RuntimeError(f"{corridor_id}: canonical shared arm is empty")
        canonical_station = station_row(
            canonical_line, canonical_member["stationCode"])
        canonical_point = [canonical_station[2], canonical_station[3]]
        if canonical_path[0] != canonical_point:
            raise RuntimeError(
                f"{corridor_id}: canonical interval does not begin at its station")

        max_station_gap = float(corridor.get("maxStationSeparationMeters", 120.0))
        max_cut_gap = float(corridor.get("maxCutSeparationMeters", 120.0))
        replaced_metres = 0.0
        merged_stations = 0
        for member, line in member_lines:
            interval_index = int(member["intervalIndex"])
            interval = intervals_by_line[line["id"]][interval_index]
            cut_index = closest_vertex(
                interval, member["cut"],
                float(member.get("maxCutSearchMeters", 5.0)))
            old_terminal = terminal_path(interval, member["side"], cut_index)
            member_cut = old_terminal[-1]
            cut_gap = equirectangular_metres(
                {"lon": canonical_path[-1][0], "lat": canonical_path[-1][1]},
                {"lon": member_cut[0], "lat": member_cut[1]},
            )
            if cut_gap > max_cut_gap:
                raise RuntimeError(
                    f"{corridor_id}: {line['id']} junction is {cut_gap:.1f} m "
                    f"from the canonical junction (limit {max_cut_gap:.1f} m)")

            row = station_row(line, member["stationCode"])
            member_station_point = [row[2], row[3]]
            expected_endpoint = interval[0] if member["side"] == "start" else interval[-1]
            if member_station_point != expected_endpoint:
                raise RuntimeError(
                    f"{corridor_id}: {line['id']} interval does not end at "
                    f"station {member['stationCode']!r}")
            station_gap = equirectangular_metres(
                {"lon": canonical_point[0], "lat": canonical_point[1]},
                {"lon": row[2], "lat": row[3]},
            )
            if station_gap > max_station_gap:
                raise RuntimeError(
                    f"{corridor_id}: {line['id']} station is {station_gap:.1f} m "
                    f"from the canonical station (limit {max_station_gap:.1f} m)")

            # A stopping service can split one shared physical run where an
            # express service has no station.  In that case the reviewed cut
            # is the stopping service's other interval endpoint.  Merely
            # joining the two cut vertices leaves a short out-and-back spike:
            # canonical cut -> old platform anchor -> canonical cut.  Move
            # that display-only anchor onto the reviewed canonical arm, and
            # let set_station_point weld both adjacent display intervals.
            cut_station_code = member.get("cutStationCode")
            if cut_station_code:
                if cut_station_code == member["stationCode"]:
                    raise RuntimeError(
                        f"{corridor_id}: cut station must differ from the arm station")
                if cut_index not in (0, len(interval) - 1):
                    raise RuntimeError(
                        f"{corridor_id}: {line['id']} cut station is not an "
                        "interval endpoint")
                cut_row = station_row(line, cut_station_code)
                cut_station_point = [cut_row[2], cut_row[3]]
                if cut_station_point != interval[cut_index]:
                    raise RuntimeError(
                        f"{corridor_id}: {line['id']} cut does not end at "
                        f"station {cut_station_code!r}")

            if member["side"] == "start":
                replacement: list[list[float]] = []
                append_distinct(replacement, canonical_path)
                append_distinct(
                    replacement,
                    interval[cut_index + 1:] if cut_station_code
                    else interval[cut_index:])
            elif member["side"] == "end":
                replacement = [list(point) for point in (
                    interval[:cut_index] if cut_station_code
                    else interval[:cut_index + 1])]
                append_distinct(replacement, list(reversed(canonical_path)))
            else:
                raise RuntimeError(
                    f"{corridor_id}: invalid side {member['side']!r}")
            intervals_by_line[line["id"]][interval_index] = replacement
            if (interval_index in blocked_by_line[line["id"]] and
                    (line["id"], interval_index) not in released_intervals):
                released_intervals.add((line["id"], interval_index))
                totals["releasedIntervals"] += 1

            if line["id"] != canonical_id:
                replaced_metres += line_length_metres(old_terminal)
            if corridor.get("mergeStation", True) and set_station_point(
                    line, intervals_by_line[line["id"]], member["stationCode"],
                    canonical_point):
                merged_stations += 1
            if cut_station_code and corridor.get("mergeStation", True):
                if set_station_point(
                        line, intervals_by_line[line["id"]], cut_station_code,
                        canonical_path[-1]):
                    merged_stations += 1

        totals["groups"] += 1
        totals["arms"] += len(members)
        totals["mergedStations"] += merged_stations
        totals["snappedMetres"] += replaced_metres

    totals["snappedMetres"] = round(totals["snappedMetres"], 1)
    return totals


def rounded(part: list[list[float]]) -> list[list[float]]:
    """Seven decimals — a centimetre, and the precision the derivative has
    always been written at. Lane splitting and corridor snapping interpolate,
    so without this a computed vertex writes seventeen digits of a number whose
    last nine are noise."""
    return [[round(point[0], 7), round(point[1], 7)] for point in part]


def bounds_of(fragments: list[dict], stations: list[dict]) -> dict:
    """The region's own extent, so the client never guesses one from a constant."""
    min_lon = min_lat = math.inf
    max_lon = max_lat = -math.inf
    for fragment in fragments:
        for part in fragment["parts"]:
            for lon, lat in part:
                min_lon, max_lon = min(min_lon, lon), max(max_lon, lon)
                min_lat, max_lat = min(min_lat, lat), max(max_lat, lat)
    for station in stations:
        lon, lat = station["lon"], station["lat"]
        min_lon, max_lon = min(min_lon, lon), max(max_lon, lon)
        min_lat, max_lat = min(min_lat, lat), max(max_lat, lat)
    return {
        "minLon": round(min_lon, 7), "minLat": round(min_lat, 7),
        "maxLon": round(max_lon, 7), "maxLat": round(max_lat, 7),
    }


def build(
    rail_dir: Path, output: Path,
    small_region_max_bytes: int = DEFAULT_SMALL_REGION_MAX_BYTES,
) -> dict:
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    metadata: dict[str, dict] = {}
    package_order: dict[str, int] = {}
    region_records: list[dict] = []
    package_digests: dict[str, str] = {}
    source_lines = source_intervals = source_segments = source_vertices = 0
    built_fragments = built_parts = built_vertices = built_stations = 0
    alignment_withheld_intervals = 0
    alignment_withheld_lines: set[str] = set()
    shared_corridor_totals = {
        "groups": 0, "arms": 0, "mergedStations": 0,
        "snappedMetres": 0.0, "releasedIntervals": 0,
        "unresolvedGroups": 0,
    }
    corridor_path = rail_dir / "shared-corridors.json"
    corridors = []
    if corridor_path.exists():
        reviewed = json.loads(corridor_path.read_bytes())
        if reviewed.get("format") != SHARED_CORRIDOR_FORMAT:
            raise RuntimeError(
                f"{corridor_path}: expected format {SHARED_CORRIDOR_FORMAT!r}")
        corridors = reviewed.get("corridors") or []
    lane_path = rail_dir / "display-lanes.json"
    lane_rows_by_region: dict[str, list[list]] = {}
    follow_rows_by_region: dict[str, list[list]] = {}
    released_by_region: dict[str, list[list]] = {}
    parts_by_region: dict[str, list[list]] = {}
    color_by_region: dict[str, dict[str, dict]] = {}
    render_group_by_region: dict[str, dict[str, str]] = {}
    non_joining_previous_by_region: dict[str, set[tuple[str, int]]] = {}
    # `strokeExcludedByRegion[region] = [[lineId, reason], ...]`
    # (build-display-lanes.mjs's `computePartsByRegionRows`): the single
    # source of truth for which continuous-region lines the web engine
    # (rail-network.js, `drawsContinuousStroke && !serviceSplitForLine`)
    # declines to build into a strokeModel chain, and therefore has no
    # `partsByRegion` rows for. Read here as a plain line-id set per region
    # rather than re-deriving the same test (or guessing at a
    # `serviceStatus` naming convention — a whole-line exclusion need not
    # start with "partial_", see 美祢線 below) — this module and
    # build-display-lanes.mjs must agree on the same list without either
    # naming the other.
    stroke_excluded_by_region: dict[str, set[str]] = {}
    if lane_path.exists():
        lanes = json.loads(lane_path.read_bytes())
        if lanes.get("format") != DISPLAY_LANES_FORMAT:
            raise RuntimeError(
                f"{lane_path}: expected format {DISPLAY_LANES_FORMAT!r}")
        lane_rows_by_region = lanes.get("byRegion") or {}
        follow_rows_by_region = lanes.get("followsByRegion") or {}
        released_by_region = lanes.get("releasedIntervalsByRegion") or {}
        parts_by_region = lanes.get("partsByRegion") or {}
        color_by_region = lanes.get("colorByRegion") or {}
        stroke_excluded_by_region = {
            region: {str(row[0]) for row in rows}
            for region, rows in (lanes.get("strokeExcludedByRegion") or {}).items()
        }
        # `renderGroupByRegion[region][lineId] = groupId` (build-display-
        # lanes.mjs's `deriveRenderGroupByRegion`, na-render-groups.json's
        # `byLineId`) — the same identity collapse rail-network.js's
        # `railwayIdentityFor` reads on the web, carried into the manifest so
        # the Swift side can mirror it: two lines with the same `renderGroup`
        # are one railway for interchange purposes even when they are not
        # also one colour override.
        render_group_by_region = lanes.get("renderGroupByRegion") or {}
        non_joining_previous_by_region = {
            region: {(str(row[0]), int(row[2])) for row in rows}
            for region, rows in (
                lanes.get("chainBoundariesByRegion") or {}).items()
        }

    # `[lineId#partIndex]` of every `loop` part build-display-lanes.mjs
    # reversed to the canonical (positive-area) winding on the way into
    # `partsByRegion` — see that file's `reversedLoopParts`. The reversal
    # itself needs nothing further here: a reversed part is always emitted as
    # an embedded-geometry row (`chain_from_embedded_coordinates` below reads
    # `row[7]` verbatim, already walked the reversed way), so the chain built
    # from it is already the reversed chain. What this set guards is the
    # invariant the web build already enforces at generation time — a lane,
    # follow or family-window row measures along the part in one fixed
    # direction, and rail-network.js derives its OWN (unreversed) parts for
    # the web rather than reading `partsByRegion` at all, so a row on a
    # reversed part would put the two renderers' measures at mirrored ends of
    # the ring. Checked again here, independently, in case a stale or
    # hand-edited display-lanes.json ever disagrees with its own promise.
    reversed_loop_parts_by_region: dict[str, set[str]] = {
        region: set(keys)
        for region, keys in (lanes.get("reversedLoopParts") or {}).items()
    } if lane_path.exists() else {}

    # `familyWindowsByRegion[region]` rows are `[lineId, partIndex,
    # fromMetres, toMetres, role, groupId]` — the family-collapse windows a
    # continuous chain draws its own stroke through (role 1, tenant) or in
    # place of (role 0, landlord, in the family colour). Read from the same
    # lane artefact as the other North America-only rows above.
    family_windows_by_region: dict[str, list[list]] = lanes.get(
        "familyWindowsByRegion") if lane_path.exists() else {}
    family_windows_by_region = family_windows_by_region or {}

    # The family colours those windows resolve against, one dict per region.
    # Each reviewed render-group policy file (`RENDER_GROUP_POLICY_FILENAMES`)
    # claims the regions it governs in its own `scope` — `na-render-
    # groups.json` for us/ca, `jp-render-groups.json` for jp — exactly like
    # build-display-lanes.mjs's `renderGroupPolicyByRegion` resolves the same
    # two files. A file with no `scope` at all (only ever a hand-built test
    # fixture; every real reviewed file carries one) falls back to every
    # region, matching this reader's old single-file behaviour. Read directly
    # rather than through the lane artefact (which only pre-resolves per-LINE
    # overrides, not the per-FAMILY palette a family window needs). Optional:
    # a region with no family windows never has to have either file, but a
    # window naming a group its region's dict does not have fails closed in
    # `chain_family_windows` rather than drawing an unreviewed colour.
    render_group_colors_by_region: dict[str, dict[str, dict]] = {}
    # Which explicit-`scope` file already claimed a region — mirrors build-
    # display-lanes.mjs's own collision check on `renderGroupsByRegion`. A
    # file with no `scope` at all (the hand-built test-fixture fallback
    # above) never registers here and is never checked against, so it can
    # still be silently superseded the way this reader's old single-file
    # behaviour always allowed.
    scoped_by_region: dict[str, str] = {}
    input_sha256: dict[str, str] = {}
    if corridor_path.exists():
        input_sha256["shared-corridors.json"] = hashlib.sha256(
            corridor_path.read_bytes()).hexdigest()
    if lane_path.exists():
        input_sha256["display-lanes.json"] = hashlib.sha256(
            lane_path.read_bytes()).hexdigest()
    # `byLineId` keys from every reviewed render-group policy file, paired
    # with the regions that file's own `scope` claims — read here so the
    # build report can flag a policy entry that names no line any loaded
    # package actually has (`danglingRenderGroupIds`, spec section 6).
    render_group_policy_by_line_id: list[tuple[list[str], dict]] = []
    for filename in RENDER_GROUP_POLICY_FILENAMES:
        render_groups_path = rail_dir / filename
        if not render_groups_path.exists():
            continue
        render_groups_raw = render_groups_path.read_bytes()
        input_sha256[filename] = hashlib.sha256(render_groups_raw).hexdigest()
        render_groups_doc = json.loads(render_groups_raw)
        render_groups_format = render_groups_doc.get("format")
        if render_groups_format == NA_RENDER_GROUPS_FORMAT_DEPRECATED:
            warnings.warn(
                f"{render_groups_path}: reading deprecated format "
                f"{NA_RENDER_GROUPS_FORMAT_DEPRECATED!r} (`groups`) — rename to "
                f"{NA_RENDER_GROUPS_FORMAT!r} (`families`). Support for the "
                "deprecated format will be removed in a future release.",
                stacklevel=2)
            families = render_groups_doc.get("groups") or {}
        elif render_groups_format in RENDER_GROUP_POLICY_FORMATS:
            families = render_groups_doc.get("families") or {}
        else:
            raise RuntimeError(
                f"{render_groups_path}: expected format one of "
                f"{sorted(RENDER_GROUP_POLICY_FORMATS)!r} (or deprecated "
                f"{NA_RENDER_GROUPS_FORMAT_DEPRECATED!r}), got "
                f"{render_groups_format!r}")
        explicit_scope = render_groups_doc.get("scope")
        scope = explicit_scope or list(REGIONS)
        for region in scope:
            if explicit_scope and region in scoped_by_region:
                raise RuntimeError(
                    f"two render-group policies claim region {region!r} in their "
                    f"`scope`: {scoped_by_region[region]!r} and {filename!r}")
            if explicit_scope:
                scoped_by_region[region] = filename
            render_group_colors_by_region[region] = families
        render_group_policy_by_line_id.append(
            (list(scope), render_groups_doc.get("byLineId") or {}))

    display_hubs_doc: dict = {}
    display_hubs_path = rail_dir / "display-hubs.json"
    if display_hubs_path.exists():
        display_hubs_raw = display_hubs_path.read_bytes()
        input_sha256["display-hubs.json"] = hashlib.sha256(display_hubs_raw).hexdigest()
        display_hubs_doc = json.loads(display_hubs_raw)

    region_line_ids: dict[str, set[str]] = {}
    identity_summaries: dict[str, dict] = {}
    timings_seconds: dict[str, float] = {}
    fragment_counts: dict[str, int] = {}
    report_regions: dict[str, dict] = {}

    for region in REGIONS:
        region_start_time = time.monotonic()
        path = rail_dir / f"{region}-2025.json"
        raw = path.read_bytes()
        package_digests[region] = hashlib.sha256(raw).hexdigest()
        package = json.loads(raw)
        region_line_ids[region] = {line["id"] for line in package["lines"]}
        comparison = (((package.get("geometrySource") or {})
                       .get("officialGeometryComparison") or {})
                      .get("byLine") or {})

        source_intervals_by_line = {
            line["id"]: decoded_intervals(line) for line in package["lines"]
        }
        intervals_by_line = {
            line_id: [[list(point) for point in interval] for interval in intervals]
            for line_id, intervals in source_intervals_by_line.items()
        }
        released_intervals: set[tuple[str, int]] = set()
        corridor_counts = apply_shared_corridors(
            region, package, intervals_by_line, corridors, released_intervals)
        straighten_st_clair_west_display(
            region, package, intervals_by_line, follow_rows_by_region.get(region, []))
        # The reviewed alignment releases (display-releases.json, copied into
        # the lane artefact) open exactly the intervals they name, the same
        # way a reviewed corridor replacement does.
        for line_id, interval_index in released_by_region.get(region, []):
            released_intervals.add((str(line_id), int(interval_index)))
        for name, value in corridor_counts.items():
            shared_corridor_totals[name] += value
        group_lengths: dict[str, float] = defaultdict(float)
        for line in package["lines"]:
            key = f"{line.get('operator') or ''}\0{line['name']}"
            group_lengths[key] += sum(float(row[0]) for row in line.get("segments") or [])

        lane_rows_by_line: dict[str, list[list]] = defaultdict(list)
        for row in lane_rows_by_region.get(region, []):
            lane_rows_by_line[str(row[0])].append(row)
        follow_rows_by_line: dict[str, list[list]] = defaultdict(list)
        for row in follow_rows_by_region.get(region, []):
            follow_rows_by_line[str(row[0])].append(row)
        parts_rows_by_line: dict[str, list[list]] = defaultdict(list)
        for row in parts_by_region.get(region, []):
            parts_rows_by_line[str(row[0])].append(row)
        family_rows_by_line: dict[str, list[list]] = defaultdict(list)
        for row in family_windows_by_region.get(region, []):
            family_rows_by_line[str(row[0])].append(row)
        region_families: dict[str, dict] = {}
        # Every line's chains are needed before any follow can be re-based
        # onto its canonical line's chain.
        chains_by_line: dict[str, list[dict]] = {}
        # Lines this region draws through the ordinary, per-interval lane
        # path (`parts_by_lane`, below) instead of a continuous chain — the
        # same path tw/hk/mo/kr always draw through. `partsByRegion`
        # (build-display-lanes.mjs) only emits rows for a line its own
        # network model actually built into one stroke; a line it declines
        # — today, a serviceStatus split, part or all of the line
        # substitute-bussed or suspended — has no rows to build a chain
        # from, and none should be guessed. `strokeExcludedByRegion` (also
        # build-display-lanes.mjs, from the SAME `drawsContinuousStroke &&
        # serviceSplitForLine` test the web engine runs) is that exclusion's
        # record: read here, not re-derived from a `serviceStatus` naming
        # convention, so this module and build-display-lanes.mjs agree on
        # which lines are exempted without either naming the other.
        region_stroke_excluded = stroke_excluded_by_region.get(region) or set()
        excluded_from_continuous: set[str] = set()
        if region in CONTINUOUS_STROKE_REGIONS:
            for line in package["lines"]:
                line_id = line["id"]
                line_withheld = set(
                    (comparison.get(line_id) or {})
                    .get("displayBlockedIntervals") or [])
                line_withheld -= {
                    interval_index for other_id, interval_index in released_intervals
                    if other_id == line_id
                }
                # `partsByRegion` (build-display-lanes.mjs) names the web's
                # own display parts for this line, one row per part in
                # partIndex order — build chains from THOSE boundaries so a
                # chain here and a web display part always agree on how many
                # pieces the line comes apart into, instead of this module
                # re-deriving its own splitting rules from the raw intervals
                # (the bug this replaced: a branch, a retrace or a reversal
                # the web splits on `continuous_chains` never saw, silently
                # collapsing several web parts into one chain here).
                rows_for_parts = sorted(
                    parts_rows_by_line.get(line_id, []), key=lambda row: int(row[1]))
                expected = list(range(len(rows_for_parts)))
                actual = [int(row[1]) for row in rows_for_parts]
                if rows_for_parts and actual == expected:
                    chains_by_line[line_id] = chains_from_parts_rows(
                        rows_for_parts, intervals_by_line[line_id],
                        line.get("stations") or [], line_withheld, line_id, region)
                    continue
                # No usable partsByRegion rows. Expected — and handled by
                # drawing through the non-continuous lane path below —
                # exactly when build-display-lanes.mjs itself recorded this
                # line as stroke-excluded (`strokeExcludedByRegion`).
                # Anything else missing rows is a real gap (a stale or
                # missing display-lanes.json, a checkout mid-migration) and
                # fails the build rather than silently drawing a continuous
                # stroke the web disagrees with, or silently leaving the
                # line undrawn.
                if line_id in region_stroke_excluded:
                    excluded_from_continuous.add(line_id)
                    service_status = str(line.get("serviceStatus") or "")
                    print(
                        f"NOTE: {region}|{line_id}: serviceStatus "
                        f"{service_status!r} splits this line out of "
                        "partsByRegion (strokeExcludedByRegion); drawing it "
                        "through the non-continuous lane path instead of a "
                        "continuous chain, the same as tw/hk/mo/kr",
                        file=sys.stderr,
                    )
                    continue
                raise RuntimeError(
                    f"{region}|{line_id}: no usable partsByRegion rows "
                    f"(found {len(rows_for_parts)}, partIndex {actual!r}) "
                    "and not recorded in strokeExcludedByRegion to explain "
                    "the absence — a continuous-stroke line must have one "
                    "or the other")
            # A display-lanes.json older than the withheld-spans slot still
            # builds — the two chain builders' own measures are the fallback
            # — but it builds a map whose dash edges are the ones grooming
            # already moved, so it says so rather than passing silently.
            stale_parts = sum(
                1 for line_chains in chains_by_line.values()
                for chain in line_chains if not chain.get("webWithheldSpans"))
            if stale_parts:
                print(
                    f"NOTE: {region}: {stale_parts} partsByRegion row(s) carry no "
                    "withheld spans (slot 8); their dashed spans were re-derived "
                    "here instead, which for a plain interval-range row measures "
                    "the geometry BEFORE grooming and can put a dash edge a few "
                    "hundred metres from where the web draws it. Rebuild "
                    "display-lanes.json (build-display-lanes.mjs) to restore parity",
                    file=sys.stderr,
                )

        line_keys_by_station: dict[str, list[str]] = defaultdict(list)
        region_fragments: list[dict] = []
        region_stations: list[dict] = []
        region_min_zoom: int | None = None
        for order, line in enumerate(package["lines"]):
            source_lines += 1
            key = f"{region}|{line['id']}"
            group_key = f"{line.get('operator') or ''}\0{line['name']}"
            group_km = group_lengths[group_key]
            ported_min = length_min_zoom(group_km)
            rank = int(line.get("rank", 0))
            rank_min = (3, 3, 4, 5, 6)[rank] if 0 <= rank < 5 else 0
            lod_min = max(ported_min, rank_min, wide_min_zoom(group_km))
            # A render-group colour override (na-render-groups.json `groups`,
            # via build-display-lanes.mjs's `colorByRegion`) wins over the
            # package's own colour, matching rail-network.js's
            # colorOverrideByLine — the same operator collapse (LIRR,
            # Metro-North, Metrolink) that draws one colour on the web draws
            # the same one here, and an unlisted line keeps the package's own.
            color_override = (color_by_region.get(region) or {}).get(line["id"])
            line_color = (color_override or {}).get("color") or line.get("color") or "#7a7a7a"
            line_color_dark = (
                (color_override or {}).get("colorDark")
                or line.get("colorDark") or line_color
            )
            # na-render-groups.json's render group for this line, or None for
            # a line the reviewed policy does not name (it keeps deciding
            # railway identity from operator+name, same as the web's
            # `visibilityGroupKey` fallback). Present regardless of whether
            # the group also carries a colour override — see
            # `render_group_by_region` above.
            render_group = (render_group_by_region.get(region) or {}).get(line["id"])
            package_order[key] = order
            metadata[key] = {
                "id": line["id"], "region": region, "name": line["name"],
                "nameRoma": line.get("nameRoma"), "operator": line.get("operator"),
                "operatorLogo": line.get("operatorLogo"), "kind": line.get("kind"),
                "rank": rank, "color": line_color,
                "colorDark": line_color_dark,
                "renderGroup": render_group,
                "minZoomMapLibre": ported_min, "lodMinZoomMapLibre": lod_min,
                "visibilityLengthKm": round(group_km, 3),
                "logo": f"/rail/logos/{line['id']}.png" if line.get("logo") else None,
            }
            withheld = set(
                (comparison.get(line["id"]) or {})
                .get("displayBlockedIntervals") or [])
            withheld -= {
                interval_index for line_id, interval_index in released_intervals
                if line_id == line["id"]
            }
            if withheld:
                metadata[key]["withheldDisplayIntervals"] = sorted(withheld)
                alignment_withheld_lines.add(key)
            for row in line.get("stations") or []:
                if key not in line_keys_by_station[row[0]]:
                    line_keys_by_station[row[0]].append(key)

            intervals = intervals_by_line[line["id"]]
            lane_pieces = split_intervals_by_lane(
                intervals, lane_rows_by_line.get(line["id"], []))
            source_geometry = source_intervals_by_line[line["id"]]
            source_intervals += len(source_geometry)
            source_vertices += sum(len(interval) for interval in source_geometry)
            source_segments += sum(
                max(0, len(interval) - 1) for interval in source_geometry)

            # One PART per station-to-station interval — or per lane piece where
            # a reviewed lane cuts one. That granularity is the renderer's cull
            # unit: the map keeps a part whose own bounding box meets the padded
            # viewport and skips the rest, so nothing has to be clipped here for
            # a transcontinental railway to cost only what is on screen.
            parts_by_lane: dict[float, list[list[list[float]]]] = defaultdict(list)
            continuous_chains_for_line: list[dict] = []
            line_is_continuous = (
                region in CONTINUOUS_STROKE_REGIONS
                and line["id"] not in excluded_from_continuous)
            if line_is_continuous:
                # One fragment per chain of intervals, uncut: the lane rows
                # ride along in metres and the device bakes the offset in. A
                # withheld interval no longer breaks the chain — the alignment
                # gate's verdict is real geometry held back from comparison,
                # not missing track, so `continuous_chains` draws through it
                # and records the span in `withheld` for the renderer to dash.
                continuous_chains_for_line = chains_by_line[line["id"]]
                alignment_withheld_intervals += sum(
                    1 for interval_index in withheld
                    if interval_index < len(intervals))
                rows_for_line = lane_rows_by_line.get(line["id"], [])
                follows_for_line = follow_rows_by_line.get(line["id"], [])
                family_rows_for_line = family_rows_by_line.get(line["id"], [])
                # Fail closed: a lane/follow/family row naming a partIndex
                # this line's own chain list does not have is a real
                # disagreement between this module's chains and the web's
                # display parts, not something to silently drop the row over
                # (the bug this replaces — see the long comment above where
                # chains are built).
                built_part_indices = {
                    chain.get("partIndex", 0) for chain in continuous_chains_for_line}
                reversed_parts_for_region = reversed_loop_parts_by_region.get(region) or set()
                def raise_if_reversed(row_kind: str, part_index: int) -> None:
                    part_key = f"{line['id']}#{part_index}"
                    if part_key in reversed_parts_for_region:
                        raise RuntimeError(
                            f"{region}|{line['id']}: {row_kind} row names partIndex "
                            f"{part_index!r}, but display-lanes.json's "
                            f"reversedLoopParts says that part was reversed to its "
                            "canonical winding and must carry neither a lane, a "
                            "follow, nor a family-window row (their measures would "
                            "mirror rail-network.js's own, unreversed part)")
                for row in rows_for_line:
                    if int(row[1]) not in built_part_indices:
                        raise RuntimeError(
                            f"{region}|{line['id']}: lane row {row!r} names "
                            f"partIndex {row[1]!r} with no matching chain "
                            f"(have {sorted(built_part_indices)})")
                    raise_if_reversed("lane", int(row[1]))
                for row in follows_for_line:
                    if int(row[1]) not in built_part_indices:
                        raise RuntimeError(
                            f"{region}|{line['id']}: follow row {row!r} names "
                            f"partIndex {row[1]!r} with no matching chain "
                            f"(have {sorted(built_part_indices)})")
                    raise_if_reversed("follow", int(row[1]))
                for row in family_rows_for_line:
                    if int(row[1]) not in built_part_indices:
                        raise RuntimeError(
                            f"{region}|{line['id']}: family window row {row!r} "
                            f"names partIndex {row[1]!r} with no matching "
                            f"chain (have {sorted(built_part_indices)})")
                    raise_if_reversed("family window", int(row[1]))
                region_render_group_colors = render_group_colors_by_region.get(region) or {}
                for chain_index, chain in enumerate(continuous_chains_for_line):
                    family_windows = chain_family_windows(
                        family_rows_for_line, chain, region_render_group_colors,
                        region, line["id"])
                    for window in family_windows:
                        group_id = window[3]
                        if group_id not in region_families:
                            group_color = region_render_group_colors[group_id]
                            region_families[group_id] = {
                                "color": group_color["color"],
                                "colorDark": (
                                    group_color.get("colorDark")
                                    or group_color["color"]),
                            }
                    fragment = {
                        "lineKey": key, "lane": 0.0,
                        "parts": [rounded(part) for part in chain["parts"]],
                        "continuous": True, "chain": chain_index,
                        "laneRows": chain_lane_rows(rows_for_line, chain),
                        "follows": chain_follow_rows(
                            follows_for_line, chain,
                            chains_by_line, region, line["id"]),
                        "totalMetres": round(
                            chain.get("endMetres", chain["startMetres"])
                            - chain["startMetres"], 1),
                        "withheld": chain.get("withheld") or [],
                        "familyWindows": family_windows,
                    }
                    if (line["id"], chain_index) in (
                            non_joining_previous_by_region.get(region) or set()):
                        fragment["joinPrevious"] = False
                    region_fragments.append(fragment)
                    built_fragments += 1
                    built_parts += len(chain["parts"])
                    built_vertices += sum(len(part) for part in chain["parts"])
                if continuous_chains_for_line:
                    region_min_zoom = (
                        lod_min if region_min_zoom is None
                        else min(region_min_zoom, lod_min))
            elif withheld:
                # The alignment gate is an interval-level verdict, so it is
                # applied to the interval geometry rather than to lane pieces
                # that may straddle two of them.
                if lane_rows_by_line.get(line["id"]):
                    raise RuntimeError(
                        f"{line['id']}: display lanes cannot cross withheld intervals")
                for interval_index, interval in enumerate(intervals):
                    if interval_index in withheld:
                        alignment_withheld_intervals += 1
                        continue
                    if len(interval) >= 2:
                        parts_by_lane[0.0].append(rounded(interval))
            else:
                for lane, piece in lane_pieces:
                    if len(piece) >= 2:
                        parts_by_lane[float(lane)].append(rounded(piece))

            for lane, parts in sorted(parts_by_lane.items()):
                region_fragments.append(
                    {"lineKey": key, "lane": lane, "parts": parts})
                built_fragments += 1
                built_parts += len(parts)
                built_vertices += sum(len(part) for part in parts)
            if parts_by_lane:
                region_min_zoom = (
                    lod_min if region_min_zoom is None
                    else min(region_min_zoom, lod_min))

            station_zoom = station_density_min_zoom(line, ported_min)
            station_count = len(line.get("stations") or [])
            for index, row in enumerate(line.get("stations") or []):
                terminal = not bool(line.get("isLoop")) and index in (0, station_count - 1)
                own_min = ported_min if terminal else station_zoom
                display_lane = (
                    None if line_is_continuous
                    else station_lane([row[2], row[3]], lane_pieces))
                station_record = {
                    "id": f"{line['id']}:{row[0]}", "lineKey": key,
                    "stationCode": row[0], "name": row[1],
                    "lon": row[2], "lat": row[3],
                    "nameRoma": row[4] if len(row) > 4 else None,
                    "minZoomMapLibre": own_min,
                    "lodMinZoomMapLibre": max(own_min, lod_min),
                    "isTerminal": terminal, "order": order,
                }
                if display_lane is not None:
                    station_record["lane"] = display_lane[0]
                    station_record["bearing"] = round(display_lane[1], 3)
                for chain_index, chain in enumerate(continuous_chains_for_line):
                    anchor = chain["anchorIndexByStation"].get(index)
                    if anchor is None and index == station_count - 1 \
                            and line.get("isLoop"):
                        # A loop's last station is the wrap interval's end,
                        # which the chain indexes as station 0's successor.
                        anchor = chain["anchorIndexByStation"].get(station_count)
                    if anchor is not None:
                        station_record["slot"] = [chain_index, anchor]
                        break
                if "slot" not in station_record and continuous_chains_for_line:
                    # Every station of a continuous-stroke line must resolve
                    # to a slot — a bead the map cannot anchor lands off the
                    # offset stroke (see RailMapView.swift's
                    # `parallelStationCoordinate` / `rail-network.js`'s own
                    # nearest-vertex fallback, both of which this build is
                    # supposed to make unnecessary). Nothing above should
                    # ever leave a gap here, so this is a fail-closed net,
                    # not an expected path: look for the closest vertex this
                    # line's own chains actually have, and only accept it
                    # within a metre — station geometry that is truly off
                    # the line by more than that is a data problem, not a
                    # rounding gap, and must be raised rather than papered
                    # over with a guess.
                    best_gap = math.inf
                    best_slot: list[int] | None = None
                    for chain_index, chain in enumerate(continuous_chains_for_line):
                        for vertex_index, point in enumerate(chain["polyline"]):
                            gap = equirectangular_metres(
                                {"lon": row[2], "lat": row[3]},
                                {"lon": point[0], "lat": point[1]})
                            if gap < best_gap:
                                best_gap = gap
                                best_slot = [chain_index, vertex_index]
                    if best_slot is not None and best_gap <= 1.0:
                        station_record["slot"] = best_slot
                    else:
                        raise RuntimeError(
                            f"{region}|{line['id']}: station {row[0]!r} "
                            f"({station_record['id']}) has no chain vertex "
                            f"within 1 m (closest is {best_gap:.1f} m) — a "
                            "continuous-stroke station must always resolve "
                            "to a slot")
                region_stations.append(station_record)

        winners = label_winners(region_stations)
        for station in region_stations:
            station["showsLabel"] = station["id"] in winners
            station["groupLineKeys"] = line_keys_by_station[station["stationCode"]]
            station.pop("order", None)
        built_stations += len(region_stations)

        # Group this region's fragments and station rows by lineKey (already
        # `f"{region}|{line['id']}"`, the same key `metadata` is keyed by) and
        # emit one independently decodable JSON chunk per line, in the
        # region's own package line order (the order `package["lines"]`
        # lists them, i.e. the order v1's region file emitted fragments in)
        # so a line's neighbours in the package sit next to it in the blob
        # (spec section 2-3). A fragment or station naming a lineKey with no
        # manifest line entry is a build error, not a silent drop.
        fragments_by_key: dict[str, list[dict]] = defaultdict(list)
        for fragment in region_fragments:
            fragments_by_key[fragment["lineKey"]].append(fragment)
        stations_by_key: dict[str, list[dict]] = defaultdict(list)
        for station in region_stations:
            stations_by_key[station["lineKey"]].append(station)
        for key in fragments_by_key:
            if key not in metadata:
                raise RuntimeError(
                    f"{key}: display fragment lineKey has no manifest line entry")
        for key in stations_by_key:
            if key not in metadata:
                raise RuntimeError(
                    f"{key}: display station lineKey has no manifest line entry")

        ordered_keys = sorted(
            set(fragments_by_key) | set(stations_by_key),
            key=lambda key: package_order[key])

        line_labels = display_identity.line_display_labels(region, package["lines"])

        blob = bytearray()
        largest_chunk_bytes = 0
        largest_chunk_line_id = None
        for key in ordered_keys:
            line_id = metadata[key]["id"]
            line_fragments = fragments_by_key.get(key, [])
            line_stations = stations_by_key.get(key, [])
            chunk_doc = {
                "format": FORMAT, "region": region, "lineId": line_id,
                "detail": "full",
                "families": {}, "lines": line_fragments, "stations": line_stations,
            }
            chunk_bytes = compact_json(chunk_doc)
            offset = len(blob)
            blob.extend(chunk_bytes)
            length = len(chunk_bytes)
            min_lon = min_lat = math.inf
            max_lon = max_lat = -math.inf
            vertex_count = 0
            chain_values: set = set()
            depends_on_ids: set[str] = set()
            for fragment in line_fragments:
                for part in fragment["parts"]:
                    vertex_count += len(part)
                    for lon, lat in part:
                        min_lon, max_lon = min(min_lon, lon), max(max_lon, lon)
                        min_lat, max_lat = min(min_lat, lat), max(max_lat, lat)
                if "chain" in fragment:
                    chain_values.add(fragment["chain"])
                for follow_row in fragment.get("follows") or []:
                    canonical_key = follow_row[2]
                    canonical_id = canonical_key.split("|", 1)[1]
                    if canonical_id != line_id:
                        depends_on_ids.add(canonical_id)
                    if canonical_key not in metadata:
                        raise RuntimeError(
                            f"{key}: follow row names canonical line "
                            f"{canonical_key!r}, which has no manifest line "
                            "entry in this region")
            if chain_values:
                chain_count = len(chain_values)
            elif line_fragments:
                chain_count = 1
            else:
                chain_count = 0
            entry = metadata[key]
            entry["chunk"] = {
                "offset": offset, "length": length,
                "sha256": hashlib.sha256(chunk_bytes).hexdigest(),
            }
            # Station rows count towards the load rect too: a line whose every
            # display interval is withheld still ships its platforms, and the
            # manifest validator on the client requires bounds on every line.
            for station_row in line_stations:
                lon, lat = station_row["lon"], station_row["lat"]
                min_lon, max_lon = min(min_lon, lon), max(max_lon, lon)
                min_lat, max_lat = min(min_lat, lat), max(max_lat, lat)
            if line_fragments or line_stations:
                entry["bounds"] = {
                    "minLon": round(min_lon, 7), "minLat": round(min_lat, 7),
                    "maxLon": round(max_lon, 7), "maxLat": round(max_lat, 7),
                }
            entry["stationCount"] = len(line_stations)
            entry["vertexCount"] = vertex_count
            entry["chainCount"] = chain_count
            entry["dependsOn"] = sorted(depends_on_ids)
            fragment_counts[key] = len(line_fragments)
            label = line_labels.get(line_id) or {}
            entry["displayLabel"] = label.get("displayLabel")
            entry["nameKey"] = label.get("nameKey")
            entry["operatorShort"] = label.get("operatorShort")
            if length > largest_chunk_bytes:
                largest_chunk_bytes = length
                largest_chunk_line_id = line_id

        full_bytes = len(blob)
        load_strategy = "whole" if full_bytes <= small_region_max_bytes else "lines"
        overview_lines = 0
        dp_seconds_start = time.monotonic()
        if load_strategy == "lines":
            for key in ordered_keys:
                entry = metadata[key]
                if not line_qualifies_for_overview(entry):
                    continue
                line_id = entry["id"]
                line_fragments = fragments_by_key.get(key, [])
                line_stations = stations_by_key.get(key, [])
                overview_fragments = []
                overview_vertex_count = 0
                for fragment in line_fragments:
                    overview_fragment, vertex_count = build_overview_fragment(fragment)
                    overview_fragments.append(overview_fragment)
                    overview_vertex_count += vertex_count
                overview_stations = [
                    station for station in line_stations
                    if station.get("minZoomMapLibre", 0) <= OVERVIEW_STATION_MAX_ZOOM
                ]
                overview_doc = {
                    "format": FORMAT, "region": region, "lineId": line_id,
                    "detail": "overview",
                    "families": {}, "lines": overview_fragments,
                    "stations": overview_stations,
                }
                overview_bytes_doc = compact_json(overview_doc)
                overview_offset = len(blob)
                blob.extend(overview_bytes_doc)
                entry["overview"] = {
                    "offset": overview_offset, "length": len(overview_bytes_doc),
                    "sha256": hashlib.sha256(overview_bytes_doc).hexdigest(),
                    "vertexCount": overview_vertex_count,
                }
                overview_lines += 1
        dp_seconds = round(time.monotonic() - dp_seconds_start, 3)

        blob_bytes = bytes(blob)
        overview_bytes_total = len(blob_bytes) - full_bytes
        name = f"{region}.display.bin"
        (output / name).write_bytes(blob_bytes)

        hub_by_station_id = display_identity.hub_index(display_hubs_doc, region)
        station_doc = display_identity.build_station_identity(
            region, package["lines"], hub_by_station_id)
        stations_data = json.dumps(
            station_doc, ensure_ascii=False, indent=None).encode("utf-8")
        stations_name = f"{region}.stations.json"
        (output / stations_name).write_bytes(stations_data)
        identity_summaries[region] = display_identity.identity_summary(
            station_doc, line_labels, package["lines"])

        region_vertex_count = sum(
            len(part) for fragment in region_fragments for part in fragment["parts"])
        record = {
            "region": region, "file": name, "bytes": len(blob_bytes),
            "sha256": hashlib.sha256(blob_bytes).hexdigest(),
            "stationsFile": stations_name, "stationsBytes": len(stations_data),
            "stationsSHA256": hashlib.sha256(stations_data).hexdigest(),
            # Family colours this region's fragments actually name — a
            # groupId a family window resolved against, keyed to the
            # `color`/`colorDark` `chain_family_windows` already fail-closed
            # checked exist in `na-render-groups.json`. Moved here (v1 held
            # it in the whole-region file) since v2's per-line chunks always
            # carry an empty `families` block.
            "families": region_families,
            "lineCount": len(ordered_keys), "stationCount": len(region_stations),
            "vertexCount": region_vertex_count,
            "loadStrategy": load_strategy,
            "fullBytes": full_bytes, "overviewBytes": overview_bytes_total,
            # The earliest MapLibre zoom at which anything in this region can
            # be drawn. A camera wider than that has nothing to show, so the
            # client can skip the read entirely rather than decode a national
            # network for a renderer that will reject every line in it.
            "minZoomMapLibre": region_min_zoom if region_min_zoom is not None else 0,
        }
        # A region with nothing in it has no extent, and saying so is not the
        # same as saying it is at the origin: the bounds are the client's
        # intersection test, and a zero rect at 0°N 0°E would match a camera
        # in the Gulf of Guinea. Absent bounds mean "never".
        if region_fragments or region_stations:
            record.update(bounds_of(region_fragments, region_stations))
        region_records.append(record)

        timings_seconds[region] = round(time.monotonic() - region_start_time, 3)
        report_regions[region] = {
            "lines": len(ordered_keys), "stations": len(region_stations),
            "vertices": region_vertex_count, "blobBytes": len(blob_bytes),
            "manifestBytes": None,
            "largestChunkBytes": largest_chunk_bytes,
            "largestChunkLineId": largest_chunk_line_id,
            "danglingRenderGroupIds": [],
            "loadStrategy": load_strategy,
            "overviewLines": overview_lines, "overviewBytes": overview_bytes_total,
            "fullBytes": full_bytes, "dpSeconds": dp_seconds,
            **identity_summaries[region],
        }

    # `byLineId` keys from every reviewed render-group policy file that name
    # no line in any package loaded within that file's own `scope` (spec
    # section 6, `danglingRenderGroupIds`).
    dangling_ids: set[str] = set()
    for scope, by_line_id in render_group_policy_by_line_id:
        governed_ids: set[str] = set()
        for scope_region in scope:
            governed_ids |= region_line_ids.get(scope_region, set())
        for line_id in by_line_id:
            if line_id not in governed_ids:
                dangling_ids.add(line_id)
    for region in report_regions:
        report_regions[region]["danglingRenderGroupIds"] = sorted(dangling_ids)

    generated_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    manifest = {
        "format": FORMAT,
        "generatedAt": generated_at,
        "packageSHA256": package_digests,
        "inputSHA256": input_sha256,
        "source": {
            "lines": source_lines, "intervals": source_intervals,
            "segments": source_segments, "vertices": source_vertices,
        },
        "built": {
            "regions": len(region_records), "lineFragments": built_fragments,
            "parts": built_parts, "vertices": built_vertices,
            "stations": built_stations,
            "sharedCorridors": shared_corridor_totals,
            "alignmentWithheldIntervals": alignment_withheld_intervals,
            "alignmentWithheldLines": len(alignment_withheld_lines),
        },
        "lines": metadata,
        "regions": region_records,
    }
    manifest_bytes = compact_json(manifest)
    (output / "manifest.json").write_bytes(manifest_bytes)
    for region in report_regions:
        report_regions[region]["manifestBytes"] = len(manifest_bytes)

    # Self-check (spec section 8): every manifest line's chunk must decode
    # standalone at its byte range, name the right lineId, carry the right
    # fragment/station counts and sha256, a region's chunks must tile its
    # blob exactly (contiguous, no gap, no overlap), every `dependsOn` id
    # must resolve to a manifest line in the same region, and a region
    # record's lineCount/stationCount/vertexCount must equal the sums over
    # its own lines.
    for record in region_records:
        region = record["region"]
        region_blob = (output / record["file"]).read_bytes()
        region_keys = sorted(
            (key for key, entry in metadata.items() if entry["region"] == region),
            key=lambda key: metadata[key]["chunk"]["offset"])
        region_ids = {metadata[key]["id"] for key in region_keys}
        sum_stations = sum_vertices = 0
        cursor = 0
        for key in region_keys:
            entry = metadata[key]
            chunk = entry["chunk"]
            if "bounds" not in entry:
                raise RuntimeError(
                    f"{region}: manifest line {entry['id']!r} has no bounds; the "
                    "client rejects the whole manifest without them")
            if chunk["offset"] != cursor:
                raise RuntimeError(
                    f"{region}: chunk for {entry['id']!r} starts at "
                    f"{chunk['offset']}, expected {cursor} (chunks must tile "
                    "the blob exactly)")
            chunk_bytes = region_blob[chunk["offset"]:chunk["offset"] + chunk["length"]]
            if hashlib.sha256(chunk_bytes).hexdigest() != chunk["sha256"]:
                raise RuntimeError(
                    f"{region}: chunk for {entry['id']!r} sha256 mismatch")
            decoded = json.loads(chunk_bytes)
            if decoded.get("lineId") != entry["id"]:
                raise RuntimeError(
                    f"{region}: chunk for {entry['id']!r} decodes lineId "
                    f"{decoded.get('lineId')!r}")
            if len(decoded.get("lines") or []) != fragment_counts.get(key, 0):
                raise RuntimeError(
                    f"{region}: chunk for {entry['id']!r} fragment count mismatch")
            if len(decoded.get("stations") or []) != entry.get("stationCount", 0):
                raise RuntimeError(
                    f"{region}: chunk for {entry['id']!r} station count mismatch")
            for depends_on_id in entry.get("dependsOn") or []:
                if depends_on_id not in region_ids:
                    raise RuntimeError(
                        f"{region}: chunk for {entry['id']!r} dependsOn "
                        f"{depends_on_id!r}, which has no manifest line "
                        "entry in this region")
            sum_stations += entry.get("stationCount", 0)
            sum_vertices += entry.get("vertexCount", 0)
            cursor += chunk["length"]
        if cursor != record["fullBytes"]:
            raise RuntimeError(
                f"{region}: full chunks cover {cursor} bytes, expected "
                f"fullBytes {record['fullBytes']}")
        # Overview chunks (spec A4): tile [fullBytes, blobBytes) exactly,
        # every one decodes standalone, is tagged detail == "overview", names
        # the right lineId, and never carries more vertices than its full
        # chunk.
        overview_keys = sorted(
            (key for key in region_keys if "overview" in metadata[key]),
            key=lambda key: metadata[key]["overview"]["offset"])
        overview_cursor = record["fullBytes"]
        for key in overview_keys:
            entry = metadata[key]
            overview = entry["overview"]
            if overview["offset"] != overview_cursor:
                raise RuntimeError(
                    f"{region}: overview chunk for {entry['id']!r} starts at "
                    f"{overview['offset']}, expected {overview_cursor} "
                    "(overview chunks must tile the blob exactly)")
            overview_bytes = region_blob[
                overview["offset"]:overview["offset"] + overview["length"]]
            if hashlib.sha256(overview_bytes).hexdigest() != overview["sha256"]:
                raise RuntimeError(
                    f"{region}: overview chunk for {entry['id']!r} sha256 mismatch")
            decoded_overview = json.loads(overview_bytes)
            if decoded_overview.get("detail") != "overview":
                raise RuntimeError(
                    f"{region}: overview chunk for {entry['id']!r} decodes "
                    f"detail {decoded_overview.get('detail')!r}, expected "
                    "'overview'")
            if decoded_overview.get("lineId") != entry["id"]:
                raise RuntimeError(
                    f"{region}: overview chunk for {entry['id']!r} decodes "
                    f"lineId {decoded_overview.get('lineId')!r}")
            if overview["vertexCount"] > entry.get("vertexCount", 0):
                raise RuntimeError(
                    f"{region}: overview chunk for {entry['id']!r} has "
                    f"{overview['vertexCount']} vertices, more than its full "
                    f"chunk's {entry.get('vertexCount', 0)}")
            overview_cursor += overview["length"]
        if overview_cursor != len(region_blob):
            raise RuntimeError(
                f"{region}: overview chunks cover up to {overview_cursor} "
                f"bytes, blob is {len(region_blob)} bytes")
        if record["lineCount"] != len(region_keys):
            raise RuntimeError(
                f"{region}: record lineCount {record['lineCount']} != "
                f"{len(region_keys)} manifest lines")
        if record["stationCount"] != sum_stations:
            raise RuntimeError(
                f"{region}: record stationCount {record['stationCount']} != "
                f"sum over lines {sum_stations}")
        if record["vertexCount"] != sum_vertices:
            raise RuntimeError(
                f"{region}: record vertexCount {record['vertexCount']} != "
                f"sum over lines {sum_vertices}")

    report = {
        "format": REPORT_FORMAT, "generatedAt": generated_at,
        "regions": report_regions,
        "timingsSeconds": timings_seconds,
    }
    (output / "display-network-report.json").write_bytes(compact_json(report))

    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rail-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--small-region-max-bytes", type=int,
        default=DEFAULT_SMALL_REGION_MAX_BYTES)
    args = parser.parse_args()
    manifest = build(args.rail_dir, args.output, args.small_region_max_bytes)
    print(json.dumps({
        "format": manifest["format"], **manifest["source"], **manifest["built"],
        "bytes": {
            record["region"]: record["bytes"] for record in manifest["regions"]
        },
    }))


if __name__ == "__main__":
    main()
