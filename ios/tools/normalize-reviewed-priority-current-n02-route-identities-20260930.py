#!/usr/bin/env python3
"""Materialize a bounded current-N02 route-identity batch for 12 exact trips.

The output is intentionally partial.  Official train pages establish the dated
ordered passenger calls, operator material establishes named line scope, and
the shipped N02 package establishes only a current snapshot identity.  None of
those sources supplies a daily validity interval for the physical line id.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASE = ROOT / "app/data/train-service-history"
DEFAULT_CANDIDATE = (
    DEFAULT_BASE
    / "sources/candidates/reviewed-priority-current-n02-route-identities-20260930.json"
)
DEFAULT_RAIL_PACKAGE = ROOT / "app/public/rail/jp-2025.json"
SOURCE_OUTPUT = Path(
    "sources/source-registry-priority-current-n02-route-identities-20260930.jsonl"
)
LINE_OUTPUT = Path(
    "normalized/trip-lines/priority-current-n02-route-identities-20260930/seeds.jsonl"
)
FACT_OUTPUT = Path(
    "normalized/fact-sources-priority-current-n02-route-identities-20260930.jsonl"
)


def read_jsonl(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(
            json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
        ),
        encoding="utf-8",
    )


def rows_from(base: Path, pattern: str, excluded: set[Path] | None = None):
    excluded = excluded or set()
    for path in sorted(base.glob(pattern)):
        if path.is_file() and path not in excluded:
            for line_number, row in enumerate(read_jsonl(path), 1):
                yield path, line_number, row


def expand_groups(candidate: dict) -> list[dict]:
    segments = []
    for group in candidate["segment_groups"]:
        path = group["station_path"]
        if len(path) < 2:
            raise ValueError(f"empty segment group for {group['trip_id']}")
        for offset, (from_station_id, to_station_id) in enumerate(zip(path, path[1:])):
            segments.append(
                {
                    "trip_id": group["trip_id"],
                    "sequence": group["sequence_start"] + offset,
                    "from_station_id": from_station_id,
                    "to_station_id": to_station_id,
                    "current_n02_line_id": group["current_n02_line_id"],
                    "segment_source_id": group["segment_source_id"],
                    "evidence_source_ids": group["evidence_source_ids"],
                }
            )
    return segments


def normalize(base: Path, candidate_path: Path, rail_package_path: Path) -> dict[str, int]:
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    if candidate.get("schema_version") != 1:
        raise ValueError("unsupported priority route-identity candidate schema")

    segments = expand_groups(candidate)
    target_trip_ids = {row["trip_id"] for row in segments}
    if len(target_trip_ids) != 12 or len(segments) != 116:
        raise ValueError(
            f"reviewed scope changed: expected 12 trips and 116 legs, got "
            f"{len(target_trip_ids)} trips and {len(segments)} legs"
        )

    source_output = base / SOURCE_OUTPUT
    line_output = base / LINE_OUTPUT
    fact_output = base / FACT_OUTPUT
    new_sources = candidate["new_sources"]
    new_source_ids = {row["source_id"] for row in new_sources}
    if len(new_source_ids) != len(new_sources):
        raise ValueError("duplicate source_id in priority route candidate")
    existing_source_ids = {
        row["source_id"]
        for _, _, row in rows_from(
            base, "sources/source-registry*.jsonl", excluded={source_output}
        )
    }
    collisions = existing_source_ids & new_source_ids
    if collisions:
        raise ValueError(f"new source ids already exist elsewhere: {sorted(collisions)}")
    available_source_ids = existing_source_ids | new_source_ids

    trips = {
        row["trip_id"]
        for _, _, row in rows_from(base, "normalized/trips/**/*.jsonl")
    }
    missing_trips = target_trip_ids - trips
    if missing_trips:
        raise ValueError(f"unknown priority trips: {sorted(missing_trips)}")

    stop_chains: dict[str, list[dict]] = defaultdict(list)
    for _, _, row in rows_from(base, "normalized/stop-times/**/*.jsonl"):
        if row["trip_id"] in target_trip_ids:
            stop_chains[row["trip_id"]].append(row)
    for trip_id in target_trip_ids:
        stops = sorted(stop_chains[trip_id], key=lambda row: row["stop_sequence"])
        expected = list(range(1, len(stops) + 1))
        if [row["stop_sequence"] for row in stops] != expected:
            raise ValueError(f"non-contiguous stop sequence for {trip_id}")
        expected_pairs = [
            (left["station_id"], right["station_id"])
            for left, right in zip(stops, stops[1:])
        ]
        route = sorted(
            (row for row in segments if row["trip_id"] == trip_id),
            key=lambda row: row["sequence"],
        )
        if [row["sequence"] for row in route] != list(range(1, len(route) + 1)):
            raise ValueError(f"non-contiguous route sequence for {trip_id}")
        actual_pairs = [
            (row["from_station_id"], row["to_station_id"]) for row in route
        ]
        if actual_pairs != expected_pairs:
            raise ValueError(f"route does not match exact passenger-call chain for {trip_id}")

    current_station_codes = {}
    for path, line_number, row in rows_from(base, "normalized/station-identities*.jsonl"):
        if row.get("reference_kind") != "current_n02":
            continue
        station_id = row["station_id"]
        code = row.get("current_source_code")
        previous = current_station_codes.setdefault(station_id, code)
        if previous != code:
            raise ValueError(f"conflicting station identity at {path}:{line_number}")

    identities = {
        row["current_n02_line_id"]: row for row in candidate["line_identities"]
    }
    if len(identities) != len(candidate["line_identities"]) or len(identities) != 14:
        raise ValueError("expected 14 unique reviewed current-N02 line identities")
    package = json.loads(rail_package_path.read_text(encoding="utf-8"))
    if package.get("version") != "2025.5.0":
        raise ValueError("reviewed jp-2025 package version drift")
    package_lines = defaultdict(list)
    for line in package["lines"]:
        package_lines[line.get("id")].append(line)

    for group in candidate["segment_groups"]:
        identity = identities[group["current_n02_line_id"]]
        lines = package_lines.get(identity["current_n02_line_id"], [])
        if len(lines) != 1:
            raise ValueError(
                f"current line identity missing or ambiguous: {identity['current_n02_line_id']}"
            )
        station_order = [station[0] for station in lines[0].get("stations", []) if station]
        positions = []
        for station_id in group["station_path"]:
            code = current_station_codes.get(station_id)
            matching = [index for index, value in enumerate(station_order) if value == code]
            if len(matching) != 1:
                raise ValueError(
                    f"ambiguous or missing N02 station order for {station_id} on "
                    f"{identity['current_n02_line_id']}"
                )
            positions.append(matching[0])
        increasing = all(left < right for left, right in zip(positions, positions[1:]))
        decreasing = all(left > right for left, right in zip(positions, positions[1:]))
        if not (increasing or decreasing):
            raise ValueError(
                f"non-monotonic N02 station path for {group['trip_id']} on "
                f"{identity['current_n02_line_id']}: {positions}"
            )

    referenced_source_ids = set()
    line_rows = []
    fact_rows = []
    roles = candidate["evidence_source_roles"]
    for spec in segments:
        identity = identities.get(spec["current_n02_line_id"])
        if identity is None:
            raise ValueError(f"unreviewed current line id: {spec['current_n02_line_id']}")
        lines = package_lines.get(identity["current_n02_line_id"], [])
        if len(lines) != 1:
            raise ValueError(
                f"current line identity missing or ambiguous: {identity['current_n02_line_id']}"
            )
        line = lines[0]
        if (line.get("name"), line.get("operator")) != (
            identity["line_name"], identity["operator_name"]
        ):
            raise ValueError(f"current line metadata drift: {identity['current_n02_line_id']}")
        codes = {station[0] for station in line.get("stations", []) if station}
        for station_id in (spec["from_station_id"], spec["to_station_id"]):
            code = current_station_codes.get(station_id)
            if not code or code not in codes:
                raise ValueError(
                    f"{station_id} is not an endpoint member of "
                    f"{identity['current_n02_line_id']}"
                )
        referenced_source_ids.add(spec["segment_source_id"])
        referenced_source_ids.update(spec["evidence_source_ids"])
        if spec["segment_source_id"] not in spec["evidence_source_ids"]:
            raise ValueError("segment source must also be pinned as identity evidence")
        line_rows.append(
            {
                "trip_id": spec["trip_id"],
                "sequence": spec["sequence"],
                "from_station_id": spec["from_station_id"],
                "to_station_id": spec["to_station_id"],
                "line_name": identity["line_name"],
                "operator_id": identity["operator_id"],
                "reference_kind": "current_n02",
                "current_n02_line_id": identity["current_n02_line_id"],
                "source_id": spec["segment_source_id"],
                "confidence": "high",
            }
        )
        for source_id in spec["evidence_source_ids"]:
            role = roles.get(source_id)
            if not role or not role.get("role") or not role.get("locator"):
                raise ValueError(f"missing evidence role for {source_id}")
            fact_rows.append(
                {
                    "entity_type": "trip",
                    "entity_id": spec["trip_id"],
                    "field_name": (
                        f"route_lines.segment.{spec['sequence']}.current_n02_identity"
                    ),
                    "source_id": source_id,
                    "page_or_locator": (
                        f"Evidence role: {role['role']}. {role['locator']} "
                        "This is combined current-identity evidence; daily temporal "
                        "coverage remains unverified."
                    ),
                    "confidence": "high",
                    "verification_status": "partial",
                }
            )

    missing_sources = referenced_source_ids - available_source_ids
    if missing_sources:
        raise ValueError(f"unknown evidence sources: {sorted(missing_sources)}")
    if referenced_source_ids - set(roles):
        raise ValueError("some referenced sources lack role declarations")

    existing_line_keys = {
        (row["trip_id"], row["sequence"])
        for _, _, row in rows_from(
            base, "normalized/trip-lines/**/*.jsonl", excluded={line_output}
        )
    }
    collisions = existing_line_keys & {
        (row["trip_id"], row["sequence"]) for row in line_rows
    }
    if collisions:
        raise ValueError(f"route segment keys already exist elsewhere: {sorted(collisions)}")

    partial_state = {row["trip_id"]: row for row in candidate["partial_route_state"]}
    if set(partial_state) != target_trip_ids:
        raise ValueError("partial route-state scope does not match normalized trips")
    completeness_seen = set()
    for path in sorted((base / "normalized").glob("fact-completeness*.jsonl")):
        rows = read_jsonl(path)
        changed = False
        for row in rows:
            trip_id = row.get("entity_id")
            if trip_id in target_trip_ids and row.get("dimension") == "route_lines":
                if row.get("status") not in {"unknown", "partial"}:
                    raise ValueError(f"cannot promote route completeness for {trip_id}")
                row.update(
                    status="partial",
                    confidence="high",
                    notes=(
                        f"All passenger-pair legs have source-pinned current N02 identities. "
                        f"{partial_state[trip_id]['notes']} No solver result is asserted."
                    ),
                )
                completeness_seen.add(trip_id)
                changed = True
        if changed:
            write_jsonl(path, rows)
    if completeness_seen != target_trip_ids:
        raise ValueError(
            f"missing route completeness rows: {sorted(target_trip_ids - completeness_seen)}"
        )

    queue_seen = set()
    for path in sorted((base / "normalized").glob("research-queue*.jsonl")):
        rows = read_jsonl(path)
        changed = False
        for row in rows:
            trip_id = row.get("entity_id")
            if trip_id in target_trip_ids and row.get("missing_dimension") == "route_lines":
                if row.get("status") != "open":
                    raise ValueError(f"route research must remain open for {trip_id}")
                row["notes"] = (
                    "Current N02 identity and ordered endpoint membership are source-pinned. "
                    "Obtain a physical-line validity interval covering 2026-09-30 before "
                    "marking route_lines verified; no solver result has been run or asserted."
                )
                queue_seen.add(trip_id)
                changed = True
        if changed:
            write_jsonl(path, rows)
    if queue_seen != target_trip_ids:
        raise ValueError(
            f"missing route research rows: {sorted(target_trip_ids - queue_seen)}"
        )

    line_keys = [(row["trip_id"], row["sequence"]) for row in line_rows]
    fact_keys = [
        (row["entity_type"], row["entity_id"], row["field_name"], row["source_id"])
        for row in fact_rows
    ]
    if len(line_keys) != len(set(line_keys)):
        raise ValueError("duplicate generated route segment key")
    if len(fact_keys) != len(set(fact_keys)):
        raise ValueError("duplicate generated fact-source key")
    if any("rail_history_id" in row for row in line_rows):
        raise ValueError("priority current-N02 output must not assert history ids")

    write_jsonl(source_output, new_sources)
    write_jsonl(line_output, sorted(line_rows, key=lambda row: (row["trip_id"], row["sequence"])))
    write_jsonl(fact_output, sorted(fact_rows, key=lambda row: (row["entity_id"], row["field_name"], row["source_id"])))
    return {
        "trips": len(target_trip_ids),
        "segments": len(line_rows),
        "line_identities": len(identities),
        "fact_sources": len(fact_rows),
        "partial_routes": len(completeness_seen),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--canonical-dir", type=Path, default=DEFAULT_BASE)
    parser.add_argument("--candidate", type=Path, default=DEFAULT_CANDIDATE)
    parser.add_argument("--rail-package", type=Path, default=DEFAULT_RAIL_PACKAGE)
    args = parser.parse_args()
    counts = normalize(args.canonical_dir, args.candidate, args.rail_package)
    print(
        f"Normalized {counts['segments']} current-N02 passenger legs for "
        f"{counts['trips']} exact trips across {counts['line_identities']} line identities; "
        "route completeness remains partial and research remains open"
    )


if __name__ == "__main__":
    main()
