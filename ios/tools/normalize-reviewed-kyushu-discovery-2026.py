#!/usr/bin/env python3
"""Normalize one exact-date JR Kyushu 九州横断特急 occurrence."""

from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-kyushu-kyushu-odan5-20260930.json"
SUFFIX = "kyushu-discovery-2026"
SOURCE_ID = "jr-kyushu-kyushu-odan5-20260930"
ENGLISH_SOURCE_ID = "jr-kyushu-kyushu-odan-official-english-2026"
STATION_SOURCE_ID = "jtm-current-station-directory"
EXPECTED_URL = (
    "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0030/00308301.html"
    "?c=28742&d=30&ym=202609"
)
EXPECTED_NAMES = [
    "熊本", "新水前寺", "肥後大津", "立野", "阿蘇", "宮地",
    "豊後荻", "豊後竹田", "緒方", "三重町", "大分", "別府",
]
WEEKDAYS = [
    "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday",
]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def rows_for(pattern, excluded=None):
    for path in sorted(BASE.glob(pattern)):
        if not path.is_file() or (excluded is not None and path.resolve() == excluded.resolve()):
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            if raw.strip():
                yield json.loads(raw)


def resolve_stations(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    resolved = {}
    for name in names:
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == "九州旅客鉄道"
            for station in line["stations"]
            if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(f"Ambiguous or missing JR Kyushu station identity for {name}: {sorted(codes)}")
        code = next(iter(codes))
        resolved[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
        }
    return resolved


def main():
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if candidate["candidate_status"] != "visually_reviewed":
        raise ValueError("Candidate must remain visually reviewed")
    if candidate["source_id"] != SOURCE_ID or candidate["source_url"] != EXPECTED_URL:
        raise ValueError("Reviewed source identity or URL changed")
    service_date = candidate["service_date"]
    if service_date != "2026-09-30" or service_date > manifest["as_of_date"]:
        raise ValueError("Exact service date changed or exceeds the manifest cutoff")

    service = candidate["service"]
    if service != {
        "service_id": "kyushu-cross-express",
        "canonical_name": "九州横断特急",
        "service_class": "limited_express",
        "historical_generation": 1,
        "jr_scope": "jr",
    }:
        raise ValueError("Reviewed service identity changed")
    trip = candidate["trip"]
    stops = trip["stop_times"]
    if (trip["public_number"], trip["train_number"], trip["direction"]) != (
        "5", "1075D", "熊本→別府"
    ):
        raise ValueError("Reviewed train identity changed")
    if [row["name_snapshot"] for row in stops] != EXPECTED_NAMES:
        raise ValueError("Reviewed stop sequence changed")
    if [row["stop_sequence"] for row in stops] != list(range(1, 13)):
        raise ValueError("Reviewed stop numbering changed")
    if (stops[0]["departure_time"], stops[-1]["arrival_time"]) != ("15:23", "18:45"):
        raise ValueError("Reviewed endpoint clocks changed")

    source_ids = {
        row["source_id"] for row in rows_for("sources/source-registry*.jsonl")
    }
    for required_source in (SOURCE_ID, STATION_SOURCE_ID, ENGLISH_SOURCE_ID):
        if required_source not in source_ids:
            raise ValueError(f"Missing source registry row {required_source}")
    target_service = BASE / f"normalized/services-{SUFFIX}.jsonl"
    for row in rows_for("normalized/services*.jsonl", target_service):
        if row["service_id"] == service["service_id"]:
            raise ValueError(f"Service id already exists: {service['service_id']}")

    stations = resolve_stations(EXPECTED_NAMES)
    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing_stations = {
        row["station_id"]: row
        for row in rows_for("normalized/station-identities*.jsonl", station_target)
    }
    new_stations = []
    for station in stations.values():
        existing = existing_stations.get(station["station_id"])
        if existing is not None:
            expected = {key: station[key] for key in station}
            actual = {key: existing.get(key) for key in station}
            if actual != expected:
                raise ValueError(f"Station identity conflict: {actual} != {expected}")
        else:
            new_stations.append(station)

    valid_until = (date.fromisoformat(service_date) + timedelta(days=1)).isoformat()
    trip_id = "jr-kyushu.kyushu-cross-express.5.2026-09-30"
    version_id = trip_id + ".version"
    calendar_id = trip_id + ".calendar"
    data = defaultdict(list)
    data["services"].append({
        **service,
        "first_verified_date": service_date,
        "last_verified_date": service_date,
    })
    data["service-name-periods"].append({
        "service_id": service["service_id"],
        "name": service["canonical_name"],
        "language": "ja",
        "valid_from": service_date,
        "valid_until": valid_until,
        "name_type": "canonical",
        "source_id": SOURCE_ID,
    })
    data["service-name-periods"].append({
        "service_id": service["service_id"],
        "name": "KYUSHU ODAN TOKKYU",
        "language": "en",
        "valid_from": service_date,
        "valid_until": valid_until,
        "name_type": "official_english",
        "source_id": ENGLISH_SOURCE_ID,
    })
    data["timetable-versions"].append({
        "timetable_version_id": version_id,
        "operator_scope": "jr-kyushu",
        "effective_from": service_date,
        "effective_until": valid_until,
        "edition_name": "JR時刻表2026年10月号 exact 2026-09-30 train detail",
        "revision_type": "source_snapshot",
        "completeness": "partial",
        "source_ids": [SOURCE_ID],
    })
    data["calendars"].append({
        "calendar_id": calendar_id,
        "valid_from": service_date,
        "valid_until": valid_until,
        "holiday_policy": "none",
        **{weekday: 0 for weekday in WEEKDAYS},
    })
    data["calendar-exceptions"].append({
        "calendar_id": calendar_id,
        "service_date": service_date,
        "exception_type": "add",
        "source_id": SOURCE_ID,
        "reason": "Exact date-qualified official train-detail page; no recurrence inferred",
    })
    data["trips"].append({
        "trip_id": trip_id,
        "timetable_version_id": version_id,
        "service_id": service["service_id"],
        "calendar_id": calendar_id,
        "train_number": trip["train_number"],
        "public_number": trip["public_number"],
        "origin_station_id": stations[EXPECTED_NAMES[0]]["station_id"],
        "destination_station_id": stations[EXPECTED_NAMES[-1]]["station_id"],
        "direction": trip["direction"],
        "service_class": service["service_class"],
        "notes": (
            "Single exact-date official train-detail occurrence with complete published "
            "passenger stops and minute clocks. Operator segments and ordered physical lines "
            "remain unresolved."
        ),
    })
    for stop in stops:
        call_type = stop["call_type"]
        data["stop-times"].append({
            "trip_id": trip_id,
            "stop_sequence": stop["stop_sequence"],
            "station_id": stations[stop["name_snapshot"]]["station_id"],
            "arrival_time": stop["arrival_time"],
            "departure_time": stop["departure_time"],
            "day_offset": 0,
            "call_type": call_type,
            "pickup_allowed": 0 if call_type == "destination" else 1,
            "dropoff_allowed": 0 if call_type == "origin" else 1,
            "platform": stop["platform"],
            "time_accuracy": "minute",
            "source_id": SOURCE_ID,
        })

    statuses = {
        "identity": ("verified", "high", "The official detail page prints 九州横断特急5号."),
        "train_number": ("verified", "high", "The official detail page prints 1075D."),
        "operator": ("unknown", "low", "Publisher identity is not segment-level operating evidence."),
        "validity_calendar": ("verified", "high", "Only the exact date-qualified 2026-09-30 occurrence is emitted."),
        "origin_destination": ("verified", "high", "The first and last passenger calls are printed."),
        "stops": ("verified", "high", "The official table prints the complete 12-stop passenger sequence."),
        "times": ("verified", "high", "All displayed arrival and departure clocks are preserved exactly."),
        "route_lines": ("unknown", "low", "No ordered physical-line identity is promoted from the timetable page."),
        "station_refs": ("verified", "high", "Every name resolves to one current JR Kyushu station sourceCode."),
        "provenance": ("partial", "medium", "Official date-qualified URL is pinned; no reuse grant was identified."),
    }
    source_locators = {
        "identity": (SOURCE_ID, "列車種 / 列車名 rows"),
        "train_number": (SOURCE_ID, "列車番号 row"),
        "validity_calendar": (SOURCE_ID, "date-qualified URL and September calendar day 30"),
        "origin_destination": (SOURCE_ID, "first and last rows of the station/time table"),
        "stops": (SOURCE_ID, "12 rows under 駅名"),
        "times": (SOURCE_ID, "時刻 column"),
        "station_refs": (STATION_SOURCE_ID, "exact JR Kyushu name/code resolution in shipped station directory"),
        "provenance": (SOURCE_ID, "official JR Kyushu timetable URL reviewed 2026-09-29"),
    }
    for dimension, (status, confidence, notes) in statuses.items():
        data["fact-completeness"].append({
            "entity_type": "trip",
            "entity_id": trip_id,
            "dimension": dimension,
            "status": status,
            "confidence": confidence,
            "notes": notes,
        })
        if dimension in source_locators:
            source_id, locator = source_locators[dimension]
            data["fact-sources"].append({
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": dimension,
                "source_id": source_id,
                "page_or_locator": locator,
                "confidence": confidence,
                "verification_status": status,
            })
    for dimension, status, notes in [
        ("operator", "open", "Obtain segment-level official operator evidence for the exact route."),
        ("route_lines", "open", "Obtain ordered physical-line evidence with 2026 validity."),
        ("provenance", "license_blocked", "No redistribution or automated-extraction grant was identified."),
    ]:
        data["research-queue"].append({
            "research_id": f"{trip_id}.{dimension}",
            "entity_type": "trip",
            "entity_id": trip_id,
            "missing_dimension": dimension,
            "status": status,
            "notes": notes,
        })

    targets = {
        "services": target_service,
        "service-name-periods": BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl",
        "timetable-versions": BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl",
        "station-identities": station_target,
        "fact-sources": BASE / f"normalized/fact-sources-{SUFFIX}.jsonl",
        "fact-completeness": BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl",
        "research-queue": BASE / f"normalized/research-queue-{SUFFIX}.jsonl",
        "trips": BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl",
        "stop-times": BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl",
        "calendars": BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl",
        "calendar-exceptions": BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl",
    }
    data["station-identities"] = sorted(new_stations, key=lambda row: row["station_id"])
    for entity, target in targets.items():
        write_jsonl(target, data[entity])
    print("Normalized 九州横断特急5号: 1 exact occurrence, 12 complete passenger stops, no route/operator promotion.")


if __name__ == "__main__":
    main()
