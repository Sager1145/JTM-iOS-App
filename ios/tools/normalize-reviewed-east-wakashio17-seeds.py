#!/usr/bin/env python3
"""Normalize the source-pinned Wakashio 17 timetable for 2026-09-29/30.

The calendar is exception-only. It promotes only the two exact September cells
reviewed as ``td.ok`` on the official JR East train-detail page. Publisher
identity is not promoted to operator-segment or physical-line evidence.
"""
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-east-wakashio17-20260929-30.json"
SUFFIX = "east-wakashio17-20260929-30"
SCOPE = "jr-east"
STATION_SOURCE_ID = "jtm-current-station-directory"
SOURCE_ID = "jr-east-wakashio17-20260929-30"
SOURCE_URL = "https://timetables.jreast.co.jp/2610/train/095/098781.html"
SOURCE_HASH = "sha256:15ff3b2fde28534cf240474658742b9cad30d29313510ffe17eff91d1640414a"
OPERATING_DATES = ["2026-09-29", "2026-09-30"]
WEEKDAYS = [
    "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday",
]
EXPECTED_STOPS = [
    ("東京", "003785", None, "20:00", "京１", "origin"),
    ("蘇我", "004281", "20:36", "20:37", "５", "passenger_stop"),
    ("土気", "004436", "20:46", "20:47", None, "passenger_stop"),
    ("大網", "004450", "20:51", "20:51", "２", "passenger_stop"),
    ("茂原", "004751", "20:59", "21:00", "３", "passenger_stop"),
    ("上総一ノ宮", "004901", "21:08", None, "２", "destination"),
]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    ))


def day_after(value):
    return (date.fromisoformat(value) + timedelta(days=1)).isoformat()


def load_existing_rows(pattern, excluded_path):
    rows = []
    for path in sorted((BASE / "normalized").glob(pattern)):
        if path.resolve() == excluded_path.resolve():
            continue
        rows.extend(
            json.loads(line)
            for line in path.read_text().splitlines()
            if line.strip()
        )
    return rows


def validate_candidate(candidate, as_of):
    if candidate["candidate_status"] != "reviewed_official_html":
        raise ValueError("Candidate must retain reviewed_official_html status")
    if len(candidate["trips"]) != 1:
        raise ValueError("Expected exactly one reviewed Wakashio schedule variant")

    trip = candidate["trips"][0]
    source = trip["source"]
    if source["source_id"] != SOURCE_ID:
        raise ValueError("Reviewed source ID changed")
    if source["url_or_locator"] != SOURCE_URL:
        raise ValueError("Official Wakashio 17 URL changed")
    if source["content_hash"] != SOURCE_HASH:
        raise ValueError("Reviewed Wakashio 17 content hash changed")
    if source["automated_extraction_allowed"] is not False:
        raise ValueError("Unexpected extraction permission")
    if trip["operating_dates"] != OPERATING_DATES:
        raise ValueError("Reviewed td.ok date cells changed")
    if any(value > as_of for value in trip["operating_dates"]):
        raise ValueError("Candidate date exceeds manifest cutoff")
    if (
        trip["service_id"], trip["service_name"], trip["public_number"],
        trip["train_number"], trip["variant_id"],
    ) != (
        "wakashio", "わかしお", "17", "1067M", "weekday-requested-dates",
    ):
        raise ValueError("Reviewed Wakashio 17 identity changed")

    actual_stops = [
        (
            row["name_snapshot"], row["arrival_time"], row["departure_time"],
            row["platform"], row["call_type"],
        )
        for row in trip["stop_times"]
    ]
    expected_stops = [
        (name, arrival, departure, platform, call_type)
        for name, _, arrival, departure, platform, call_type in EXPECTED_STOPS
    ]
    if actual_stops != expected_stops:
        raise ValueError("Reviewed Wakashio 17 stop/time table changed")
    if [row["stop_sequence"] for row in trip["stop_times"]] != list(range(1, 7)):
        raise ValueError("Wakashio 17 stop sequence changed")


def resolve_stations(candidate):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    operator = candidate["operator_name_for_station_match"]
    stations = {}
    for name, code, *_ in EXPECTED_STOPS:
        matching_lines = {
            line["name"]
            for line in package["lines"]
            if line["operator"] == operator
            for station in line["stations"]
            if station[0] == code and station[1] == name
        }
        if not matching_lines:
            raise ValueError(f"Reviewed station group disappeared: ({code}, {name})")
        if name == "東京" and "京葉線" not in matching_lines:
            raise ValueError("Reviewed Keiyo Tokyo station group disappeared")
        stations[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
            "rail_history_id": None,
        }
    return stations


def main():
    candidate = json.loads(CANDIDATE.read_text())
    as_of = json.loads((BASE / "manifest.json").read_text())["as_of_date"]
    validate_candidate(candidate, as_of)
    stations = resolve_stations(candidate)
    reviewed_trip = candidate["trips"][0]
    source = reviewed_trip["source"]

    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing_station_rows = load_existing_rows("station-identities*.jsonl", station_target)
    existing_stations = {row["station_id"]: row for row in existing_station_rows}
    for station in stations.values():
        existing = existing_stations.get(station["station_id"])
        if existing and existing["name_snapshot"] != station["name_snapshot"]:
            raise ValueError(f"Existing station identity name conflict: {station['station_id']}")
    new_station_rows = sorted(
        (station for station in stations.values() if station["station_id"] not in existing_stations),
        key=lambda row: row["station_id"],
    )

    service_target = BASE / f"normalized/services-{SUFFIX}.jsonl"
    existing_service_rows = load_existing_rows("services*.jsonl", service_target)
    existing_services = {row["service_id"]: row for row in existing_service_rows}
    existing_service = existing_services.get("wakashio")
    if existing_service and existing_service["canonical_name"] != "わかしお":
        raise ValueError("Existing Wakashio service identity conflict")

    services = [] if existing_service else [{
        "service_id": "wakashio",
        "canonical_name": "わかしお",
        "service_class": "limited_express",
        "historical_generation": 1,
        "first_verified_date": OPERATING_DATES[0],
        "last_verified_date": OPERATING_DATES[-1],
        "jr_scope": "jr",
    }]
    valid_from = OPERATING_DATES[0]
    valid_until = day_after(OPERATING_DATES[-1])
    trip_id = f"{SCOPE}.wakashio.17.weekday-requested-dates.{valid_from}"
    version_id = trip_id + ".version"
    calendar_id = trip_id + ".calendar"

    service_names = [{
        "service_id": "wakashio",
        "name": "わかしお",
        "language": "ja",
        "valid_from": valid_from,
        "valid_until": valid_until,
        "name_type": "display",
        "source_id": SOURCE_ID,
    }]
    timetable_versions = [{
        "timetable_version_id": version_id,
        "operator_scope": SCOPE,
        "effective_from": valid_from,
        "effective_until": valid_until,
        "edition_name": "JR時刻表2026年10月号 official detail; requested dates",
        "revision_type": "source_snapshot",
        "completeness": "partial",
        "source_ids": [SOURCE_ID],
    }]
    calendars = [{
        "calendar_id": calendar_id,
        "valid_from": valid_from,
        "valid_until": valid_until,
        "holiday_policy": "none",
        **{weekday: 0 for weekday in WEEKDAYS},
    }]
    exceptions = [{
        "calendar_id": calendar_id,
        "service_date": service_date,
        "exception_type": "add",
        "reason": "Exact calendar date marked td.ok on the official schedule-variant page",
        "source_id": SOURCE_ID,
    } for service_date in OPERATING_DATES]
    reviewed_stops = reviewed_trip["stop_times"]
    trips = [{
        "trip_id": trip_id,
        "timetable_version_id": version_id,
        "service_id": "wakashio",
        "calendar_id": calendar_id,
        "train_number": "1067M",
        "public_number": "17",
        "origin_station_id": stations["東京"]["station_id"],
        "destination_station_id": stations["上総一ノ宮"]["station_id"],
        "service_class": "limited_express",
        "notes": (
            "Official train-detail variant with complete published passenger stops and minute "
            "clocks for two exact td.ok dates. Tokyo is the current Keiyo platform group, "
            "consistent with the published 京１ platform. Operator segments and ordered route "
            "lines remain unknown."
        ),
    }]
    stop_times = []
    for reviewed_stop in reviewed_stops:
        call_type = reviewed_stop["call_type"]
        stop_times.append({
            "trip_id": trip_id,
            "stop_sequence": reviewed_stop["stop_sequence"],
            "station_id": stations[reviewed_stop["name_snapshot"]]["station_id"],
            "arrival_time": reviewed_stop["arrival_time"],
            "departure_time": reviewed_stop["departure_time"],
            "day_offset": 0,
            "call_type": call_type,
            "pickup_allowed": 0 if call_type == "destination" else 1,
            "dropoff_allowed": 0 if call_type == "origin" else 1,
            "platform": reviewed_stop["platform"],
            "time_accuracy": "minute",
            "source_id": SOURCE_ID,
        })

    completeness = {
        "identity": ("verified", "high", "The official page prints the service name and public number."),
        "train_number": ("verified", "high", "The official page prints internal train number 1067M."),
        "operator": ("unknown", "low", "Publisher identity is not operator-segment evidence."),
        "validity_calendar": ("verified", "high", "Both emitted dates are exact td.ok calendar cells for this variant."),
        "origin_destination": ("verified", "high", "The first and last timed passenger calls are printed."),
        "stops": ("verified", "high", "The official 停車駅一覧 prints the complete passenger-stop sequence."),
        "times": ("verified", "high", "Every published passenger stop has its displayed minute arrival/departure clock."),
        "route_lines": ("unknown", "low", "No ordered physical-line evidence is promoted."),
        "station_refs": ("verified", "high", "Each stop resolves to a reviewed current station group; 京１ disambiguates the Keiyo Tokyo group."),
        "provenance": ("partial", "medium", "Official URL and SHA-256 are pinned; redistribution authorization is unresolved."),
    }
    fact_completeness = [{
        "entity_type": "trip",
        "entity_id": trip_id,
        "dimension": dimension,
        "status": status,
        "confidence": confidence,
        "notes": notes,
    } for dimension, (status, confidence, notes) in completeness.items()]

    source_locator = "Official train-detail page: September td.ok cells and complete stop/time table"
    fact_sources = [{
        "entity_type": "trip",
        "entity_id": trip_id,
        "field_name": field_name,
        "source_id": SOURCE_ID,
        "page_or_locator": source_locator,
        "confidence": "high",
        "verification_status": "verified",
    } for field_name in [
        "identity", "train_number", "validity_calendar",
        "origin_destination", "stops", "times",
    ]]
    fact_sources.extend([
        {
            "entity_type": "trip",
            "entity_id": trip_id,
            "field_name": "station_refs",
            "source_id": STATION_SOURCE_ID,
            "page_or_locator": (
                "app/public/rail/jp-2025.json; exact station-code/name matches; official 京１ "
                "platform disambiguates jp.n02.003785 for Tokyo"
            ),
            "confidence": "high",
            "verification_status": "verified",
        },
        {
            "entity_type": "trip",
            "entity_id": trip_id,
            "field_name": "provenance",
            "source_id": SOURCE_ID,
            "page_or_locator": "Official URL and reviewed SHA-256",
            "confidence": "medium",
            "verification_status": "partial",
        },
    ])
    research_queue = [{
        "research_id": f"{trip_id}.{dimension}",
        "entity_type": "trip",
        "entity_id": trip_id,
        "missing_dimension": dimension,
        "status": "open",
        "notes": notes,
    } for dimension, notes in {
        "operator": "Obtain explicit operator-segment evidence for the dated train variant.",
        "route_lines": "Obtain explicit ordered physical-line identities for the dated train variant.",
        "provenance": "Resolve timetable-fact redistribution authorization.",
    }.items()]

    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": [source],
        service_target: services,
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": service_names,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": timetable_versions,
        station_target: new_station_rows,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": fact_completeness,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": research_queue,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": trips,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_times,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)

    print(
        f"Normalized {len(trips)} Wakashio 17 schedule variant, "
        f"{len(stop_times)} complete stop rows, {len(exceptions)} exact occurrences, "
        f"and {len(new_station_rows)} new station identities."
    )


if __name__ == "__main__":
    main()
