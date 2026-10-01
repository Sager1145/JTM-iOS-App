#!/usr/bin/env python3
"""Stage the two source-pinned Narita Express 5 branches for September 30."""

import json
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "east-narita-express5-20260930"
CANDIDATE = BASE / "candidates/jr-east-narita-express5-20260930.json"
DAY, NEXT_DAY = "2026-09-30", "2026-10-01"
SOURCE = "jr-east-narita-express5-20260930"
URL = "https://timetables.jreast.co.jp/2610/train/030/031141.html"
SERVICE = "narita-express"
STATION_NAME_ALIASES = {"空港第２ビル": "空港第2ビル"}
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED = {
    "2005M": ("大船", "成田空港", 9, "06:38", "08:36"),
    "2205M": ("新宿", "成田空港", 7, "07:07", None),
}


def read_rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude:
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line)


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def validate(candidate):
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"],
            candidate["source_id"], candidate["source_url"]) != (
            "reviewed_official_html", False, DAY, SOURCE, URL):
        raise ValueError("Reviewed date, source, or staging status changed")
    if DAY > json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]:
        raise ValueError("Service date exceeds manifest cutoff")
    if candidate["coupling_note"] != "東京－成田空港は2205Mを併結 / 東京－成田空港は2005Mに併結":
        raise ValueError("Official coupling note changed")
    trips = candidate["trips"]
    if len(trips) != 2 or {trip["train_number"] for trip in trips} != set(EXPECTED):
        raise ValueError("Expected exactly the 2005M and 2205M columns")
    for trip in trips:
        number = trip["train_number"]
        origin, destination, count, first, last = EXPECTED[number]
        if (trip["trip_id"], trip["origin"], trip["destination"]) != (
                f"jr-east.narita-express.5.{number.lower()}.exact-{DAY}", origin, destination):
            raise ValueError(f"Trip identity changed: {number}")
        stops = trip["stops"]
        if len(stops) != count or stops[0][:3] != [origin, None, first] or stops[-1][:3] != [destination, last, None]:
            raise ValueError(f"Reviewed endpoints or stop count changed: {number}")
        if stops[0][4] != "origin" or stops[-1][4] != "destination":
            raise ValueError("Terminal call types changed")
        previous = None
        for name, arrival, departure, platform, call_type in stops:
            if call_type not in {"origin", "passenger_stop", "destination", "pass"}:
                raise ValueError(f"Unsupported call type at {name}")
            if platform is not None and not platform.isdigit():
                raise ValueError(f"Invalid printed platform at {name}")
            for clock in (arrival, departure):
                if clock is None:
                    continue
                parsed = datetime.strptime(clock, "%H:%M")
                if previous is not None and parsed < previous:
                    raise ValueError(f"Clock reversal at {name} in {number}")
                previous = parsed
    first, second = trips
    if first["train_number"] != "2005M" or second["train_number"] != "2205M":
        raise ValueError("Branch order changed")
    if first["stops"][5] != ["東京", "07:25", "07:31", "４", "passenger_stop"]:
        raise ValueError("2005M coupling point changed")
    if second["stops"][2] != ["品川", None, None, None, "pass"]:
        raise ValueError("2205M Shinagawa pass-through changed")
    if second["stops"][3] != ["東京", "07:29", None, "４", "passenger_stop"]:
        raise ValueError("2205M coupling point changed")
    if any(arrival is not None or departure is not None or platform is not None
           for _, arrival, departure, platform, _ in second["stops"][4:]):
        raise ValueError("2205M unprinted downstream cells must stay unknown")
    if any(row["trip_id"] in {trip["trip_id"] for trip in trips}
           for row in read_rows("normalized/trips/*/*.jsonl", BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")):
        raise ValueError("Existing Narita Express 5 trip conflicts with this batch")
    return trips


def station_ids(trips):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    names = {stop[0] for trip in trips for stop in trip["stops"]}
    result = {}
    for name in names:
        directory_name = STATION_NAME_ALIASES.get(name, name)
        codes = {station[0] for line in package["lines"] if line["operator"] == "東日本旅客鉄道"
                 for station in line["stations"] if station[1] == directory_name}
        if name in {"東京", "武蔵小杉"}:
            codes &= {"東京": {"003766"}, "武蔵小杉": {"004301"}}[name]
        if len(codes) != 1:
            raise ValueError(f"Ambiguous JR East station group for {name}: {sorted(codes)}")
        result[name] = "jp.n02." + next(iter(codes))
    return result


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    trips = validate(candidate)
    if any(row["service_id"] == SERVICE for row in read_rows(
            "normalized/services*.jsonl", BASE / f"normalized/services-{SUFFIX}.jsonl")):
        raise ValueError("Shared Narita Express service exists; reconcile before staging")
    stations = station_ids(trips)
    known_stations = {row["station_id"] for row in read_rows(
        "normalized/station-identities*.jsonl", BASE / f"normalized/station-identities-{SUFFIX}.jsonl")}
    station_rows = [{"station_id": sid, "name_snapshot": STATION_NAME_ALIASES.get(name, name),
                     "reference_kind": "current_n02", "current_source_code": sid.removeprefix("jp.n02."),
                     "rail_history_id": None} for name, sid in sorted(stations.items()) if sid not in known_stations]
    versions, trip_rows, stop_rows, calendars, exceptions = [], [], [], [], []
    completeness, facts, queue = [], [], []
    for trip in trips:
        tid, number = trip["trip_id"], trip["train_number"]
        version, calendar = tid + ".version", tid + ".calendar"
        complete = number == "2005M"
        versions.append({"timetable_version_id": version, "operator_scope": "jr-east",
                         "effective_from": DAY, "effective_until": NEXT_DAY,
                         "edition_name": f"JR時刻表2026年10月号; 成田エクスプレス5号 {number} exact 9/30",
                         "revision_type": "source_snapshot", "completeness": "partial", "source_ids": [SOURCE]})
        trip_rows.append({"trip_id": tid, "timetable_version_id": version, "service_id": SERVICE,
                          "calendar_id": calendar, "train_number": number, "public_number": "5",
                          "origin_station_id": stations[trip["origin"]],
                          "destination_station_id": stations[trip["destination"]],
                          "service_class": "limited_express",
                          "notes": "Coupled at Tokyo. " + ("This column prints all nine passenger-call clocks."
                          if complete else "After Tokyo this column prints no independent clock or platform; unknown cells remain null.")})
        for sequence, (name, arrival, departure, platform, call_type) in enumerate(trip["stops"], 1):
            stop_rows.append({"trip_id": tid, "stop_sequence": sequence, "station_id": stations[name],
                              "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
                              "call_type": call_type,
                              "pickup_allowed": int(call_type in {"origin", "passenger_stop"}),
                              "dropoff_allowed": int(call_type in {"passenger_stop", "destination"}),
                              "platform": platform,
                              "time_accuracy": "minute" if arrival or departure else "unknown",
                              "source_id": SOURCE})
        calendars.append({"calendar_id": calendar, "valid_from": DAY, "valid_until": NEXT_DAY,
                          "holiday_policy": "none", **{weekday: 0 for weekday in WEEKDAYS}})
        exceptions.append({"calendar_id": calendar, "service_date": DAY, "exception_type": "add",
                           "reason": "September 30 current-variant calendar cell", "source_id": SOURCE})
        statuses = {
            "identity": ("verified", "high", "Official two-column Narita Express 5 page."),
            "train_number": ("verified", "high", f"Official column prints {number}."),
            "validity_calendar": ("verified", "high", "September 30 uses this displayed variant."),
            "origin_destination": ("verified", "high", "Official title names both branch endpoints."),
            "stops": (("verified", "high", "All nine 2005M passenger calls printed.") if complete else
                      ("partial", "medium", "Post-Tokyo 2205M cells are blank; shared calls follow coupling note.")),
            "times": (("verified", "high", "All printed 2005M passenger-call clocks captured.") if complete else
                      ("partial", "medium", "Tokyo departure and all later 2205M-column clocks are unprinted.")),
            "station_refs": ("verified", "high", "Names matched to current JR East N02 station groups."),
            "operator": ("unknown", "low", "No dated ordered operator segments."),
            "route_lines": ("unknown", "low", "No dated ordered physical-line IDs."),
            "provenance": ("partial", "medium", "Official URL pinned; redistribution grant unconfirmed."),
        }
        for dimension, (status, confidence, note) in statuses.items():
            completeness.append({"entity_type": "trip", "entity_id": tid, "dimension": dimension,
                                 "status": status, "confidence": confidence, "notes": note})
            if status in {"verified", "partial"} and dimension != "provenance":
                facts.append({"entity_type": "trip", "entity_id": tid, "field_name": dimension,
                              "source_id": "jtm-current-station-directory" if dimension == "station_refs" else SOURCE,
                              "page_or_locator": "app/public/rail/jp-2025.json" if dimension == "station_refs" else candidate["source_locator"],
                              "confidence": confidence, "verification_status": status})
            if status != "verified":
                queue.append({"research_id": f"{tid}.{dimension}", "entity_type": "trip", "entity_id": tid,
                              "missing_dimension": dimension, "status": "open", "notes": note})
    ofuna, shinjuku = trips
    relations = [
        {"trip_id": ofuna["trip_id"], "related_trip_id": shinjuku["trip_id"],
         "relation_type": "couples_with", "from_sequence": 6, "to_sequence": 9, "source_id": SOURCE},
        {"trip_id": shinjuku["trip_id"], "related_trip_id": ofuna["trip_id"],
         "relation_type": "couples_with", "from_sequence": 4, "to_sequence": 7, "source_id": SOURCE},
    ]
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": [{
            "source_id": SOURCE, "publisher": "東日本旅客鉄道株式会社 / 株式会社交通新聞社",
            "title": "成田エクスプレス 5号 2005M / 2205M 停車駅一覧",
            "source_type": "official_train_timetable", "url_or_locator": URL,
            "issue": "JR時刻表2026年10月号", "publication_date": None,
            "effective_date": DAY, "accessed_at": DAY,
            "license_status": "no_reuse_grant_identified", "redistribution_status": "verification_only",
            "automated_extraction_allowed": False,
            "notes": "September 30 current-variant cell; reciprocal Tokyo–Narita Airport coupling notes. 2205M post-Tokyo cells remain blank.",
        }],
        BASE / f"normalized/services-{SUFFIX}.jsonl": [{
            "service_id": SERVICE, "canonical_name": "成田エクスプレス", "service_class": "limited_express",
            "jr_scope": "jr", "historical_generation": 1,
            "first_verified_date": DAY, "last_verified_date": DAY,
        }],
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": [{
            "service_id": SERVICE, "name": "成田エクスプレス", "language": "ja",
            "valid_from": DAY, "valid_until": NEXT_DAY, "name_type": "display", "source_id": SOURCE,
        }],
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_rows,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": trip_rows,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_rows,
        BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl": relations,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": facts,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": queue,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print("Staged 2 Narita Express 5 branches: 9 timed 2005M calls, 4 known 2205M clocks, 2 coupling relations")


if __name__ == "__main__":
    main()
