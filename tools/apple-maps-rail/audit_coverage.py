#!/usr/bin/env python3
"""Audit an Apple Maps capture plan against catalog areas and rail inventory."""

from __future__ import annotations

import argparse
import json
import math
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

from planner import (METERS_PER_DEGREE_LAT, NETWORK_CACHE_FILTER_VERSION, SCALE_TOLERANCE, _eligible,
                     _geometry_bounds, _line_matches_city, _line_segments, _meters_per_degree_lon,
                     apply_network_extents)

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

# These are concrete identity gaps in the checked-in US/Canada compact packages.
# They are kept separate from geographic coverage: a box over a system is not
# evidence that the repository contains the system or all of its branches.
KNOWN_REPOSITORY_GAPS = {
    "albuquerque_santa_fe": ["New Mexico Rail Runner Express"],
    "atlanta": ["Atlanta Streetcar", "MARTA Red Line"],
    "baltimore": ["MTA Light RailLink"],
    "buffalo": ["NFT Metro Rail"],
    "calgary": ["CTrain"],
    "charlotte": ["CATS LYNX", "CityLYNX Gold Line"],
    "cleveland": ["GCRTA Red Line", "GCRTA Blue Line", "GCRTA Green Line", "GCRTA Waterfront Line"],
    "denver": ["RTD Rail"],
    "detroit": ["QLINE"],
    "el_paso": ["El Paso Streetcar"],
    "jacksonville": ["JTA Skyway"],
    "kansas_city": ["KC Streetcar"],
    "kenosha": ["Kenosha Streetcar"],
    "las_vegas": ["Las Vegas Monorail"],
    "little_rock": ["Rock Region Metro Streetcar"],
    "memphis": ["MATA Trolley"],
    "milwaukee": ["The Hop"],
    "minneapolis_st_paul": ["METRO Blue Line", "Northstar"],
    "montreal": ["STM Metro", "REM"],
    "morgantown": ["WVU Personal Rapid Transit"],
    "norfolk": ["The Tide"],
    "oklahoma_city": ["OKC Streetcar"],
    "phoenix": ["Valley Metro Rail", "Tempe Streetcar"],
    "portland": ["MAX", "WES"],
    "sacramento": ["SacRT light rail"],
    "san_diego": ["San Diego Trolley"],
    "san_juan": ["Tren Urbano"],
    "st_louis": ["MetroLink"],
    "toronto": ["UP Express"],
    "tucson": ["Sun Link", "Sun Tran Streetcar"],
    "washington": ["DC Streetcar", "VRE"],
}
GENERIC_SYSTEM_WORDS = {"line", "rail", "transit", "metro", "streetcar", "light", "rapid",
                        "commuter", "regional", "subway", "express", "train"}
IDENTITY_ALIASES = {"up express": ["union", "pearson"]}
MATCH_ALIASES = {
    "cats lynx": ["lynx"],
    "mta light raillink": ["lightraillink"],
    "stm green line": ["ligne", "verte"],
    "stm orange line": ["ligne", "orange"],
    "stm yellow line": ["ligne", "jaune"],
    "stm blue line": ["ligne", "bleue"],
    "the tide": ["tide"],
    "san diego trolley": ["sdmts"],
}


def _load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def _identity_tokens(value: str) -> list[str]:
    alias = IDENTITY_ALIASES.get(value.casefold().strip())
    if alias:
        return alias
    return [token for token in re.sub(r"[^a-z0-9]+", " ", value.casefold()).split()
            if len(token) >= 3 and token not in GENERIC_SYSTEM_WORDS]


def _supplement_resolves(system: str, lines: list[dict[str, Any]],
                         expected_systems: list[str]) -> bool:
    system_tokens = _identity_tokens(system)
    granular = [expected for expected in expected_systems
                if system_tokens and all(token in _identity_tokens(expected) for token in system_tokens)]
    required = granular or [system]
    texts = [re.sub(r"[^a-z0-9]+", "", " ".join(str(line.get(key, "")) for key in
                                                  ("id", "name", "operator", "sourceTags")).casefold())
             for line in lines]
    # Every named line in a sourced extent must have its own relation match. One
    # convenient route relation cannot clear an entire multi-line system gap.
    return bool(texts) and all(any(all(token in text for token in
                                           MATCH_ALIASES.get(expected.casefold().strip(), _identity_tokens(expected)))
                                   for text in texts)
                               for expected in required)


def conservative_footprint(calibration: dict[str, Any]) -> tuple[float, float]:
    """Guaranteed inner viewport at the low side of accepted scale tolerance."""
    width_px, height_px = calibration["image_size"]
    margin = float(calibration.get("inner_margin_px", 100))
    mpp = float(calibration["target_meters_per_pixel"]) * (1 - SCALE_TOLERANCE)
    return (width_px - 2 * margin) * mpp, (height_px - 2 * margin) * mpp


def tile_rect(tile: dict[str, Any], width_m: float, height_m: float) -> list[float]:
    lat, lon = float(tile["lat"]), float(tile["lon"])
    return [lat - height_m / 2 / METERS_PER_DEGREE_LAT,
            lon - width_m / 2 / _meters_per_degree_lon(lat),
            lat + height_m / 2 / METERS_PER_DEGREE_LAT,
            lon + width_m / 2 / _meters_per_degree_lon(lat)]


def _covers_interval(intervals: list[tuple[float, float]], start: float, end: float,
                     epsilon: float = 1e-10) -> bool:
    cursor = start
    for left, right in sorted(intervals):
        if right < cursor - epsilon:
            continue
        if left > cursor + epsilon:
            return False
        cursor = max(cursor, right)
        if cursor >= end - epsilon:
            return True
    return cursor >= end - epsilon


def rectangle_covered(target: list[float], rectangles: list[list[float]]) -> bool:
    """Exact axis-aligned union check using a latitude sweep."""
    south, west, north, east = target
    candidates = [r for r in rectangles
                  if r[2] >= south and r[0] <= north and r[3] >= west and r[1] <= east]
    events = {south, north}
    for r in candidates:
        events.add(max(south, r[0])); events.add(min(north, r[2]))
    ys = sorted(events)
    for low, high in zip(ys, ys[1:]):
        if high <= low:
            continue
        y = (low + high) / 2
        intervals = [(max(west, r[1]), min(east, r[3])) for r in candidates if r[0] <= y <= r[2]]
        if not _covers_interval(intervals, west, east):
            return False
    # Protect degenerate targets and exact north/south edges as well.
    for y in (south, north):
        intervals = [(max(west, r[1]), min(east, r[3])) for r in candidates if r[0] <= y <= r[2]]
        if not _covers_interval(intervals, west, east):
            return False
    return True


def _clip_parameter_interval(a: tuple[float, float], b: tuple[float, float],
                             rect: list[float]) -> tuple[float, float] | None:
    """Return the parameter interval of lat/lon segment inside a rectangle."""
    south, west, north, east = rect
    x0, y0, x1, y1 = a[1], a[0], b[1], b[0]
    dx, dy = x1 - x0, y1 - y0
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, x0 - west), (dx, east - x0), (-dy, y0 - south), (dy, north - y0)):
        if p == 0:
            if q < 0:
                return None
            continue
        t = q / p
        if p < 0:
            if t > t1:
                return None
            t0 = max(t0, t)
        else:
            if t < t0:
                return None
            t1 = min(t1, t)
    return t0, t1


def line_covered(line: dict[str, Any], rectangles: list[list[float]],
                 segments: list[list[tuple[float, float]]] | None = None) -> bool:
    if not rectangles:
        return False
    if segments is None:
        segments = _line_segments(line)
    for segment in segments:
        if len(segment) == 1:
            lat, lon = segment[0]
            if not any(r[0] <= lat <= r[2] and r[1] <= lon <= r[3] for r in rectangles):
                return False
        for a, b in zip(segment, segment[1:]):
            intervals = [interval for rect in rectangles
                         if (interval := _clip_parameter_interval(a, b, rect)) is not None]
            if not _covers_interval(intervals, 0.0, 1.0):
                return False
    return True


def audit(catalog: dict[str, Any], plan: dict[str, Any], rail_payloads: list[dict[str, Any]],
          extents: dict[str, Any] | None = None) -> dict[str, Any]:
    base_cities = catalog.get("cities", [])
    all_cities = apply_network_extents(base_cities, extents) if extents is not None else apply_network_extents(base_cities)
    width_m, height_m = conservative_footprint(plan["calibration"])
    calibration = plan["calibration"]
    alignment = calibration.get("alignment_validation", {})
    residual = alignment.get("residual_offset_pixels", [math.inf, math.inf])
    alignment_ok = (calibration.get("coordinate_alignment_verified") is True
                    and len(calibration.get("coordinate_offset_pixels", [])) == 2
                    and int(alignment.get("station_matches", 0)) > 0
                    and len(residual) == 2
                    and max(abs(float(residual[0])), abs(float(residual[1]))) <= 20)
    tiles = plan.get("tiles", [])
    all_rectangles = [tile_rect(tile, width_m, height_m) for tile in tiles]
    planned_city_ids = {str(city_id) for tile in tiles
                        for city_id in tile.get("cities", [tile.get("city")]) if city_id}
    explicit_scope = plan.get("selected_city_ids")
    if explicit_scope is None and isinstance(plan.get("city_ids"), list):
        explicit_scope = plan["city_ids"]
    scoped_city_ids = set(map(str, explicit_scope)) if explicit_scope is not None else planned_city_ids
    cities = [city for city in all_cities if city["id"] in scoped_city_ids]

    city_results = []
    for city in cities:
        boxes = city.get("bounds", [])
        covered = [rectangle_covered(box, all_rectangles) for box in boxes]
        city_results.append({
            "id": city["id"],
            "present_in_plan": city["id"] in planned_city_ids,
            "catalog_and_network_extent_boxes": len(boxes),
            "boxes_covered": sum(covered),
            "geographic_coverage": "PASS" if covered and all(covered) else "ERROR",
            "repository_geometry_gaps": [],
            "network_extent_evidence": ("verified" if city.get("network_extent_verified") else
                                        "sourced-provisional" if city.get("network_extent_sources") else
                                        "catalog-provisional"),
        })

    lines_by_id: dict[str, dict[str, Any]] = {}
    for payload in rail_payloads:
        if (payload.get("format") == "compact-v1-supplement"
                and payload.get("filterVersion") != NETWORK_CACHE_FILTER_VERSION):
            continue
        for line in payload.get("lines", []):
            if _eligible(line):
                line_id = str(line.get("id") or line.get("name") or "")
                lines_by_id.setdefault(line_id, line)
    all_lines = list(lines_by_id.values())
    geometry_by_id = {}
    bounds_by_id = {}
    for line in all_lines:
        line_id = str(line.get("id") or line.get("name") or "")
        geometry_by_id[line_id] = _line_segments(line)
        bounds_by_id[line_id] = _geometry_bounds(geometry_by_id[line_id])
    direct_matches = {
        str(line.get("id") or line.get("name") or ""):
        [city for city in cities
         if _line_matches_city(line, city,
                               geometry_by_id[str(line.get("id") or line.get("name") or "")],
                               bounds_by_id[str(line.get("id") or line.get("name") or "")])]
        for line in all_lines
    }
    matched_operators = {str(line.get("operator", "")).strip().casefold()
                         for line in all_lines if direct_matches[str(line.get("id") or line.get("name") or "")]}
    lines = [line for line in all_lines
             if direct_matches[str(line.get("id") or line.get("name") or "")]
             or (line.get("sourceCity") in scoped_city_ids)
             or str(line.get("operator", "")).strip().casefold() in matched_operators]
    tiles_by_line: dict[str, list[list[float]]] = defaultdict(list)
    for tile, rect in zip(tiles, all_rectangles):
        for line_id in tile.get("rail_lines", []):
            tiles_by_line[str(line_id)].append(rect)
    line_results = []
    for line in lines:
        line_id = str(line.get("id") or line.get("name") or "")
        direct_metros = [city["id"] for city in direct_matches[line_id]]
        covered = line_covered(line, tiles_by_line.get(line_id, []), geometry_by_id[line_id])
        line_results.append({
            "id": line_id,
            "operator": line.get("operator"),
            "name": line.get("name"),
            "inventory_source": "supplemental-osm" if line.get("sourceCity") else "canonical-package",
            "direct_metros": direct_metros,
            "assigned_to_plan": bool(tiles_by_line.get(line_id)),
            "whole_geometry_covered": covered,
        })

    supplemental_by_city: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for line in lines:
        if line.get("sourceCity"):
            supplemental_by_city[str(line["sourceCity"])].append(line)
    gaps = []
    supplemented = []
    canonical_matches = []
    city_by_id = {city["id"]: city for city in cities}
    canonical_by_city = {}
    canonical_lines = [line for line in lines if not line.get("sourceCity")]
    for city_id in scoped_city_ids:
        if city_id not in city_by_id:
            continue
        direct = [line for line in canonical_lines if city_by_id[city_id] in direct_matches[
            str(line.get("id") or line.get("name") or "")]]
        operators = {str(line.get("operator", "")).strip().casefold() for line in direct}
        canonical_by_city[city_id] = [line for line in canonical_lines
                                     if line in direct or str(line.get("operator", "")).strip().casefold() in operators]
    for city_id, systems in KNOWN_REPOSITORY_GAPS.items():
        if city_id not in scoped_city_ids:
            continue
        expected = city_by_id.get(city_id, {}).get("network_extent_systems", [])
        canonical = [system for system in systems
                     if _supplement_resolves(system, canonical_by_city.get(city_id, []), expected)]
        unresolved_canonical = [system for system in systems if system not in canonical]
        resolved = [system for system in unresolved_canonical
                    if _supplement_resolves(system, supplemental_by_city.get(city_id, []),
                                            expected)]
        unresolved = [system for system in unresolved_canonical if system not in resolved]
        if canonical:
            canonical_matches.append({"city": city_id, "systems_or_routes": canonical})
        if resolved:
            supplemented.append({"city": city_id, "systems_or_routes": resolved})
        if unresolved:
            gaps.append({"city": city_id, "systems_or_routes": unresolved})
    remaining_by_city = {row["city"]: row["systems_or_routes"] for row in gaps}
    for city_result in city_results:
        city_result["repository_geometry_gaps"] = remaining_by_city.get(city_result["id"], [])
    missing_lines = [r for r in line_results if not r["assigned_to_plan"]]
    uncovered_lines = [r for r in line_results if r["assigned_to_plan"] and not r["whole_geometry_covered"]]
    canonical_ids = {str(line.get("id") or line.get("name") or "") for line in lines if not line.get("sourceCity")}
    supplemental_ids = {str(line.get("id") or line.get("name") or "") for line in lines if line.get("sourceCity")}
    missing_ids = {row["id"] for row in missing_lines}
    uncovered_ids = {row["id"] for row in uncovered_lines}
    failed_cities = [r for r in city_results if r["geographic_coverage"] != "PASS"]
    provisional = [r["id"] for r in city_results if r["network_extent_evidence"] != "verified"]
    result = "PASS"
    if not alignment_ok or failed_cities or missing_lines or uncovered_lines:
        result = "ERROR"
    elif gaps or provisional:
        result = "INCOMPLETE"
    return {
        "version": 1,
        "result": result,
        "scope": {
            "catalog_cities": len(cities),
            "plan_city_labels": len(planned_city_ids),
            "selected_cities": len(cities),
            "tiles": len(tiles),
            "eligible_repository_lines": len(canonical_ids),
            "eligible_supplemental_lines": len(supplemental_ids),
            "eligible_planning_lines": len(lines),
            "conservative_inner_footprint_m": [round(width_m, 3), round(height_m, 3)],
            "scale_tolerance": SCALE_TOLERANCE,
            "inner_margin_px_each_side": plan["calibration"].get("inner_margin_px", 100),
            "coordinate_alignment_verified": alignment_ok,
            "coordinate_offset_pixels": calibration.get("coordinate_offset_pixels"),
            "alignment_residual_pixels": residual if all(math.isfinite(float(x)) for x in residual) else None,
        },
        "summary": {
            "cities_geographically_covered": len(city_results) - len(failed_cities),
            "repository_lines_assigned": len(canonical_ids - missing_ids),
            "repository_lines_whole_geometry_covered": len(canonical_ids - missing_ids - uncovered_ids),
            "supplemental_lines_assigned": len(supplemental_ids - missing_ids),
            "supplemental_lines_whole_geometry_covered": len(supplemental_ids - missing_ids - uncovered_ids),
            "planning_lines_assigned": len(lines) - len(missing_lines),
            "planning_lines_whole_geometry_covered": len(lines) - len(missing_lines) - len(uncovered_lines),
            "cities_with_remaining_supplemental_geometry_gaps": len(gaps),
            "cities_with_osm_supplemental_geometry": len(supplemented),
            "cities_with_only_provisional_extent_evidence": len(provisional),
        },
        "city_results": city_results,
        "repository_line_results": line_results,
        "unassigned_repository_lines": missing_lines,
        "assigned_but_uncovered_repository_lines": uncovered_lines,
        "known_repository_inventory_gaps": gaps,
        "canonical_inventory_matches_for_static_findings": canonical_matches,
        "osm_supplemented_inventory_gaps": supplemented,
        "provisional_extent_cities": provisional,
        "limitations": [
            "Geographic PASS proves the plan covers declared catalog and network-extent rectangles at the smallest accepted screenshot scale; each extent's evidence state is reported separately.",
            "Whole-geometry PASS proves every checked-in eligible line segment is inside tagged screenshot footprints, including split branches and outer termini.",
            "It does not prove a provisional catalog rectangle contains a whole current system; verified network-extents evidence is required.",
            "Repository identity gaps remain blockers even when their geographic rectangles are covered.",
            "Tile centers are trusted only after station-coordinate alignment is verified with at most 20 px residual offset.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", type=Path, default=HERE / "cities.json")
    parser.add_argument("--plan", type=Path, default=REPO / "outputs/apple-maps-rail/plan.json")
    parser.add_argument("--extents", type=Path, default=HERE / "network-extents.json")
    parser.add_argument("--rail", type=Path, action="append")
    parser.add_argument("--network-cache", type=Path,
                        default=REPO / "outputs/apple-maps-rail/network-cache")
    parser.add_argument("--output", type=Path, default=REPO / "outputs/apple-maps-rail/coverage-audit.json")
    args = parser.parse_args()
    rail_paths = args.rail or [REPO / "app/public/rail/us-2025.json", REPO / "app/public/rail/ca-2025.json"]
    if args.network_cache.exists():
        rail_paths.extend(sorted(args.network_cache.glob("*.json")))
    extents = _load_json(args.extents) if args.extents.exists() else None
    report = audit(_load_json(args.catalog), _load_json(args.plan), [_load_json(path) for path in rail_paths], extents)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"result": report["result"], **report["summary"], "output": str(args.output)}, indent=2))
    return 0 if report["result"] in {"PASS", "INCOMPLETE"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
