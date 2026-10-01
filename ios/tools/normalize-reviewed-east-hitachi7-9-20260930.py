#!/usr/bin/env python3
"""Stage source-pinned JR East Hitachi 7 and 9 for 2026-09-30."""

import json
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "east-hitachi7-9-20260930"
CANDIDATE = BASE / f"candidates/jr-{SUFFIX}.json"
DAY = "2026-09-30"
NEXT_DAY = "2026-10-01"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED = {
    "7": ("7M", "https://timetables.jreast.co.jp/2610/train/045/047851.html", "品川", "いわき", 10),
    "9": ("9M", "https://timetables.jreast.co.jp/2610/train/045/048321.html", "品川", "いわき", 14),
}
PRINTED_EQUIPMENT = ["座席未指定券", "グリーン車指定席", "普通車全車指定席"]
PRINTED_PLATFORMS = {
    "7": {"品川": "９", "東京": "７", "上野": "８", "水戸": "４"},
    "9": {"品川": "９", "東京": "８", "上野": "８", "水戸": "４"},
}


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def resolve_stations(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    result = {}
    for name in names:
        codes = {
            station[0] for line in package["lines"] if line["operator"] == "東日本旅客鉄道"
            for station in line["stations"] if station[1] == name
        }
        if name == "東京":
            codes &= {"003766"}
        if len(codes) != 1:
            raise ValueError(f"Ambiguous JR East station group for {name}: {sorted(codes)}")
        result[name] = "jp.n02." + next(iter(codes))
    return result


def validate(candidate):
    if candidate["candidate_status"] != "reviewed_official_html" or candidate["canonical"] is not False:
        raise ValueError("Candidate review or staging status changed")
    trips = candidate["trips"]
    if len(trips) != 2 or {t["public_number"] for t in trips} != set(EXPECTED):
        raise ValueError("Expected exactly Hitachi 7 and 9")
    for trip in trips:
        number = trip["public_number"]
        internal, url, origin, destination, stop_count = EXPECTED[number]
        if (trip["trip_id"], trip["service_date"], trip["train_number"], trip["source_id"], trip["source_url"]) != (
            f"jr-east.hitachi.{number}.exact-{DAY}", DAY, internal, f"jr-east-hitachi{number}-20260930", url
        ):
            raise ValueError(f"Trip identity/source drift for Hitachi {number}")
        if trip["printed_equipment"] != PRINTED_EQUIPMENT or trip["printed_platforms"] != PRINTED_PLATFORMS[number]:
            raise ValueError(f"Printed equipment/platform drift for Hitachi {number}")
        stops = trip["stops"]
        if len(stops) != stop_count or stops[0][0] != origin or stops[-1][0] != destination:
            raise ValueError(f"Stop list drift for Hitachi {number}")
        if stops[0][1] is not None or stops[-1][2] is not None:
            raise ValueError("Unprinted terminal side must remain empty")
        previous = None
        for name, arrival, departure in stops:
            for clock in (arrival, departure):
                if clock is None:
                    continue
                parsed = datetime.strptime(clock, "%H:%M")
                if previous is not None and parsed < previous:
                    raise ValueError(f"Clock reversal in Hitachi {number} at {name}")
                previous = parsed
    return trips


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    trips = validate(candidate)
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    if DAY > manifest["as_of_date"]:
        raise ValueError("Trip date is beyond manifest as-of date")
    station_ids = resolve_stations({stop[0] for trip in trips for stop in trip["stops"]})
    existing_stations = {
        json.loads(line)["station_id"]
        for path in (BASE / "normalized").glob("station-identities*.jsonl")
        if path.name != f"station-identities-{SUFFIX}.jsonl"
        for line in path.read_text(encoding="utf-8").splitlines() if line.strip()
    }
    station_rows = [
        {"station_id": sid, "name_snapshot": name, "reference_kind": "current_n02",
         "current_source_code": sid.removeprefix("jp.n02."), "rail_history_id": None}
        for name, sid in sorted(station_ids.items()) if sid not in existing_stations
    ]
    sources, versions, normalized_trips, stops, calendars, exceptions, formations = [], [], [], [], [], [], []
    completeness, facts, queue = [], [], []
    for trip in trips:
        number = trip["public_number"]
        trip_id = trip["trip_id"]
        source_id = trip["source_id"]
        version_id = trip_id + ".version"
        calendar_id = trip_id + ".calendar"
        sources.append({
            "source_id": source_id, "publisher": "東日本旅客鉄道株式会社",
            "title": f"時刻表（停車駅一覧）特急ひたち {number}号",
            "source_type": "official_timetable", "url_or_locator": trip["source_url"],
            "issue": "2026年10月掲載ページ", "publication_date": None,
            "effective_date": DAY, "accessed_at": DAY,
            "license_status": "no_reuse_grant_identified", "redistribution_status": "verification_only",
            "automated_extraction_allowed": False,
            "notes": "The September 30 calendar cell selects this displayed variant; reviewed station platforms and equipment are staged without car-count inference.",
        })
        versions.append({
            "timetable_version_id": version_id, "operator_scope": "jr-east", "effective_from": DAY,
            "effective_until": NEXT_DAY, "edition_name": f"JR East Hitachi {number}; exact-{DAY}",
            "revision_type": "source_snapshot", "completeness": "partial", "source_ids": [source_id],
        })
        normalized_trips.append({
            "trip_id": trip_id, "timetable_version_id": version_id, "service_id": "hitachi",
            "calendar_id": calendar_id, "train_number": trip["train_number"],
            "public_number": number, "origin_station_id": station_ids[trip["stops"][0][0]],
            "destination_station_id": station_ids[trip["stops"][-1][0]], "service_class": "limited_express",
            "notes": "One source-pinned service date. Physical route and operator segments are unknown.",
        })
        for sequence, (name, arrival, departure) in enumerate(trip["stops"], 1):
            call_type = "origin" if sequence == 1 else "destination" if sequence == len(trip["stops"]) else "passenger_stop"
            stops.append({
                "trip_id": trip_id, "stop_sequence": sequence, "station_id": station_ids[name],
                "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
                "call_type": call_type, "pickup_allowed": 0 if call_type == "destination" else 1,
                "dropoff_allowed": 0 if call_type == "origin" else 1,
                "platform": trip["printed_platforms"].get(name),
                "time_accuracy": "minute", "source_id": source_id,
            })
        formations.append({
            "formation_id": f"{trip_id}.formation.{DAY}", "trip_id": trip_id,
            "service_date": DAY, "evidence_kind": "planned", "all_reserved": True,
            "green_car_available": True, "source_id": source_id,
            "notes": "This train's September 30 page prints 普通車全車指定席 and グリーン車指定席. Exact car count, series, car assignments and actual consist are unverified.",
        })
        calendars.append({
            "calendar_id": calendar_id, "valid_from": DAY, "valid_until": NEXT_DAY,
            "holiday_policy": "none", **{weekday: 0 for weekday in WEEKDAYS},
        })
        exceptions.append({
            "calendar_id": calendar_id, "service_date": DAY, "exception_type": "add",
            "reason": "September 30 current-variant calendar cell", "source_id": source_id,
        })
        dimensions = {
            "identity": ("verified", "high"), "train_number": ("verified", "high"),
            "validity_calendar": ("verified", "high"), "origin_destination": ("verified", "high"),
            "stops": ("verified", "high"), "times": ("verified", "high"),
            "station_refs": ("verified", "high"), "operator": ("unknown", "low"),
            "route_lines": ("unknown", "low"), "provenance": ("partial", "medium"),
            "formation": ("partial", "high"),
        }
        for dimension, (status, confidence) in dimensions.items():
            completeness.append({
                "entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
                "status": status, "confidence": confidence,
                "notes": "Train-specific reserved-seat and green-car equipment printed; no dated car diagram or actual consist" if dimension == "formation"
                else "No ordered physical-line or dated operator-segment evidence" if status == "unknown"
                else "Source URL is pinned; reuse grant unconfirmed" if dimension == "provenance"
                else "Source-pinned 2026-09-30 schedule and current N02 station-group match",
            })
            if status == "verified":
                facts.append({
                    "entity_type": "trip", "entity_id": trip_id, "field_name": dimension,
                    "source_id": "jtm-current-station-directory" if dimension == "station_refs" else source_id,
                    "page_or_locator": "app/public/rail/jp-2025.json" if dimension == "station_refs" else trip["source_locator"],
                    "confidence": confidence, "verification_status": "verified",
                })
            if status != "verified":
                queue.append({
                    "research_id": f"{trip_id}.{dimension}", "entity_type": "trip", "entity_id": trip_id,
                    "missing_dimension": dimension, "status": "open",
                    "notes": "Find exact-date car count, series and car assignments" if dimension == "formation"
                    else "Find direct dated operator and physical-line evidence" if dimension != "provenance"
                    else "Resolve timetable-fact redistribution authorization",
                })
        for field, locator in (
            ("formation.all_reserved", "2026-09-30 current variant; 設備: 普通車全車指定席 and グリーン車指定席"),
            ("formation.green_car_available", "2026-09-30 current variant; 設備: グリーン車指定席"),
            ("stop_times.platform", "2026-09-30 current variant; 時刻詳細: 番線 column, printed stations only"),
        ):
            facts.append({
                "entity_type": "trip", "entity_id": trip_id, "field_name": field,
                "source_id": source_id, "page_or_locator": locator,
                "confidence": "high", "verification_status": "verified",
            })
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": sources,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_rows,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": normalized_trips,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stops,
        BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl": formations,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": facts,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": queue,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print(f"Staged {len(trips)} Hitachi trips, {len(stops)} passenger calls, {len(formations)} equipment records")


if __name__ == "__main__":
    main()
