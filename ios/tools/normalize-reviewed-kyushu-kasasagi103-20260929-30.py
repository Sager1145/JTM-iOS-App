#!/usr/bin/env python3
"""Normalize two source-pinned 2026 Kasasagi 103 occurrences."""

from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-kyushu-kasasagi103-20260929-30.json"
SUFFIX = "kyushu-kasasagi103-20260929-30"
STATION_SOURCE_ID = "jtm-current-station-directory"
DATES = ("2026-09-29", "2026-09-30")
SOURCE_PREFIX = "jr-kyushu-kasasagi103-"
URL_PREFIX = "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0019/00194501.html?c=08291&d="
NAMES = ("博多", "二日市", "鳥栖", "新鳥栖", "佐賀", "江北", "肥前鹿島")
TIMES = (
    (None, "13:16"), ("13:27", "13:27"), ("13:37", "13:38"),
    ("13:41", "13:42"), ("13:54", "13:55"), ("14:04", "14:04"),
    ("14:17", None),
)
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def rows_for(pattern, excluded=None):
    for path in sorted(BASE.glob(pattern)):
        if not path.is_file() or (excluded and path.resolve() == excluded.resolve()):
            continue
        for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if raw.strip():
                yield path, line_number, json.loads(raw)


def resolve_stations():
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    resolved = {}
    for name in NAMES:
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == "九州旅客鉄道"
            for station in line["stations"]
            if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(f"Ambiguous or missing JR Kyushu station {name}: {sorted(codes)}")
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
    if candidate["candidate_status"] != "visually_reviewed" or tuple(candidate["service_dates"]) != DATES:
        raise ValueError("Reviewed dates or status changed")
    if max(DATES) > manifest["as_of_date"]:
        raise ValueError("Reviewed dates exceed manifest cutoff")
    service = candidate["service"]
    if service != {
        "service_id": "kasasagi", "canonical_name": "かささぎ",
        "service_class": "limited_express", "historical_generation": 1, "jr_scope": "jr",
    }:
        raise ValueError("Reviewed service identity changed")
    trip = candidate["trip"]
    stops = trip["stop_times"]
    if (trip["public_number"], trip["train_number"], trip["direction"]) != (
        "103", "1003M", "博多→肥前鹿島"
    ):
        raise ValueError("Reviewed train identity changed")
    if tuple(row["name_snapshot"] for row in stops) != NAMES:
        raise ValueError("Reviewed stop sequence changed")
    if tuple((row["arrival_time"], row["departure_time"]) for row in stops) != TIMES:
        raise ValueError("Reviewed minute clocks changed")
    if [row["stop_sequence"] for row in stops] != list(range(1, 8)):
        raise ValueError("Reviewed stop numbering changed")
    if [row["call_type"] for row in stops] != [
        "origin", *(["passenger_stop"] * 5), "destination"
    ]:
        raise ValueError("Reviewed passenger-call types changed")

    sources = candidate["sources"]
    if len(sources) != 2:
        raise ValueError("Both date-qualified sources are required")
    for service_date, source in zip(DATES, sources):
        expected_source_id = SOURCE_PREFIX + service_date.replace("-", "") + "-exact"
        expected_url = URL_PREFIX + service_date[-2:] + "&ym=202609"
        if (source["source_id"], source["url_or_locator"], source["effective_date"]) != (
            expected_source_id, expected_url, service_date
        ):
            raise ValueError("Date-qualified source pin changed")
        if source["automated_extraction_allowed"] is not False or source["redistribution_status"] != "verification_only":
            raise ValueError("Source reuse restrictions changed")

    registry_target = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    source_ids = {row["source_id"] for _, _, row in rows_for("sources/source-registry*.jsonl", registry_target)}
    if STATION_SOURCE_ID not in source_ids:
        raise ValueError("Current station directory source is missing")
    for source in sources:
        if source["source_id"] in source_ids:
            raise ValueError(f"Source id already exists: {source['source_id']}")

    service_target = BASE / f"normalized/services-{SUFFIX}.jsonl"
    existing_services = [
        row for _, _, row in rows_for("normalized/services*.jsonl", service_target)
        if row["service_id"] == "kasasagi"
    ]
    if existing_services:
        for existing in existing_services:
            for key, value in service.items():
                if existing.get(key) != value:
                    raise ValueError(f"Existing Kasasagi service conflicts on {key}")

    stations = resolve_stations()
    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing_stations = defaultdict(list)
    for _, _, row in rows_for("normalized/station-identities*.jsonl", station_target):
        existing_stations[row["station_id"]].append(row)
    new_stations = []
    for station in stations.values():
        rows = existing_stations[station["station_id"]]
        if rows:
            for existing in rows:
                if any(existing.get(key) != value for key, value in station.items()):
                    raise ValueError(f"Station identity conflict for {station['name_snapshot']}")
        else:
            new_stations.append(station)

    data = defaultdict(list)
    if not existing_services:
        data["services"].append({**service, "first_verified_date": DATES[0], "last_verified_date": DATES[-1]})
    for service_date, source in zip(DATES, sources):
        source_id = source["source_id"]
        valid_until = (date.fromisoformat(service_date) + timedelta(days=1)).isoformat()
        trip_id = f"jr-kyushu.kasasagi.103.{service_date}"
        version_id = trip_id + ".version"
        calendar_id = trip_id + ".calendar"
        data["service-name-periods"].append({
            "service_id": "kasasagi", "name": "かささぎ", "language": "ja",
            "valid_from": service_date, "valid_until": valid_until,
            "name_type": "canonical", "source_id": source_id,
        })
        data["timetable-versions"].append({
            "timetable_version_id": version_id, "operator_scope": "jr-kyushu",
            "effective_from": service_date, "effective_until": valid_until,
            "edition_name": f"JR時刻表2026年10月号 exact {service_date} train detail",
            "revision_type": "source_snapshot", "publication_date": None,
            "completeness": "partial", "source_ids": [source_id],
        })
        data["calendars"].append({
            "calendar_id": calendar_id, "valid_from": service_date,
            "valid_until": valid_until, "holiday_policy": "none",
            **{weekday: 0 for weekday in WEEKDAYS},
        })
        data["calendar-exceptions"].append({
            "calendar_id": calendar_id, "service_date": service_date,
            "exception_type": "add", "source_id": source_id,
            "reason": "Exact date-qualified official train-detail page; no recurrence inferred",
        })
        data["trips"].append({
            "trip_id": trip_id, "timetable_version_id": version_id,
            "service_id": "kasasagi", "calendar_id": calendar_id,
            "train_number": "1003M", "public_number": "103",
            "origin_station_id": stations[NAMES[0]]["station_id"],
            "destination_station_id": stations[NAMES[-1]]["station_id"],
            "direction": "博多→肥前鹿島", "service_class": "limited_express",
            "notes": "Exact-date official JR Kyushu detail with all seven passenger calls and minute clocks. Operator segments and ordered physical lines remain unresolved.",
        })
        for stop in stops:
            call_type = stop["call_type"]
            data["stop-times"].append({
                "trip_id": trip_id, "stop_sequence": stop["stop_sequence"],
                "station_id": stations[stop["name_snapshot"]]["station_id"],
                "arrival_time": stop["arrival_time"], "departure_time": stop["departure_time"],
                "day_offset": 0, "call_type": call_type,
                "pickup_allowed": 0 if call_type == "destination" else 1,
                "dropoff_allowed": 0 if call_type == "origin" else 1,
                "platform": stop["platform"], "time_accuracy": "minute", "source_id": source_id,
            })
        dimensions = {
            "identity": ("verified", "high", source_id, "列車種 / 列車名 rows print 特急 かささぎ103号."),
            "train_number": ("verified", "high", source_id, "列車番号 row prints 1003M."),
            "operator": ("unknown", "low", None, "Publisher identity is not segment-level operating evidence."),
            "validity_calendar": ("verified", "high", source_id, f"Date-qualified URL selects {service_date}; only this occurrence is emitted."),
            "origin_destination": ("verified", "high", source_id, "First and last table rows print 博多 and 肥前鹿島."),
            "stops": ("verified", "high", source_id, "All seven passenger calls are printed."),
            "times": ("verified", "high", source_id, "All displayed arrival and departure minute clocks are preserved."),
            "route_lines": ("unknown", "low", None, "No ordered physical-line identity is promoted."),
            "station_refs": ("verified", "high", STATION_SOURCE_ID, "Each call resolves to one current JR Kyushu station sourceCode."),
            "provenance": ("partial", "medium", source_id, "Official date-qualified URL is pinned; no reuse grant was identified."),
        }
        for dimension, (status, confidence, evidence_source, notes) in dimensions.items():
            data["fact-completeness"].append({
                "entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
                "status": status, "confidence": confidence, "notes": notes,
            })
            if evidence_source is not None:
                data["fact-sources"].append({
                    "entity_type": "trip", "entity_id": trip_id, "field_name": dimension,
                    "source_id": evidence_source, "page_or_locator": notes,
                    "confidence": confidence, "verification_status": status,
                })
        for dimension, status, notes in (
            ("operator", "open", "Obtain segment-level official operator evidence."),
            ("route_lines", "open", "Obtain dated ordered physical-line evidence."),
            ("provenance", "license_blocked", "No redistribution or automated-extraction grant was identified."),
        ):
            data["research-queue"].append({
                "research_id": f"{trip_id}.{dimension}", "entity_type": "trip",
                "entity_id": trip_id, "missing_dimension": dimension,
                "status": status, "notes": notes,
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
    write_jsonl(registry_target, sources)
    for entity, target in targets.items():
        write_jsonl(target, data[entity])
    print("Normalized かささぎ103号: 2 exact occurrences, 7 complete calls each; no route/operator promotion.")


if __name__ == "__main__":
    main()
