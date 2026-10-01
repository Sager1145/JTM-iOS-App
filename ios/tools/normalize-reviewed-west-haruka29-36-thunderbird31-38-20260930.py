#!/usr/bin/env python3
"""Stage sixteen date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka29-36-thunderbird31-38-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.29.2026-09-30': {'identity': ('haruka', '29', '1029M', '毎日運転', '256991'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '13:00', '30'), ('新大阪', '006911', '13:27', '13:28', '3'), ('大阪', '007068', '13:32', '13:33', '21'), ('天王寺', '007439', '13:45', '13:47', '15'), ('関西空港', '007958', '14:20', None, None)]},
    'jr-west.haruka.30.2026-09-30': {'identity': ('haruka', '30', '1030M', '毎日運転', '257251'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '14:14', None), ('天王寺', '007439', '14:48', '14:50', '18'), ('大阪', '007068', '15:01', '15:02', '24'), ('新大阪', '006911', '15:06', '15:07', '1'), ('京都', '006079', '15:34', None, '30')]},
    'jr-west.haruka.31.2026-09-30': {'identity': ('haruka', '31', '1031M', '毎日運転', '257001'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '13:30', '30'), ('新大阪', '006911', '13:57', '13:58', '3'), ('大阪', '007068', '14:02', '14:03', '21'), ('天王寺', '007439', '14:15', '14:17', '15'), ('関西空港', '007958', '14:50', None, None)]},
    'jr-west.haruka.32.2026-09-30': {'identity': ('haruka', '32', '1032M', '毎日運転', '257261'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '14:44', None), ('天王寺', '007439', '15:18', '15:20', '18'), ('大阪', '007068', '15:31', '15:32', '24'), ('新大阪', '006911', '15:36', '15:37', '1'), ('京都', '006079', '16:04', None, '30')]},
    'jr-west.haruka.33.2026-09-30': {'identity': ('haruka', '33', '1033M', '毎日運転', '257011'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '14:00', '30'), ('新大阪', '006911', '14:27', '14:28', '3'), ('大阪', '007068', '14:32', '14:33', '21'), ('天王寺', '007439', '14:45', '14:47', '15'), ('関西空港', '007958', '15:20', None, None)]},
    'jr-west.haruka.34.2026-09-30': {'identity': ('haruka', '34', '1034M', '毎日運転', '257271'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '15:14', None), ('天王寺', '007439', '15:48', '15:50', '18'), ('大阪', '007068', '16:01', '16:02', '24'), ('新大阪', '006911', '16:06', '16:07', '1'), ('京都', '006079', '16:34', None, '30')]},
    'jr-west.haruka.35.2026-09-30': {'identity': ('haruka', '35', '1035M', '毎日運転', '257021'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '14:30', '30'), ('新大阪', '006911', '14:57', '14:58', '3'), ('大阪', '007068', '15:02', '15:03', '21'), ('天王寺', '007439', '15:15', '15:17', '15'), ('関西空港', '007958', '15:50', None, None)]},
    'jr-west.haruka.36.2026-09-30': {'identity': ('haruka', '36', '1036M', '毎日運転', '257281'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '15:44', None), ('天王寺', '007439', '16:18', '16:20', '18'), ('大阪', '007068', '16:31', '16:32', '24'), ('新大阪', '006911', '16:36', '16:37', '1'), ('京都', '006079', '17:04', None, '30')]},
    'jr-west.thunderbird.31.2026-09-30': {'identity': ('thunderbird', '31', '4031M', '毎日運転', '257831'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '15:40', '11'), ('新大阪', '006911', '15:43', '15:44', '4'), ('京都', '006079', '16:06', '16:08', '0'), ('敦賀', '010186', '17:00', None, '32')]},
    'jr-west.thunderbird.32.2026-09-30': {'identity': ('thunderbird', '32', '4032M', '土曜・休日運休', '258131'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '16:43', '33'), ('京都', '006079', '17:39', '17:40', '7'), ('新大阪', '006911', '18:03', '18:04', '9'), ('大阪', '007068', '18:09', None, '5')]},
    'jr-west.thunderbird.33.2026-09-30': {'identity': ('thunderbird', '33', '4033M', '毎日運転', '257841'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '16:09', '11'), ('新大阪', '006911', '16:12', '16:13', '4'), ('京都', '006079', '16:36', '16:37', '0'), ('敦賀', '010186', '17:30', None, '31')]},
    'jr-west.thunderbird.34.2026-09-30': {'identity': ('thunderbird', '34', '4034M', '土曜・休日運休', '258151'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '17:14', '33'), ('京都', '006079', '18:09', '18:10', '7'), ('新大阪', '006911', '18:33', '18:34', '9'), ('大阪', '007068', '18:39', None, '5')]},
    'jr-west.thunderbird.35.2026-09-30': {'identity': ('thunderbird', '35', '4035M', '毎日運転', '257851'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '16:40', '11'), ('新大阪', '006911', '16:43', '16:44', '4'), ('京都', '006079', '17:06', '17:08', '0'), ('敦賀', '010186', '18:00', None, '32')]},
    'jr-west.thunderbird.36.2026-09-30': {'identity': ('thunderbird', '36', '4036M', '土曜・休日運休', '258171'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '17:44', '33'), ('京都', '006079', '18:39', '18:40', '7'), ('新大阪', '006911', '19:02', '19:03', '9'), ('大阪', '007068', '19:07', None, '3')]},
    'jr-west.thunderbird.37.2026-09-30': {'identity': ('thunderbird', '37', '4037M', '毎日運転', '257861'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '17:09', '11'), ('新大阪', '006911', '17:13', '17:13', '4'), ('京都', '006079', '17:36', '17:37', '0'), ('敦賀', '010186', '18:30', None, '31')]},
    'jr-west.thunderbird.38.2026-09-30': {'identity': ('thunderbird', '38', '4038M', '毎日運転', '258191'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '18:12', '33'), ('近江今津', '004835', '18:35', '18:36', None), ('堅田', '005626', '18:54', '18:55', None), ('京都', '006079', '19:09', '19:11', '7'), ('新大阪', '006911', '19:32', '19:33', '9'), ('大阪', '007068', '19:37', None, '3')]}}



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
    if len(candidate["trips"]) != 16 or set(selected) != set(EXPECTED):
        raise ValueError("Expected precisely sixteen reviewed trips")
    source_path = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    sources = {row["source_id"]: row for row in
               (json.loads(line) for line in source_path.read_text(encoding="utf-8").splitlines() if line)}
    if len(sources) != 16 or any(source_id in {row["source_id"] for row in rows("sources/source-registry*.jsonl")}
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
                           "notes": "Published seat categories only; actual car count, series and dispatch unverified."})
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
