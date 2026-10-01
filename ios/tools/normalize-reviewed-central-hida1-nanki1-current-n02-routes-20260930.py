#!/usr/bin/env python3
"""Materialize two source-pinned current-N02 routes without temporal verification.

The dated train pages establish passenger calls. Operator documents establish
named line scope and the Kawarada transfer. The shipped N02 package supplies
only current line identities, not their validity on the train service date.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "sources/candidates/reviewed-central-hida1-nanki1-current-n02-routes-20260930.json"
RAIL_PACKAGE = ROOT / "app/public/rail/jp-2025.json"
SUFFIX = "central-hida1-nanki1-current-n02-routes-20260930"
SOURCE_OUTPUT = Path(f"sources/source-registry-{SUFFIX}.jsonl")
OPERATOR_OUTPUT = Path(f"normalized/operators-{SUFFIX}.jsonl")
STATION_OUTPUT = Path(f"normalized/station-identities-{SUFFIX}.jsonl")
LINE_OUTPUT = Path(f"normalized/trip-lines/{SUFFIX}/seeds.jsonl")
FACT_OUTPUT = Path(f"normalized/fact-sources-{SUFFIX}.jsonl")
STATUS_PATHS = {
    "jr-central.hida.1.2026-09-30": (
        Path("normalized/fact-completeness-central-hida1-20260930.jsonl"),
        Path("normalized/research-queue-central-hida1-20260930.jsonl"),
    ),
    "jr-central.nanki.1.2026-09-30": (
        Path("normalized/fact-completeness-central-nanki1-20260930.jsonl"),
        Path("normalized/research-queue-central-nanki1-20260930.jsonl"),
    ),
}
TARGET_TRIPS = {
    "jr-central.hida.1.2026-09-30",
    "jr-central.nanki.1.2026-09-30",
}


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def rows_from(base: Path, pattern: str, excluded: set[Path] | None = None):
    for path in sorted(base.glob(pattern)):
        if path.is_file() and path not in (excluded or set()):
            for row in read_jsonl(path):
                yield row


def require_unique_new_ids(base: Path, candidate: dict) -> None:
    new_source_ids = [row["source_id"] for row in candidate["new_sources"]]
    if len(new_source_ids) != len(set(new_source_ids)):
        raise ValueError("duplicate new source id")
    existing_sources = {
        row["source_id"]
        for row in rows_from(base, "sources/source-registry*.jsonl", {base / SOURCE_OUTPUT})
    }
    if existing_sources.intersection(new_source_ids):
        raise ValueError("new source id collides with an existing source")
    existing_operators = {
        row["operator_id"]
        for row in rows_from(base, "normalized/operators*.jsonl", {base / OPERATOR_OUTPUT})
    }
    if "ise-railway" in existing_operators:
        raise ValueError("Ise Railway operator id already exists elsewhere")
    existing_stations = {
        row["station_id"]
        for row in rows_from(base, "normalized/station-identities*.jsonl", {base / STATION_OUTPUT})
    }
    if candidate["route_only_station"]["station_id"] in existing_stations:
        raise ValueError("route-only Kawarada already exists elsewhere")
    existing_line_keys = {
        (row["trip_id"], row["sequence"])
        for row in rows_from(base, "normalized/trip-lines/**/*.jsonl", {base / LINE_OUTPUT})
    }
    if any(trip_id in TARGET_TRIPS for trip_id, _ in existing_line_keys):
        raise ValueError("a target trip already has route lines elsewhere")


def prepare_partial_route_states(base: Path) -> dict[Path, list[dict]]:
    """Update only the two route dimensions, leaving research open."""
    prepared = {}
    for trip_id, (completeness_path, queue_path) in STATUS_PATHS.items():
        completeness_path = base / completeness_path
        queue_path = base / queue_path
        completeness = read_jsonl(completeness_path)
        route_rows = [
            row for row in completeness
            if row.get("entity_type") == "trip"
            and row.get("entity_id") == trip_id
            and row.get("dimension") == "route_lines"
        ]
        if len(route_rows) != 1 or route_rows[0]["status"] not in {"unknown", "partial"}:
            raise ValueError(f"invalid existing route completeness for {trip_id}")
        route_rows[0].update(
            status="partial",
            confidence="high",
            notes=(
                "Ordered passenger route has source-pinned current N02 identities; "
                "the 2025-12-31 snapshot has no physical-line validity interval "
                "covering 2026-09-30. No solver-verified route is asserted."
            ),
        )
        queue = read_jsonl(queue_path)
        research_rows = [
            row for row in queue
            if row.get("entity_type") == "trip"
            and row.get("entity_id") == trip_id
            and row.get("missing_dimension") == "route_lines"
        ]
        if len(research_rows) != 1 or research_rows[0]["status"] != "open":
            raise ValueError(f"route research must remain open for {trip_id}")
        research_rows[0]["notes"] = (
            "Current N02 line identities and ordered endpoint membership are "
            "source-pinned. Obtain a physical-line validity interval covering "
            "2026-09-30 before verifying route_lines; no solver result is asserted."
        )
        prepared[completeness_path] = completeness
        prepared[queue_path] = queue
    return prepared


def normalize(base: Path, candidate_path: Path, rail_package_path: Path) -> dict[str, int]:
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    if candidate.get("schema_version") != 1:
        raise ValueError("unsupported candidate schema")
    if {trip["trip_id"] for trip in candidate["trips"]} != TARGET_TRIPS:
        raise ValueError("reviewed two-trip scope changed")
    require_unique_new_ids(base, candidate)

    sources = {row["source_id"] for row in candidate["new_sources"]}
    sources.update(row["source_id"] for row in rows_from(base, "sources/source-registry*.jsonl"))
    lines = {row["current_n02_line_id"]: row for row in candidate["line_identities"]}
    if len(lines) != 6 or len(lines) != len(candidate["line_identities"]):
        raise ValueError("reviewed six-line scope changed")
    package = json.loads(rail_package_path.read_text(encoding="utf-8"))
    if package.get("version") != "2025.5.0":
        raise ValueError("shipped N02 package version changed")
    package_lines = defaultdict(list)
    for line in package["lines"]:
        package_lines[line["id"]].append(line)
    for line_id, identity in lines.items():
        matches = package_lines[line_id]
        if len(matches) != 1:
            raise ValueError(f"missing or duplicate N02 line: {line_id}")
        if (matches[0]["name"], matches[0]["operator"]) != (
            identity["line_name"], identity["operator_name"]
        ):
            raise ValueError(f"N02 line metadata drift: {line_id}")

    route_only = candidate["route_only_station"]
    if (route_only["station_id"], route_only["name_snapshot"], route_only["current_source_code"]) != (
        "jp.n02.006285", "河原田", "006285"
    ):
        raise ValueError("reviewed Kawarada identity changed")
    station_codes = {
        row["station_id"]: row["current_source_code"]
        for row in rows_from(base, "normalized/station-identities*.jsonl")
        if row.get("reference_kind") == "current_n02"
    }
    station_codes[route_only["station_id"]] = route_only["current_source_code"]

    normalized_trips = {
        row["trip_id"]: row
        for row in rows_from(base, "normalized/trips/**/*.jsonl")
        if row["trip_id"] in TARGET_TRIPS
    }
    if set(normalized_trips) != TARGET_TRIPS:
        raise ValueError("target trip missing from normalized input")
    stops_by_trip = defaultdict(list)
    for row in rows_from(base, "normalized/stop-times/**/*.jsonl"):
        if row["trip_id"] in TARGET_TRIPS:
            stops_by_trip[row["trip_id"]].append(row)

    output = []
    facts = []
    route_only_count = 0
    mlit_source = "mlit-n02-2025-central-hida-nanki-route-20260930"
    for trip in candidate["trips"]:
        trip_id = trip["trip_id"]
        train_source = trip["train_source_id"]
        if train_source not in sources:
            raise ValueError(f"missing exact train source: {train_source}")
        stops = sorted(stops_by_trip[trip_id], key=lambda row: row["stop_sequence"])
        if [row["stop_sequence"] for row in stops] != list(range(1, len(stops) + 1)):
            raise ValueError(f"noncontiguous passenger calls: {trip_id}")
        stop_path = [row["station_id"] for row in stops]
        if stop_path != trip["expected_passenger_path"]:
            raise ValueError(f"exact passenger-call chain drift: {trip_id}")
        if (stop_path[0], stop_path[-1]) != (
            normalized_trips[trip_id]["origin_station_id"],
            normalized_trips[trip_id]["destination_station_id"],
        ):
            raise ValueError(f"trip endpoints changed: {trip_id}")
        if route_only["station_id"] in stop_path:
            raise ValueError("route-only Kawarada appeared in passenger calls")

        groups = trip["groups"]
        if len(groups) != (2 if "hida" in trip_id else 4):
            raise ValueError(f"reviewed group count changed: {trip_id}")
        chain = []
        sequence = 0
        for group in groups:
            line_id = group["current_n02_line_id"]
            identity = lines[line_id]
            source_id = group["line_source_id"]
            if source_id not in sources or mlit_source not in sources:
                raise ValueError(f"unknown line evidence source: {source_id}")
            path = group["station_path"]
            if len(path) < 2 or (chain and chain[-1] != path[0]):
                raise ValueError(f"broken group chain: {trip_id}")
            chain.extend(path if not chain else path[1:])
            package_order = [station[0] for station in package_lines[line_id][0]["stations"]]
            positions = []
            for station_id in path:
                code = station_codes.get(station_id)
                hits = [index for index, value in enumerate(package_order) if value == code]
                if len(hits) != 1:
                    raise ValueError(f"station not uniquely on {line_id}: {station_id}")
                positions.append(hits[0])
            if not (all(a < b for a, b in zip(positions, positions[1:])) or
                    all(a > b for a, b in zip(positions, positions[1:]))):
                raise ValueError(f"N02 station order drift on {line_id}")
            for left, right in zip(path, path[1:]):
                sequence += 1
                output.append({
                    "trip_id": trip_id,
                    "sequence": sequence,
                    "from_station_id": left,
                    "to_station_id": right,
                    "line_name": identity["line_name"],
                    "operator_id": identity["operator_id"],
                    "reference_kind": "current_n02",
                    "current_n02_line_id": line_id,
                    "source_id": source_id,
                    "confidence": "high",
                })
                for evidence_id in (train_source, source_id, mlit_source):
                    facts.append({
                        "entity_type": "trip",
                        "entity_id": trip_id,
                        "field_name": f"route_lines.segment.{sequence}.current_n02_identity",
                        "source_id": evidence_id,
                        "page_or_locator": (
                            "Exact-date passenger calls; official named-line scope; current N02 "
                            "identity and ordered endpoint membership. The 2025-12-31 snapshot "
                            "does not establish 2026-09-30 physical-line validity."
                        ),
                        "confidence": "high",
                        "verification_status": "partial",
                    })
        if [station_id for station_id in chain if station_id != route_only["station_id"]] != stop_path:
            raise ValueError(f"route path differs from passenger calls: {trip_id}")
        if trip_id.endswith("nanki.1.2026-09-30"):
            route_only_count += chain.count(route_only["station_id"])
            boundary = next(index for index, station_id in enumerate(chain) if station_id == route_only["station_id"])
            if output[-sequence + boundary - 1]["current_n02_line_id"] == output[-sequence + boundary]["current_n02_line_id"]:
                raise ValueError("route-only Kawarada must split distinct N02 identities")
        elif route_only["station_id"] in chain:
            raise ValueError("Kawarada appeared in Hida route")
    if route_only_count != 1 or len(output) != 24:
        raise ValueError("reviewed route scope changed: expected 24 segments and one Kawarada")

    operator = {
        "operator_id": "ise-railway",
        "legal_name": "伊勢鉄道株式会社",
        "display_name": "伊勢鉄道",
        "operator_type": "third_sector",
        "valid_from": "1987-03-27",
        "valid_until": None,
    }
    station = {
        "station_id": route_only["station_id"],
        "name_snapshot": route_only["name_snapshot"],
        "reference_kind": "current_n02",
        "current_source_code": route_only["current_source_code"],
    }
    keys = [(row["entity_id"], row["field_name"], row["source_id"]) for row in facts]
    if len(keys) != len(set(keys)):
        raise ValueError("duplicate route evidence fact")
    partial_states = prepare_partial_route_states(base)
    write_jsonl(base / SOURCE_OUTPUT, candidate["new_sources"])
    write_jsonl(base / OPERATOR_OUTPUT, [operator])
    write_jsonl(base / STATION_OUTPUT, [station])
    write_jsonl(base / LINE_OUTPUT, output)
    write_jsonl(base / FACT_OUTPUT, facts)
    for path, rows in partial_states.items():
        write_jsonl(path, rows)
    return {"trips": 2, "segments": len(output), "route_only_stations": route_only_count}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--canonical-dir", type=Path, default=BASE)
    parser.add_argument("--candidate", type=Path, default=CANDIDATE)
    parser.add_argument("--rail-package", type=Path, default=RAIL_PACKAGE)
    args = parser.parse_args()
    counts = normalize(args.canonical_dir, args.candidate, args.rail_package)
    print(
        f"Normalized {counts['segments']} current-N02 segments for {counts['trips']} "
        "exact trips with one route-only Kawarada; temporal route validity remains open"
    )


if __name__ == "__main__":
    main()
