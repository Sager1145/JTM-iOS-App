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
TRAIN_URL_TEMPLATE = "https://timetable.jr-odekake.net/train-timetable/{page_id}?date={yyyymmdd}"


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


def train_source_id(train_number: str, day: str) -> str:
    return f"jr-odekake-ishizuchi-{train_number.lower()}-{day.replace('-', '')}-special"


def train_url(reviewed_page: dict, day: str) -> str:
    return TRAIN_URL_TEMPLATE.format(
        page_id=reviewed_page["page_id"], yyyymmdd=day.replace("-", "")
    )


def official_train_sources(candidate: dict, trips_source: list[dict]) -> list[dict]:
    policy = candidate["source_policy"]
    pages = candidate["reviewed_train_pages"]
    rows = []
    for trip in trips_source:
        public_number = trip["public_number"]
        reviewed_page = pages[public_number]
        for day in trip["operating_dates"]:
            rows.append({
                "source_id": train_source_id(reviewed_page["train_number"], day),
                "publisher": policy["publisher"],
                "title": f"いしづち{public_number}号 列車時刻表（{day}）",
                "source_type": policy["source_type"],
                "url_or_locator": train_url(reviewed_page, day),
                "accessed_at": "2026-09-29T00:00:00-04:00",
                "issue": "JR時刻表 2026年10月号",
                "effective_date": day,
                "content_hash": None,
                "archive_locator": None,
                "license_status": policy["license_status"],
                "redistribution_status": policy["redistribution_status"],
                "automated_extraction_allowed": policy["automated_extraction_allowed"],
                "notes": (
                    "Exact dated special-service variant checked from the official line grid and "
                    "linked train page. Passenger calls, clocks, platforms, train number, "
                    "operating-day text and published pass marks were reviewed. Pass rows are "
                    "retained only as negative stop-pattern evidence and are not normalized."
                ),
            })
    return rows


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
    if candidate.get("candidate_status") != "reviewed_official_html":
        raise ValueError("Ishizuchi candidate has not completed official HTML review")
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

    reviewed_pages = candidate.get("reviewed_train_pages", {})
    if set(reviewed_pages) != EXPECTED_NUMBERS:
        raise ValueError("Reviewed Ishizuchi train-page inventory changed")
    for trip in trips_source:
        public_number = trip["public_number"]
        reviewed_page = reviewed_pages[public_number]
        expected_direction = "down" if int(public_number) % 2 else "up"
        if trip["direction"] != expected_direction:
            raise ValueError(f"Ishizuchi {public_number}: unexpected direction")
        expected_train_number = f"{9000 + int(public_number)}{'M' if int(public_number) in {3, 9, 10, 15, 16, 21, 22, 27, 28} else 'D'}"
        if reviewed_page["train_number"] != expected_train_number:
            raise ValueError(f"Ishizuchi {public_number}: unexpected special train number")
        calls = reviewed_page["passenger_calls"]
        if (calls[0][0], calls[-1][0]) != (trip["origin"], trip["destination"]):
            raise ValueError(f"Ishizuchi {public_number}: announcement and train-page endpoints disagree")
        if calls[0][1] or calls[0][2] != trip["departure_time"]:
            raise ValueError(f"Ishizuchi {public_number}: malformed origin clock")
        if calls[-1][1] != trip["arrival_time"] or calls[-1][2]:
            raise ValueError(f"Ishizuchi {public_number}: malformed destination clock")
        expected_row_count = 10 if public_number in FIVE_DAY_NUMBERS or expected_direction == "up" else 13
        if len(calls) + reviewed_page["omitted_pass_row_count"] != expected_row_count:
            raise ValueError(f"Ishizuchi {public_number}: reviewed call/pass row total changed")
        for call in calls:
            if len(call) != 4 or not call[0]:
                raise ValueError(f"Ishizuchi {public_number}: malformed passenger call {call}")
        for day in trip["operating_dates"]:
            if f"date={day.replace('-', '')}" not in train_url(reviewed_page, day):
                raise ValueError(f"Ishizuchi {public_number}: exact date missing from train URL")

    source_output = base / f"sources/source-registry-{SUFFIX}.jsonl"
    service_output = base / f"normalized/services-{SUFFIX}.jsonl"
    station_output = base / f"normalized/station-identities-{SUFFIX}.jsonl"
    source_documents = []
    for reviewed_source in [source] + official_train_sources(candidate, trips_source):
        source_documents.extend(source_rows(base, reviewed_source, source_output))

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
        {
            call[0]
            for reviewed_page in reviewed_pages.values()
            for call in reviewed_page["passenger_calls"]
        },
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
        "edition_name": "JR Shikoku 2026 Silver Week shortened Ishizuchi complete passenger calls",
        "revision_type": "planned_exception",
        "completeness": "partial",
        "source_ids": [source["source_id"]] + [
            train_source_id(reviewed_pages[trip["public_number"]]["train_number"], day)
            for trip in trips_source
            for day in trip["operating_dates"]
        ],
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
        reviewed_page = reviewed_pages[public_number]
        calls = reviewed_page["passenger_calls"]
        dated_source_ids = [
            train_source_id(reviewed_page["train_number"], day)
            for day in reviewed["operating_dates"]
        ]
        trip_id = f"jr-shikoku.ishizuchi.{public_number}.2026-09-18"
        calendar_id = calendar_ids["five" if public_number in FIVE_DAY_NUMBERS else "six"]
        origin = stations[calls[0][0]]
        destination = stations[calls[-1][0]]
        trips.append({
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": service["service_id"],
            "calendar_id": calendar_id,
            "train_number": reviewed_page["train_number"],
            "public_number": public_number,
            "origin_station_id": origin["station_id"],
            "destination_station_id": destination["station_id"],
            "direction": reviewed["direction"],
            "service_class": service["service_class"],
            "notes": (
                "Exact-date line grids and linked special-service pages agree across all announced dates. "
                f"{reviewed_page['omitted_pass_row_count']} published pass rows are deliberately omitted; "
                "operator segments and route lines remain unresolved."
            ),
        })
        for sequence, (name, arrival, departure, platform) in enumerate(calls, start=1):
            first = sequence == 1
            last = sequence == len(calls)
            stop_times.append({
                "trip_id": trip_id,
                "stop_sequence": sequence,
                "station_id": stations[name]["station_id"],
                "arrival_time": arrival,
                "departure_time": departure,
                "day_offset": 0,
                "call_type": "origin" if first else "destination" if last else "passenger_stop",
                "pickup_allowed": 0 if last else 1,
                "dropoff_allowed": 0 if first else 1,
                "platform": platform,
                "time_accuracy": "minute",
                "source_id": dated_source_ids[0],
            })

        statuses = {
            "identity": ("verified", "high", "All exact dated line grids and train pages identify Ishizuchi and its public number."),
            "train_number": ("verified", "high", "All applicable exact dated line grids and train pages agree on the special internal train number."),
            "operator": ("unknown", "low", "Publisher identity is not operator-segment evidence."),
            "validity_calendar": ("verified", "high", "The reviewed merged date cell explicitly applies to this row."),
            "origin_destination": ("verified", "high", "The announcement and exact dated train pages agree on both shortened-operation endpoints."),
            "stops": ("verified", "high", "Passenger calls are complete; separately displayed passing rows are deliberately omitted."),
            "times": ("verified", "high", "Arrival and departure clocks are recorded for every passenger call without inferring blank cells."),
            "route_lines": ("unknown", "low", "No ordered physical route identity is printed."),
            "station_refs": ("verified", "high", "Each passenger-call station uniquely matches one JR Shikoku sourceCode."),
            "provenance": ("partial", "medium", "Official exact-date URLs are recorded; the pages explicitly restrict reuse."),
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

        for dimension in ("identity", "train_number", "origin_destination", "stops", "times"):
            for dated_source_id in dated_source_ids:
                fact_sources.append({
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": dimension,
                    "source_id": dated_source_id,
                    "page_or_locator": "Exact dated official line grid and linked special train page",
                    "confidence": "high",
                    "verification_status": "verified",
                })
        fact_sources.extend([
            {
                "entity_type": "trip", "entity_id": trip_id,
                "field_name": "validity_calendar", "source_id": source["source_id"],
                "page_or_locator": locator + "; merged operating-date cell",
                "confidence": "high", "verification_status": "verified",
            },
            {
                "entity_type": "trip", "entity_id": trip_id,
                "field_name": "station_refs", "source_id": STATION_SOURCE_ID,
                "page_or_locator": "app/public/rail/jp-2025.json exact JR Shikoku name/code match",
                "confidence": "high", "verification_status": "verified",
            },
            {
                "entity_type": "trip", "entity_id": trip_id,
                "field_name": "provenance", "source_id": source["source_id"],
                "page_or_locator": "Official PDF URL and SHA-256",
                "confidence": "medium", "verification_status": "partial",
            },
        ])
        for dated_source_id in dated_source_ids:
            fact_sources.append({
                "entity_type": "trip", "entity_id": trip_id,
                "field_name": "provenance", "source_id": dated_source_id,
                "page_or_locator": "Exact dated official train page; reuse prohibited",
                "confidence": "medium", "verification_status": "partial",
            })

        research = {
            "operator": "Obtain ordered operator-boundary evidence.",
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
        f"Normalized 26 Ishizuchi templates, 154 exact dated occurrences, {len(stop_times)} passenger-call rows, "
        f"2 shared calendars, and {len(new_station_rows)} new station identities in {base}."
    )
    print("Coverage declarations intentionally unchanged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
