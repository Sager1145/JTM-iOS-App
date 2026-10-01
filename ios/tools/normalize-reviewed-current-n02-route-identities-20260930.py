#!/usr/bin/env python3
"""Attach reviewed current-N02 identities to bounded partial route evidence.

Run this after normalize-reviewed-route-evidence.py.  The normalizer preserves
partial route completeness because the current N02 snapshot has no per-line
daily validity interval.  The uncalled Nippori physical boundary is represented
only as a route-segment endpoint, never as a canonical timetable stop.
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
    / "sources/candidates/reviewed-current-n02-route-identities-20260930.json"
)
DEFAULT_RAIL_PACKAGE = ROOT / "app/public/rail/jp-2025.json"
SOURCE_OUTPUT = Path("sources/source-registry-current-n02-route-identities-20260930.jsonl")
STATION_OUTPUT = Path(
    "normalized/station-identities-current-n02-route-identities-20260930.jsonl"
)
ADDITION_OUTPUT = Path(
    "normalized/trip-lines/current-n02-route-identities-20260930/urban-segments.jsonl"
)
FACT_OUTPUT = Path("normalized/fact-sources-current-n02-route-identities-20260930.jsonl")


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
    patches = []
    for group in candidate["segment_groups"]:
        path = group["station_path"]
        if len(path) < 2:
            raise ValueError(f"empty segment group for {group['trip_id']}")
        for offset, (from_station_id, to_station_id) in enumerate(zip(path, path[1:])):
            patches.append(
                {
                    **{
                        key: group[key]
                        for key in (
                            "trip_id",
                            "current_n02_line_id",
                            "segment_source_id",
                            "evidence_source_ids",
                            "evidence_locator",
                        )
                    },
                    "input_sequence": group["input_sequence_start"] + offset,
                    "output_sequence": group["output_sequence_start"] + offset,
                    "prior_output_sequence": (
                        group["prior_output_sequence_start"] + offset
                        if "prior_output_sequence_start" in group
                        else None
                    ),
                    "from_station_id": from_station_id,
                    "to_station_id": to_station_id,
                }
            )
    return patches


def source_ids_in(base: Path, excluded: Path) -> set[str]:
    return {
        row["source_id"]
        for _, _, row in rows_from(
            base, "sources/source-registry*.jsonl", excluded={excluded}
        )
    }


def current_station_codes(base: Path, excluded: set[Path] | None = None) -> dict[str, str]:
    result = {}
    for path, line_number, row in rows_from(
        base, "normalized/station-identities*.jsonl", excluded=excluded
    ):
        if row.get("reference_kind") != "current_n02":
            continue
        station_id = row["station_id"]
        code = row.get("current_source_code")
        if station_id in result and result[station_id] != code:
            raise ValueError(f"conflicting station identity at {path}:{line_number}")
        result[station_id] = code
    return result


def locate_segment(
    row_locations: list[tuple[Path, int, dict]], spec: dict
) -> tuple[Path, int, dict]:
    matches = [
        item
        for item in row_locations
        if item[2]["trip_id"] == spec["trip_id"]
        and item[2]["from_station_id"] == spec["from_station_id"]
        and item[2]["to_station_id"] == spec["to_station_id"]
    ]
    if len(matches) != 1:
        raise ValueError(
            "expected one existing segment for "
            f"{spec['trip_id']} {spec['from_station_id']}->{spec['to_station_id']}; "
            f"found {len(matches)}"
        )
    path, line_number, row = matches[0]
    allowed_sequences = {
        value
        for value in (
            spec["input_sequence"], spec["output_sequence"],
            spec.get("prior_output_sequence"),
        )
        if value is not None
    }
    if row["sequence"] not in allowed_sequences:
        raise ValueError(
            f"sequence drift at {path}:{line_number}: {row['sequence']} not in "
            f"{sorted(allowed_sequences)}"
        )
    return path, line_number, row


def locate_boundary_segment(
    row_locations: list[tuple[Path, int, dict]], spec: dict
) -> tuple[Path, int, dict]:
    """Find either the original passenger-pair leg or its normalized first half."""
    allowed_to_station_ids = {spec["to_station_id"], spec["boundary_station_id"]}
    matches = [
        item
        for item in row_locations
        if item[2]["trip_id"] == spec["trip_id"]
        and item[2]["from_station_id"] == spec["from_station_id"]
        and item[2]["to_station_id"] in allowed_to_station_ids
    ]
    if len(matches) != 1:
        raise ValueError(
            "expected one unsplit or normalized boundary segment for "
            f"{spec['trip_id']} {spec['from_station_id']}->"
            f"{sorted(allowed_to_station_ids)}; found {len(matches)}"
        )
    path, line_number, row = matches[0]
    if row["sequence"] not in {spec["input_sequence"], spec["first_sequence"]}:
        raise ValueError(
            f"boundary sequence drift at {path}:{line_number}: {row['sequence']}"
        )
    return path, line_number, row


def identity_fact_rows(
    spec: dict,
    output_sequence: int,
    confidence: str,
    evidence_source_roles: dict[str, dict],
) -> list[dict]:
    rows = []
    for source_id in spec["evidence_source_ids"]:
        evidence = evidence_source_roles[source_id]
        rows.append(
            {
                "entity_type": "trip",
                "entity_id": spec["trip_id"],
                "field_name": f"route_lines.segment.{output_sequence}.current_n02_identity",
                "source_id": source_id,
                "page_or_locator": (
                    f"Evidence role: {evidence['role']}. {evidence['locator']} "
                    "This source is one part of the combined identity review; "
                    "daily temporal coverage remains unverified."
                ),
                "confidence": confidence,
                "verification_status": "partial",
            }
        )
    return rows


def normalize(base: Path, candidate_path: Path, rail_package_path: Path) -> dict[str, int]:
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    if candidate.get("schema_version") != 1:
        raise ValueError("unsupported route-identity candidate schema")

    patches = expand_groups(candidate)
    additions = candidate["new_segments"]
    boundary_splits = candidate["route_only_boundary_splits"]
    route_only_stations = candidate["route_only_station_identities"]
    if (len(patches), len(additions), len(boundary_splits), len(route_only_stations)) != (57, 4, 2, 1):
        raise ValueError(
            "reviewed scope changed: expected 57 patches, 4 additions, "
            "2 route-only boundary splits and 1 route-only station identity"
        )

    source_output = base / SOURCE_OUTPUT
    station_output = base / STATION_OUTPUT
    addition_output = base / ADDITION_OUTPUT
    fact_output = base / FACT_OUTPUT
    new_sources = candidate["new_sources"]
    new_source_ids = {row["source_id"] for row in new_sources}
    if len(new_source_ids) != len(new_sources):
        raise ValueError("duplicate new source_id")
    existing_source_ids = source_ids_in(base, source_output)
    collisions = new_source_ids & existing_source_ids
    if collisions:
        raise ValueError(f"new source ids already exist elsewhere: {sorted(collisions)}")
    available_source_ids = existing_source_ids | new_source_ids

    identities = {
        row["current_n02_line_id"]: row for row in candidate["line_identities"]
    }
    if len(identities) != len(candidate["line_identities"]):
        raise ValueError("duplicate line identity in candidate")
    package = json.loads(rail_package_path.read_text(encoding="utf-8"))
    package_lines = defaultdict(list)
    for line in package["lines"]:
        package_lines[line.get("id")].append(line)
    station_codes = current_station_codes(base, excluded={station_output})
    station_rows = []
    package_stations = defaultdict(set)
    for line in package["lines"]:
        for station in line.get("stations", []):
            if len(station) >= 2:
                package_stations[station[0]].add(station[1])
    for spec in route_only_stations:
        station_id = spec["station_id"]
        code = spec["current_source_code"]
        if station_id in station_codes:
            raise ValueError(f"route-only station already exists elsewhere: {station_id}")
        if spec.get("reference_kind") != "current_n02" or spec.get("rail_history_id") is not None:
            raise ValueError(f"invalid route-only current station identity: {station_id}")
        if spec["name_snapshot"] not in package_stations.get(code, set()):
            raise ValueError(f"route-only station metadata drift: {station_id}")
        station_codes[station_id] = code
        station_rows.append(
            {
                "station_id": station_id,
                "name_snapshot": spec["name_snapshot"],
                "reference_kind": "current_n02",
                "current_source_code": code,
                "rail_history_id": None,
            }
        )
    route_only_station_ids = {row["station_id"] for row in station_rows}
    # A boundary is uncalled only for the trips declared here; other trains can stop there.
    route_only_trip_ids = {spec["trip_id"] for spec in boundary_splits}
    for path, line_number, row in rows_from(
        base, "normalized/stop-times/**/*.jsonl"
    ):
        if (row.get("trip_id") in route_only_trip_ids
                and row.get("station_id") in route_only_station_ids):
            raise ValueError(
                f"route-only boundary must not be a passenger stop on this trip at {path}:{line_number}"
            )

    referenced_source_ids = set()
    for identity in identities.values():
        referenced_source_ids.update(identity["identity_source_ids"])
        lines = package_lines.get(identity["current_n02_line_id"], [])
        if len(lines) != 1:
            raise ValueError(
                f"current line identity is missing or ambiguous: {identity['current_n02_line_id']}"
            )
        line = lines[0]
        if (line.get("name"), line.get("operator")) != (
            identity["line_name"],
            identity["operator_name"],
        ):
            raise ValueError(
                f"current line metadata drift: {identity['current_n02_line_id']}"
            )

    for spec in patches + additions + boundary_splits:
        referenced_source_ids.add(spec["segment_source_id"])
        referenced_source_ids.update(spec["evidence_source_ids"])
    for spec in route_only_stations:
        referenced_source_ids.update(spec["evidence_source_ids"])
    missing_sources = referenced_source_ids - available_source_ids
    if missing_sources:
        raise ValueError(f"unknown evidence sources: {sorted(missing_sources)}")
    evidence_source_roles = candidate.get("evidence_source_roles", {})
    missing_roles = referenced_source_ids - set(evidence_source_roles)
    if missing_roles:
        raise ValueError(f"missing evidence roles: {sorted(missing_roles)}")
    for source_id in referenced_source_ids:
        evidence = evidence_source_roles[source_id]
        if (
            not isinstance(evidence, dict)
            or not isinstance(evidence.get("role"), str)
            or not evidence["role"].strip()
            or not isinstance(evidence.get("locator"), str)
            or not evidence["locator"].strip()
        ):
            raise ValueError(f"invalid evidence role for {source_id}")

    line_files = sorted((base / "normalized/trip-lines").rglob("*.jsonl"))
    line_files = [path for path in line_files if path != addition_output]
    rows_by_file = {path: read_jsonl(path) for path in line_files}
    row_locations = [
        (path, line_number, row)
        for path, rows in rows_by_file.items()
        for line_number, row in enumerate(rows, 1)
    ]
    changed_paths = set()
    fact_rows = []

    def assert_identity_endpoints(spec: dict, identity: dict) -> None:
        line = package_lines[identity["current_n02_line_id"]][0]
        line_codes = {station[0] for station in line.get("stations", []) if station}
        for station_id in (spec["from_station_id"], spec["to_station_id"]):
            code = station_codes.get(station_id)
            if not code or code not in line_codes:
                raise ValueError(
                    f"{station_id} is not a current endpoint on {identity['current_n02_line_id']}"
                )

    for spec in patches:
        identity = identities.get(spec["current_n02_line_id"])
        if identity is None:
            raise ValueError(f"unreviewed current line id: {spec['current_n02_line_id']}")
        assert_identity_endpoints(spec, identity)
        path, line_number, row = locate_segment(row_locations, spec)
        if row.get("operator_id") != identity["operator_id"]:
            raise ValueError(f"operator drift at {path}:{line_number}")
        if row.get("reference_kind") not in (None, "current_n02"):
            raise ValueError(f"historical identity cannot be overwritten at {path}:{line_number}")
        existing_id = row.get("current_n02_line_id")
        if existing_id not in (None, identity["current_n02_line_id"]):
            raise ValueError(f"current identity conflict at {path}:{line_number}")
        row.update(
            sequence=spec["output_sequence"],
            line_name=identity["line_name"],
            reference_kind="current_n02",
            current_n02_line_id=identity["current_n02_line_id"],
            source_id=spec["segment_source_id"],
        )
        row.pop("rail_history_id", None)
        changed_paths.add(path)
        fact_rows.extend(
            identity_fact_rows(
                spec,
                spec["output_sequence"],
                row["confidence"],
                evidence_source_roles,
            )
        )

    addition_rows = []
    for spec in additions:
        identity = identities.get(spec["current_n02_line_id"])
        if identity is None:
            raise ValueError(f"unreviewed current line id: {spec['current_n02_line_id']}")
        assert_identity_endpoints(spec, identity)
        addition_rows.append(
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
                "confidence": spec["confidence"],
            }
        )
        fact_rows.extend(
            identity_fact_rows(
                spec, spec["sequence"], spec["confidence"], evidence_source_roles
            )
        )

    for spec in boundary_splits:
        if spec["boundary_station_id"] not in route_only_station_ids:
            raise ValueError(
                f"undeclared route-only boundary for {spec['trip_id']}: "
                f"{spec['boundary_station_id']}"
            )
        incoming = identities.get(spec["incoming_current_n02_line_id"])
        outgoing = identities.get(spec["outgoing_current_n02_line_id"])
        if incoming is None or outgoing is None or incoming == outgoing:
            raise ValueError(f"invalid route-only line transition for {spec['trip_id']}")
        first = {
            **spec,
            "output_sequence": spec["first_sequence"],
            "from_station_id": spec["from_station_id"],
            "to_station_id": spec["boundary_station_id"],
            "current_n02_line_id": incoming["current_n02_line_id"],
        }
        second = {
            **spec,
            "sequence": spec["second_sequence"],
            "from_station_id": spec["boundary_station_id"],
            "to_station_id": spec["to_station_id"],
            "current_n02_line_id": outgoing["current_n02_line_id"],
        }
        assert_identity_endpoints(first, incoming)
        assert_identity_endpoints(second, outgoing)
        path, line_number, row = locate_boundary_segment(row_locations, spec)
        if row.get("operator_id") != incoming["operator_id"] or incoming["operator_id"] != outgoing["operator_id"]:
            raise ValueError(f"operator drift at {path}:{line_number}")
        if row.get("reference_kind") not in (None, "current_n02"):
            raise ValueError(f"historical identity cannot be overwritten at {path}:{line_number}")
        row.update(
            sequence=spec["first_sequence"],
            to_station_id=spec["boundary_station_id"],
            line_name=incoming["line_name"],
            reference_kind="current_n02",
            current_n02_line_id=incoming["current_n02_line_id"],
            source_id=spec["segment_source_id"],
        )
        row.pop("rail_history_id", None)
        changed_paths.add(path)
        addition_rows.append(
            {
                "trip_id": spec["trip_id"],
                "sequence": spec["second_sequence"],
                "from_station_id": spec["boundary_station_id"],
                "to_station_id": spec["to_station_id"],
                "line_name": outgoing["line_name"],
                "operator_id": outgoing["operator_id"],
                "reference_kind": "current_n02",
                "current_n02_line_id": outgoing["current_n02_line_id"],
                "source_id": spec["segment_source_id"],
                "confidence": row["confidence"],
            }
        )
        fact_rows.extend(
            identity_fact_rows(
                first, spec["first_sequence"], row["confidence"], evidence_source_roles
            )
        )
        fact_rows.extend(
            identity_fact_rows(
                second, spec["second_sequence"], row["confidence"], evidence_source_roles
            )
        )

    all_rows = [row for rows in rows_by_file.values() for row in rows] + addition_rows
    keys = [(row["trip_id"], row["sequence"]) for row in all_rows]
    if len(keys) != len(set(keys)):
        duplicates = sorted(key for key in set(keys) if keys.count(key) > 1)
        raise ValueError(f"duplicate trip line sequence after normalization: {duplicates}")

    target_trip_ids = {
        spec["trip_id"] for spec in patches + additions + boundary_splits
    }
    for trip_id in target_trip_ids:
        rows = sorted(
            (row for row in all_rows if row["trip_id"] == trip_id),
            key=lambda row: row["sequence"],
        )
        if [row["sequence"] for row in rows] != list(range(1, len(rows) + 1)):
            raise ValueError(f"non-contiguous route sequence for {trip_id}")
        if any(
            left["to_station_id"] != right["from_station_id"]
            for left, right in zip(rows, rows[1:])
        ):
            raise ValueError(f"discontinuous route chain for {trip_id}")

    partial_state = {
        row["trip_id"]: row for row in candidate["partial_route_state"]
    }
    if set(partial_state) != target_trip_ids:
        raise ValueError("partial route-state scope does not match normalized trips")
    completeness_seen = set()
    for path in sorted((base / "normalized").glob("fact-completeness*.jsonl")):
        rows = read_jsonl(path)
        changed = False
        for row in rows:
            trip_id = row.get("entity_id")
            if trip_id in partial_state and row.get("dimension") == "route_lines":
                if row.get("status") != "partial":
                    raise ValueError(f"route completeness must remain partial for {trip_id}")
                row["notes"] = partial_state[trip_id]["completeness_notes"]
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
            if trip_id in partial_state and row.get("missing_dimension") == "route_lines":
                if row.get("status") != "open":
                    raise ValueError(f"route research must remain open for {trip_id}")
                row["notes"] = partial_state[trip_id]["research_notes"]
                queue_seen.add(trip_id)
                changed = True
        if changed:
            write_jsonl(path, rows)
    if queue_seen != target_trip_ids:
        raise ValueError(f"missing route research rows: {sorted(target_trip_ids - queue_seen)}")

    completeness = {
        (row["entity_id"], row["dimension"]): row
        for _, _, row in rows_from(base, "normalized/fact-completeness*.jsonl")
    }
    for trip_id in target_trip_ids:
        route = completeness.get((trip_id, "route_lines"))
        if route is None or route["status"] != "partial":
            raise ValueError(f"route completeness must remain partial for {trip_id}")

    fact_keys = [
        (row["entity_type"], row["entity_id"], row["field_name"], row["source_id"])
        for row in fact_rows
    ]
    if len(fact_keys) != len(set(fact_keys)):
        raise ValueError("duplicate generated fact-source key")

    for path in changed_paths:
        write_jsonl(path, rows_by_file[path])
    write_jsonl(source_output, new_sources)
    write_jsonl(station_output, station_rows)
    write_jsonl(addition_output, sorted(addition_rows, key=lambda row: (row["trip_id"], row["sequence"])))
    write_jsonl(
        fact_output,
        sorted(
            fact_rows,
            key=lambda row: (
                row["entity_id"], row["field_name"], row["source_id"]
            ),
        ),
    )
    return {
        "patched_segments": len(patches),
        "split_segments": len(boundary_splits),
        "added_segments": len(additions) + len(boundary_splits),
        "route_only_stations": len(station_rows),
        "fact_sources": len(fact_rows),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--canonical-dir", type=Path, default=DEFAULT_BASE)
    parser.add_argument("--candidate", type=Path, default=DEFAULT_CANDIDATE)
    parser.add_argument("--rail-package", type=Path, default=DEFAULT_RAIL_PACKAGE)
    args = parser.parse_args()
    counts = normalize(args.canonical_dir, args.candidate, args.rail_package)
    print(
        "Normalized "
        f"{counts['patched_segments']} current-N02 identities, "
        f"split {counts['split_segments']} Nippori-boundary legs, added "
        f"{counts['added_segments']} urban segments, and wrote "
        f"{counts['route_only_stations']} route-only station identity; "
        "route completeness remains partial"
    )


if __name__ == "__main__":
    main()
