#!/usr/bin/env python3
"""Find public railway lines that should reuse one compact-v1 corridor.

This audit is deliberately cross-line.  The ordinary package audits validate
one line at a time and therefore cannot see two service lines that describe the
same railway with slightly different vertices.

The high-confidence rule is intentionally narrow:

* both lines have the same railway type (high-speed, commuter, metro, ...);
* both call at the same two grouped stations consecutively;
* their surveyed paths stay in the same corridor; and
* the paths are not already coincident after compact-v1 decoding.

It reports rather than edits.  A finding is a review candidate, never an
automatic merge instruction: physical-track evidence still has to be recorded
in ``shared-corridors.json`` before either renderer may reuse the geometry.
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


REGIONS = ("us", "ca")
EARTH_M = 6_371_000.0


def haversine(a, b):
    lat1, lat2 = math.radians(a[1]), math.radians(b[1])
    dlat = lat2 - lat1
    dlon = math.radians(b[0] - a[0])
    q = (math.sin(dlat / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 2 * EARTH_M * math.asin(min(1.0, math.sqrt(q)))


def line_length(points):
    return sum(haversine(a, b) for a, b in zip(points, points[1:]))


def decode_intervals(line):
    """Decode exactly as CompactPackage.decodeIntervals does."""
    stations = line.get("stations") or []
    if not stations:
        return []
    result = []
    previous_last = None
    for index, segment in enumerate(line.get("segments") or []):
        _, continues, stored = segment[:3]
        points = [list(point) for point in stored]
        if continues:
            head = previous_last if previous_last is not None else (
                points[0] if points else None)
            points = ([head] if head is not None else []) + points
        if points:
            start = stations[index % len(stations)]
            end = stations[(index + 1) % len(stations)]
            points[0] = [start[2], start[3]]
            points[-1] = [end[2], end[3]]
            previous_last = points[-1]
        result.append(points)
    return result


def point_at(points, distance_m):
    if not points:
        return None
    if distance_m <= 0:
        return points[0]
    walked = 0.0
    for a, b in zip(points, points[1:]):
        length = haversine(a, b)
        if walked + length >= distance_m and length > 0:
            t = (distance_m - walked) / length
            return [a[0] + (b[0] - a[0]) * t,
                    a[1] + (b[1] - a[1]) * t]
        walked += length
    return points[-1]


def samples(points, spacing_m=100.0):
    length = line_length(points)
    count = max(2, int(math.ceil(length / spacing_m)) + 1)
    return [point_at(points, length * index / (count - 1))
            for index in range(count)]


def nearest_distance(point, points):
    # Sampling at 100 m and testing against vertices is sufficient for the
    # broad corridor gate, while keeping the North America audit dependency
    # free.  Densify each tested path first so long source segments do not
    # manufacture a large distance.
    return min(haversine(point, candidate) for candidate in points)


def distance_profile(a, b):
    sa, sb = samples(a), samples(b)
    distances = ([nearest_distance(point, sb) for point in sa]
                 + [nearest_distance(point, sa) for point in sb])
    distances.sort()
    p95 = distances[min(len(distances) - 1, int(len(distances) * 0.95))]
    return statistics.median(distances), p95, max(distances)


def proper_crossing_count(left, right):
    """Count interior segment crossings between two candidate paths.

    Shared endpoints and collinear/coincident track are deliberately ignored.
    An interior crossing is the high-signal version of the screenshot defect:
    two service descriptions for one station interval swap sides even though
    no junction exists in the stopping pattern.
    """
    def orientation(first, second, point):
        return ((second[0] - first[0]) * (point[1] - first[1])
                - (second[1] - first[1]) * (point[0] - first[0]))

    crossings = 0
    epsilon = 1e-14
    for first, second in zip(left, left[1:]):
        for third, fourth in zip(right, right[1:]):
            if (max(first[0], second[0]) <= min(third[0], fourth[0])
                    or max(third[0], fourth[0]) <= min(first[0], second[0])
                    or max(first[1], second[1]) <= min(third[1], fourth[1])
                    or max(third[1], fourth[1]) <= min(first[1], second[1])):
                continue
            one = orientation(first, second, third)
            two = orientation(first, second, fourth)
            three = orientation(third, fourth, first)
            four = orientation(third, fourth, second)
            if one * two < -epsilon and three * four < -epsilon:
                crossings += 1
    return crossings


def railway_type(region, line):
    if line.get("isHSR") or line.get("kind") in {"highspeed", "shinkansen"}:
        return "highspeed"
    if line.get("kind"):
        return line["kind"]

    text = " ".join((line.get("id", ""), line.get("name", ""),
                     line.get("operator", ""))).casefold()
    if region == "tw":
        if "thsr" in text or "高速" in text:
            return "highspeed"
        if any(mark in text for mark in ("mrt", "metro", "捷運")):
            return "metro"
        return "conventional"
    if region == "hk":
        if "-lr-" in text or "light rail" in text or "輕鐵" in text:
            return "lightrail"
        if "tram" in text or "電車" in text:
            return "streetcar"
        return "metro"
    if region == "mo":
        return "lightrail"
    if region == "kr":
        metro_marks = ("jihacheol", "metro", "subway", "도시철도", "지하철",
                       "ui-sinseol", "everline", "sinbundang")
        return "metro" if any(mark in text for mark in metro_marks) else "conventional"
    return "unknown"


def is_paired_alignment(line):
    """JP paired running alignments are physical alternatives, not services."""
    return bool(line.get("alignmentOf") or line.get("alignmentRole")
                or "-p1" in line.get("id", "") or "-p2" in line.get("id", ""))


def trusted_identity(region, left, right):
    """Whether metadata itself supports a shared public-service identity."""
    if region in {"us", "ca"}:
        return bool(left.get("sourceFeed")
                    and left.get("sourceFeed") == right.get("sourceFeed")
                    and left.get("operator") == right.get("operator"))
    if region == "jp" and (is_paired_alignment(left) or is_paired_alignment(right)):
        return False
    return bool(left.get("operator")
                and left.get("operator") == right.get("operator"))


def audit_package(region, package, median_limit, p95_limit):
    groups = defaultdict(list)
    for line in package.get("lines") or []:
        intervals = decode_intervals(line)
        stations = line.get("stations") or []
        for index, points in enumerate(intervals):
            if not points or index >= len(stations):
                continue
            start = stations[index][0]
            end = stations[(index + 1) % len(stations)][0]
            key = (tuple(sorted((start, end))), railway_type(region, line))
            groups[key].append((line, index, points, start, end))

    findings = []
    already = 0
    rejected_geometry = 0
    rejected_identity = 0
    for (station_pair, mode), rows in groups.items():
        if len(rows) < 2:
            continue
        for left_index in range(len(rows)):
            for right_index in range(left_index + 1, len(rows)):
                left, li, left_path, left_start, _ = rows[left_index]
                right, ri, right_path, right_start, _ = rows[right_index]
                if left.get("id") == right.get("id"):
                    continue
                if left_start != right_start:
                    right_path = list(reversed(right_path))
                if left_path == right_path:
                    already += 1
                    continue
                if not trusted_identity(region, left, right):
                    rejected_identity += 1
                    continue
                left_length = line_length(left_path)
                right_length = line_length(right_path)
                if min(left_length, right_length) < 250:
                    continue
                endpoint_gap = max(haversine(left_path[0], right_path[0]),
                                   haversine(left_path[-1], right_path[-1]))
                ratio = max(left_length, right_length) / min(left_length, right_length)
                median, p95, maximum = distance_profile(left_path, right_path)
                if (endpoint_gap > 160 or ratio > 1.25
                        or median > median_limit or p95 > p95_limit):
                    rejected_geometry += 1
                    continue
                canonical, other = sorted((left, right), key=lambda item: (
                    -(sum(len(piece) for piece in decode_intervals(item))),
                    item.get("id", "")))
                findings.append({
                    "region": region,
                    "status": "candidate",
                    "type": mode,
                    "stationIds": list(station_pair),
                    "stationNames": sorted({
                        row[1] for item in (left, right)
                        for row in item.get("stations", [])
                        if row[0] in station_pair
                    }),
                    "lineIds": sorted((left["id"], right["id"])),
                    "canonicalLineId": canonical["id"],
                    "otherLineId": other["id"],
                    "sourceFeed": left.get("sourceFeed"),
                    "operator": left.get("operator"),
                    "leftInterval": li,
                    "rightInterval": ri,
                    "lengthMeters": round(min(left_length, right_length), 1),
                    "endpointGapMeters": round(endpoint_gap, 1),
                    "medianSeparationMeters": round(median, 1),
                    "p95SeparationMeters": round(p95, 1),
                    "maxSeparationMeters": round(maximum, 1),
                    "properCrossings": proper_crossing_count(
                        left_path, right_path),
                })
    findings.sort(key=lambda row: (-row["lengthMeters"], row["lineIds"]))
    return findings, {
        "lines": len(package.get("lines") or []),
        "candidatePairs": len(findings),
        "alreadyCoincidentPairs": already,
        "rejectedDifferentIdentity": rejected_identity,
        "rejectedDifferentCorridor": rejected_geometry,
    }


def markdown(report):
    lines = [
        "# Shared railway corridor audit",
        "",
        "Geometry candidates where same-type, same-operator/service-source lines ",
        "call at the same consecutive station pair but decode differently. A row ",
        "remains open until operator data and physical-track evidence both confirm it.",
        "",
        "| Region | Open candidates | Reviewed fixes | Already coincident | Different identity | Different corridor |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for region in REGIONS:
        row = report["regions"][region]
        lines.append(
            f"| {region.upper()} | {row['openCandidatePairs']} | "
            f"{row['reviewedCorridors']} | {row['alreadyCoincidentPairs']} | "
            f"{row['rejectedDifferentIdentity']} | "
            f"{row['rejectedDifferentCorridor']} |")
    lines += ["", "## Reviewed fixes", ""]
    for row in report["reviewedCorridors"]:
        lines.append(
            f"- **{row['region'].upper()} · {row['id']}** — "
            f"{', '.join(f'`{line_id}`' for line_id in row['lineIds'])}; "
            f"{len(row['evidenceTypes'])} source types")
    lines += ["", "## Open review candidates", ""]
    open_findings = sorted(
        (row for row in report["findings"] if row["status"] == "candidate"),
        key=lambda row: (-row.get("properCrossings", 0),
                         -row["lengthMeters"], row["lineIds"]),
    )
    for row in open_findings:
        crossing_note = (f", {row['properCrossings']} interior crossings"
                         if row.get("properCrossings") else "")
        lines.append(
            f"- **{row['region'].upper()} · {row['stationNames']}** — "
            f"`{row['lineIds'][0]}` / `{row['lineIds'][1]}`; "
            f"{row['lengthMeters']:.0f} m, median {row['medianSeparationMeters']:.1f} m, "
            f"p95 {row['p95SeparationMeters']:.1f} m{crossing_note}")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rail-dir", type=Path,
                        default=Path(__file__).resolve().parents[2] / "public" / "rail")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--median-m", type=float, default=35.0)
    parser.add_argument("--p95-m", type=float, default=110.0)
    args = parser.parse_args()

    report = {
        "format": "jtm-shared-corridor-audit-v1",
        "criteria": {
            "sameRailwayType": True,
            "sameOperatorOrOfficialFeed": True,
            "consecutiveSharedStationPair": True,
            "medianSeparationMeters": args.median_m,
            "p95SeparationMeters": args.p95_m,
            "interiorCrossingsReported": True,
        },
        "regions": {},
        "findings": [],
        "reviewedCorridors": [],
    }
    for region in REGIONS:
        path = args.rail_dir / f"{region}-2025.json"
        package = json.loads(path.read_text())
        findings, summary = audit_package(
            region, package, args.median_m, args.p95_m)
        report["regions"][region] = summary
        report["findings"].extend(findings)

    registry_path = args.rail_dir / "shared-corridors.json"
    registry = (json.loads(registry_path.read_text())
                if registry_path.exists() else {"corridors": []})
    reviewed_line_pairs = {}
    reviewed_station_pairs = []
    for corridor in registry.get("corridors") or []:
        line_ids = sorted({
            line_id
            for line_id in (
                list(corridor.get("lineIds") or [])
                + [member.get("lineId")
                   for member in corridor.get("members") or []]
                + [line_id
                   for interval in corridor.get("intervals") or []
                   for line_id in interval.get("lineIds") or []]
            )
            if line_id
        })
        evidence_types = sorted({row.get("type")
                                 for row in corridor.get("evidence") or []
                                 if row.get("type")})
        report["reviewedCorridors"].append({
            "id": corridor.get("id"),
            "region": corridor.get("region"),
            "lineIds": line_ids,
            "evidenceTypes": evidence_types,
        })
        if corridor.get("stationPairs"):
            for station_pair in corridor["stationPairs"]:
                reviewed_station_pairs.append({
                    "region": corridor.get("region"),
                    "stationIds": tuple(sorted(station_pair)),
                    "lineIds": set(line_ids),
                    "corridorId": corridor.get("id"),
                })
        for interval in corridor.get("intervals") or []:
            station_pair = interval.get("stationCodes") or []
            interval_lines = set(interval.get("lineIds") or [])
            if len(station_pair) == 2 and len(interval_lines) >= 2:
                reviewed_station_pairs.append({
                    "region": corridor.get("region"),
                    "stationIds": tuple(sorted(station_pair)),
                    "lineIds": interval_lines,
                    "corridorId": corridor.get("id"),
                })
        if len(line_ids) == 2 and not corridor.get("stationPairs"):
            reviewed_line_pairs[(corridor.get("region"), tuple(line_ids))] = corridor.get("id")

    reviewed_candidates = defaultdict(int)
    for finding in report["findings"]:
        corridor_id = reviewed_line_pairs.get(
            (finding["region"], tuple(finding["lineIds"])))
        if not corridor_id:
            finding_lines = set(finding["lineIds"])
            finding_stations = tuple(sorted(finding["stationIds"]))
            corridor_id = next((
                row["corridorId"] for row in reviewed_station_pairs
                if row["region"] == finding["region"]
                and row["stationIds"] == finding_stations
                and finding_lines <= row["lineIds"]
            ), None)
        if corridor_id:
            finding["status"] = "reviewed-fixed"
            finding["reviewedCorridorId"] = corridor_id
            reviewed_candidates[finding["region"]] += 1
    reviewed_counts = defaultdict(int)
    for corridor in report["reviewedCorridors"]:
        reviewed_counts[corridor["region"]] += 1
    for region, summary in report["regions"].items():
        summary["reviewedCandidatePairs"] = reviewed_candidates[region]
        summary["openCandidatePairs"] = (
            summary["candidatePairs"] - reviewed_candidates[region])
        summary["reviewedCorridors"] = reviewed_counts[region]

    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.json:
        args.json.write_text(encoded)
    else:
        print(encoded, end="")
    if args.markdown:
        args.markdown.write_text(markdown(report))


if __name__ == "__main__":
    main()
