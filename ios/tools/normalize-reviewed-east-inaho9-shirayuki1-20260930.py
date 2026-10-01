#!/usr/bin/env python3
"""Normalize exact-date JR East Inaho 9 and Shirayuki 1 evidence."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-east-inaho9-shirayuki1-20260930.json"
SOURCE_REGISTRY = BASE / "sources/source-registry-national-family-gap-audit-20260930.jsonl"
SUFFIX = "east-inaho9-shirayuki1-20260930"
DAY = "2026-09-30"
UNTIL = "2026-10-01"

EXPECTED = {
    "jr-east.inaho.9.exact-2026-09-30": {
        "source_id": "jr-east-inaho9-family-gap-20260930",
        "source_url": "https://timetables.jreast.co.jp/2610/train/060/064031.html",
        "source_sha256": "5c8674ca0fc1174ec75fecd5a7b68240f9134a6f86ba8ad8a7c0b0be7ea4f8d7",
        "train_number": "9M",
        "printed_equipment": ["グリーン車指定席", "普通車一部指定席"],
        "stops": [
            ["新潟", None, "17:58"], ["豊栄", "18:11", "18:11"],
            ["新発田", "18:21", "18:22"], ["中条", "18:31", "18:31"],
            ["坂町", "18:37", "18:38"], ["村上", "18:46", "18:47"],
            ["府屋", "19:18", "19:19"], ["あつみ温泉", "19:30", "19:31"],
            ["鶴岡", "19:51", "19:51"], ["余目", "20:01", "20:02"],
            ["酒田", "20:10", None],
        ],
        "platforms": {"新潟": "５", "新発田": "１", "坂町": "３", "村上": "３", "余目": "２", "酒田": "１"},
    },
    "jr-east.shirayuki.1.exact-2026-09-30": {
        "source_id": "jr-east-shirayuki1-family-gap-20260930",
        "source_url": "https://timetables.jreast.co.jp/2610/train/060/063941.html",
        "source_sha256": "cad7e30d426d151b9dbeca9221e6454b1dc825458af7c3ab9ee5b05a1052b9ca",
        "train_number": "51M",
        "printed_equipment": ["普通車一部指定席"],
        "stops": [
            ["新井", None, "10:23"], ["上越妙高", "10:30", "10:31"],
            ["高田", "10:35", "10:36"], ["春日山", "10:40", "10:40"],
            ["直江津", "10:46", "10:48"], ["柿崎", "10:59", "11:00"],
            ["柏崎", "11:14", "11:15"], ["長岡", "11:39", "11:40"],
            ["見附", "11:49", "11:49"], ["東三条", "11:57", "11:58"],
            ["加茂", "12:04", "12:05"], ["新津", "12:18", "12:18"],
            ["新潟", "12:30", None],
        ],
        "platforms": {"直江津": "６", "柏崎": "２", "長岡": "２", "東三条": "１", "新津": "４", "新潟": "３"},
    },
}


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows))


def station_ids(trips):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    allowed = {"東日本旅客鉄道", "えちごトキめき鉄道"}
    names = {name for trip in trips for name, _, _ in trip["stops"]}
    result = {}
    for name in names:
        codes = {
            station[0]
            for line in package["lines"]
            for station in line["stations"]
            if station[1] == name and line["operator"] in allowed
        }
        if len(codes) != 1:
            raise ValueError(f"ambiguous current N02 station {name}: {sorted(codes)}")
        result[name] = "jp.n02." + next(iter(codes))
    return result


def verify_candidate(candidate, sources):
    if candidate["candidate_status"] != "reviewed_official_html" or candidate["canonical"]:
        raise ValueError("candidate review state changed")
    if len(candidate["trips"]) != 2:
        raise ValueError("expected exactly two independent trips")
    by_source = {row["source_id"]: row for row in sources}
    for trip in candidate["trips"]:
        expected = EXPECTED[trip["trip_id"]]
        for field in ["source_id", "source_url", "source_sha256", "train_number", "printed_equipment"]:
            if trip[field] != expected[field]:
                raise ValueError(f"source-pinned field changed: {trip['trip_id']} {field}")
        if trip["stops"] != expected["stops"] or trip["printed_platforms"] != expected["platforms"]:
            raise ValueError(f"published calls/platforms changed: {trip['trip_id']}")
        if trip["calendar_observation"] != {"month": "2026年9月", "day": 30, "cell_class": "ok"}:
            raise ValueError(f"exact-date observation changed: {trip['trip_id']}")
        source = by_source[trip["source_id"]]
        if source["url_or_locator"] != trip["source_url"]:
            raise ValueError(f"source URL mismatch: {trip['trip_id']}")
        if source["content_hash"] != "sha256:" + trip["source_sha256"]:
            raise ValueError(f"source hash mismatch: {trip['trip_id']}")


def main():
    candidate = json.loads(CANDIDATE.read_text())
    sources = read_jsonl(SOURCE_REGISTRY)
    verify_candidate(candidate, sources)
    trips = candidate["trips"]
    stations = station_ids(trips)

    other_station_ids = {
        row["station_id"]
        for path in BASE.glob("normalized/station-identities*.jsonl")
        if SUFFIX not in path.name
        for row in read_jsonl(path)
    }
    station_rows = [
        {
            "station_id": station_id,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": station_id.removeprefix("jp.n02."),
            "rail_history_id": None,
        }
        for name, station_id in sorted(stations.items(), key=lambda pair: pair[1])
        if station_id not in other_station_ids
    ]

    services = []
    name_periods = []
    versions = []
    calendars = []
    exceptions = []
    normalized_trips = []
    stop_times = []
    formations = []
    fact_sources = []
    completeness = []
    research_queue = []

    for trip in trips:
        trip_id = trip["trip_id"]
        source_id = trip["source_id"]
        calendar_id = trip_id + ".calendar"
        version_id = trip_id + ".version"
        services.append({
            "service_id": trip["service_id"],
            "canonical_name": trip["service_name"],
            "service_class": "limited_express",
            "historical_generation": 1,
            "jr_scope": trip["jr_scope"],
            "first_verified_date": DAY,
            "last_verified_date": DAY,
        })
        name_periods.append({
            "service_id": trip["service_id"],
            "name": trip["service_name"],
            "language": "ja",
            "name_type": "primary",
            "valid_from": DAY,
            "valid_until": UNTIL,
            "source_id": source_id,
        })
        versions.append({
            "timetable_version_id": version_id,
            "operator_scope": "jr-east",
            "effective_from": DAY,
            "effective_until": UNTIL,
            "edition_name": f"JR時刻表2026年10月号; exact September 30; {trip['service_name']}{trip['public_number']}号",
            "revision_type": "source_snapshot",
            "completeness": "partial",
            "source_ids": [source_id],
        })
        calendars.append({
            "calendar_id": calendar_id,
            "valid_from": DAY,
            "valid_until": UNTIL,
            "holiday_policy": "none",
            **{day: 0 for day in ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]},
        })
        exceptions.append({
            "calendar_id": calendar_id,
            "service_date": DAY,
            "exception_type": "add",
            "reason": "2026年9月30日 td.ok",
            "source_id": source_id,
        })
        trip_notes = trip["route_note"]
        if trip["printed_remarks"]:
            trip_notes += " Printed remark: " + trip["printed_remarks"]
        normalized_trips.append({
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": trip["service_id"],
            "calendar_id": calendar_id,
            "train_number": trip["train_number"],
            "public_number": trip["public_number"],
            "origin_station_id": stations[trip["stops"][0][0]],
            "destination_station_id": stations[trip["stops"][-1][0]],
            "service_class": "limited_express",
            "notes": trip_notes,
        })
        for sequence, (name, arrival, departure) in enumerate(trip["stops"], 1):
            call_type = "origin" if sequence == 1 else "destination" if sequence == len(trip["stops"]) else "passenger_stop"
            stop_times.append({
                "trip_id": trip_id,
                "stop_sequence": sequence,
                "station_id": stations[name],
                "arrival_time": arrival,
                "departure_time": departure,
                "day_offset": 0,
                "call_type": call_type,
                "pickup_allowed": int(call_type != "destination"),
                "dropoff_allowed": int(call_type != "origin"),
                "platform": trip["printed_platforms"].get(name),
                "time_accuracy": "minute",
                "source_id": source_id,
            })
        equipment_note = " / ".join(trip["printed_equipment"])
        formations.append({
            **trip["formation"],
            "formation_id": trip_id + ".formation." + DAY,
            "trip_id": trip_id,
            "service_date": DAY,
            "source_id": source_id,
            "notes": f"Printed equipment: {equipment_note}. Planned reservation equipment only; car count, vehicle series, car assignments and actual dispatch unknown.",
        })

        verified_dimensions = ["identity", "train_number", "validity_calendar", "origin_destination", "stops", "times", "station_refs"]
        for dimension in verified_dimensions:
            completeness.append({
                "entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
                "status": "verified", "confidence": "high",
                "notes": "Direct 2026-09-30 timetable and unique current N02 station identity match.",
            })
            fact_sources.append({
                "entity_type": "trip", "entity_id": trip_id, "field_name": dimension,
                "source_id": "jtm-current-station-directory" if dimension == "station_refs" else source_id,
                "page_or_locator": "app/public/rail/jp-2025.json" if dimension == "station_refs" else trip["source_locator"],
                "confidence": "high", "verification_status": "verified",
            })
        completeness.append({
            "entity_type": "trip", "entity_id": trip_id, "dimension": "formation",
            "status": "partial", "confidence": "high",
            "notes": f"Exact page prints {equipment_note}; car count, vehicle series, car assignments and actual dispatch unknown.",
        })
        fact_sources.append({
            "entity_type": "trip", "entity_id": trip_id, "field_name": "formation.all_reserved",
            "source_id": source_id, "page_or_locator": "設備: 普通車一部指定席",
            "confidence": "high", "verification_status": "verified",
        })
        if trip["formation"]["green_car_available"] is True:
            fact_sources.append({
                "entity_type": "trip", "entity_id": trip_id, "field_name": "formation.green_car_available",
                "source_id": source_id, "page_or_locator": "設備: グリーン車指定席",
                "confidence": "high", "verification_status": "verified",
            })
        for dimension in ["operator", "route_lines"]:
            completeness.append({
                "entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
                "status": "unknown", "confidence": "low", "notes": trip["route_note"],
            })
        completeness.append({
            "entity_type": "trip", "entity_id": trip_id, "dimension": "provenance",
            "status": "partial", "confidence": "medium",
            "notes": "Official timetable is retained as verification-only evidence; redistribution permission is unresolved.",
        })
        for dimension, status, notes in [
            ("formation", "open", "Find train-specific car count, vehicle series and car assignments; actual dispatch remains separate."),
            ("operator", "open", trip["route_note"]),
            ("route_lines", "open", trip["route_note"]),
            ("provenance", "license_blocked", "Resolve timetable-fact redistribution permission."),
        ]:
            research_queue.append({
                "research_id": trip_id + "." + dimension,
                "entity_type": "trip", "entity_id": trip_id,
                "missing_dimension": dimension, "status": status, "notes": notes,
            })

    outputs = {
        BASE / f"normalized/services-{SUFFIX}.jsonl": services,
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": name_periods,
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_rows,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": normalized_trips,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_times,
        BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl": formations,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": research_queue,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print(f"normalized {len(trips)} trips, {len(stop_times)} calls, {len(station_rows)} station identities")


if __name__ == "__main__":
    main()
