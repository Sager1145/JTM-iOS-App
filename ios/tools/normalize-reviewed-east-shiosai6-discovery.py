#!/usr/bin/env python3
"""Normalize the independently reviewed JR East Shiosai 6 exact-day seed."""
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-east-shiosai6-20260930-discovery.json"
SUFFIX = "discovery-east-2026"
SOURCE_ID = "jr-east-shiosai6-20260930-discovery"
SOURCE_URL = "https://timetables.jreast.co.jp/2610/train/095/098821.html"
SOURCE_HASH = "sha256:2401bb8205ced0e15787bcf1139e0bfbee3ae7cbb8d45679c9660d778cc4eab8"
ENGLISH_SOURCE_ID = "jr-east-shiosai-official-english-20260929"
ENGLISH_SOURCE_URL = "https://traininfo.jreast.co.jp/train_info/e/express.aspx?group=shiosai"
SERVICE_DATE = "2026-09-30"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows))


def source_row():
    rows = [json.loads(line) for line in (BASE / "sources/source-registry-discovery-east-2026.jsonl").read_text().splitlines() if line.strip()]
    matches = [row for row in rows if row["source_id"] == SOURCE_ID]
    if len(matches) != 1:
        raise ValueError("Expected exactly one pinned Shiosai source registry row")
    row = matches[0]
    if row["url_or_locator"] != SOURCE_URL or row.get("content_hash") != SOURCE_HASH:
        raise ValueError("Pinned Shiosai source URL/hash changed")
    english = [row for row in rows if row["source_id"] == ENGLISH_SOURCE_ID]
    if len(english) != 1 or english[0]["url_or_locator"] != ENGLISH_SOURCE_URL:
        raise ValueError("Pinned official English Shiosai source changed")
    return row


def resolve_stations(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    resolved = {}
    for name in names:
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == "東日本旅客鉄道"
            for station in line["stations"]
            if station[1] == name
        }
        if name == "東京":
            codes = {code for code in codes if code == "003766"}
        if len(codes) != 1:
            raise ValueError(f"Expected one reviewed JR East station group for {name}: {sorted(codes)}")
        resolved[name] = "jp.n02." + next(iter(codes))
    return resolved


def validate(candidate):
    if candidate["candidate_status"] != "reviewed_official_html":
        raise ValueError("Candidate review status changed")
    trip = candidate["trip"]
    if trip["source_id"] != SOURCE_ID or trip["operating_dates"] != [SERVICE_DATE]:
        raise ValueError("Exact source/date pin changed")
    if (trip["service_id"], trip["public_number"], trip["train_number"]) != ("shiosai", "6", "4006M"):
        raise ValueError("Reviewed train identity changed")
    stops = trip["stop_times"]
    if [row["stop_sequence"] for row in stops] != list(range(1, 7)):
        raise ValueError("Reviewed stop sequence changed")
    if [row["name_snapshot"] for row in stops] != ["佐倉", "四街道", "千葉", "船橋", "錦糸町", "東京"]:
        raise ValueError("Reviewed stop names changed")
    if (stops[0]["departure_time"], stops[-1]["arrival_time"]) != ("07:04", "07:59"):
        raise ValueError("Reviewed endpoint clocks changed")
    return trip


def main():
    source_row()
    candidate = json.loads(CANDIDATE.read_text())
    trip = validate(candidate)
    stops = trip["stop_times"]
    station_ids = resolve_stations(row["name_snapshot"] for row in stops)
    trip_id = "jr-east.shiosai.6.exact-2026-09-30"
    version_id = trip_id + ".version"
    calendar_id = trip_id + ".calendar"

    existing_station_ids = set()
    for path in (BASE / "normalized").glob("station-identities*.jsonl"):
        if path.name == f"station-identities-{SUFFIX}.jsonl":
            continue
        existing_station_ids.update(
            json.loads(line)["station_id"] for line in path.read_text().splitlines() if line.strip()
        )
    station_rows = [
        {
            "station_id": station_id,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": station_id.removeprefix("jp.n02."),
            "rail_history_id": None,
        }
        for name, station_id in station_ids.items() if station_id not in existing_station_ids
    ]

    normalized_stops = []
    for row in stops:
        call_type = row["call_type"]
        normalized_stops.append({
            "trip_id": trip_id,
            "stop_sequence": row["stop_sequence"],
            "station_id": station_ids[row["name_snapshot"]],
            "arrival_time": row["arrival_time"],
            "departure_time": row["departure_time"],
            "day_offset": 0,
            "call_type": call_type,
            "pickup_allowed": 0 if call_type == "destination" else 1,
            "dropoff_allowed": 0 if call_type == "origin" else 1,
            "platform": row["platform"],
            "time_accuracy": "minute",
            "source_id": SOURCE_ID,
        })

    completeness_notes = {
        "identity": ("verified", "high", "The official page prints しおさい 6号."),
        "train_number": ("verified", "high", "The official page prints 4006M."),
        "operator": ("unknown", "low", "Publisher identity is not operator-segment evidence."),
        "validity_calendar": ("verified", "high", "2026-09-30 is an explicit td.ok cell on this schedule variant."),
        "origin_destination": ("verified", "high", "The first and last timed passenger calls are printed."),
        "stops": ("verified", "high", "The official 停車駅一覧 prints all six passenger calls."),
        "times": ("verified", "high", "The official page prints the minute clocks for every passenger call."),
        "route_lines": ("unknown", "low", "No ordered physical line evidence is promoted."),
        "station_refs": ("verified", "high", "Names resolve to reviewed current JR East N02 station groups."),
        "provenance": ("partial", "medium", "Official URL and SHA-256 are pinned; redistribution authorization is unresolved."),
    }
    fact_completeness = [
        {"entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
         "status": status, "confidence": confidence, "notes": notes}
        for dimension, (status, confidence, notes) in completeness_notes.items()
    ]
    verified_fields = ("identity", "train_number", "validity_calendar", "origin_destination", "stops", "times")
    fact_sources = [
        {"entity_type": "trip", "entity_id": trip_id, "field_name": field,
         "source_id": SOURCE_ID, "page_or_locator": "Official page: 2026-09-30 td.ok and complete stop/time table",
         "confidence": "high", "verification_status": "verified"}
        for field in verified_fields
    ]
    fact_sources.append({
        "entity_type": "trip", "entity_id": trip_id, "field_name": "provenance",
        "source_id": SOURCE_ID, "page_or_locator": "Official URL and reviewed SHA-256",
        "confidence": "medium", "verification_status": "partial",
    })
    fact_sources.append({
        "entity_type": "trip", "entity_id": trip_id, "field_name": "station_refs",
        "source_id": "jtm-current-station-directory",
        "page_or_locator": "app/public/rail/jp-2025.json; exact operator and station-name group match",
        "confidence": "high", "verification_status": "verified",
    })

    outputs = {
        BASE / f"normalized/services-{SUFFIX}.jsonl": [{
            "service_id": "shiosai", "canonical_name": "しおさい", "service_class": "limited_express",
            "historical_generation": 1, "first_verified_date": SERVICE_DATE,
            "last_verified_date": SERVICE_DATE, "jr_scope": "jr",
        }],
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": [
            {
                "service_id": "shiosai", "name": "しおさい", "language": "ja",
                "valid_from": SERVICE_DATE, "valid_until": "2026-10-01", "name_type": "display", "source_id": SOURCE_ID,
            },
            {
                "service_id": "shiosai", "name": "Shiosai", "language": "en",
                "valid_from": SERVICE_DATE, "valid_until": "2026-10-01",
                "name_type": "official_english", "source_id": ENGLISH_SOURCE_ID,
            },
        ],
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": [{
            "timetable_version_id": version_id, "operator_scope": "jr-east", "effective_from": SERVICE_DATE,
            "effective_until": "2026-10-01", "edition_name": "JR時刻表2026年10月号 official detail; exact-2026-09-30",
            "revision_type": "source_snapshot", "completeness": "partial", "source_ids": [SOURCE_ID],
        }],
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_rows,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": [{
            "trip_id": trip_id, "timetable_version_id": version_id, "service_id": "shiosai", "calendar_id": calendar_id,
            "train_number": "4006M", "public_number": "6", "origin_station_id": station_ids["佐倉"],
            "destination_station_id": station_ids["東京"], "service_class": "limited_express",
            "notes": "Exact official date and complete passenger-stop table; operator segments and route lines remain unknown.",
        }],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": normalized_stops,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar_id, "valid_from": SERVICE_DATE, "valid_until": "2026-10-01",
            "holiday_policy": "none", **{weekday: 0 for weekday in WEEKDAYS},
        }],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar_id, "service_date": SERVICE_DATE, "exception_type": "add",
            "reason": "Exact calendar date marked td.ok on this schedule-variant page", "source_id": SOURCE_ID,
        }],
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": fact_completeness,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": [
            {"research_id": f"{trip_id}.{dimension}", "entity_type": "trip", "entity_id": trip_id,
             "missing_dimension": dimension, "status": "open", "notes": note}
            for dimension, note in (
                ("operator", "Obtain explicit operator-segment evidence for this dated trip."),
                ("route_lines", "Obtain ordered physical line identities for this dated trip."),
                ("provenance", "Resolve timetable-fact redistribution authorization."),
            )
        ],
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print(f"Normalized Shiosai 6 for {SERVICE_DATE}: 1 trip, {len(normalized_stops)} stops, {len(station_rows)} new station identities")


if __name__ == "__main__":
    main()
