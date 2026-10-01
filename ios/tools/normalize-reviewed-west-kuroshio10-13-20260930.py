#!/usr/bin/env python3
# coding: utf-8
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio10-13-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.10.2026-09-30': {'identity': ('kuroshio', '10', '2060M', '土曜・休日運休', '144491'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('白浜', '008915', None, '07:10', None), ('紀伊田辺', '008867', '07:20', '07:22', None), ('南部', '008845', '07:28', '07:28', None), ('御坊', '008657', '07:52', '07:53', None), ('湯浅', '008554', '08:06', '08:07', None), ('藤並', '008517', '08:10', '08:11', None), ('箕島', '008481', '08:17', '08:18', None), ('海南', '008442', '08:29', '08:30', None), ('和歌山', '008365', '08:39', '08:41', '1'), ('和泉砂川', '008142', '08:58', '08:58', None), ('日根野', '008072', '09:03', '09:04', None), ('天王寺', '007439', '09:34', '09:35', '18'), ('大阪', '007068', '09:46', '09:47', '24'), ('新大阪', '006911', '09:52', None, '2')]}, 'jr-west.kuroshio.11.2026-09-30': {'identity': ('kuroshio', '11', '61M', '毎日運転', '144341'), 'equipment': ['オーシャンアロー車両で運転', '女性専用席があります', 'グリーン車指定席（パノラマ型グリーン車）', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '12:13', '2'), ('大阪', '007068', '12:17', '12:18', '21'), ('天王寺', '007439', '12:30', '12:32', '15'), ('日根野', '008072', '12:57', '12:57', None), ('和歌山', '008365', '13:15', '13:18', '4'), ('海南', '008442', '13:27', '13:27', None), ('御坊', '008657', '14:00', '14:00', None), ('紀伊田辺', '008867', '14:29', '14:31', None), ('白浜', '008915', '14:41', '14:43', None), ('周参見', '009191', '15:07', '15:08', None), ('串本', '009265', '15:40', '15:40', None), ('古座', '009224', '15:49', '15:50', None), ('太地', '009025', '16:08', '16:09', None), ('紀伊勝浦', '008974', '16:16', '16:17', None), ('新宮', '008874', '16:40', None, None)]}, 'jr-west.kuroshio.12.2026-09-30': {'identity': ('kuroshio', '12', '62M', '土曜・休日運休', '144511'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新宮', '008874', None, '06:27', None), ('紀伊勝浦', '008974', '06:44', '06:45', None), ('太地', '009025', '06:51', '06:52', None), ('古座', '009224', '07:10', '07:10', None), ('串本', '009265', '07:18', '07:19', None), ('周参見', '009191', '07:50', '07:51', None), ('白浜', '008915', '08:13', '08:20', None), ('紀伊田辺', '008867', '08:30', '08:32', None), ('南部', '008845', '08:37', '08:38', None), ('御坊', '008657', '09:02', '09:03', None), ('湯浅', '008554', '09:16', '09:16', None), ('藤並', '008517', '09:19', '09:20', None), ('箕島', '008481', '09:26', '09:27', None), ('海南', '008442', '09:38', '09:39', None), ('和歌山', '008365', '09:48', '09:50', '1'), ('日根野', '008072', '10:08', '10:09', None), ('天王寺', '007439', '10:33', '10:35', '18'), ('大阪', '007068', '10:46', '10:47', '24'), ('新大阪', '006911', '10:51', '10:52', '1'), ('京都', '006079', '11:17', None, '0')]}, 'jr-west.kuroshio.13.2026-09-30': {'identity': ('kuroshio', '13', '2063M', '毎日運転', '144351'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '13:13', '2'), ('大阪', '007068', '13:17', '13:18', '21'), ('天王寺', '007439', '13:30', '13:32', '15'), ('日根野', '008072', '13:57', '13:57', None), ('和歌山', '008365', '14:15', '14:18', '4'), ('海南', '008442', '14:27', '14:27', None), ('箕島', '008481', '14:39', '14:40', None), ('藤並', '008517', '14:46', '14:47', None), ('湯浅', '008554', '14:50', '14:50', None), ('御坊', '008657', '15:04', '15:04', None), ('南部', '008845', '15:27', '15:28', None), ('紀伊田辺', '008867', '15:35', '15:36', None), ('白浜', '008915', '15:47', None, None)]}}


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
        fact_rows.append({"entity_type": "trip", "entity_id": tid,
                          "field_name": "formation.women_only_seat_available", "source_id": source_id,
                          "page_or_locator": "2026-09-30 車両設備情報: 女性専用席があります",
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
