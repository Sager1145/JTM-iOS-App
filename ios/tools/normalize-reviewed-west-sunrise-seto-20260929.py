#!/usr/bin/env python3
"""Normalize the reviewed 2026-09-29 Sunrise Seto overnight occurrence."""

from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-west-sunrise-seto-20260929.json"
SUFFIX = "west-sunrise-seto-20260929"
SOURCE_ID = "jr-west-sunrise-seto-20260929"
SOURCE_URL = "https://timetable.jr-odekake.net/train-timetable/38492?date=20260929"
SOURCE_HASH = "sha256:8c47b02e1a5fda8e8f5a6080037869a1c95896b2a32d328b7d9bdbf3ab8afa1c"
STATION_SOURCE_ID = "jtm-current-station-directory"
SERVICE_DATE = "2026-09-29"
WEEKDAYS = [
    "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday",
]
EXPECTED_STATION_CODES = {
    "東京": "003766",
    "横浜": "004633",
    "熱海": "005685",
    "沼津": "005689",
    "富士": "005522",
    "静岡": "006128",
    "浜松": "007059",
    "姫路": "006509",
    "岡山": "007310",
    "児島": "007919",
    "坂出": "008240",
    "高松": "008163",
}
EXPECTED_STOPS = [
    ("東京", None, "21:26", 0, "9"),
    ("横浜", "21:51", "21:52", 0, "6"),
    ("熱海", "22:55", "22:57", 0, "2"),
    ("沼津", "23:15", "23:16", 0, None),
    ("富士", "23:31", "23:32", 0, None),
    ("静岡", "23:57", "23:59", 0, "4"),
    ("浜松", "00:53", "00:54", 1, "4"),
    ("姫路", "05:25", "05:26", 1, "8"),
    ("岡山", "06:27", "06:31", 1, "8"),
    ("児島", "06:52", "06:53", 1, None),
    ("坂出", "07:09", "07:10", 1, None),
    ("高松", "07:27", None, 1, "6"),
]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    ), encoding="utf-8")


def load_rows(root, pattern, excluded_path):
    rows = []
    for path in sorted(root.glob(pattern)):
        if not path.is_file() or path.resolve() == excluded_path.resolve():
            continue
        rows.extend(
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    return rows


def validate_candidate(candidate, as_of):
    if (
        candidate.get("candidate_status") != "reviewed_official_html"
        or candidate.get("canonical") is not True
        or candidate.get("promotion_scope") != "scheduled_service_departing_2026-09-29_only"
    ):
        raise ValueError("Sunrise Seto candidate review contract changed")
    if candidate.get("selected_service_date") != SERVICE_DATE or SERVICE_DATE > as_of:
        raise ValueError("Selected service date must remain 2026-09-29 within the manifest cutoff")

    source = candidate["source"]
    actual_source = (
        source.get("source_id"), source.get("url_or_locator"), source.get("content_hash"),
        source.get("redistribution_status"), source.get("automated_extraction_allowed"),
    )
    expected_source = (SOURCE_ID, SOURCE_URL, SOURCE_HASH, "verification_only", False)
    if actual_source != expected_source:
        raise ValueError(f"Reviewed official source contract changed: {actual_source}")

    service = candidate["service"]
    if (
        service.get("service_id"), service.get("canonical_name"),
        service.get("service_class"), service.get("jr_scope"),
    ) != ("sunrise-seto", "サンライズ瀬戸", "limited_express", "through_jr"):
        raise ValueError("Reviewed service identity changed")

    trip = candidate["trip"]
    if (
        trip.get("train_number"), trip.get("public_number"),
        trip.get("origin"), trip.get("destination"),
    ) != ("5031M", None, "東京", "高松"):
        raise ValueError("Reviewed trip identity changed")
    stops = trip["stop_times"]
    observed = [
        (row["name_snapshot"], row["arrival_time"], row["departure_time"],
         row["day_offset"], row["platform"])
        for row in stops
    ]
    if observed != EXPECTED_STOPS:
        raise ValueError("Reviewed stop clocks, offsets, or platforms changed")
    if [row["stop_sequence"] for row in stops] != list(range(1, 13)):
        raise ValueError("Reviewed stop sequence changed")
    if stops[0]["call_type"] != "origin" or stops[-1]["call_type"] != "destination":
        raise ValueError("Reviewed endpoint call types changed")


def resolve_stations(candidate):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    available = {
        (station[0], station[1])
        for line in package["lines"]
        for station in line["stations"]
    }
    names = {row["name_snapshot"] for row in candidate["trip"]["stop_times"]}
    if names != set(EXPECTED_STATION_CODES):
        raise ValueError("Reviewed station inventory changed")
    stations = {}
    for name, code in EXPECTED_STATION_CODES.items():
        if (code, name) not in available:
            raise ValueError(f"Reviewed current station group disappeared: ({code}, {name})")
        stations[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
            "rail_history_id": None,
        }
    return stations


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    as_of = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]
    validate_candidate(candidate, as_of)
    source = candidate["source"]
    stations = resolve_stations(candidate)

    source_target = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    for row in load_rows(BASE / "sources", "source-registry*.jsonl", source_target):
        if row["source_id"] == SOURCE_ID:
            raise ValueError("Source ID collision outside this batch")

    service_target = BASE / f"normalized/services-{SUFFIX}.jsonl"
    for row in load_rows(BASE / "normalized", "services*.jsonl", service_target):
        if row["service_id"] == "sunrise-seto":
            raise ValueError("Service ID collision outside this batch")

    trip_target = BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl"
    trip_id = "jr-west.sunrise-seto.5031m.2026-09-29"
    existing_trip_ids = {
        row["trip_id"]
        for row in load_rows(BASE / "normalized", "trips/**/*.jsonl", trip_target)
    }
    if trip_id in existing_trip_ids:
        raise ValueError("Trip ID collision outside this batch")

    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing_stations = {
        row["station_id"]: row
        for row in load_rows(BASE / "normalized", "station-identities*.jsonl", station_target)
    }
    for station in stations.values():
        existing = existing_stations.get(station["station_id"])
        if existing and (
            existing.get("name_snapshot"), existing.get("current_source_code")
        ) != (station["name_snapshot"], station["current_source_code"]):
            raise ValueError(f"Station identity collision: {station['station_id']}")
    new_stations = sorted(
        (station for station in stations.values() if station["station_id"] not in existing_stations),
        key=lambda row: row["station_id"],
    )

    service_day = date.fromisoformat(SERVICE_DATE)
    valid_until = (service_day + timedelta(days=1)).isoformat()
    version_id = trip_id + ".version"
    calendar_id = trip_id + ".calendar"
    reviewed_stops = candidate["trip"]["stop_times"]

    services = [{
        **candidate["service"],
        "first_verified_date": SERVICE_DATE,
        "last_verified_date": SERVICE_DATE,
    }]
    service_names = [{
        "service_id": "sunrise-seto",
        "name": "サンライズ瀬戸",
        "language": "ja",
        "valid_from": SERVICE_DATE,
        "valid_until": valid_until,
        "name_type": "canonical",
        "source_id": SOURCE_ID,
    }]
    versions = [{
        "timetable_version_id": version_id,
        "operator_scope": "jr-through",
        "effective_from": SERVICE_DATE,
        "effective_until": valid_until,
        "edition_name": "JR時刻表2026年10月号 official dated detail; 5031M Sunrise Seto",
        "revision_type": "source_snapshot",
        "completeness": "partial",
        "source_ids": [SOURCE_ID],
    }]
    calendars = [{
        "calendar_id": calendar_id,
        "valid_from": SERVICE_DATE,
        "valid_until": valid_until,
        "holiday_policy": "none",
        **{weekday: 0 for weekday in WEEKDAYS},
    }]
    exceptions = [{
        "calendar_id": calendar_id,
        "service_date": SERVICE_DATE,
        "exception_type": "add",
        "source_id": SOURCE_ID,
        "reason": "2026-09-29 is marked drivingday-01 on official page 38492",
    }]
    trips = [{
        "trip_id": trip_id,
        "timetable_version_id": version_id,
        "service_id": "sunrise-seto",
        "calendar_id": calendar_id,
        "train_number": "5031M",
        "public_number": None,
        "origin_station_id": stations["東京"]["station_id"],
        "destination_station_id": stations["高松"]["station_id"],
        "direction": "東京→高松",
        "service_class": "limited_express",
        "notes": (
            "Official dated Sunrise Seto column for the service date 2026-09-29. "
            "The trip departs Tokyo that evening and its Hamamatsu-through-Takamatsu calls "
            "occur on the following civil date with day_offset 1."
        ),
    }]
    stop_times = []
    for stop in reviewed_stops:
        call_type = stop["call_type"]
        stop_times.append({
            "trip_id": trip_id,
            "stop_sequence": stop["stop_sequence"],
            "station_id": stations[stop["name_snapshot"]]["station_id"],
            "arrival_time": stop["arrival_time"],
            "departure_time": stop["departure_time"],
            "day_offset": stop["day_offset"],
            "call_type": call_type,
            "pickup_allowed": 0 if call_type == "destination" else 1,
            "dropoff_allowed": 0 if call_type == "origin" else 1,
            "platform": stop["platform"],
            "time_accuracy": "minute",
            "source_id": SOURCE_ID,
        })

    completeness_contract = {
        "identity": ("verified", "high", "The page names 寝台特急 サンライズ瀬戸 and destination 高松."),
        "train_number": ("verified", "high", "The Sunrise Seto column prints train number 5031M."),
        "operator": ("unknown", "low", "The publishing site does not establish ordered operator boundaries for this through trip."),
        "validity_calendar": ("verified", "high", "2026-09-29 is a drivingday-01 cell for this displayed timetable."),
        "origin_destination": ("verified", "high", "The heading and endpoint cells establish Tokyo to Takamatsu."),
        "stops": ("verified", "high", "All timed passenger-call cells in the Sunrise Seto column are retained in order."),
        "times": ("verified", "high", "All printed arrival, departure, next-day, and platform cells are retained verbatim."),
        "route_lines": ("unknown", "low", "No ordered physical line identities are promoted from the timetable page."),
        "station_refs": ("verified", "high", "Every printed station resolves to a reviewed current N02 group."),
        "provenance": ("partial", "high", "Official URL and SHA-256 are pinned; the page prohibits unauthorized reuse."),
    }
    fact_completeness = [{
        "entity_type": "trip",
        "entity_id": trip_id,
        "dimension": dimension,
        "status": status,
        "confidence": confidence,
        "notes": notes,
    } for dimension, (status, confidence, notes) in completeness_contract.items()]

    source_fields = [
        "identity", "train_number", "validity_calendar", "origin_destination", "stops", "times",
    ]
    fact_sources = [{
        "entity_type": "trip",
        "entity_id": trip_id,
        "field_name": field_name,
        "source_id": SOURCE_ID,
        "page_or_locator": "Official page 38492: 2026年9月 calendar and Sunrise Seto 5031M column",
        "confidence": "high",
        "verification_status": "verified",
    } for field_name in source_fields]
    fact_sources.extend([
        {
            "entity_type": "trip",
            "entity_id": trip_id,
            "field_name": "station_refs",
            "source_id": STATION_SOURCE_ID,
            "page_or_locator": "app/public/rail/jp-2025.json; reviewed current sourceCode/name groups",
            "confidence": "high",
            "verification_status": "verified",
        },
        {
            "entity_type": "trip",
            "entity_id": trip_id,
            "field_name": "provenance",
            "source_id": SOURCE_ID,
            "page_or_locator": "Official dated URL, SHA-256, and page reuse notice",
            "confidence": "high",
            "verification_status": "partial",
        },
    ])
    research_queue = [{
        "research_id": f"{trip_id}.{dimension}",
        "entity_type": "trip",
        "entity_id": trip_id,
        "missing_dimension": dimension,
        "status": "license_blocked" if dimension == "provenance" else "open",
        "notes": notes,
    } for dimension, notes in {
        "operator": "Obtain dated train-specific ordered operator boundaries.",
        "route_lines": "Obtain dated direct evidence for each ordered physical line segment.",
        "provenance": "The official page prohibits unauthorized reproduction, copying, and processing.",
    }.items()]

    outputs = {
        source_target: [source],
        service_target: services,
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": service_names,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        station_target: new_stations,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": fact_completeness,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": research_queue,
        trip_target: trips,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_times,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)

    print(
        f"Sunrise Seto {SERVICE_DATE}: 1 trip, {len(stop_times)} passenger calls, "
        f"{sum(row['day_offset'] == 1 for row in stop_times)} next-day calls."
    )


if __name__ == "__main__":
    main()
