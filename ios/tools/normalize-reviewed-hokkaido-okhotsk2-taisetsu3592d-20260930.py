#!/usr/bin/env python3
"""Stage adjacent 72D / 3592D official columns for 2026-09-30 only."""

import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "hokkaido-okhotsk2-taisetsu3592d-20260930"
CANDIDATE = BASE / "candidates/jr-hokkaido-okhotsk2-taisetsu3592d-20260930.json"
SOURCE_ID = "jr-hokkaido-okhotsk2-taisetsu3592d-20260930"
SOURCE_URL = "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111"
DAY, NEXT_DAY = "2026-09-30", "2026-10-01"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED = {
    "72D": ("okhotsk", "オホーツク", "limited_express", "2", "網走", "札幌", 15, "06:55", "12:10"),
    "3592D": ("taisetsu", "大雪", "special_rapid", None, "網走", "旭川", 11, "08:04", "11:51"),
}


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def resolve_stations(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    result = {}
    for name in names:
        codes = {station[0] for line in package["lines"] if line["operator"] == "北海道旅客鉄道"
                 for station in line["stations"] if station[1] == name}
        if len(codes) != 1:
            raise ValueError(f"Expected one JR Hokkaido station group for {name}: {sorted(codes)}")
        result[name] = "jp.n02." + next(iter(codes))
    return result


def validate(candidate):
    if candidate["candidate_status"] != "visually_reviewed" or candidate["canonical"] is not False:
        raise ValueError("Review or staging status changed")
    trips = candidate["trips"]
    if len(trips) != 2 or {trip["train_number"] for trip in trips} != set(EXPECTED):
        raise ValueError("Reviewed train identities changed")
    for trip in trips:
        number = trip["train_number"]
        service, name, kind, public, origin, destination, count, first, last = EXPECTED[number]
        expected_id = f"jr-hokkaido.{service}.{public if public else number.lower()}.exact-{DAY}"
        if (trip["trip_id"], trip["service_id"], trip["service_name"], trip["service_class"],
                trip["public_number"], trip["origin"], trip["destination"], trip["service_date"],
                trip["source_id"], trip["source_url"]) != (
                expected_id, service, name, kind, public, origin, destination, DAY, SOURCE_ID, SOURCE_URL):
            raise ValueError(f"Exact-date train/source identity changed: {number}")
        stops = trip["stops"]
        if len(stops) != count or stops[0] != [origin, None, first] or stops[-1] != [destination, last, None]:
            raise ValueError(f"Reviewed stop count/endpoints changed: {number}")
        if len({row[0] for row in stops}) != count:
            raise ValueError(f"Duplicate passenger call: {number}")
        if trip.get("printed_platforms") != ({"札幌": "(7)"} if number == "72D" else {}):
            raise ValueError(f"Reviewed printed platform changed: {number}")
        previous = None
        for station, arrival, departure in stops:
            for clock in (arrival, departure):
                if clock is None:
                    continue
                parsed = datetime.strptime(clock, "%H:%M")
                if previous is not None and parsed < previous:
                    raise ValueError(f"Clock reversal at {station} on {number}")
                previous = parsed
    return trips


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    trips = validate(candidate)
    if DAY > json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]:
        raise ValueError("Service day exceeds as-of date")
    existing_services = [
        json.loads(line)["service_id"] for path in BASE.glob("normalized/services*.jsonl")
        if path.name != f"services-{SUFFIX}.jsonl"
        for line in path.read_text(encoding="utf-8").splitlines() if line.strip()
    ]
    if any(service in existing_services for service in ("okhotsk", "taisetsu")):
        raise ValueError("Shared service row now exists; reconcile before staging")
    stations = resolve_stations({stop[0] for trip in trips for stop in trip["stops"]})
    known_station_ids = {
        json.loads(line)["station_id"]
        for path in (BASE / "normalized").glob("station-identities*.jsonl")
        if path.name != f"station-identities-{SUFFIX}.jsonl"
        for line in path.read_text(encoding="utf-8").splitlines() if line.strip()
    }
    station_rows = [
        {"station_id": sid, "name_snapshot": name, "reference_kind": "current_n02",
         "current_source_code": sid.removeprefix("jp.n02."), "rail_history_id": None}
        for name, sid in sorted(stations.items()) if sid not in known_station_ids
    ]
    versions, seeds, stop_rows, calendars, exceptions = [], [], [], [], []
    completeness, facts, queue = [], [], []
    for trip in trips:
        tid, number = trip["trip_id"], trip["train_number"]
        vid, cid = tid + ".version", tid + ".calendar"
        versions.append({"timetable_version_id": vid, "operator_scope": "jr-hokkaido",
                         "effective_from": DAY, "effective_until": NEXT_DAY,
                         "edition_name": "JR時刻表 令和8年10月号; selected exact 2026-09-30 column",
                         "revision_type": "source_snapshot", "completeness": "partial", "source_ids": [SOURCE_ID]})
        seeds.append({"trip_id": tid, "timetable_version_id": vid, "service_id": trip["service_id"],
                      "calendar_id": cid, "train_number": number, "public_number": trip["public_number"],
                      "origin_station_id": stations[trip["origin"]],
                      "destination_station_id": stations[trip["destination"]],
                      "service_class": trip["service_class"],
                      "notes": "Exact-date official column; unprinted intermediate arrival sides and physical route/operator segments remain unknown."})
        for seq, (name, arrival, departure) in enumerate(trip["stops"], 1):
            call_type = "origin" if seq == 1 else "destination" if seq == len(trip["stops"]) else "passenger_stop"
            stop_rows.append({"trip_id": tid, "stop_sequence": seq, "station_id": stations[name],
                              "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
                              "call_type": call_type, "pickup_allowed": 0 if call_type == "destination" else 1,
                              "dropoff_allowed": 0 if call_type == "origin" else 1,
                              "platform": trip["printed_platforms"].get(name),
                              "time_accuracy": "minute", "source_id": SOURCE_ID})
        calendars.append({"calendar_id": cid, "valid_from": DAY, "valid_until": NEXT_DAY,
                          "holiday_policy": "none", **{day: 0 for day in WEEKDAYS}})
        exceptions.append({"calendar_id": cid, "service_date": DAY, "exception_type": "add",
                           "reason": "Exact selected date on operator timetable", "source_id": SOURCE_ID})
        statuses = {
            "identity": ("verified", "high", f"Official {number} / {trip['service_name']} train column."),
            "train_number": ("verified", "high", f"Official column prints {number}."),
            "validity_calendar": ("verified", "high", "Official selector is 2026-09-30."),
            "origin_destination": ("verified", "high", "First and last timed passenger calls are printed."),
            "stops": ("verified", "high", "All printed passenger calls captured; レ pass-through and || off-route rows excluded."),
            "times": ("partial", "medium", "Every printed clock captured; unprinted intermediate arrival sides remain unknown."),
            "station_refs": ("verified", "high", "Names resolve to current JR Hokkaido N02 station groups."),
            "operator": ("unknown", "low", "No dated operator-segment proof."),
            "route_lines": ("unknown", "low", "No ordered physical line IDs."),
            "provenance": ("partial", "medium", "Official URL pinned; reuse grant unconfirmed."),
        }
        for dimension, (status, confidence, note) in statuses.items():
            completeness.append({"entity_type": "trip", "entity_id": tid, "dimension": dimension,
                                 "status": status, "confidence": confidence, "notes": note})
            if status in ("verified", "partial") and dimension != "provenance":
                facts.append({"entity_type": "trip", "entity_id": tid, "field_name": dimension,
                              "source_id": "jtm-current-station-directory" if dimension == "station_refs" else SOURCE_ID,
                              "page_or_locator": "app/public/rail/jp-2025.json" if dimension == "station_refs" else trip["source_locator"],
                              "confidence": confidence, "verification_status": status})
            if dimension in ("times", "operator", "route_lines", "provenance"):
                queue.append({"research_id": f"{tid}.{dimension}", "entity_type": "trip", "entity_id": tid,
                              "missing_dimension": dimension, "status": "open", "notes": note})
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": [{
            "source_id": SOURCE_ID, "publisher": "北海道旅客鉄道株式会社 / 株式会社交通新聞社",
            "title": "［特急］オホーツク・［特快］大雪 上り 2026年9月30日 72D / 3592D 列",
            "source_type": "official_timetable", "url_or_locator": SOURCE_URL,
            "issue": "JR時刻表 令和8年10月号", "publication_date": None,
            "effective_date": DAY, "accessed_at": DAY,
            "license_status": "terms_published_no_reuse_grant_identified",
            "redistribution_status": "verification_only", "automated_extraction_allowed": False,
            "notes": "Selected date, tenth and twelfth columns visually reviewed. Site prohibits unauthorized reproduction or processing.",
        }],
        BASE / f"normalized/services-{SUFFIX}.jsonl": [
            {"service_id": trip["service_id"], "canonical_name": trip["service_name"],
             "service_class": trip["service_class"], "jr_scope": "jr", "historical_generation": 1,
             "first_verified_date": DAY, "last_verified_date": DAY}
            for trip in trips
        ],
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": [
            {"service_id": trip["service_id"], "name": trip["service_name"], "language": "ja",
             "valid_from": DAY, "valid_until": NEXT_DAY, "name_type": "display", "source_id": SOURCE_ID}
            for trip in trips
        ],
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_rows,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": seeds,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_rows,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": facts,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": queue,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print(f"Staged 72D / 3592D: {len(stop_rows)} printed passenger calls")


if __name__ == "__main__":
    main()
