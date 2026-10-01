#!/usr/bin/env python3
# coding: utf-8
"""Stage four source-reviewed September 30 Yakumo trains."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo13-16-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXISTING_15 = "jr-west.yakumo.15.2026-09-30"
EXPECTED = {'jr-west.yakumo.13.2026-09-30': {'identity': ('yakumo', '13', '1013M', '毎日運転', '278871'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '13:13', '2'), ('倉敷', '007598', '13:24', '13:24', None), ('備中高梁', '006686', '13:47', '13:48', None), ('新見', '006070', '14:15', '14:16', None), ('生山', '005452', '14:50', '14:51', None), ('米子', '004758', '15:28', '15:29', '2'), ('安来', '004748', '15:36', '15:36', None), ('松江', '004638', '15:51', '15:52', None), ('玉造温泉', '004736', '15:57', '15:58', None), ('出雲市', '004943', '16:19', None, None)]}, 'jr-west.yakumo.14.2026-09-30': {'identity': ('yakumo', '14', '1014M', '毎日運転', '631'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '10:38', None), ('玉造温泉', '004736', '10:57', '10:58', None), ('松江', '004638', '11:04', '11:07', None), ('安来', '004748', '11:22', '11:23', None), ('米子', '004758', '11:31', '11:35', '1'), ('生山', '005452', '12:15', '12:15', None), ('新見', '006070', '12:43', '12:44', None), ('備中高梁', '006686', '13:09', '13:10', None), ('総社', '007263', '13:25', '13:26', None), ('倉敷', '007598', '13:33', '13:34', None), ('岡山', '007310', '13:46', None, '3')]}, 'jr-west.yakumo.15.2026-09-30': {'identity': ('yakumo', '15', '1015M', '毎日運転', '681'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '14:13', '2'), ('倉敷', '007598', '14:24', '14:24', None), ('備中高梁', '006686', '14:47', '14:48', None), ('新見', '006070', '15:15', '15:16', None), ('根雨', '005255', '16:03', '16:04', None), ('米子', '004758', '16:27', '16:28', '2'), ('安来', '004748', '16:35', '16:35', None), ('松江', '004638', '16:51', '16:54', None), ('玉造温泉', '004736', '17:02', '17:02', None), ('宍道', '004793', '17:10', '17:10', None), ('出雲市', '004943', '17:23', None, None)]}, 'jr-west.yakumo.16.2026-09-30': {'identity': ('yakumo', '16', '1016M', '毎日運転', '278911'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '11:44', None), ('宍道', '004793', '11:54', '11:55', None), ('玉造温泉', '004736', '12:03', '12:04', None), ('松江', '004638', '12:10', '12:11', None), ('安来', '004748', '12:26', '12:27', None), ('米子', '004758', '12:34', '12:35', '1'), ('根雨', '005255', '12:59', '13:03', None), ('新見', '006070', '13:45', '13:46', None), ('備中高梁', '006686', '14:13', '14:14', None), ('倉敷', '007598', '14:35', '14:36', None), ('岡山', '007310', '14:47', None, '3')]}}


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
    prior_sources = {row["source_id"]: row for row in rows("sources/source-registry*.jsonl")}
    if len(sources) != 3 or any(source_id in prior_sources
                                for source_id in sources):
        raise ValueError("Source registry collision or omission")
    existing_trips = {row["trip_id"]: row for row in rows("normalized/trips/**/*.jsonl")}
    if set(existing_trips) & (set(selected) - {EXISTING_15}):
        raise ValueError("Trip id collision")
    if EXISTING_15 not in existing_trips:
        raise ValueError("Previously normalized Yakumo 15 missing")
    existing_services = {row["service_id"] for row in rows("normalized/services*.jsonl")}
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    station_codes = {(station[0], station[1]) for line in package["lines"]
                     for station in line.get("stations", [])}
    existing_stations = {row.get("current_source_code"): row
                         for row in rows("normalized/station-identities*.jsonl")}
    existing_stations.update({row.get("current_source_code"): row
                              for row in rows("normalized/station-identities/**/*.jsonl")})
    station_additions = []
    versions, calendars, exceptions, trips, stops, formations, overrides = [], [], [], [], [], [], []
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
        source = (prior_sources if tid == EXISTING_15 else sources).get(source_id)
        if source is None or (source["url_or_locator"], source["effective_date"],
                source["redistribution_status"]) != (url, DAY, "verification_only"):
            raise ValueError(f"Official source drift: {tid}")
        if service not in existing_services:
            raise ValueError(f"Service identity missing: {service}")
        calls = [(stop["name"], stop["code"], stop["arrival"], stop["departure"], stop["platform"])
                 for stop in item["stops"]]
        if calls != spec["calls"] or [stop["call_type"] for stop in item["stops"]] != (
                ["origin"] + ["passenger_stop"] * (len(calls) - 2) + ["destination"]):
            raise ValueError(f"Printed passenger calls drift: {tid}")
        if tid == EXISTING_15:
            existing = existing_trips[tid]
            if (existing["service_id"], existing["public_number"], existing["train_number"]) != (
                    service, public, number):
                raise ValueError("Existing Yakumo 15 identity drift")
            prior_calls = sorted((row for row in rows("normalized/stop-times/**/*.jsonl")
                                  if row["trip_id"] == tid), key=lambda row: row["stop_sequence"])
            if [(row["station_id"], row["arrival_time"], row["departure_time"])
                    for row in prior_calls] != [
                    ("jp.n02." + code, arrival, departure)
                    for _, code, arrival, departure, platform in calls]:
                raise ValueError("Existing Yakumo 15 calls differ from September 30 page")
            for sequence, (_, _, _, _, platform) in enumerate(calls, 1):
                prior_platform = prior_calls[sequence - 1].get("platform")
                if prior_platform not in (None, platform):
                    raise ValueError("Existing Yakumo 15 platform conflicts with page")
                if platform is not None and prior_platform is None:
                    overrides.append({"trip_id": tid, "service_date": DAY,
                                      "stop_sequence": sequence, "source_id": source_id,
                                      "platform_override": platform, "platform_override_present": 1})
            prior_formations = [row for row in rows("normalized/trip-formations/**/*.jsonl")
                                if row["trip_id"] == tid and row["service_date"] == DAY]
            if len(prior_formations) != 1 or not prior_formations[0]["all_reserved"] or not prior_formations[0]["green_car_available"]:
                raise ValueError("Existing Yakumo 15 seat plan differs from page")
            fact_rows.append({"entity_type": "trip", "entity_id": tid,
                              "field_name": "platforms", "source_id": source_id,
                              "page_or_locator": "2026-09-30 train page: 岡山 2; 米子 2",
                              "confidence": "high", "verification_status": "verified"})
            continue
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
        f"normalized/trip-stop-time-overrides/{SUFFIX}/seeds.jsonl": overrides,
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
