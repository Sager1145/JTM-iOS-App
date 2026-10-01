#!/usr/bin/env python3
"""Stage sixteen date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka21-28-thunderbird23-30-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.21.2026-09-30': {'identity': ('haruka', '21', '1021M', '毎日運転', '256951'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '11:00', '30'), ('新大阪', '006911', '11:27', '11:28', '3'), ('大阪', '007068', '11:32', '11:33', '21'), ('天王寺', '007439', '11:45', '11:47', '15'), ('関西空港', '007958', '12:20', None, None)]},
    'jr-west.haruka.22.2026-09-30': {'identity': ('haruka', '22', '1022M', '毎日運転', '257211'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '12:14', None), ('天王寺', '007439', '12:48', '12:50', '18'), ('大阪', '007068', '13:01', '13:02', '24'), ('新大阪', '006911', '13:06', '13:07', '1'), ('京都', '006079', '13:34', None, '30')]},
    'jr-west.haruka.23.2026-09-30': {'identity': ('haruka', '23', '1023M', '毎日運転', '256961'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '11:30', '30'), ('新大阪', '006911', '11:57', '11:58', '3'), ('大阪', '007068', '12:02', '12:03', '21'), ('天王寺', '007439', '12:15', '12:17', '15'), ('関西空港', '007958', '12:50', None, None)]},
    'jr-west.haruka.24.2026-09-30': {'identity': ('haruka', '24', '1024M', '毎日運転', '257221'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '12:44', None), ('天王寺', '007439', '13:18', '13:20', '18'), ('大阪', '007068', '13:31', '13:32', '24'), ('新大阪', '006911', '13:36', '13:37', '1'), ('京都', '006079', '14:04', None, '30')]},
    'jr-west.haruka.25.2026-09-30': {'identity': ('haruka', '25', '1025M', '毎日運転', '256971'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '12:00', '30'), ('新大阪', '006911', '12:27', '12:28', '3'), ('大阪', '007068', '12:32', '12:33', '21'), ('天王寺', '007439', '12:45', '12:47', '15'), ('関西空港', '007958', '13:20', None, None)]},
    'jr-west.haruka.26.2026-09-30': {'identity': ('haruka', '26', '1026M', '毎日運転', '257231'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '13:14', None), ('天王寺', '007439', '13:48', '13:50', '18'), ('大阪', '007068', '14:01', '14:02', '24'), ('新大阪', '006911', '14:06', '14:07', '1'), ('京都', '006079', '14:34', None, '30')]},
    'jr-west.haruka.27.2026-09-30': {'identity': ('haruka', '27', '1027M', '毎日運転', '256981'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '12:30', '30'), ('新大阪', '006911', '12:57', '12:58', '3'), ('大阪', '007068', '13:02', '13:03', '21'), ('天王寺', '007439', '13:15', '13:17', '15'), ('関西空港', '007958', '13:50', None, None)]},
    'jr-west.haruka.28.2026-09-30': {'identity': ('haruka', '28', '1028M', '毎日運転', '257241'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '13:44', None), ('天王寺', '007439', '14:18', '14:20', '18'), ('大阪', '007068', '14:31', '14:32', '24'), ('新大阪', '006911', '14:36', '14:37', '1'), ('京都', '006079', '15:04', None, '30')]},
    'jr-west.thunderbird.23.2026-09-30': {'identity': ('thunderbird', '23', '4023M', '毎日運転', '257791'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '12:42', '11'), ('新大阪', '006911', '12:45', '12:46', '4'), ('京都', '006079', '13:09', '13:10', '0'), ('敦賀', '010186', '14:03', None, '32')]},
    'jr-west.thunderbird.24.2026-09-30': {'identity': ('thunderbird', '24', '4024M', '毎日運転', '258091'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '14:14', '33'), ('京都', '006079', '15:09', '15:10', '7'), ('新大阪', '006911', '15:32', '15:32', '9'), ('大阪', '007068', '15:36', None, '3')]},
    'jr-west.thunderbird.25.2026-09-30': {'identity': ('thunderbird', '25', '4025M', '毎日運転', '257801'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '13:12', '11'), ('新大阪', '006911', '13:15', '13:16', '4'), ('京都', '006079', '13:39', '13:40', '0'), ('敦賀', '010186', '14:33', None, '31')]},
    'jr-west.thunderbird.26.2026-09-30': {'identity': ('thunderbird', '26', '4026M', '毎日運転', '258101'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '15:14', '33'), ('京都', '006079', '16:09', '16:10', '7'), ('新大阪', '006911', '16:32', '16:32', '9'), ('大阪', '007068', '16:36', None, '3')]},
    'jr-west.thunderbird.27.2026-09-30': {'identity': ('thunderbird', '27', '4027M', '毎日運転', '257811'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '14:12', '11'), ('新大阪', '006911', '14:15', '14:16', '4'), ('京都', '006079', '14:39', '14:40', '0'), ('敦賀', '010186', '15:33', None, '31')]},
    'jr-west.thunderbird.28.2026-09-30': {'identity': ('thunderbird', '28', '4028M', '毎日運転', '258111'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '15:44', '33'), ('京都', '006079', '16:39', '16:40', '7'), ('新大阪', '006911', '17:02', '17:02', '9'), ('大阪', '007068', '17:06', None, '3')]},
    'jr-west.thunderbird.29.2026-09-30': {'identity': ('thunderbird', '29', '4029M', '毎日運転', '257821'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '15:09', '11'), ('新大阪', '006911', '15:13', '15:13', '4'), ('京都', '006079', '15:36', '15:37', '0'), ('敦賀', '010186', '16:31', None, '31')]},
    'jr-west.thunderbird.30.2026-09-30': {'identity': ('thunderbird', '30', '4030M', '毎日運転', '258121'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '16:13', '33'), ('京都', '006079', '17:09', '17:10', '7'), ('新大阪', '006911', '17:32', '17:32', '9'), ('大阪', '007068', '17:36', None, '3')]}}



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
