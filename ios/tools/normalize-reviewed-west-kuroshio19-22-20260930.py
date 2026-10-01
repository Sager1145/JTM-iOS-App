#!/usr/bin/env python3
# coding: utf-8
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio19-22-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.19.2026-09-30': {'identity': ('kuroshio', '19', '2069M', '毎日運転', '18841'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '16:13', '2'), ('大阪', '007068', '16:17', '16:18', '21'), ('天王寺', '007439', '16:31', '16:32', '15'), ('日根野', '008072', '16:57', '16:58', None), ('和泉砂川', '008142', '17:02', '17:03', None), ('和歌山', '008365', '17:18', '17:20', '4'), ('海南', '008442', '17:28', '17:29', None), ('箕島', '008481', '17:40', '17:41', None), ('藤並', '008517', '17:47', '17:47', None), ('湯浅', '008554', '17:51', '17:51', None), ('御坊', '008657', '18:04', '18:05', None), ('南部', '008845', '18:28', '18:28', None), ('紀伊田辺', '008867', '18:35', '18:36', None), ('白浜', '008915', '18:47', None, None)]}, 'jr-west.kuroshio.20.2026-09-30': {'identity': ('kuroshio', '20', '2070M', '毎日運転', '183811'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('白浜', '008915', None, '12:20', None), ('紀伊田辺', '008867', '12:30', '12:32', None), ('南部', '008845', '12:38', '12:38', None), ('御坊', '008657', '13:02', '13:03', None), ('湯浅', '008554', '13:16', '13:16', None), ('藤並', '008517', '13:20', '13:20', None), ('箕島', '008481', '13:27', '13:27', None), ('海南', '008442', '13:39', '13:39', None), ('和歌山', '008365', '13:48', '13:50', '1'), ('日根野', '008072', '14:08', '14:08', None), ('天王寺', '007439', '14:33', '14:35', '18'), ('大阪', '007068', '14:46', '14:47', '24'), ('新大阪', '006911', '14:51', None, '2')]}, 'jr-west.kuroshio.21.2026-09-30': {'identity': ('kuroshio', '21', '71M', '土曜・休日運休', '50631'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '17:13', '2'), ('大阪', '007068', '17:17', '17:18', '21'), ('天王寺', '007439', '17:33', '17:35', '15'), ('和泉府中', '007871', '17:52', '17:52', None), ('日根野', '008072', '18:02', '18:02', None), ('和泉砂川', '008142', '18:07', '18:07', None), ('和歌山', '008365', '18:22', '18:25', '4'), ('海南', '008442', '18:33', '18:34', None), ('箕島', '008481', '18:45', '18:46', None), ('藤並', '008517', '18:52', '18:53', None), ('湯浅', '008554', '18:56', '18:56', None), ('御坊', '008657', '19:10', '19:10', None), ('南部', '008845', '19:33', '19:33', None), ('紀伊田辺', '008867', '19:40', '19:42', None), ('白浜', '008915', '19:54', '19:56', None), ('周参見', '009191', '20:17', '20:17', None), ('串本', '009265', '20:50', '20:50', None), ('古座', '009224', '20:59', '20:59', None), ('太地', '009025', '21:16', '21:16', None), ('紀伊勝浦', '008974', '21:23', '21:23', None), ('新宮', '008874', '21:41', None, None)]}, 'jr-west.kuroshio.22.2026-09-30': {'identity': ('kuroshio', '22', '72M', '毎日運転', '183821'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新宮', '008874', None, '11:27', None), ('紀伊勝浦', '008974', '11:49', '11:49', None), ('太地', '009025', '11:56', '11:56', None), ('古座', '009224', '12:14', '12:14', None), ('串本', '009265', '12:22', '12:23', None), ('周参見', '009191', '12:58', '12:58', None), ('白浜', '008915', '13:19', '13:26', None), ('紀伊田辺', '008867', '13:36', '13:37', None), ('御坊', '008657', '14:06', '14:07', None), ('海南', '008442', '14:39', '14:39', None), ('和歌山', '008365', '14:48', '14:50', '1'), ('日根野', '008072', '15:08', '15:08', None), ('天王寺', '007439', '15:33', '15:35', '18'), ('大阪', '007068', '15:46', '15:47', '24'), ('新大阪', '006911', '15:51', None, '2')]}}


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
        ocean_arrow = "オーシャンアロー車両で運転" in item["printed_equipment"]
        formations.append({"formation_id": f"{tid}.formation.{DAY}", "trip_id": tid,
                           "service_date": DAY, "evidence_kind": "planned",
                           "all_reserved": all_reserved, "green_car_available": True,
                           "source_id": source_id,
                           **({"formation_label": "オーシャンアロー車両"} if ocean_arrow else {}),
                           "notes": ("Printed Ocean Arrow vehicle and panorama Green plan; actual dispatch, car count and capacity unverified." if ocean_arrow else "Printed seat categories only; actual vehicle, car count, capacity and dispatch unverified.")})
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
        women_only_car = "女性専用車両があります" in item["printed_equipment"]
        fact_rows.append({"entity_type": "trip", "entity_id": tid,
                          "field_name": ("formation.women_only_car_available" if women_only_car
                                         else "formation.women_only_seat_available"),
                          "source_id": source_id,
                          "page_or_locator": ("2026-09-30 車両設備情報: 女性専用車両があります"
                                              if women_only_car else
                                              "2026-09-30 車両設備情報: 女性専用席があります"),
                          "confidence": "high", "verification_status": "verified"})
        if ocean_arrow:
            fact_rows.append({"entity_type": "trip", "entity_id": tid,
                              "field_name": "formation.formation_label", "source_id": source_id,
                              "page_or_locator": "2026-09-30 車両設備情報: オーシャンアロー車両で運転",
                              "confidence": "high", "verification_status": "verified"})
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
