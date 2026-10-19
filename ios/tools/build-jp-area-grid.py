#!/usr/bin/env python3
"""Build and validate the compact offline Japan area lookup raster.

The expected boundary input is ``dataofjapan/land``'s ``japan.geojson``:
https://github.com/dataofjapan/land/blob/master/japan.geojson.  That file was
converted from Geospatial Information Authority of Japan (GSI) Global Map
Japan data.  Its README says use follows the source terms and requires source
attribution (and, for commercial use, reporting usage to the copyright
holder).  The generated JSON therefore retains the short attribution
``Global Map Japan (GSI), via dataofjapan/land``.

The output covers 122.5..146.0 E and 24.0..45.8 N at 0.02-degree resolution.
Row zero is the southernmost row. ``rows_rle`` contains one flattened list of
``[areaValue, runLength, ...]`` per row; values are zero outside Japan and
1..11 in the order given by ``leaves``. ``extents`` contains station bounding
boxes, padded by three percent in both dimensions.

This generator is intentionally network-free and uses only the Python standard
library.  Download the boundary input separately, then run for example:

  python3 -I ios/tools/build-jp-area-grid.py \
    --boundaries /path/to/japan.geojson \
    --stations app/data/stations.json \
    --out ios/RailMap/jp-area-grid.json

Pass ``--check`` with ``--stations`` and ``--out`` to independently decode and
validate an existing output file.
"""

from __future__ import annotations

import argparse
import json
import math
import os
from collections import defaultdict
from pathlib import Path
from typing import Iterable, Iterator, Sequence


MIN_LON = 122.5
MIN_LAT = 24.0
MAX_LON = 146.0
MAX_LAT = 45.8
STEP = 0.02
COLS = math.ceil((MAX_LON - MIN_LON) / STEP)
ROWS = math.ceil((MAX_LAT - MIN_LAT) / STEP)
NEAREST_LIMIT = 0.12
SOURCE = "Global Map Japan (GSI), via dataofjapan/land"

LEAVES = [
    "hokkaido", "tohoku", "kanto", "hokuriku", "koshin", "tokai",
    "kinki", "chugoku", "shikoku", "kyushu", "okinawa",
]

PREFECTURES = {
    "北海道": "hokkaido",
    "青森県": "tohoku", "岩手県": "tohoku", "宮城県": "tohoku",
    "秋田県": "tohoku", "山形県": "tohoku", "福島県": "tohoku",
    "茨城県": "kanto", "栃木県": "kanto", "群馬県": "kanto",
    "埼玉県": "kanto", "千葉県": "kanto", "東京都": "kanto",
    "神奈川県": "kanto",
    "新潟県": "hokuriku", "富山県": "hokuriku", "石川県": "hokuriku",
    "福井県": "hokuriku",
    "山梨県": "koshin", "長野県": "koshin",
    "岐阜県": "tokai", "静岡県": "tokai", "愛知県": "tokai",
    "三重県": "tokai",
    "滋賀県": "kinki", "京都府": "kinki", "大阪府": "kinki",
    "兵庫県": "kinki", "奈良県": "kinki", "和歌山県": "kinki",
    "鳥取県": "chugoku", "島根県": "chugoku", "岡山県": "chugoku",
    "広島県": "chugoku", "山口県": "chugoku",
    "徳島県": "shikoku", "香川県": "shikoku", "愛媛県": "shikoku",
    "高知県": "shikoku",
    "福岡県": "kyushu", "佐賀県": "kyushu", "長崎県": "kyushu",
    "熊本県": "kyushu", "大分県": "kyushu", "宮崎県": "kyushu",
    "鹿児島県": "kyushu",
    "沖縄県": "okinawa",
}

SPOT_CHECKS = [
    ("Sapporo", 43.068, 141.351, 1),
    ("Sendai", 38.260, 140.882, 2),
    ("Tokyo", 35.681, 139.767, 3),
    ("Niigata", 37.912, 139.062, 4),
    ("Kanazawa", 36.578, 136.648, 4),
    ("Nagano", 36.643, 138.189, 5),
    ("Nagoya", 35.170, 136.881, 6),
    ("Shizuoka", 34.972, 138.389, 6),
    ("Kyoto", 34.985, 135.758, 7),
    ("Osaka", 34.702, 135.495, 7),
    ("Kobe", 34.680, 135.180, 7),
    ("Okayama", 34.666, 133.918, 8),
    ("Shimonoseki", 33.950, 130.922, 8),
    ("Takamatsu", 34.350, 134.047, 9),
    ("Moji", 33.946, 130.962, 10),
    ("Hakata", 33.590, 130.420, 10),
    ("Kagoshima-Chuo", 31.584, 130.541, 10),
    ("Naha", 26.206, 127.652, 11),
    ("Busan", 35.115, 129.041, 0),
    ("Taipei", 25.048, 121.517, 0),
]

Point = tuple[float, float]
Segment = tuple[float, float, float, float, int]


def polygons(geometry: dict) -> Iterator[list[list[list[float]]]]:
    """Yield polygons as lists of rings from Polygon or MultiPolygon GeoJSON."""
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if kind == "Polygon":
        yield coordinates
    elif kind == "MultiPolygon":
        yield from coordinates
    else:
        raise ValueError(f"unsupported boundary geometry: {kind!r}")


def load_boundaries(path: Path) -> list[tuple[int, list[list[list[float]]]]]:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("type") != "FeatureCollection":
        raise ValueError("boundaries must be a GeoJSON FeatureCollection")

    seen: set[str] = set()
    result: list[tuple[int, list[list[list[float]]]]] = []
    for feature in data.get("features", []):
        name = feature.get("properties", {}).get("nam_ja")
        if name not in PREFECTURES:
            raise ValueError(f"unknown or missing prefecture nam_ja: {name!r}")
        if name in seen:
            raise ValueError(f"duplicate prefecture feature: {name}")
        seen.add(name)
        value = LEAVES.index(PREFECTURES[name]) + 1
        for polygon in polygons(feature.get("geometry", {})):
            result.append((value, polygon))

    missing = sorted(set(PREFECTURES) - seen)
    if missing:
        raise ValueError(f"missing prefectures: {', '.join(missing)}")
    return result


def centre(row: int, col: int) -> Point:
    return (MIN_LON + (col + 0.5) * STEP, MIN_LAT + (row + 0.5) * STEP)


def rasterize(polys: Sequence[tuple[int, list[list[list[float]]]]]) -> list[bytearray]:
    """Fill polygon interiors at cell centres using an even/odd scanline rule."""
    grid = [bytearray(COLS) for _ in range(ROWS)]
    for value, polygon in polys:
        ys = [point[1] for ring in polygon for point in ring]
        first_row = max(0, math.ceil((min(ys) - MIN_LAT) / STEP - 0.5))
        last_row = min(ROWS - 1, math.ceil((max(ys) - MIN_LAT) / STEP - 0.5) - 1)
        for row in range(first_row, last_row + 1):
            y = MIN_LAT + (row + 0.5) * STEP
            crossings: list[float] = []
            for ring in polygon:
                for a, b in zip(ring, ring[1:]):
                    x1, y1 = a
                    x2, y2 = b
                    if (y1 <= y < y2) or (y2 <= y < y1):
                        crossings.append(x1 + (y - y1) * (x2 - x1) / (y2 - y1))
            crossings.sort()
            if len(crossings) % 2:
                raise ValueError(f"odd scanline crossing count at row {row}")
            for left, right in zip(crossings[::2], crossings[1::2]):
                first_col = max(0, math.ceil((left - MIN_LON) / STEP - 0.5))
                last_col = min(COLS - 1, math.ceil((right - MIN_LON) / STEP - 0.5) - 1)
                if first_col <= last_col:
                    grid[row][first_col:last_col + 1] = bytes([value]) * (last_col - first_col + 1)
    return grid


def boundary_segments(
    polys: Sequence[tuple[int, list[list[list[float]]]]]
) -> Iterator[Segment]:
    for value, polygon in polys:
        for ring in polygon:
            for a, b in zip(ring, ring[1:]):
                yield (a[0], a[1], b[0], b[1], value)


def segment_buckets(segments: Iterable[Segment]) -> dict[tuple[int, int], list[Segment]]:
    """Index segments in expanded 0.12-degree buckets for nearby-cell queries."""
    size = NEAREST_LIMIT
    buckets: dict[tuple[int, int], list[Segment]] = defaultdict(list)
    # Longitude distance is scaled by cos(latitude); this conservative expansion
    # covers the largest longitude delta possible within the grid.
    lon_pad = NEAREST_LIMIT / math.cos(math.radians(MAX_LAT))
    for segment in segments:
        x1, y1, x2, y2, _ = segment
        bx0 = math.floor((min(x1, x2) - lon_pad - MIN_LON) / size)
        bx1 = math.floor((max(x1, x2) + lon_pad - MIN_LON) / size)
        by0 = math.floor((min(y1, y2) - NEAREST_LIMIT - MIN_LAT) / size)
        by1 = math.floor((max(y1, y2) + NEAREST_LIMIT - MIN_LAT) / size)
        for by in range(by0, by1 + 1):
            for bx in range(bx0, bx1 + 1):
                buckets[(bx, by)].append(segment)
    return buckets


def distance_squared(point: Point, segment: Segment) -> float:
    """Squared point-to-segment distance with longitude scaled at the point."""
    lon, lat = point
    x1, y1, x2, y2, _ = segment
    scale = math.cos(math.radians(lat))
    ax = (x1 - lon) * scale
    ay = y1 - lat
    bx = (x2 - lon) * scale
    by = y2 - lat
    dx = bx - ax
    dy = by - ay
    denominator = dx * dx + dy * dy
    t = 0.0 if denominator == 0.0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / denominator))
    px = ax + t * dx
    py = ay + t * dy
    return px * px + py * py


def fill_near_coast(grid: list[bytearray], polys: Sequence[tuple[int, list[list[list[float]]]]]) -> None:
    buckets = segment_buckets(boundary_segments(polys))
    limit2 = NEAREST_LIMIT * NEAREST_LIMIT
    bucket_size = NEAREST_LIMIT
    for row, values in enumerate(grid):
        lat = MIN_LAT + (row + 0.5) * STEP
        by = math.floor((lat - MIN_LAT) / bucket_size)
        for col, value in enumerate(values):
            if value:
                continue
            lon = MIN_LON + (col + 0.5) * STEP
            bx = math.floor((lon - MIN_LON) / bucket_size)
            best_distance = limit2 + 1.0
            best_value = 0
            for segment in buckets.get((bx, by), ()):
                candidate = distance_squared((lon, lat), segment)
                if candidate < best_distance:
                    best_distance = candidate
                    best_value = segment[4]
            if best_distance <= limit2:
                values[col] = best_value


def encode_row(row: Sequence[int]) -> list[int]:
    encoded: list[int] = []
    value = row[0]
    count = 1
    for current in row[1:]:
        if current == value:
            count += 1
        else:
            encoded.extend((value, count))
            value = current
            count = 1
    encoded.extend((value, count))
    return encoded


def lookup_grid(grid: Sequence[Sequence[int]], lat: float, lon: float) -> int:
    col = math.floor((lon - MIN_LON) / STEP)
    row = math.floor((lat - MIN_LAT) / STEP)
    if row < 0 or row >= ROWS or col < 0 or col >= COLS:
        return 0
    return grid[row][col]


def station_points(path: Path) -> Iterator[Point]:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("type") != "FeatureCollection":
        raise ValueError("stations must be a GeoJSON FeatureCollection")
    for index, feature in enumerate(data.get("features", [])):
        point = feature.get("properties", {}).get("display_point")
        if not (isinstance(point, list) and len(point) == 2 and
                all(isinstance(item, (int, float)) for item in point)):
            raise ValueError(f"station feature {index} has invalid display_point")
        yield (float(point[0]), float(point[1]))


def station_extents(grid: Sequence[Sequence[int]], path: Path) -> tuple[dict[str, list[float]], list[int]]:
    grouped: list[list[Point]] = [[] for _ in range(12)]
    for lon, lat in station_points(path):
        grouped[lookup_grid(grid, lat, lon)].append((lon, lat))

    extents: dict[str, list[float]] = {}
    for value, leaf in enumerate(LEAVES, 1):
        points = grouped[value]
        if not points:
            raise ValueError(f"no stations assigned to {leaf}")
        min_lon = min(point[0] for point in points)
        min_lat = min(point[1] for point in points)
        max_lon = max(point[0] for point in points)
        max_lat = max(point[1] for point in points)
        lon_pad = (max_lon - min_lon) * 0.03
        lat_pad = (max_lat - min_lat) * 0.03
        extents[leaf] = [
            round(min_lon - lon_pad, 7), round(min_lat - lat_pad, 7),
            round(max_lon + lon_pad, 7), round(max_lat + lat_pad, 7),
        ]
    return extents, [len(points) for points in grouped]


def write_grid(boundaries: Path, stations: Path, out: Path) -> None:
    polys = load_boundaries(boundaries)
    grid = rasterize(polys)
    fill_near_coast(grid, polys)
    extents, _ = station_extents(grid, stations)
    output = {
        "version": 1,
        "leaves": LEAVES,
        "minLon": MIN_LON,
        "minLat": MIN_LAT,
        "step": STEP,
        "cols": COLS,
        "rows": ROWS,
        "rows_rle": [encode_row(row) for row in grid],
        "extents": extents,
        "source": SOURCE,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    temporary = out.with_name(out.name + ".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(output, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
    os.replace(temporary, out)


class RLEGrid:
    """Independent on-demand decoder used only by check mode."""

    def __init__(self, data: dict):
        self.data = data

    def value(self, lat: float, lon: float) -> int:
        min_lon = self.data["minLon"]
        min_lat = self.data["minLat"]
        step = self.data["step"]
        col = math.floor((lon - min_lon) / step)
        row = math.floor((lat - min_lat) / step)
        if row < 0 or row >= self.data["rows"] or col < 0 or col >= self.data["cols"]:
            return 0
        offset = 0
        encoded = self.data["rows_rle"][row]
        for index in range(0, len(encoded), 2):
            value, length = encoded[index:index + 2]
            if col < offset + length:
                return value
            offset += length
        raise ValueError(f"RLE row {row} ended before column {col}")


def check_grid(out: Path, stations: Path) -> None:
    with out.open(encoding="utf-8") as handle:
        data = json.load(handle)
    expected_header = {
        "version": 1, "leaves": LEAVES, "minLon": MIN_LON,
        "minLat": MIN_LAT, "step": STEP, "cols": COLS, "rows": ROWS,
    }
    for key, expected in expected_header.items():
        if data.get(key) != expected:
            raise ValueError(f"invalid {key}: {data.get(key)!r}, expected {expected!r}")
    if len(data.get("rows_rle", [])) != ROWS:
        raise ValueError("rows_rle length does not match rows")
    for row, encoded in enumerate(data["rows_rle"]):
        if len(encoded) % 2 or sum(encoded[1::2]) != COLS:
            raise ValueError(f"invalid RLE at row {row}")
        if any(value < 0 or value > len(LEAVES) for value in encoded[::2]):
            raise ValueError(f"out-of-range value at row {row}")
        if any(length <= 0 for length in encoded[1::2]):
            raise ValueError(f"non-positive run at row {row}")
    if set(data.get("extents", {})) != set(LEAVES):
        raise ValueError("extents keys do not match leaves")

    decoder = RLEGrid(data)
    failures = []
    for name, lat, lon, expected in SPOT_CHECKS:
        actual = decoder.value(lat, lon)
        print(f"spot {name}: {actual} ({'PASS' if actual == expected else 'FAIL, expected ' + str(expected)})")
        if actual != expected:
            failures.append(name)

    counts = [0] * 12
    for lon, lat in station_points(stations):
        counts[decoder.value(lat, lon)] += 1
    total = sum(counts)
    zero_percent = counts[0] * 100.0 / total if total else 0.0
    print(f"stations: {total}; value 0: {counts[0]} ({zero_percent:.4f}%)")
    print("per-leaf stations: " + ", ".join(
        f"{leaf}={counts[value]}" for value, leaf in enumerate(LEAVES, 1)
    ))
    print(f"file size: {out.stat().st_size} bytes")
    print(f"source: {data.get('source')}")
    if failures:
        raise ValueError("failed spot checks: " + ", ".join(failures))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boundaries", type=Path, help="prefecture GeoJSON input")
    parser.add_argument("--stations", required=True, type=Path, help="stations GeoJSON input")
    parser.add_argument("--out", required=True, type=Path, help="grid JSON output")
    parser.add_argument("--check", action="store_true", help="validate and report on an existing output")
    args = parser.parse_args()
    if not args.check and args.boundaries is None:
        parser.error("--boundaries is required unless --check is used")
    return args


def main() -> None:
    args = parse_args()
    if args.check:
        check_grid(args.out, args.stations)
    else:
        write_grid(args.boundaries, args.stations, args.out)


if __name__ == "__main__":
    main()
