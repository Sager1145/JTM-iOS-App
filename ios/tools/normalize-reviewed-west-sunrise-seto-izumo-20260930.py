#!/usr/bin/env python3
# coding: utf-8
"""Stage the reviewed September 30 Tokyo departures of both Sunrise branches."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-sunrise-seto-izumo-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
SOURCE = "jr-west-odekake-sunrise-20260930"
URL = "https://timetable.jr-odekake.net/train-timetable/38492?date=20260930"
SETO = "jr-west.sunrise-seto.5031m.2026-09-30"
IZUMO = "jr-west.sunrise-izumo.5031m-4031m.2026-09-30"
EQUIPMENT = ["シングルデラックス（Ａ寝台１人個室）", "ソロ（Ｂ寝台１人個室）",
             "シングルツイン（Ｂ寝台１人個室）", "シングル（Ｂ寝台１人個室）",
             "サンライズツイン（Ｂ寝台２人個室）", "普通車全車指定席（ノビノビ座席）"]
# Independent transcription of the two September 30 columns. - denotes a blank cell.
EXPECTED = {
    SETO: ("sunrise-seto", "高松", "東京:-/21:26/9 横浜:21:51/21:52/6 熱海:22:55/22:57/2 沼津:23:15/23:16/- 富士:23:31/23:32/- 静岡:23:57/23:59/4 浜松:00:53/00:54/4 姫路:05:25/05:26/8 岡山:06:27/06:31/8 児島:06:52/06:53/- 坂出:07:09/07:10/- 高松:07:27/-/6"),
    IZUMO: ("sunrise-izumo", "出雲市", "東京:-/21:26/9 横浜:21:51/21:52/6 熱海:22:55/22:57/2 沼津:23:15/23:16/- 富士:23:31/23:32/- 静岡:23:57/23:59/4 浜松:00:53/00:54/4 姫路:05:25/05:26/8 岡山:06:27/06:34/8 倉敷:06:46/06:47/- 備中高梁:07:14/07:14/- 新見:07:43/07:44/- 米子:09:05/09:08/2 安来:09:16/09:17/- 松江:09:33/09:34/- 宍道:09:47/09:48/- 出雲市:10:00/-/-"),
}
CODES = {"東京":"003766","横浜":"004633","熱海":"005685","沼津":"005689",
         "富士":"005522","静岡":"006128","浜松":"007059","姫路":"006509",
         "岡山":"007310","児島":"007919","坂出":"008240","高松":"008163",
         "倉敷":"007598","備中高梁":"006686","新見":"006070","米子":"004758",
         "安来":"004748","松江":"004638","宍道":"004793","出雲市":"004943"}


def rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern) if SUFFIX not in str(path)
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in records), encoding="utf-8")


def expected_calls(value):
    result = []
    for index, token in enumerate(value.split(), 1):
        name, clock = token.split(":", 1)
        arrival, departure, platform = clock.split("/")
        result.append((index, name, CODES[name], None if arrival == "-" else arrival,
                       None if departure == "-" else departure,
                       None if platform == "-" else platform, int(index >= 7)))
    return result


def main():
    candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
    if (candidate["candidate_status"], candidate["canonical"],
            candidate["selected_service_date"], candidate["promotion_scope"],
            candidate["source_id"], candidate["source_url"]) != (
            "visually_reviewed_official_train_page", False, DAY,
            "scheduled_service_departing_2026-09-30_only", SOURCE, URL):
        raise ValueError("Sunrise date/source contract drift")
    if DAY > timetable.load_manifest(BASE)["as_of_date"]:
        raise ValueError("Departure date exceeds dataset cutoff")
    selected = {trip["trip_id"]: trip for trip in candidate["trips"]}
    if len(candidate["trips"]) != 2 or set(selected) != set(EXPECTED):
        raise ValueError("Expected precisely the two Sunrise branches")
    source_path = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    source = json.loads(source_path.read_text(encoding="utf-8"))
    if (source["source_id"], source["url_or_locator"], source["effective_date"],
            source["redistribution_status"]) != (SOURCE, URL, DAY, "verification_only"):
        raise ValueError("Official source drift")
    if any(row["source_id"] == SOURCE for row in rows("sources/source-registry*.jsonl")):
        raise ValueError("Duplicate official source")
    if set(selected) & {row["trip_id"] for row in rows("normalized/trips/**/*.jsonl")}:
        raise ValueError("Duplicate Sunrise trip")
    services = {row["service_id"] for row in rows("normalized/services*.jsonl")}
    if {"sunrise-seto", "sunrise-izumo"} - services:
        raise ValueError("Sunrise service identities missing")
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    station_codes = {(station[0], station[1]) for line in package["lines"]
                     for station in line.get("stations", [])}
    previous_stations = {row["current_source_code"]: row for row in
                         rows("normalized/station-identities*.jsonl")
                         if row.get("current_source_code")}
    additions, versions, calendars, exceptions, trips = [], [], [], [], []
    stops, segments, formations, fact_sources, completeness, research = [], [], [], [], [], []
    for tid, (service, destination, clock_string) in EXPECTED.items():
        item = selected[tid]
        expected = expected_calls(clock_string)
        actual = [(row["stop_sequence"], row["name"], row["code"], row["arrival"],
                   row["departure"], row["platform"], row["day_offset"])
                  for row in item["stops"]]
        expected_segments = ([{"from_sequence": 1, "to_sequence": 12, "train_number": "5031M"}]
                             if tid == SETO else
                             [{"from_sequence": 1, "to_sequence": 9, "train_number": "5031M"},
                              {"from_sequence": 9, "to_sequence": 17, "train_number": "4031M"}])
        if (item["service_id"], item["train_number"], item["origin"],
                item["destination"], item["operation_label"], item["printed_equipment"],
                item["number_segments"], actual) != (
                service, "5031M", "東京", destination, "毎日運転", EQUIPMENT,
                expected_segments, expected):
            raise ValueError(f"Printed Sunrise column drift: {tid}")
        if [row["call_type"] for row in item["stops"]] != (
                ["origin"] + ["passenger_stop"] * (len(expected)-2) + ["destination"]):
            raise ValueError(f"Passenger call types drift: {tid}")
        for _, name, code, *_ in expected:
            if (code, name) not in station_codes:
                raise ValueError(f"Current N02 station mismatch: {name}")
            prior = previous_stations.get(code)
            if prior and prior["name_snapshot"] != name:
                raise ValueError(f"Station identity conflict: {name}")
            if prior is None:
                additions.append({"station_id": "jp.n02." + code, "name_snapshot": name,
                                  "reference_kind": "current_n02", "current_source_code": code})
                previous_stations[code] = additions[-1]
        version, calendar = tid + ".version", tid + ".calendar"
        versions.append({"timetable_version_id": version, "operator_scope": "jr-through",
                         "effective_from": DAY, "effective_until": UNTIL,
                         "edition_name": f"JR時刻表2026年10月号; {DAY} {service} dated column",
                         "revision_type": "observed_date", "completeness": "partial",
                         "source_ids": [SOURCE]})
        calendars.append({"calendar_id": calendar, "valid_from": DAY, "valid_until": UNTIL,
                          "holiday_policy": "none", **{day: 0 for day in
                          ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")}})
        exceptions.append({"calendar_id": calendar, "service_date": DAY,
                           "exception_type": "add", "source_id": SOURCE,
                           "reason": "September 30 selected in official dated Sunrise page 38492"})
        trips.append({"trip_id": tid, "timetable_version_id": version, "service_id": service,
                      "calendar_id": calendar, "train_number": "5031M", "public_number": None,
                      "origin_station_id": "jp.n02.003766",
                      "destination_station_id": "jp.n02." + CODES[destination],
                      "service_class": "limited_express",
                      "notes": "Tokyo departure September 30; Hamamatsu onward October 1. Actual operation and ordered operators unverified."})
        segments.extend({"trip_id": tid, **segment} for segment in expected_segments)
        stops.extend({"trip_id": tid, "stop_sequence": sequence, "station_id": "jp.n02." + code,
                      "arrival_time": arrival, "departure_time": departure,
                      "day_offset": offset, "platform": platform,
                      "call_type": item["stops"][sequence-1]["call_type"],
                      "pickup_allowed": int(sequence != len(expected)),
                      "dropoff_allowed": int(sequence != 1), "time_accuracy": "minute",
                      "source_id": SOURCE}
                     for sequence, name, code, arrival, departure, platform, offset in expected)
        formations.append({"formation_id": tid + ".formation." + DAY, "trip_id": tid,
                           "service_date": DAY, "evidence_kind": "planned", "source_id": SOURCE,
                           "all_reserved": True, "green_car_available": False,
                           "notes": "Printed: " + "、".join(EQUIPMENT) + "; car count, capacity, series, and actual dispatch unverified."})
        for field, locator in {"identity":"Two named official page columns",
                               "train_number":"5031M header" if tid == SETO else "5031M/4031M headers",
                               "validity_calendar":"2026年9月30日 date selection", "origin_destination":"Printed endpoints",
                               "stops":f"{len(expected)} timed passenger calls", "times":"Printed clocks, platforms, and midnight transition",
                               "formation.all_reserved":"普通車全車指定席（ノビノビ座席）"}.items():
            fact_sources.append({"entity_type":"trip","entity_id":tid,"field_name":field,
                                 "source_id":SOURCE,"page_or_locator":locator,
                                 "confidence":"high","verification_status":"verified"})
        for dimension in ("identity", "train_number", "validity_calendar", "origin_destination", "stops", "times"):
            completeness.append({"entity_type":"trip","entity_id":tid,"dimension":dimension,
                                 "status":"verified","confidence":"high",
                                 "notes":"Official selected-date page 38492"})
        for dimension, note in (("formation","Printed room and Nobi Nobi categories only"),
                                ("operator","Ordered operating-company segments not established"),
                                ("route_lines","Dated physical line sequence not established")):
            completeness.append({"entity_type":"trip","entity_id":tid,"dimension":dimension,
                                 "status":"partial" if dimension=="formation" else "unknown",
                                 "confidence":"high" if dimension=="formation" else "low","notes":note})
            if dimension != "formation":
                research.append({"research_id":tid+"."+dimension,"entity_type":"trip",
                                 "entity_id":tid,"missing_dimension":dimension,"status":"open","notes":note})
    relations = [{"trip_id": first, "related_trip_id": second, "relation_type":"couples_with",
                  "from_sequence":1,"to_sequence":9,"source_id":SOURCE}
                 for first, second in ((SETO, IZUMO), (IZUMO, SETO))]
    outputs = {
        f"normalized/station-identities-{SUFFIX}.jsonl": additions,
        f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        f"normalized/trips/{SUFFIX}/seeds.jsonl": trips,
        f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stops,
        f"normalized/trip-number-segments/{SUFFIX}/seeds.jsonl": segments,
        f"normalized/trip-relations/{SUFFIX}/seeds.jsonl": relations,
        f"normalized/trip-formations/{SUFFIX}/seeds.jsonl": formations,
        f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        f"normalized/research-queue-{SUFFIX}.jsonl": research,
    }
    for path, records in outputs.items():
        write(BASE / path, records)
    print(f"Staged {len(trips)} September 30 Sunrise departures with {len(stops)} timed calls")


if __name__ == "__main__":
    main()
