#!/usr/bin/env python3
"""Promote the exact-date Shinano 2 schedule selected for 2026-09-30."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-central-shinano2-20260930.json"
SUFFIX = "reviewed-central-shinano2-20260930"
SOURCE_ID = "jr-east-shinano2-20260930"
SOURCE_URL = "https://timetables.jreast.co.jp/2610/train/000/000071.html"
ENGLISH_SOURCE_ID = "jr-central-conventional-limited-express-2026-en"
ENGLISH_SOURCE_URL = "https://global.jr-central.co.jp/en/nozomi/pdf/zairai_English.pdf"
STATION_SOURCE_ID = "jtm-current-station-directory"
SERVICE_DATE = "2026-09-30"
VALID_UNTIL = "2026-10-01"
WEEKDAYS = (
    "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday",
)
EXPECTED_STOPS = [('長野', '002031', None, '06:09', '６', 'origin'), ('篠ノ井', '002096', '06:17', '06:17', None, 'passenger_stop'), ('明科', '002345', '06:49', '06:49', None, 'passenger_stop'), ('松本', '002506', '07:03', '07:04', '１', 'passenger_stop'), ('塩尻', '002616', '07:13', '07:14', None, 'passenger_stop'), ('木曽福島', '003015', '07:42', '07:43', None, 'passenger_stop'), ('上松', '003139', '07:49', '07:49', None, 'passenger_stop'), ('南木曽', '004241', '08:08', '08:09', None, 'passenger_stop'), ('中津川', '004521', '08:21', '08:22', None, 'passenger_stop'), ('恵那', '004662', '08:30', '08:30', None, 'passenger_stop'), ('多治見', '005009', '08:50', '08:51', None, 'passenger_stop'), ('千種', '005450', '09:08', '09:08', None, 'passenger_stop'), ('金山', '005551', '09:13', '09:13', None, 'passenger_stop'), ('名古屋', '005451', '09:18', None, '１１', 'destination')]


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    ), encoding="utf-8")


def other_rows(pattern, target):
    return [
        json.loads(line)
        for path in sorted((BASE / "normalized").glob(pattern))
        if path.resolve() != target.resolve()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def validate_candidate(candidate):
    trip = candidate["trip"]
    source = trip["source"]
    if candidate["candidate_status"] != "reviewed_official_html":
        raise ValueError("Shinano 2 candidate must remain reviewed_official_html")
    if candidate["database_as_of_date"] != SERVICE_DATE:
        raise ValueError("Shinano 2 candidate cutoff changed")
    if SERVICE_DATE > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Shinano 2 date exceeds the database cutoff")
    if (
        trip["trip_id"], trip["service_id"], trip["service_name"],
        trip["public_number"], trip["train_number"], trip["service_date"],
    ) != (
        "jr-central.shinano.2.2026-09-30", "shinano", "しなの",
        "2", "1002M", SERVICE_DATE,
    ):
        raise ValueError("Reviewed Shinano 2 identity/date changed")
    if (source["source_id"], source["url_or_locator"],
            source["automated_extraction_allowed"]) != (SOURCE_ID, SOURCE_URL, False):
        raise ValueError("Reviewed Shinano 2 source changed")
    if trip["calendar_observation"] != {
        "month": "2026年9月", "day": 30, "cell_class": "ok", "variant_url": SOURCE_URL,
    }:
        raise ValueError("Reviewed September 30 operating cell changed")
    if trip["equipment"] != ["グリーン車指定席", "普通車一部指定席"]:
        raise ValueError("Reviewed equipment labels changed")
    if trip["direction"] != 'up':
        raise ValueError("Reviewed direction changed")
    actual_stops = [(
        row["name_snapshot"], row["arrival_time"], row["departure_time"],
        row["platform"], row["call_type"],
    ) for row in trip["stop_times"]]
    expected_stops = [(name, arrival, departure, platform, call_type)
                      for name, _, arrival, departure, platform, call_type
                      in EXPECTED_STOPS]
    if actual_stops != expected_stops:
        raise ValueError("Reviewed September 30 Shinano 2 stop table changed")
    if [row["stop_sequence"] for row in trip["stop_times"]] != list(range(1, 15)):
        raise ValueError("Shinano 2 stop sequence changed")
    english = candidate["official_english_name"]
    if (english["name"], english["source_id"], english["url_or_locator"]) != (
        "Shinano", ENGLISH_SOURCE_ID, ENGLISH_SOURCE_URL,
    ):
        raise ValueError("Official English Shinano source changed")


def verify_existing_service_and_english_name():
    services = {
        row["service_id"]: row
        for path in sorted((BASE / "normalized").glob("services*.jsonl"))
        for row in read_jsonl(path)
    }
    if services.get("shinano", {}).get("canonical_name") != "しなの":
        raise ValueError("Existing Shinano service identity is missing or conflicting")
    sources = {
        row["source_id"]: row
        for path in sorted((BASE / "sources").glob("source-registry*.jsonl"))
        for row in read_jsonl(path)
    }
    if sources.get(ENGLISH_SOURCE_ID, {}).get("url_or_locator") != ENGLISH_SOURCE_URL:
        raise ValueError("Official English Shinano source is missing")
    names = [
        row
        for path in sorted((BASE / "normalized").glob("service-name-periods*.jsonl"))
        for row in read_jsonl(path)
        if row["service_id"] == "shinano" and row["language"] == "en"
        and row["name"] == "Shinano" and row["source_id"] == ENGLISH_SOURCE_ID
        and row["valid_from"] <= SERVICE_DATE < row["valid_until"]
    ]
    if not names:
        raise ValueError("Official English Shinano name does not cover September 30")


def resolve_stations():
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    allowed_operators = {"東海旅客鉄道", "東日本旅客鉄道"}
    stations = {}
    for name, code, *_ in EXPECTED_STOPS:
        matches = {
            (station[0], station[1])
            for line in package["lines"] if line["operator"] in allowed_operators
            for station in line["stations"]
            if station[0] == code and station[1] == name
        }
        if matches != {(code, name)}:
            raise ValueError(f"Reviewed current station group disappeared: {(code, name)}")
        stations[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
            "rail_history_id": None,
        }
    target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing = {row["station_id"]: row
                for row in other_rows("station-identities*.jsonl", target)}
    additions = []
    for station in stations.values():
        prior = existing.get(station["station_id"])
        if prior and prior["name_snapshot"] != station["name_snapshot"]:
            raise ValueError(f"Station identity conflict: {station['station_id']}")
        if not prior:
            additions.append(station)
    return stations, sorted(additions, key=lambda row: row["station_id"])


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    validate_candidate(candidate)
    verify_existing_service_and_english_name()
    stations, new_stations = resolve_stations()
    trip = candidate["trip"]
    source = trip["source"]
    trip_id = trip["trip_id"]
    version_id = trip_id + ".version"
    calendar_id = trip_id + ".calendar"
    dimensions = {
        "identity": ("verified", "high", "Official selected variant prints しなの2号."),
        "train_number": ("verified", "high", "Official selected variant prints 1002M."),
        "operator": ("unknown", "low", "Publisher identity is not ordered operator-segment evidence."),
        "validity_calendar": ("verified", "high", "September 30 selects official schedule variant 000071."),
        "origin_destination": ("verified", "high", "First and last timed passenger calls are printed."),
        "stops": ("verified", "high", "The selected variant prints 14 passenger calls."),
        "times": ("verified", "high", "All printed arrival/departure minute clocks are retained."),
        "route_lines": ("unknown", "low", "No ordered physical-line evidence is promoted."),
        "station_refs": ("verified", "high", "Names and pinned codes match current JR Central/East groups."),
        "provenance": ("partial", "medium", "Official page is verification-only; redistribution grant unresolved."),
    }
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": [source],
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": new_stations,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": [{
            "timetable_version_id": version_id,
            "operator_scope": "jr-central",
            "effective_from": SERVICE_DATE,
            "effective_until": VALID_UNTIL,
            "edition_name": "JR時刻表2026年10月号; exact-date しなの2号",
            "revision_type": "source_snapshot",
            "completeness": "partial",
            "source_ids": [SOURCE_ID],
        }],
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar_id,
            "valid_from": SERVICE_DATE,
            "valid_until": VALID_UNTIL,
            "holiday_policy": "none",
            **{weekday: 0 for weekday in WEEKDAYS},
        }],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar_id,
            "service_date": SERVICE_DATE,
            "exception_type": "add",
            "reason": "September 30 selects official Shinano 2 schedule variant 000071",
            "source_id": SOURCE_ID,
        }],
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": [{
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": "shinano",
            "calendar_id": calendar_id,
            "train_number": "1002M",
            "public_number": "2",
            "origin_station_id": stations["長野"]["station_id"],
            "destination_station_id": stations["名古屋"]["station_id"],
            "service_class": "limited_express",
            "direction": trip["direction"],
            "notes": "Equipment: グリーン車指定席; 普通車一部指定席. Exact-date selected variant with 14 passenger calls. Operator segments and ordered physical lines remain unknown.",
        }],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": [{
            "trip_id": trip_id,
            "stop_sequence": row["stop_sequence"],
            "station_id": stations[row["name_snapshot"]]["station_id"],
            "arrival_time": row["arrival_time"],
            "departure_time": row["departure_time"],
            "day_offset": 0,
            "call_type": row["call_type"],
            "pickup_allowed": 0 if row["call_type"] == "destination" else 1,
            "dropoff_allowed": 0 if row["call_type"] == "origin" else 1,
            "platform": row["platform"],
            "time_accuracy": "minute",
            "source_id": SOURCE_ID,
        } for row in trip["stop_times"]],
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": [{
            "entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
            "status": status, "confidence": confidence, "notes": notes,
        } for dimension, (status, confidence, notes) in dimensions.items()],
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": [{
            "entity_type": "trip", "entity_id": trip_id, "field_name": dimension,
            "source_id": STATION_SOURCE_ID if dimension == "station_refs" else SOURCE_ID,
            "page_or_locator": (
                "app/public/rail/jp-2025.json; exact pinned (code, name) match"
                if dimension == "station_refs" else note
            ),
            "confidence": confidence,
            "verification_status": status,
        } for dimension, (status, confidence, note) in dimensions.items()
          if dimension not in {"operator", "route_lines"}],
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": [{
            "research_id": f"{trip_id}.{dimension}",
            "entity_type": "trip", "entity_id": trip_id,
            "missing_dimension": dimension,
            "status": "license_blocked" if dimension == "provenance" else "open",
            "notes": notes,
        } for dimension, notes in {
            "operator": "Obtain explicit ordered JR Central / JR East operator-boundary evidence.",
            "route_lines": "Obtain dated ordered physical-line identities and transition boundaries.",
            "provenance": "Resolve permission to redistribute transcribed official timetable facts.",
        }.items()],
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print(f"Normalized exact-date Shinano 2 with {len(trip['stop_times'])} passenger calls")


if __name__ == "__main__":
    main()
