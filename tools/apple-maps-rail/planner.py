"""Create compact Apple Maps capture plans from catalog areas and rail geometry."""

from __future__ import annotations

import copy
import json
import math
from pathlib import Path
from typing import Any, Iterable


METERS_PER_DEGREE_LAT = 111_320.0
SCALE_TOLERANCE = 0.07
NETWORK_CACHE_FILTER_VERSION = 4
EXCLUDED_OPERATORS = {"amtrak", "via rail", "via rail canada"}
EXCLUDED_KINDS = {"intercity", "highspeed", "tourist"}
EXCLUDED_LINE_IDS = {"hillsborough-area-regional-t-sky"}  # airport-only SkyConnect


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _validate(width_m: float, height_m: float, overlap: float, mode: str) -> None:
    if width_m <= 0 or height_m <= 0:
        raise ValueError("width_m and height_m must be positive")
    if not 0 <= overlap < 1:
        raise ValueError("overlap must be in the range [0, 1)")
    if mode not in {"metros", "corridors", "areas"}:
        raise ValueError("mode must be 'metros', 'corridors' or 'areas'")


def _city_list(cities: Any) -> list[dict[str, Any]]:
    if isinstance(cities, dict):
        cities = cities.get("cities", [])
    if not isinstance(cities, list):
        raise ValueError("cities must be a catalog object or list of city objects")
    return cities


def _select_cities(cities: list[dict[str, Any]], city_ids: Iterable[str] | None) -> list[dict[str, Any]]:
    if city_ids is None:
        return cities
    wanted = list(city_ids)
    by_id = {city.get("id"): city for city in cities}
    unknown = [city_id for city_id in wanted if city_id not in by_id]
    if unknown:
        raise ValueError(f"unknown city ids: {', '.join(unknown)}")
    return [by_id[city_id] for city_id in wanted]


def apply_network_extents(cities: list[dict[str, Any]], extents: Any = None) -> list[dict[str, Any]]:
    """Union sourced network extents into catalog bounds.

    ``network-extents.json`` is deliberately separate from the curated city list:
    it records whole-system bounds backed by operator sources, including systems
    missing from the repository rail packages. Its ``verified`` flag is preserved
    for audits; conservative provisional boxes are still useful capture targets.
    """
    if extents is None:
        path = Path(__file__).with_name("network-extents.json")
        if not path.exists():
            return cities
        with path.open(encoding="utf-8") as handle:
            extents = json.load(handle)
    if isinstance(extents, (str, Path)):
        with Path(extents).open(encoding="utf-8") as handle:
            extents = json.load(handle)
    entries = extents.get("cities", {}) if isinstance(extents, dict) else {}
    merged = copy.deepcopy(cities)
    for city in merged:
        entry = entries.get(city.get("id"), {})
        if not entry:
            continue
        for bounds in entry.get("bounds", []):
            if isinstance(bounds, list) and len(bounds) == 4 and bounds not in city.setdefault("bounds", []):
                city["bounds"].append(bounds)
        city["network_extent_systems"] = entry.get("systems", [])
        city["network_extent_sources"] = entry.get("source_urls", [])
        city["network_extent_verified"] = bool(entry.get("verified", False))
    return merged


def _eligible(line: dict[str, Any]) -> bool:
    line_id = str(line.get("id", "")).strip().casefold()
    operator = str(line.get("operator", "")).strip().casefold()
    kind = str(line.get("kind", "")).strip().casefold().replace("-", "")
    return line_id not in EXCLUDED_LINE_IDS and operator not in EXCLUDED_OPERATORS and kind not in EXCLUDED_KINDS


def _line_segments(line: dict[str, Any]) -> list[list[tuple[float, float]]]:
    """Return compact-v1 segments as separate (lat, lon) sequences.

    Segments may be disconnected branches. Keeping their boundaries is essential:
    interpolating from the final point of one to the first point of another would
    invent a rail corridor that does not exist.
    """
    segments: list[list[tuple[float, float]]] = []
    previous_last: tuple[float, float] | None = None
    for segment in line.get("segments", []):
        coordinates = segment[2] if isinstance(segment, list) and len(segment) > 2 else []
        points: list[tuple[float, float]] = []
        for coordinate in coordinates:
            if isinstance(coordinate, list) and len(coordinate) >= 2:
                lon, lat = coordinate[0], coordinate[1]
                if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
                    points.append((float(lat), float(lon)))
        continues = bool(segment[1]) if isinstance(segment, list) and len(segment) > 1 else False
        # US/CA compact-v1 continuing rows omit the shared first vertex. Restore
        # it so matching and capture include the whole station interval.
        if continues and previous_last is not None and (not points or points[0] != previous_last):
            points.insert(0, previous_last)
        if points:
            segments.append(points)
            previous_last = points[-1]
        elif not continues:
            previous_last = None
    return segments


def _line_points(line: dict[str, Any]) -> list[tuple[float, float]]:
    """Flatten points for point-in-catalog matching only, never interpolation."""
    return [point for segment in _line_segments(line) for point in segment]


def _geometry_bounds(segments: list[list[tuple[float, float]]]) -> tuple[float, float, float, float] | None:
    bounds: tuple[float, float, float, float] | None = None
    for segment in segments:
        for lat, lon in segment:
            if bounds is None:
                bounds = lat, lon, lat, lon
            else:
                bounds = (min(bounds[0], lat), min(bounds[1], lon),
                          max(bounds[2], lat), max(bounds[3], lon))
    return bounds


def _load_lines(rail_files: Iterable[str | Path] | None,
                supplemental_dir: str | Path | None = None) -> list[dict[str, Any]]:
    if rail_files is None:
        root = _repo_root()
        rail_files = [root / "app/public/rail/us-2025.json", root / "app/public/rail/ca-2025.json"]
    if supplemental_dir is None:
        supplemental_dir = _repo_root() / "outputs/apple-maps-rail/network-cache"
    rail_files = list(rail_files)
    supplement = Path(supplemental_dir)
    if supplement.exists():
        rail_files.extend(sorted(supplement.glob("*.json")))
    lines_by_id: dict[str, dict[str, Any]] = {}
    for rail_file in rail_files:
        with Path(rail_file).open(encoding="utf-8") as handle:
            payload = json.load(handle)
        if (payload.get("format") == "compact-v1-supplement"
                and payload.get("filterVersion") != NETWORK_CACHE_FILTER_VERSION):
            continue
        for line in payload.get("lines", []):
            if _eligible(line):
                line_id = str(line.get("id") or line.get("name") or "")
                lines_by_id.setdefault(line_id, line)
    return list(lines_by_id.values())


def _point_in_bounds(point: tuple[float, float], bounds: list[float]) -> bool:
    lat, lon = point
    south, west, north, east = bounds
    return south <= lat <= north and west <= lon <= east


def _line_matches_city(line: dict[str, Any], city: dict[str, Any],
                       segments: list[list[tuple[float, float]]] | None = None,
                       geometry_bounds: tuple[float, float, float, float] | None = None) -> bool:
    bounds_list = city.get("bounds", [])
    if segments is None:
        segments = _line_segments(line)
    if geometry_bounds is None:
        geometry_bounds = _geometry_bounds(segments)
    if geometry_bounds is None:
        return False
    line_south, line_west, line_north, line_east = geometry_bounds
    candidate_bounds = [bounds for bounds in bounds_list
                        if not (line_north < bounds[0] or line_south > bounds[2]
                                or line_east < bounds[1] or line_west > bounds[3])]
    if not candidate_bounds:
        return False
    for segment in segments:
        if any(_point_in_bounds(point, bounds) for bounds in candidate_bounds for point in segment):
            return True
        for a, b in zip(segment, segment[1:]):
            if any(_segment_intersects_rect(a[1], a[0], b[1], b[0],
                                            bounds[1], bounds[0], bounds[3], bounds[2])
                   for bounds in candidate_bounds):
                return True
    return False


def _city_reference_lat(city: dict[str, Any]) -> float:
    bounds = city.get("bounds", [])
    return sum((box[0] + box[2]) / 2 for box in bounds) / max(len(bounds), 1)


def _meters_per_degree_lon(lat: float) -> float:
    return max(METERS_PER_DEGREE_LAT * math.cos(math.radians(lat)), 1.0)


def _sample_segment(a: tuple[float, float], b: tuple[float, float], step_m: float, reference_lat: float) -> list[tuple[float, float]]:
    lat_scale = METERS_PER_DEGREE_LAT
    lon_scale = _meters_per_degree_lon(reference_lat)
    distance = math.hypot((b[0] - a[0]) * lat_scale, (b[1] - a[1]) * lon_scale)
    count = max(1, math.ceil(distance / step_m))
    return [(a[0] + (b[0] - a[0]) * i / count, a[1] + (b[1] - a[1]) * i / count) for i in range(count + 1)]


def _tile_id(city: dict[str, Any], lat: float, lon: float) -> str:
    return f"{city['id']}:{lat:.4f}:{lon:.4f}"


def _dedup_precision(width_m: float, height_m: float, reference_lat: float) -> float:
    """Use ~111 m global deduplication, without collapsing deliberately tiny tiles."""
    tile_degrees = min(height_m / METERS_PER_DEGREE_LAT, width_m / _meters_per_degree_lon(reference_lat))
    return max(1e-9, min(0.001, tile_degrees / 2))


def _add_tile(tiles: dict[tuple[int, int], dict[str, Any]], city: dict[str, Any], lat: float, lon: float,
              rail_line: str | None, coverage_source: str, dedup_precision: float) -> None:
    # A 0.001-degree key (~111 m north/south) normally deduplicates neighboring
    # city boxes. Tiny test/custom tiles use a proportionately finer global key.
    key = (round(lat / dedup_precision), round(lon / dedup_precision))
    existing = tiles.get(key)
    if existing is None:
        existing = {
            "id": _tile_id(city, lat, lon),
            "city": city["id"],
            "cities": [city["id"]],
            "country": city["country"],
            "lat": round(lat, 6),
            "lon": round(lon, 6),
            "rail_lines": [],
            "coverage_source": coverage_source,
        }
        tiles[key] = existing
    else:
        if city["id"] not in existing.setdefault("cities", [existing["city"]]):
            existing["cities"].append(city["id"])
        if existing["coverage_source"] != coverage_source:
            sources = set(existing["coverage_source"].split("+")) | set(coverage_source.split("+"))
            # Keep the combined metro/rail marker readable and stable for callers.
            if sources == {"metro-area", "rail-corridor"}:
                existing["coverage_source"] = "metro-area+rail-corridor"
            else:
                existing["coverage_source"] = "+".join(sorted(sources))
    if rail_line and rail_line not in existing["rail_lines"]:
        existing["rail_lines"].append(rail_line)


def _area_tiles(tiles: dict[tuple[int, int], dict[str, Any]], city: dict[str, Any], width_m: float,
                height_m: float, overlap: float, coverage_source: str) -> None:
    lat_ref = _city_reference_lat(city)
    dedup_precision = _dedup_precision(width_m, height_m, lat_ref)
    x_step, y_step = width_m * (1 - overlap), height_m * (1 - overlap)
    for south, west, north, east in city.get("bounds", []):
        # Include precisely the lattice cells whose viewport intersects a catalog
        # box. The former full extra ring multiplied fallback work substantially.
        for y_index in range(math.ceil((south * METERS_PER_DEGREE_LAT - height_m / 2) / y_step),
                             math.floor((north * METERS_PER_DEGREE_LAT + height_m / 2) / y_step) + 1):
            lat = y_index * y_step / METERS_PER_DEGREE_LAT
            # Longitude footprint is a function of the actual screenshot row,
            # not the city centroid (material for tall regional boxes).
            lon_scale = _meters_per_degree_lon(lat)
            for x_index in range(math.ceil((west * lon_scale - width_m / 2) / x_step),
                                 math.floor((east * lon_scale + width_m / 2) / x_step) + 1):
                lon = x_index * x_step / lon_scale
                _add_tile(tiles, city, lat, lon, None, coverage_source, dedup_precision)


def _segment_intersects_rect(x0: float, y0: float, x1: float, y1: float,
                             xmin: float, ymin: float, xmax: float, ymax: float) -> bool:
    """Liang–Barsky clipping test for a closed, axis-aligned viewport rectangle."""
    dx, dy = x1 - x0, y1 - y0
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, x0 - xmin), (dx, xmax - x0), (-dy, y0 - ymin), (dy, ymax - y0)):
        if p == 0:
            if q < 0:
                return False
            continue
        t = q / p
        if p < 0:
            if t > t1:
                return False
            t0 = max(t0, t)
        else:
            if t < t0:
                return False
            t1 = min(t1, t)
    return True


def _corridor_tiles(tiles: dict[tuple[int, int], dict[str, Any]], city: dict[str, Any], line: dict[str, Any],
                    width_m: float, height_m: float, overlap: float,
                    segments: list[list[tuple[float, float]]] | None = None) -> None:
    if segments is None:
        segments = _line_segments(line)
    if not segments:
        return
    lat_ref = _city_reference_lat(city)
    x_step, y_step = width_m * (1 - overlap), height_m * (1 - overlap)
    dedup_precision = _dedup_precision(width_m, height_m, lat_ref)
    # Sampling at half the smaller lattice interval makes long sparse geometry
    # continuous, including overlap=0 and custom very small viewports.
    sample_step = max(0.01, min(x_step, y_step) / 2)
    for segment in segments:
        samples: list[tuple[float, float]] = [segment[0]]
        for a, b in zip(segment, segment[1:]):
            samples.extend(_sample_segment(a, b, sample_step, lat_ref)[1:])
        # A one-point segment still deserves a tile. Duplicating it makes the
        # regular subsegment clipping path handle that case exactly.
        if len(samples) == 1:
            samples.append(samples[0])
        line_id = str(line.get("id") or line.get("name") or "unnamed-line")
        for (lat0, lon0), (lat1, lon1) in zip(samples, samples[1:]):
            y0, y1 = lat0 * METERS_PER_DEGREE_LAT, lat1 * METERS_PER_DEGREE_LAT
            y_start = math.ceil((min(y0, y1) - height_m / 2) / y_step)
            y_end = math.floor((max(y0, y1) + height_m / 2) / y_step)
            for y_index in range(y_start, y_end + 1):
                center_y = y_index * y_step
                center_lat = center_y / METERS_PER_DEGREE_LAT
                lon_scale = _meters_per_degree_lon(center_lat)
                x0, x1 = lon0 * lon_scale, lon1 * lon_scale
                x_start = math.ceil((min(x0, x1) - width_m / 2) / x_step)
                x_end = math.floor((max(x0, x1) + width_m / 2) / x_step)
                for x_index in range(x_start, x_end + 1):
                    center_x = x_index * x_step
                    if _segment_intersects_rect(x0, y0, x1, y1,
                                                center_x - width_m / 2, center_y - height_m / 2,
                                                center_x + width_m / 2, center_y + height_m / 2):
                        _add_tile(tiles, city, center_y / METERS_PER_DEGREE_LAT, center_x / lon_scale,
                                  line_id, "rail-corridor", dedup_precision)


def _distance_to_city_m(line: dict[str, Any], city: dict[str, Any],
                        segments: list[list[tuple[float, float]]] | None = None) -> float:
    """Approximate minimum geometry-to-box distance for split outer branches."""
    best = math.inf
    points = [point for segment in (segments if segments is not None else _line_segments(line)) for point in segment]
    for lat, lon in points:
        for south, west, north, east in city.get("bounds", []):
            clamped_lat = min(max(lat, south), north)
            clamped_lon = min(max(lon, west), east)
            best = min(best, math.hypot((lat - clamped_lat) * METERS_PER_DEGREE_LAT,
                                        (lon - clamped_lon) * _meters_per_degree_lon(lat)))
    return best


def plan_tiles(cities: Any, city_ids: Iterable[str] | None = None, width_m: float = 6500,
               height_m: float = 3000, overlap: float = 0.2, mode: str = "metros",
               rail_files: Iterable[str | Path] | None = None,
               supplemental_dir: str | Path | None = None,
               scale_tolerance: float = SCALE_TOLERANCE) -> list[dict[str, Any]]:
    """Return deduplicated Apple Maps capture tiles.

    ``metros`` (the default) grids every selected catalog area, then assigns each
    eligible compact-v1 line to a selected city whose bounds its geometry intersects,
    then follows that full line to its termini. Isolated branch records inherit the
    nearest directly matched city for the same operator. ``corridors`` is a
    faster corridor-first mode and falls back to catalog areas only where geometry is
    missing. ``areas`` always grids catalog boxes and does not read rail files.
    """
    _validate(width_m, height_m, overlap, mode)
    if not 0 <= scale_tolerance < 1:
        raise ValueError("scale_tolerance must be in the range [0, 1)")
    # Per-tile scale validation accepts +/-7%. Plan against the smallest accepted
    # screenshot footprint so a low-side capture cannot open coverage holes.
    width_m *= 1 - scale_tolerance
    height_m *= 1 - scale_tolerance
    selected = _select_cities(apply_network_extents(_city_list(cities)), city_ids)
    tiles: dict[tuple[int, int], dict[str, Any]] = {}
    if mode == "areas":
        for city in selected:
            _area_tiles(tiles, city, width_m, height_m, overlap, "catalog-area")
    else:
        metro_mode = mode == "metros"
        if metro_mode:
            for city in selected:
                _area_tiles(tiles, city, width_m, height_m, overlap, "metro-area")
        assigned: set[str] = set()
        matched_cities: set[str] = set()
        lines = _load_lines(rail_files, supplemental_dir=supplemental_dir)
        geometry_by_id = {}
        bounds_by_id = {}
        for line in lines:
            line_id = str(line.get("id") or line.get("name") or "")
            geometry_by_id[line_id] = _line_segments(line)
            bounds_by_id[line_id] = _geometry_bounds(geometry_by_id[line_id])
        direct_cities_by_operator: dict[str, list[dict[str, Any]]] = {}
        direct_matches: dict[str, list[dict[str, Any]]] = {}
        for line in lines:
            line_id = str(line.get("id") or line.get("name") or "")
            matches = [city for city in selected
                       if _line_matches_city(line, city, geometry_by_id[line_id], bounds_by_id[line_id])]
            direct_matches[line_id] = matches
            operator = str(line.get("operator", "")).strip().casefold()
            for city in matches:
                if city not in direct_cities_by_operator.setdefault(operator, []):
                    direct_cities_by_operator[operator].append(city)
        for city in selected:
            for line in lines:
                line_id = str(line.get("id") or line.get("name") or "")
                matches = direct_matches[line_id]
                owner = matches[0] if matches else None
                if owner is None:
                    operator = str(line.get("operator", "")).strip().casefold()
                    candidates = direct_cities_by_operator.get(operator, [])
                    if candidates:
                        owner = min(candidates, key=lambda candidate:
                                    _distance_to_city_m(line, candidate, geometry_by_id[line_id]))
                if city not in matches and city is not owner:
                    continue
                # A shared corridor is owned by the first matching selected city,
                # but every matching city has geometry and must not be area-filled.
                matched_cities.add(city["id"])
                if line_id in assigned:
                    continue
                assigned.add(line_id)
                _corridor_tiles(tiles, city, line, width_m, height_m, overlap, geometry_by_id[line_id])
        if not metro_mode:
            for city in selected:
                if city["id"] not in matched_cities:
                    _area_tiles(tiles, city, width_m, height_m, overlap, "catalog-area-fallback")
    for tile in tiles.values():
        tile["rail_lines"].sort()
    return sorted(tiles.values(), key=lambda tile: (tile["city"], tile["lat"], tile["lon"]))
