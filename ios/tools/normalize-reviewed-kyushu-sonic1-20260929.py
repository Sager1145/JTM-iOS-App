#!/usr/bin/env python3
"""Normalize the reviewed exact-date JR Kyushu Sonic 1 occurrence."""

from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-kyushu-sonic1-20260929.json"
SUFFIX = "kyushu-sonic1-20260929"
SOURCE_ID = "jr-kyushu-sonic1-20260929-exact"
STATION_SOURCE_ID = "jtm-current-station-directory"
EXPECTED_URL = (
    "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0001/00013201.html"
    "?c=28283&ym=202609&d=29"
)
EXPECTED_NAMES = [
    "博多", "香椎", "福間", "赤間", "折尾", "黒崎", "小倉", "朽網",
    "行橋", "宇島", "中津", "柳ケ浦", "宇佐", "杵築", "別府", "大分",
]
CURRENT_STATION_ALIASES = {"柳ケ浦": "柳ヶ浦"}
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
        for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if raw.strip():
                yield path, line_number, json.loads(raw)


def resolve_stations(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    resolved = {}
    for name in names:
        current_name = CURRENT_STATION_ALIASES.get(name, name)
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == "九州旅客鉄道"
            for station in line["stations"]
            if station[1] == current_name
        }
        if len(codes) != 1:
            raise ValueError(f"Ambiguous or missing JR Kyushu station identity for {name}: {sorted(codes)}")
        code = next(iter(codes))
        resolved[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": current_name,
            "reference_kind": "current_n02",
            "current_source_code": code,
        }
    return resolved


def main():
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if candidate["candidate_status"] != "visually_reviewed":
        raise ValueError("Candidate must remain visually reviewed")
    source = candidate["source"]
    if source["source_id"] != SOURCE_ID or source["url_or_locator"] != EXPECTED_URL:
        raise ValueError("Reviewed source identity or URL changed")
    if source["automated_extraction_allowed"] is not False or source["redistribution_status"] != "verification_only":
        raise ValueError("Source reuse restrictions changed")

    service_date = candidate["service_date"]
    if service_date != "2026-09-29" or service_date > manifest["as_of_date"]:
        raise ValueError("Exact service date changed or exceeds the manifest cutoff")
    service = candidate["service"]
    if service != {
        "service_id": "sonic",
        "canonical_name": "ソニック",
        "service_class": "limited_express",
        "historical_generation": 1,
        "jr_scope": "jr",
    }:
        raise ValueError("Reviewed service identity changed")

    trip = candidate["trip"]
    stops = trip["stop_times"]
    if (trip["public_number"], trip["train_number"], trip["direction"]) != (
        "1", "3001M", "博多→大分"
    ):
        raise ValueError("Reviewed train identity changed")
    if [row["name_snapshot"] for row in stops] != EXPECTED_NAMES:
        raise ValueError("Reviewed stop sequence changed")
    if [row["stop_sequence"] for row in stops] != list(range(1, 17)):
        raise ValueError("Reviewed stop numbering changed")
    if (stops[0]["departure_time"], stops[-1]["arrival_time"]) != ("06:21", "08:44"):
        raise ValueError("Reviewed endpoint clocks changed")
    if (stops[7].get("source_marker"), stops[7].get("source_marker_meaning")) != ("★", "臨時停車"):
        raise ValueError("Reviewed Kutsunami temporary-stop marker changed")

    registry_target = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    for path, line_number, row in rows_for("sources/source-registry*.jsonl", registry_target):
        if row["source_id"] == SOURCE_ID:
            raise ValueError(f"Source id already exists at {path}:{line_number}")
    service_target = BASE / f"normalized/services-{SUFFIX}.jsonl"
    for path, line_number, row in rows_for("normalized/services*.jsonl", service_target):
        if row["service_id"] == service["service_id"]:
            raise ValueError(f"Service id already exists at {path}:{line_number}")
    source_ids = {row["source_id"] for _, _, row in rows_for("sources/source-registry*.jsonl", registry_target)}
    if STATION_SOURCE_ID not in source_ids:
        raise ValueError(f"Missing canonical station directory source {STATION_SOURCE_ID}")

    stations = resolve_stations(EXPECTED_NAMES)
    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing_stations = defaultdict(list)
    for path, line_number, row in rows_for("normalized/station-identities*.jsonl", station_target):
        existing_stations[row["station_id"]].append((path, line_number, row))
    new_stations = []
    for station in stations.values():
        expected = {key: station[key] for key in station}
        if station["station_id"] in existing_stations:
            for path, line_number, existing in existing_stations[station["station_id"]]:
                actual = {key: existing.get(key) for key in station}
                if actual != expected:
                    raise ValueError(f"Station identity conflict at {path}:{line_number}: {actual} != {expected}")
        else:
            new_stations.append(station)

    valid_until = (date.fromisoformat(service_date) + timedelta(days=1)).isoformat()
    trip_id = "jr-kyushu.sonic.1.2026-09-29"
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
    data["timetable-versions"].append({
        "timetable_version_id": version_id,
        "operator_scope": "jr-kyushu",
        "effective_from": service_date,
        "effective_until": valid_until,
        "edition_name": "JR時刻表2026年10月号 exact 2026-09-29 train detail",
        "revision_type": "source_snapshot",
        "publication_date": None,
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
            "Single exact-date official train-detail occurrence with all 16 published passenger calls "
            "and minute clocks; 朽網 is source-marked ★ (temporary stop). Operator segments and "
            "ordered physical lines remain unresolved."
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

    dimensions = {
        "identity": ("verified", "high", SOURCE_ID, "列車種 / 列車名 rows print 特急 ソニック1号."),
        "train_number": ("verified", "high", SOURCE_ID, "列車番号 row prints 3001M."),
        "operator": ("unknown", "low", None, "Publisher identity is not segment-level operating evidence."),
        "validity_calendar": ("verified", "high", SOURCE_ID, "Date-qualified URL selects 2026-09-29; only that occurrence is emitted."),
        "origin_destination": ("verified", "high", SOURCE_ID, "First and last table rows print 博多 and 大分."),
        "stops": ("verified", "high", SOURCE_ID, "All 16 passenger calls are printed; 朽網 is marked ★＝臨時停車."),
        "times": ("verified", "high", SOURCE_ID, "All displayed arrival and departure minute clocks are preserved."),
        "route_lines": ("unknown", "low", None, "No ordered physical-line identity is promoted from the timetable page."),
        "station_refs": ("verified", "high", STATION_SOURCE_ID, "Each call resolves to one current JR Kyushu station sourceCode; source 柳ケ浦 maps to current 柳ヶ浦."),
        "provenance": ("partial", "medium", SOURCE_ID, "Official date-qualified URL is pinned; no reuse grant was identified."),
    }
    for dimension, (status, confidence, evidence_source, notes) in dimensions.items():
        data["fact-completeness"].append({
            "entity_type": "trip",
            "entity_id": trip_id,
            "dimension": dimension,
            "status": status,
            "confidence": confidence,
            "notes": notes,
        })
        if evidence_source is not None:
            data["fact-sources"].append({
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": dimension,
                "source_id": evidence_source,
                "page_or_locator": notes,
                "confidence": confidence,
                "verification_status": status,
            })
    for dimension, status, notes in [
        ("operator", "open", "Obtain segment-level official operator evidence for the exact route."),
        ("route_lines", "open", "Obtain dated ordered physical-line evidence."),
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
        "services": service_target,
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
    write_jsonl(registry_target, [source])
    for entity, target in targets.items():
        write_jsonl(target, data[entity])
    print(
        "Normalized ソニック1号: 1 exact occurrence, "
        f"{len(stops)} complete passenger stops, no route/operator promotion."
    )


if __name__ == "__main__":
    main()
