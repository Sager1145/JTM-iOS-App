#!/usr/bin/env python3
# coding: utf-8
"""Stage four source-reviewed September 30 Yakumo trains."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo9-12-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.yakumo.9.2026-09-30': {'identity': ('yakumo', '9', '1009M', '毎日運転', '76271'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '11:13', '2'), ('倉敷', '007598', '11:24', '11:24', None), ('備中高梁', '006686', '11:47', '11:48', None), ('新見', '006070', '12:15', '12:16', None), ('生山', '005452', '12:48', '12:49', None), ('米子', '004758', '13:25', '13:26', '2'), ('安来', '004748', '13:33', '13:34', None), ('松江', '004638', '13:48', '13:49', None), ('玉造温泉', '004736', '13:55', '13:56', None), ('宍道', '004793', '14:08', '14:08', None), ('出雲市', '004943', '14:19', None, None)]}, 'jr-west.yakumo.10.2026-09-30': {'identity': ('yakumo', '10', '1010M', '毎日運転', '76321'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '08:34', None), ('宍道', '004793', '08:47', '08:48', None), ('玉造温泉', '004736', '08:56', '08:56', None), ('松江', '004638', '09:05', '09:06', None), ('安来', '004748', '09:26', '09:26', None), ('米子', '004758', '09:34', '09:35', '1'), ('伯耆大山', '004738', '09:39', '09:40', None), ('生山', '005452', '10:13', '10:14', None), ('新見', '006070', '10:44', '10:45', None), ('備中高梁', '006686', '11:13', '11:14', None), ('倉敷', '007598', '11:35', '11:36', None), ('岡山', '007310', '11:47', None, '3')]}, 'jr-west.yakumo.11.2026-09-30': {'identity': ('yakumo', '11', '1011M', '毎日運転', '541'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '12:13', '2'), ('倉敷', '007598', '12:24', '12:24', None), ('総社', '007263', '12:32', '12:33', None), ('備中高梁', '006686', '12:49', '12:49', None), ('新見', '006070', '13:20', '13:21', None), ('根雨', '005255', '14:03', '14:03', None), ('米子', '004758', '14:26', '14:28', '2'), ('安来', '004748', '14:34', '14:35', None), ('松江', '004638', '14:54', '14:55', None), ('玉造温泉', '004736', '15:01', '15:01', None), ('宍道', '004793', '15:09', '15:09', None), ('出雲市', '004943', '15:20', None, None)]}, 'jr-west.yakumo.12.2026-09-30': {'identity': ('yakumo', '12', '1012M', '毎日運転', '278901'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '09:40', None), ('宍道', '004793', '09:55', '09:56', None), ('玉造温泉', '004736', '10:04', '10:04', None), ('松江', '004638', '10:10', '10:11', None), ('安来', '004748', '10:26', '10:27', None), ('米子', '004758', '10:34', '10:36', '1'), ('根雨', '005255', '10:59', '11:02', None), ('新見', '006070', '11:44', '11:44', None), ('備中高梁', '006686', '12:13', '12:14', None), ('倉敷', '007598', '12:35', '12:36', None), ('岡山', '007310', '12:47', None, '3')]}}


def rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern)
            if SUFFIX not in str(path)
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in records), encoding="utf-8")


def main():
    candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"]) != (
            "visually_reviewed_official_train_pages", False, DAY):
        raise ValueError("Batch date/status drift")
    if DAY > timetable.load_manifest(BASE)["as_of_date"]:
        raise ValueError("Batch exceeds dataset as-of date")
    selected = {trip["trip_id"]: trip for trip in candidate["trips"]}
    if len(candidate["trips"]) != 4 or set(selected) != set(EXPECTED):
        raise ValueError("Expected precisely four reviewed trips")
    source_path = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    sources = {row["source_id"]: row for row in
               (json.loads(line) for line in source_path.read_text(encoding="utf-8").splitlines() if line)}
    if len(sources) != 4 or any(source_id in {row["source_id"] for row in rows("sources/source-registry*.jsonl")}
                                for source_id in sources):
        raise ValueError("Source registry collision or omission")
    existing_trip_ids = {row["trip_id"] for row in rows("normalized/trips/**/*.jsonl")}
    if existing_trip_ids & set(selected):
        raise ValueError("Trip id collision")
    existing_services = {row["service_id"] for row in rows("normalized/services*.jsonl")}
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    station_codes = {(station[0], station[1]) for line in package["lines"]
                     for station in line.get("stations", [])}
    existing_stations = {row.get("current_source_code"): row
                         for row in rows("normalized/station-identities*.jsonl")}
    existing_stations.update({row.get("current_source_code"): row
                              for row in rows("normalized/station-identities/**/*.jsonl")})
    station_additions = []
    versions, calendars, exceptions, trips, stops, formations = [], [], [], [], [], []
    fact_rows, completeness, research = [], [], []
    for tid, spec in EXPECTED.items():
        item = selected[tid]
        service, public, number, label, page = spec["identity"]
        source_id = f"jr-west-odekake-{service}{public}-{number.lower()}-20260930"
        url = f"https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930"
        if (item["service_id"], item["public_number"], item["train_number"],
                item["operation_label"], item["source_id"], item["source_url"],
                item["printed_equipment"]) != (
                service, public, number, label, source_id, url, spec["equipment"]):
            raise ValueError(f"Train identity/equipment drift: {tid}")
        if (sources[source_id]["url_or_locator"], sources[source_id]["effective_date"],
                sources[source_id]["redistribution_status"]) != (url, DAY, "verification_only"):
            raise ValueError(f"Official source drift: {tid}")
        if service not in existing_services:
            raise ValueError(f"Service identity missing: {service}")
        calls = [(stop["name"], stop["code"], stop["arrival"], stop["departure"], stop["platform"])
                 for stop in item["stops"]]
        if calls != spec["calls"] or [stop["call_type"] for stop in item["stops"]] != (
                ["origin"] + ["passenger_stop"] * (len(calls) - 2) + ["destination"]):
            raise ValueError(f"Printed passenger calls drift: {tid}")
        for name, code, *_ in calls:
            if (code, name) not in station_codes:
                raise ValueError(f"N02 station mismatch: {name}")
            prior = existing_stations.get(code)
            if prior and prior["name_snapshot"] != name:
                raise ValueError(f"Conflicting station identity: {name}")
            if prior is None:
                station_additions.append({"station_id": "jp.n02." + code, "name_snapshot": name,
                                          "reference_kind": "current_n02", "current_source_code": code})
                existing_stations[code] = station_additions[-1]
        version, calendar = tid + ".version", tid + ".calendar"
        versions.append({"timetable_version_id": version, "operator_scope": "jr-west",
                         "effective_from": DAY, "effective_until": UNTIL,
                         "edition_name": f"JR Odekake {DAY} {service} {public}",
                         "revision_type": "observed_date", "completeness": "partial", "source_ids": [source_id]})
        calendars.append({"calendar_id": calendar, "valid_from": DAY, "valid_until": UNTIL,
                          "holiday_policy": "none", **{day: 0 for day in
                          ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")}})
        exceptions.append({"calendar_id": calendar, "service_date": DAY, "exception_type": "add",
                           "reason": "Selected exact-date official variant", "source_id": source_id})
        trips.append({"trip_id": tid, "timetable_version_id": version, "service_id": service,
                      "calendar_id": calendar, "train_number": number, "public_number": public,
                      "origin_station_id": "jp.n02." + calls[0][1],
                      "destination_station_id": "jp.n02." + calls[-1][1],
                      "service_class": "limited_express",
                      "notes": "Only selected date staged; physical route and train operator remain unresolved."})
        stops.extend({"trip_id": tid, "stop_sequence": index, "station_id": "jp.n02." + code,
                      "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
                      "platform": platform, "call_type": kind, "pickup_allowed": int(kind != "destination"),
                      "dropoff_allowed": int(kind != "origin"), "time_accuracy": "minute",
                      "source_id": source_id}
                     for index, (name, code, arrival, departure, platform) in enumerate(calls, 1)
                     for kind in [item["stops"][index - 1]["call_type"]])
        all_reserved = "普通車全車指定席" in item["printed_equipment"]
        formations.append({"formation_id": f"{tid}.formation.{DAY}", "trip_id": tid,
                           "service_date": DAY, "evidence_kind": "planned",
                           "all_reserved": all_reserved, "green_car_available": True,
                           "source_id": source_id,
                           "notes": "Printed Green reserved and all ordinary reserved categories only; actual vehicle, car count, capacity and dispatch unverified."})
        verified = {"identity": "Named exact-date train", "train_number": number,
                    "validity_calendar": "Selected September 30 variant",
                    "origin_destination": "Printed termini", "stops": f"{len(calls)} timed passenger calls",
                    "times": "Printed minute clocks", "station_refs": "Current N02 station identities"}
        fact_rows.extend({"entity_type": "trip", "entity_id": tid, "field_name": field,
                          "source_id": "jtm-current-station-directory" if field == "station_refs" else source_id,
                          "page_or_locator": locator, "confidence": "high", "verification_status": "verified"}
                         for field, locator in verified.items())
        fact_rows.extend({"entity_type": "trip", "entity_id": tid,
                          "field_name": f"formation.{field}", "source_id": source_id,
                          "page_or_locator": "2026-09-30 車両設備情報", "confidence": "high",
                          "verification_status": "verified"}
                         for field in ("all_reserved", "green_car_available"))
        completeness.extend({"entity_type": "trip", "entity_id": tid, "dimension": field,
                             "status": "verified", "confidence": "high", "notes": locator}
                            for field, locator in verified.items())
        completeness.extend({"entity_type": "trip", "entity_id": tid, "dimension": dimension,
                             "status": status, "confidence": confidence, "notes": note}
                            for dimension, status, confidence, note in [
                                ("formation", "partial", "high", "Planned seat categories only."),
                                ("route_lines", "unknown", "low", "Daily physical route unverified."),
                                ("operator", "unknown", "low", "Train-operation segments unverified.")])
        research.extend({"research_id": f"{tid}.{dimension}", "entity_type": "trip", "entity_id": tid,
                         "missing_dimension": dimension, "status": "open", "notes": note}
                        for dimension, note in [("route_lines", "Confirm exact-day physical route."),
                                                ("operator", "Confirm train-operation company segments.")])
    outputs = {
        f"normalized/station-identities-{SUFFIX}.jsonl": station_additions,
        f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        f"normalized/trips/{SUFFIX}/seeds.jsonl": trips,
        f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stops,
        f"normalized/trip-formations/{SUFFIX}/seeds.jsonl": formations,
        f"normalized/fact-sources-{SUFFIX}.jsonl": fact_rows,
        f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        f"normalized/research-queue-{SUFFIX}.jsonl": research,
    }
    for path, records in outputs.items():
        write(BASE / path, records)
    print(f"Staged {len(trips)} exact-date trips with {len(stops)} passenger calls")


if __name__ == "__main__":
    main()
