#!/usr/bin/env python3
"""Normalize the reviewed JR Shikoku Ishizuchi Silver Week preview batch."""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CANDIDATE_NAME = "jr-shikoku-ishizuchi-2026summer-following-candidate.json"
SUFFIX = "ishizuchi-next-batch"
SCOPE = "jr-shikoku"
STATION_SOURCE_ID = "jtm-current-station-directory"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED_SOURCE_ID = "jr-shikoku-summer-20260515-ishizuchi-silver-week-following"
EXPECTED_URL = "https://www.jr-shikoku.co.jp/03_news/press/assets/2026/07/15/20260515%20.pdf"
EXPECTED_HASH = "sha256:64e69d7df9da8d58326653d9334a7b0683c1645b5b6ba2d42d32d0f714d3c2c6"
EXPECTED_NUMBERS = {str(value) for value in range(3, 29)}
FIVE_DAY_NUMBERS = {"3", "4"}


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def iter_rows(base: Path, pattern: str, excluded: Path | None = None):
    excluded_resolved = excluded.resolve() if excluded is not None else None
    for path in sorted(base.glob(pattern)):
        if not path.is_file() or (excluded_resolved is not None and path.resolve() == excluded_resolved):
            continue
        for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if raw.strip():
                yield path, line_number, json.loads(raw)


def checked_source(candidate_source: dict) -> dict:
    if candidate_source.get("source_id") != EXPECTED_SOURCE_ID:
        raise ValueError("Reviewed Ishizuchi source id changed")
    if candidate_source.get("url_or_locator") != EXPECTED_URL:
        raise ValueError("Reviewed Ishizuchi official PDF URL changed")
    if candidate_source.get("content_hash") != EXPECTED_HASH:
        raise ValueError("Reviewed Ishizuchi PDF hash changed")
    # page_or_locator is candidate evidence metadata, not a source_documents field.
    return {
        key: value
        for key, value in candidate_source.items()
        if key != "page_or_locator"
    }


def source_rows(base: Path, source: dict, output: Path) -> list[dict]:
    for path, line_number, existing in iter_rows(base, "sources/source-registry*.jsonl", output):
        if existing["source_id"] != source["source_id"]:
            continue
        if existing != source:
            raise ValueError(f"Conflicting source id at {path}:{line_number}")
        return []
    return [source]


def service_rows(base: Path, service: dict, valid_from: str, valid_until_inclusive: str, output: Path) -> list[dict]:
    row = {
        **service,
        "historical_generation": 1,
        "first_verified_date": valid_from,
        "last_verified_date": valid_until_inclusive,
    }
    core = {key: row[key] for key in ("service_id", "canonical_name", "service_class", "historical_generation", "jr_scope")}
    for path, line_number, existing in iter_rows(base, "normalized/services*.jsonl", output):
        if existing["service_id"] != row["service_id"]:
            continue
        actual = {key: existing.get(key) for key in core}
        if actual != core:
            raise ValueError(f"Conflicting service id at {path}:{line_number}: {actual} != {core}")
        return []
    return [row]


def resolve_stations(base: Path, names: set[str], output: Path) -> tuple[dict[str, dict], list[dict]]:
    package = json.loads((REPO_ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    resolved = {}
    for name in sorted(names):
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == "四国旅客鉄道"
            for station in line["stations"]
            if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(f"Ambiguous or missing JR Shikoku station identity for {name}: {sorted(codes)}")
        code = codes.pop()
        resolved[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
        }

    existing_by_id = defaultdict(list)
    for path, line_number, existing in iter_rows(base, "normalized/station-identities*.jsonl", output):
        existing_by_id[existing["station_id"]].append((path, line_number, existing))
    for row in resolved.values():
        expected = {key: row[key] for key in ("station_id", "name_snapshot", "reference_kind", "current_source_code")}
        for path, line_number, existing in existing_by_id.get(row["station_id"], []):
            actual = {key: existing.get(key) for key in expected}
            if actual != expected:
                raise ValueError(f"Conflicting station identity at {path}:{line_number}: {actual} != {expected}")
    new_rows = [row for row in resolved.values() if row["station_id"] not in existing_by_id]
    return resolved, sorted(new_rows, key=lambda row: row["station_id"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--canonical-dir",
        type=Path,
        default=REPO_ROOT / "app/data/train-service-history",
        help="Canonical tree to update; defaults to the reviewed production inputs.",
    )
    args = parser.parse_args()
    base = args.canonical_dir.expanduser().resolve()
    if not (base / "manifest.json").is_file():
        raise SystemExit(f"canonical directory lacks manifest.json: {base}")
    candidate_path = base / "candidates" / CANDIDATE_NAME
    if not candidate_path.is_file():
        raise SystemExit(f"canonical directory lacks reviewed candidate: {candidate_path}")

    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    if candidate.get("candidate_status") != "visually_reviewed_preparation_only":
        raise ValueError("Ishizuchi candidate must retain its double-reviewed preparation status")
    if candidate.get("canonical") is not False:
        raise ValueError("Ishizuchi candidate must remain non-canonical input")
    source = checked_source(candidate["source"])
    if candidate.get("database_as_of_date") != json.loads((base / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Candidate database_as_of_date no longer matches the target manifest")

    trips_source = candidate["trips"]
    public_numbers = {trip["public_number"] for trip in trips_source}
    if len(trips_source) != 26 or public_numbers != EXPECTED_NUMBERS:
        raise ValueError("Reviewed Ishizuchi 26-row inventory changed")
    five_dates = tuple(candidate["evidence_interpretation"]["date_cell_9_19_to_23"])
    six_dates = tuple(candidate["evidence_interpretation"]["date_cell_9_18_to_23"])
    if five_dates != tuple(f"2026-09-{day:02d}" for day in range(19, 24)):
        raise ValueError("Reviewed five-day merged cell changed")
    if six_dates != tuple(f"2026-09-{day:02d}" for day in range(18, 24)):
        raise ValueError("Reviewed six-day merged cell changed")
    for trip in trips_source:
        expected_dates = five_dates if trip["public_number"] in FIVE_DAY_NUMBERS else six_dates
        if tuple(trip["operating_dates"]) != expected_dates:
            raise ValueError(f"Reviewed date scope changed for Ishizuchi {trip['public_number']}")
    if sum(len(trip["operating_dates"]) for trip in trips_source) != 154:
        raise ValueError("Reviewed Ishizuchi occurrence total changed")

    source_output = base / f"sources/source-registry-{SUFFIX}.jsonl"
    service_output = base / f"normalized/services-{SUFFIX}.jsonl"
    station_output = base / f"normalized/station-identities-{SUFFIX}.jsonl"
    source_documents = source_rows(base, source, source_output)

    existing_source_ids = {
        row["source_id"]
        for _, _, row in iter_rows(base, "sources/source-registry*.jsonl", source_output)
    }
    existing_source_ids.update(row["source_id"] for row in source_documents)
    if STATION_SOURCE_ID not in existing_source_ids:
        raise ValueError(f"Missing station directory source {STATION_SOURCE_ID}")

    valid_from = "2026-09-18"
    valid_until = "2026-09-24"
    service = candidate["service"]
    services = service_rows(base, service, valid_from, "2026-09-23", service_output)
    stations, new_station_rows = resolve_stations(
        base,
        {value for trip in trips_source for value in (trip["origin"], trip["destination"])},
        station_output,
    )

    version_id = "jr-shikoku.ishizuchi.silver-week-2026.version"
    calendar_ids = {
        "five": "jr-shikoku.ishizuchi.silver-week-2026.five-day.calendar",
        "six": "jr-shikoku.ishizuchi.silver-week-2026.six-day.calendar",
    }
    timetable_versions = [{
        "timetable_version_id": version_id,
        "operator_scope": SCOPE,
        "effective_from": valid_from,
        "effective_until": valid_until,
        "publication_date": source["publication_date"],
        "edition_name": "JR Shikoku 2026 Silver Week shortened Ishizuchi endpoint table",
        "revision_type": "planned_exception",
        "completeness": "partial",
        "source_ids": [source["source_id"]],
    }]
    calendars = [
        {
            "calendar_id": calendar_id,
            "valid_from": valid_from,
            "valid_until": valid_until,
            "holiday_policy": "none",
            **{weekday: 0 for weekday in WEEKDAYS},
        }
        for calendar_id in calendar_ids.values()
    ]
    exceptions = []
    for key, values in (("five", five_dates), ("six", six_dates)):
        exceptions.extend({
            "calendar_id": calendar_ids[key],
            "service_date": service_date,
            "exception_type": "add",
            "source_id": source["source_id"],
            "reason": "PDF physical p.17 merged operating-date cell for the shortened Ishizuchi table",
        } for service_date in values)

    trips = []
    stop_times = []
    fact_sources = []
    fact_completeness = []
    research_queue = []
    locator = candidate["source"]["page_or_locator"]
    for reviewed in trips_source:
        public_number = reviewed["public_number"]
        trip_id = f"jr-shikoku.ishizuchi.{public_number}.2026-09-18"
        calendar_id = calendar_ids["five" if public_number in FIVE_DAY_NUMBERS else "six"]
        origin = stations[reviewed["origin"]]
        destination = stations[reviewed["destination"]]
        trips.append({
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": service["service_id"],
            "calendar_id": calendar_id,
            "train_number": None,
            "public_number": public_number,
            "origin_station_id": origin["station_id"],
            "destination_station_id": destination["station_id"],
            "direction": reviewed["direction"],
            "service_class": service["service_class"],
            "notes": (
                "Official planned-exception table publishes public number and endpoint clocks only. "
                "Intermediate stops, internal train number, operator segments and route lines remain unresolved."
            ),
        })
        stop_times.extend([
            {
                "trip_id": trip_id,
                "stop_sequence": 1,
                "station_id": origin["station_id"],
                "arrival_time": None,
                "departure_time": reviewed["departure_time"],
                "day_offset": 0,
                "call_type": "origin",
                "pickup_allowed": 1,
                "dropoff_allowed": 0,
                "time_accuracy": "minute",
                "source_id": source["source_id"],
            },
            {
                "trip_id": trip_id,
                "stop_sequence": 2,
                "station_id": destination["station_id"],
                "arrival_time": reviewed["arrival_time"],
                "departure_time": None,
                "day_offset": 0,
                "call_type": "destination",
                "pickup_allowed": 0,
                "dropoff_allowed": 1,
                "time_accuracy": "minute",
                "source_id": source["source_id"],
            },
        ])

        statuses = {
            "identity": ("verified", "high", "The official row identifies Ishizuchi and its public number."),
            "train_number": ("unknown", "low", "Public number is printed; internal train number is absent."),
            "operator": ("unknown", "low", "Publisher identity is not operator-segment evidence."),
            "validity_calendar": ("verified", "high", "The reviewed merged date cell explicitly applies to this row."),
            "origin_destination": ("verified", "high", "Both shortened-operation endpoints are printed."),
            "stops": ("partial", "high", "Only the shortened-operation endpoints are printed; intermediate calls are not supplied."),
            "times": ("partial", "high", "Only origin departure and destination arrival are printed."),
            "route_lines": ("unknown", "low", "No ordered physical route identity is printed."),
            "station_refs": ("verified", "high", "Each printed station uniquely matches one JR Shikoku sourceCode."),
            "provenance": ("partial", "high", "Official URL and reviewed PDF hash are recorded; reuse permission remains unresolved."),
        }
        source_facts = {
            "identity": (source["source_id"], locator, "verified"),
            "train_number": (source["source_id"], locator + "; public number only", "unknown"),
            "validity_calendar": (source["source_id"], locator + "; merged operating-date cell", "verified"),
            "origin_destination": (source["source_id"], locator, "verified"),
            "stops": (source["source_id"], locator + "; endpoints only", "partial"),
            "times": (source["source_id"], locator + "; endpoint clocks only", "partial"),
            "station_refs": (STATION_SOURCE_ID, "app/public/rail/jp-2025.json exact JR Shikoku name/code match", "verified"),
            "provenance": (source["source_id"], "Official PDF URL and SHA-256", "partial"),
        }
        for dimension, (status, confidence, notes) in statuses.items():
            fact_completeness.append({
                "entity_type": "trip",
                "entity_id": trip_id,
                "dimension": dimension,
                "status": status,
                "confidence": confidence,
                "notes": notes,
            })
            if dimension in source_facts:
                source_id, page_or_locator, verification_status = source_facts[dimension]
                fact_sources.append({
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": dimension,
                    "source_id": source_id,
                    "page_or_locator": page_or_locator,
                    "confidence": confidence,
                    "verification_status": verification_status,
                })

        research = {
            "train_number": "Obtain an official internal train-number source; do not derive it from the public number.",
            "operator": "Obtain ordered operator-boundary evidence.",
            "stops": "Obtain the complete intermediate passenger-stop list.",
            "times": "Obtain arrival/departure clocks for intermediate passenger stops.",
            "route_lines": "Obtain dated ordered physical route identities.",
            "provenance": "Resolve redistribution authorization for the transcribed timetable facts.",
        }
        research_queue.extend({
            "research_id": f"{trip_id}.{dimension}",
            "entity_type": "trip",
            "entity_id": trip_id,
            "missing_dimension": dimension,
            "status": "license_blocked" if dimension == "provenance" else "open",
            "notes": notes,
        } for dimension, notes in research.items())

    outputs = {
        source_output: source_documents,
        service_output: services,
        base / f"normalized/service-name-periods-{SUFFIX}.jsonl": [{
            "service_id": service["service_id"],
            "name": service["canonical_name"],
            "language": "ja",
            "valid_from": valid_from,
            "valid_until": valid_until,
            "name_type": "canonical",
            "source_id": source["source_id"],
        }],
        base / f"normalized/timetable-versions-{SUFFIX}.jsonl": timetable_versions,
        station_output: new_station_rows,
        base / f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        base / f"normalized/fact-completeness-{SUFFIX}.jsonl": fact_completeness,
        base / f"normalized/research-queue-{SUFFIX}.jsonl": research_queue,
        base / f"normalized/trips/reviewed-{SUFFIX}/seeds-{SUFFIX}.jsonl": trips,
        base / f"normalized/stop-times/reviewed-{SUFFIX}/seeds-{SUFFIX}.jsonl": stop_times,
        base / f"normalized/calendars/reviewed-{SUFFIX}/seeds-{SUFFIX}.jsonl": calendars,
        base / f"normalized/calendar-exceptions/reviewed-{SUFFIX}/seeds-{SUFFIX}.jsonl": exceptions,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)

    print(
        f"Normalized 26 Ishizuchi templates, 154 explicit occurrences, {len(stop_times)} endpoint rows, "
        f"2 shared calendars, and {len(new_station_rows)} new station identities in {base}."
    )
    print("Coverage declarations intentionally unchanged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
