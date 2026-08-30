#!/usr/bin/env python3
"""Fast structural and cross-platform preflight for JTM rail packages.

This deliberately does not claim surveyed-track correctness. It catches broken
contracts cheaply and emits heuristic geometry candidates for deeper review.
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


def haversine(a: list[float], b: list[float]) -> float:
    lon1, lat1 = math.radians(a[0]), math.radians(a[1])
    lon2, lat2 = math.radians(b[0]), math.radians(b[1])
    dlon, dlat = lon2 - lon1, lat2 - lat1
    value = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(value)))


def finite_coordinate(value: Any) -> bool:
    return (
        isinstance(value, list)
        and len(value) >= 2
        and all(isinstance(item, (int, float)) and math.isfinite(item) for item in value[:2])
        and -180 <= value[0] <= 180
        and -90 <= value[1] <= 90
    )


def find_repo(start: Path) -> Path:
    current = start.resolve()
    for candidate in (current, *current.parents):
        if (candidate / "app/public/rail").is_dir() and (candidate / "ios").is_dir():
            return candidate
    raise SystemExit(f"could not find a JTM repository above {start}")


class Audit:
    def __init__(self, repo: Path) -> None:
        self.repo = repo
        self.issues: list[dict[str, Any]] = []
        self.packages: dict[str, dict[str, Any]] = {}

    def issue(self, severity: str, code: str, message: str, **context: Any) -> None:
        self.issues.append({"severity": severity, "code": code, "message": message, **context})

    def require_file(self, path: Path, country: str, code: str) -> bool:
        if path.is_file():
            return True
        self.issue("ERROR", code, f"missing {path.relative_to(self.repo)}", country=country)
        return False

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
                    "ERROR", "PACKAGE_HEADER", f"{key} is {package.get(key)!r}, expected {expected!r}", country=country
                )

        lines = package.get("lines")
        if not isinstance(lines, list) or not lines:
            self.issue("ERROR", "EMPTY_LINES", "package has no lines", country=country)
            return

        ids = [line.get("id") for line in lines if isinstance(line, dict)]
        for line_id, count in Counter(ids).items():
            if line_id and count > 1:
                self.issue("ERROR", "DUPLICATE_LINE_ID", f"duplicate line id {line_id}", country=country, line=line_id)

        station_rows = segment_rows = vertex_rows = 0
        for line_index, line in enumerate(lines):
            if not isinstance(line, dict):
                self.issue("ERROR", "INVALID_LINE", f"line {line_index} is not an object", country=country)
                continue
            line_id = line.get("id") or f"line[{line_index}]"
            stations, segments = line.get("stations"), line.get("segments")
            if not isinstance(stations, list) or len(stations) < 2:
                self.issue("ERROR", "INVALID_STATIONS", "line needs at least two stations", country=country, line=line_id)
                continue
            if not isinstance(segments, list) or len(segments) not in {len(stations) - 1, len(stations)}:
                count = len(segments) if isinstance(segments, list) else "invalid"
                self.issue(
                    "ERROR", "SEGMENT_COUNT", f"{count} segments for {len(stations)} stations", country=country, line=line_id
                )
                continue

            station_rows += len(stations)
            segment_rows += len(segments)
            local_station_ids: list[str] = []
            station_points: list[list[float] | None] = []
            for station_index, station in enumerate(stations):
                if not isinstance(station, list) or len(station) < 4:
                    self.issue(
                        "ERROR", "INVALID_STATION_ROW", f"station {station_index} has invalid compact row", country=country, line=line_id
                    )
                    station_points.append(None)
                    continue
                local_station_ids.append(str(station[0]))
                point = [station[2], station[3]]
                if not finite_coordinate(point):
                    self.issue(
                        "ERROR", "INVALID_STATION_COORDINATE", f"station {station_index} coordinate is invalid", country=country, line=line_id
                    )
                    station_points.append(None)
                else:
                    station_points.append(point)
            for station_id, count in Counter(local_station_ids).items():
                if count > 1:
                    self.issue(
                        "ERROR", "DUPLICATE_STATION_IN_LINE", f"station id {station_id} occurs {count} times", country=country, line=line_id
                    )

            for segment_index, segment in enumerate(segments):
                if not isinstance(segment, list) or len(segment) < 3:
                    self.issue(
                        "ERROR", "INVALID_SEGMENT_ROW", f"segment {segment_index} has invalid compact row", country=country, line=line_id
                    )
                    continue
                # Compact segments are stored in station-interval order. The
                # second field is a direction/structure marker, not an index.
                ordinal, coordinates = segment_index, segment[2]
                if not isinstance(coordinates, list) or len(coordinates) < 2 or not all(
                    finite_coordinate(point) for point in coordinates
                ):
                    self.issue(
                        "ERROR", "INVALID_SEGMENT_GEOMETRY", f"segment {ordinal} has invalid coordinates", country=country, line=line_id
                    )
                    continue

                vertex_rows += len(coordinates)
                expected_from = station_points[ordinal] if ordinal < len(station_points) else None
                expected_to = station_points[(ordinal + 1) % len(station_points)]
                if expected_from and expected_to:
                    forward = haversine(coordinates[0], expected_from) + haversine(coordinates[-1], expected_to)
                    reverse = haversine(coordinates[-1], expected_from) + haversine(coordinates[0], expected_to)
                    endpoint_gap = min(forward, reverse) / 2
                    if endpoint_gap > 1_000:
                        self.issue(
                            "ERROR",
                            "SEGMENT_ENDPOINT_GAP",
                            f"segment {ordinal} endpoints average {endpoint_gap:.0f} m from station anchors",
                            country=country,
                            line=line_id,
                        )
                    elif endpoint_gap > 250:
                        self.issue(
                            "WARNING",
                            "SEGMENT_ENDPOINT_REVIEW",
                            f"segment {ordinal} endpoints average {endpoint_gap:.0f} m from station anchors",
                            country=country,
                            line=line_id,
                        )

                direct = haversine(coordinates[0], coordinates[-1])
                walked = sum(haversine(a, b) for a, b in zip(coordinates, coordinates[1:]))
                if direct >= 20_000 and (len(coordinates) == 2 or (direct > 0 and walked / direct < 1.002)):
                    self.issue(
                        "WARNING",
                        "REVIEW_STRAIGHT_CHORD",
                        f"segment {ordinal} is {direct / 1000:.1f} km with path/chord ratio {walked / direct:.5f}",
                        country=country,
                        line=line_id,
                    )
                largest_jump = max(haversine(a, b) for a, b in zip(coordinates, coordinates[1:]))
                if largest_jump > 25_000:
                    self.issue(
                        "WARNING",
                        "LARGE_VERTEX_JUMP",
                        f"segment {ordinal} contains a {largest_jump / 1000:.1f} km vertex jump",
                        country=country,
                        line=line_id,
                    )
        self.packages[country] = {
            "version": package.get("version"),
            "lines": len(lines),
            "stationRows": station_rows,
            "segments": segment_rows,
            "vertices": vertex_rows,
            "extraSegments": sum(len(line.get("extraSegments", [])) for line in lines if isinstance(line, dict)),
        }

        self.require_file(rail_dir / f"{country}-2025.sources.md", country, "MISSING_SOURCE_NOTES")
        suffix = "" if country == "jp" else f"-{country}"
        for family in ("stations", "rail-sections", "station-readings"):
            code = f"MISSING_{family.upper().replace('-', '_')}"
            self.require_file(self.repo / f"app/data/{family}{suffix}.json", country, code)
        self.require_file(self.repo / f"app/data/train-store{suffix}.json", country, "MISSING_SAMPLE_STORE")

    def audit_cross_platform(self, countries: list[str]) -> None:
        paths = {
            "js": self.repo / "app/public/railmap-style.js",
            "swift": self.repo / "ios/RailMap/RailStyle.swift",
            "copy": self.repo / "ios/copy-rail-packages.sh",
            "regions": self.repo / "ios/RailMap/RegionCatalog.swift",
            "datum": self.repo / "ios/RailMap/AppleMapDatum.swift",
        }
        for path in paths.values():
            if not path.is_file():
                self.issue("ERROR", "MISSING_CROSS_PLATFORM_FILE", f"missing {path.relative_to(self.repo)}")
                return

        js_text = paths["js"].read_text(encoding="utf-8")
        swift_text = paths["swift"].read_text(encoding="utf-8")
        js_match = re.search(r"SEGMENT_SIMPLIFY_TOLERANCE_PX\s*=\s*([0-9.]+)", js_text)
        swift_match = re.search(r"simplifyTolerance:\s*Double\s*=\s*([0-9.]+)", swift_text)
        if not js_match or not swift_match:
            self.issue("ERROR", "SIMPLIFY_CONTRACT_MISSING", "could not read Web/Swift simplification constants")
        elif js_match.group(1) != swift_match.group(1):
            self.issue(
                "ERROR", "SIMPLIFY_CONTRACT_MISMATCH", f"Web uses {js_match.group(1)} but iOS uses {swift_match.group(1)}"
            )

        copy_text = paths["copy"].read_text(encoding="utf-8")
        region_text = paths["regions"].read_text(encoding="utf-8")
        for country in countries:
            if f"case {country}" not in region_text:
                self.issue("ERROR", "IOS_REGION_MISSING", f"RegionCatalog has no case {country}", country=country)
            if not re.search(rf"\b{re.escape(country)}\b", copy_text):
                self.issue("ERROR", "IOS_COPY_MISSING", f"copy script does not mention {country}", country=country)

        datum_text = paths["datum"].read_text(encoding="utf-8")
        datum_match = re.search(r"gcj02Countries[^=]*=\s*\[([^]]*)\]", datum_text)
        if datum_match:
            datum_countries = re.findall(r'"([a-z]{2})"', datum_match.group(1))
            self.issue("INFO", "APPLE_DATUM_SCOPE", f"current MapKit GCJ-02 display scope: {', '.join(datum_countries) or 'none'}")

    def result(self) -> dict[str, Any]:
        counts = Counter(issue["severity"] for issue in self.issues)
        return {
            "repo": str(self.repo),
            "packages": self.packages,
            "counts": {level: counts.get(level, 0) for level in ("ERROR", "WARNING", "INFO")},
            "issues": self.issues,
            "limitations": [
                "Structural preflight only; it does not prove official inventory completeness, topology, surveyed alignment, or visual correctness.",
                "Straight-chord and endpoint findings are review heuristics and require primary-source evidence.",
            ],
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="repository path or a child directory")
    parser.add_argument("--countries", default="jp,tw,hk,mo", help="comma-separated package codes")
    parser.add_argument("--json", type=Path, help="write the full report to this path, or use '-' for stdout only")
    parser.add_argument("--strict", action="store_true", help="exit non-zero when heuristic warnings remain")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = find_repo(args.repo)
    countries = [item.strip().lower() for item in args.countries.split(",") if item.strip()]
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
                f"{summary['stationRows']} station rows | {summary['segments']} segments | "
                f"{summary['vertices']} vertices | {summary['extraSegments']} extra segments"
            )
        counts = result["counts"]
        print(f"  findings: {counts['ERROR']} errors, {counts['WARNING']} warnings, {counts['INFO']} info")
        for issue in result["issues"]:
            subject = "/".join(value for value in (issue.get("country"), issue.get("line")) if value)
            prefix = f" [{subject}]" if subject else ""
            print(f"  {issue['severity']} {issue['code']}{prefix}: {issue['message']}")
        print("  limitation: structural preflight; official inventory, topology, surveyed alignment, and visual checks remain required")
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
