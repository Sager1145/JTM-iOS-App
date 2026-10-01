#!/usr/bin/env python3
"""Normalize four exact-date JR Shikoku Ishizuchi trips for 2026-09-30."""

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-shikoku-ishizuchi3-5-7-9-20260930.json"
SUFFIX = "reviewed-shikoku-ishizuchi3-5-7-9-20260930"
DAY = "2026-09-30"
UNTIL = "2026-10-01"
STATION_SOURCE = "jtm-current-station-directory"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")

EXPECTED = {
    "3": {"train":"1003M","partner":"3M","page":"33291","count":14,"range":[3,14],"platform":"8",
          "operation":"９月１９～２３日・１０月１０日・１１月２１日は運休",
          "stops_sha256":"bb1f6969fcbd7f73d88c0220f60449c68d49e804fd7ffaf887aad953babb1c2a"},
    "5": {"train":"1005M","partner":"5M","page":"292","count":13,"range":[3,13],"platform":"7",
          "operation":"９月１８～２３日・１０月１０日・１１月２１日は運休",
          "stops_sha256":"14925bc25ec8488267dab2146a301febb2fbe73230c71a285f44616e01ddcd29"},
    "7": {"train":"1007M","partner":"7M","page":"362","count":13,"range":[3,13],"platform":"6",
          "operation":"９月１８～２３日・１０月１０日・１１月２１日は運休",
          "stops_sha256":"dcc942e8df780d2855138ecb3f3719f422823db2d5279c65cdfe41ebf7d6bbbc"},
    "9": {"train":"1009M","partner":"9M","page":"125062","count":13,"range":[3,13],"platform":"7",
          "operation":"９月１８～２３日・１０月１０日・１１月２１日は運休",
          "stops_sha256":"eabe467e592d3a715183a053ad8cce5d6fcb266d1261aba99537bb5ed4518d7c"},
}


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude or not path.is_file():
            continue
        yield from read_jsonl(path)


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    ordered = sorted(records, key=lambda row: json.dumps(row, ensure_ascii=False, sort_keys=True))
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in ordered),
        encoding="utf-8",
    )


def stop_hash(stops):
    payload = json.dumps(stops, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


def verify_candidate(candidate, prior_source_ids):
    if (candidate["candidate_status"] != "reviewed_official_html"
            or candidate["canonical"] is not False
            or candidate["service_date"] != DAY
            or len(candidate["trips"]) != 4):
        raise ValueError("Candidate status, date, or bounded trip count changed")
    source_by_id = {row["source_id"]: row for row in candidate["sources"]}
    if len(source_by_id) != 4 or prior_source_ids.intersection(source_by_id):
        raise ValueError("Source ids are missing, duplicated, or collide with an existing registry")
    for trip in candidate["trips"]:
        public = trip["public_number"]
        expected = EXPECTED.get(public)
        if expected is None:
            raise ValueError(f"Unexpected public number {public}")
        trip_id = f"jr-shikoku.ishizuchi.{public}.{expected['train'].lower()}.exact-2026-09-30"
        url = f"https://timetable.jr-odekake.net/train-timetable/{expected['page']}?date=20260930"
        source = source_by_id[trip["source_id"]]
        if (trip["trip_id"], trip["service_id"], trip["service_name"], trip["train_number"],
                trip["origin"], trip["destination"], trip["source_url"]
                ) != (trip_id, "ishizuchi", "いしづち", expected["train"], "高松", "松山", url):
            raise ValueError(f"Source-pinned identity changed for Ishizuchi {public}")
        if source["url_or_locator"] != url or source["automated_extraction_allowed"] is not False:
            raise ValueError(f"Source URL or permission changed for Ishizuchi {public}")
        if trip["calendar_observation"] != {
                "month":"2026年9月", "day":30, "cell_class":"ok", "operation_text":expected["operation"]}:
            raise ValueError(f"Calendar evidence changed for Ishizuchi {public}")
        if (len(trip["stops"]), stop_hash(trip["stops"]), trip["coupled_stop_range"]
                ) != (expected["count"], expected["stops_sha256"], expected["range"]):
            raise ValueError(f"Printed calls or coupling range changed for Ishizuchi {public}")
        if (trip["stops"][0]["platform"], trip["stops"][-1]["platform"],
                trip["coupling"]["partner_train_number"], trip["coupling"]["printed_section"]
                ) != (expected["platform"], "1", expected["partner"], "宇多津－松山"):
            raise ValueError(f"Platform or coupling evidence changed for Ishizuchi {public}")
        if trip["printed_equipment"] != ["普通車一部指定席"]:
            raise ValueError(f"Seat equipment changed for Ishizuchi {public}")
        formation = trip["formation"]
        if formation["all_reserved"] is not False or any(formation[field] is not None for field in (
                "green_car_available", "car_count", "reserved_seat_capacity", "vehicle_series", "actual_dispatch")):
            raise ValueError(f"Unprinted formation claim found for Ishizuchi {public}")


def station_ids(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    result = {}
    for name in sorted(names):
        codes = {
            station[0]
            for line in package["lines"] if line["operator"] == "四国旅客鉄道"
            for station in line["stations"] if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(f"Ambiguous or absent JR Shikoku station {name}: {sorted(codes)}")
        result[name] = "jp.n02." + next(iter(codes))
    return result


def main():
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    if DAY > manifest["as_of_date"]:
        raise ValueError("Candidate date exceeds database cutoff")
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    source_target = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    prior_source_ids = {row["source_id"] for row in rows("sources/source-registry*.jsonl", source_target)}
    verify_candidate(candidate, prior_source_ids)

    service = next((row for row in rows("normalized/services*.jsonl") if row["service_id"] == "ishizuchi"), None)
    if not service or service["canonical_name"] != "いしづち":
        raise ValueError("Existing Ishizuchi service identity missing or inconsistent")
    trip_target = BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl"
    existing_trip_ids = {row["trip_id"] for row in rows("normalized/trips/*/*.jsonl", trip_target)}
    candidate_trip_ids = {trip["trip_id"] for trip in candidate["trips"]}
    if existing_trip_ids.intersection(candidate_trip_ids):
        raise ValueError("Exact Ishizuchi trip id already exists")

    names = {stop["name"] for trip in candidate["trips"] for stop in trip["stops"]}
    stations = station_ids(names)
    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    prior_stations = {row["station_id"]: row for row in rows("normalized/station-identities*.jsonl", station_target)}
    station_rows = []
    for name, station_id in stations.items():
        record = {"station_id":station_id,"name_snapshot":name,"reference_kind":"current_n02",
                  "current_source_code":station_id.removeprefix("jp.n02.")}
        previous = prior_stations.get(station_id)
        if previous and any(previous.get(key) != value for key, value in record.items()):
            raise ValueError(f"Station identity conflict for {name}")
        if previous is None:
            station_rows.append(record)

    versions, calendars, exceptions, trips, stop_times = [], [], [], [], []
    formations, facts, completeness, research = [], [], [], []
    for trip in candidate["trips"]:
        trip_id, source_id, public = trip["trip_id"], trip["source_id"], trip["public_number"]
        calendar_id, version_id = trip_id + ".calendar", trip_id + ".version"
        versions.append({"timetable_version_id":version_id,"operator_scope":"jr-shikoku",
                         "effective_from":DAY,"effective_until":UNTIL,
                         "edition_name":f"JR時刻表2026年10月号 exact 2026-09-30 paired detail: いしづち{public}号",
                         "revision_type":"source_snapshot","completeness":"partial","source_ids":[source_id]})
        calendars.append({"calendar_id":calendar_id,"valid_from":DAY,"valid_until":UNTIL,
                          "holiday_policy":"none",**{weekday:0 for weekday in WEEKDAYS}})
        exceptions.append({"calendar_id":calendar_id,"service_date":DAY,"exception_type":"add",
                           "source_id":source_id,"reason":"2026年9月 day 30 td.ok; not among printed suspended dates"})
        trips.append({"trip_id":trip_id,"timetable_version_id":version_id,"service_id":"ishizuchi",
                      "calendar_id":calendar_id,"train_number":trip["train_number"],"public_number":public,
                      "origin_station_id":stations["高松"],"destination_station_id":stations["松山"],
                      "service_class":"limited_express","direction":"高松→松山",
                      "notes":"Exact-date paired official detail. Independent clocks use the Ishizuchi column; through clocks use the Shiokaze column only across the printed 宇多津－松山 coupling. Route and operator segments remain unresolved."})
        for sequence, stop in enumerate(trip["stops"], 1):
            call = "origin" if sequence == 1 else "destination" if sequence == len(trip["stops"]) else "passenger_stop"
            stop_times.append({"trip_id":trip_id,"stop_sequence":sequence,"station_id":stations[stop["name"]],
                               "arrival_time":stop["arrival"],"departure_time":stop["departure"],"day_offset":0,
                               "call_type":call,"pickup_allowed":0 if call == "destination" else 1,
                               "dropoff_allowed":0 if call == "origin" else 1,"platform":stop["platform"],
                               "time_accuracy":"minute","source_id":source_id})
        formations.append({"formation_id":f"{trip_id}.formation.{DAY}","trip_id":trip_id,
                           "service_date":DAY,"evidence_kind":"planned","all_reserved":False,
                           "source_id":source_id,
                           "notes":"Printed 普通車一部指定席 only; green availability, car count, series, capacity, and actual dispatch are unknown."})
        verified = {
            "identity":"Paired detail prints 特急 いしづち and public number.",
            "train_number":f"Paired detail prints {trip['train_number']}.",
            "validity_calendar":"September 30 is shown and is not among the printed suspension dates.",
            "origin_destination":"Heading and displayed rows print 高松 to 松山.",
            "stops":f"{len(trip['stops'])} printed passenger calls across independent and explicitly coupled columns.",
            "times":"All normalized clocks and platforms are printed; candidate retains their column provenance.",
            "station_refs":"Names match unique current JR Shikoku N02 station identities.",
        }
        for dimension, note in verified.items():
            completeness.append({"entity_type":"trip","entity_id":trip_id,"dimension":dimension,
                                 "status":"verified","confidence":"high","notes":note})
            facts.append({"entity_type":"trip","entity_id":trip_id,"field_name":dimension,
                          "source_id":STATION_SOURCE if dimension == "station_refs" else source_id,
                          "page_or_locator":"2026-09-30 paired train detail and printed coupling section",
                          "confidence":"high","verification_status":"verified"})
        completeness.extend([
            {"entity_type":"trip","entity_id":trip_id,"dimension":"formation","status":"partial","confidence":"high","notes":"Only 普通車一部指定席 is printed."},
            {"entity_type":"trip","entity_id":trip_id,"dimension":"operator","status":"unknown","confidence":"low","notes":"No ordered operator-boundary source."},
            {"entity_type":"trip","entity_id":trip_id,"dimension":"route_lines","status":"unknown","confidence":"low","notes":"No dated ordered physical line IDs."},
            {"entity_type":"trip","entity_id":trip_id,"dimension":"provenance","status":"partial","confidence":"medium","notes":"Official verification URL; reproduction and processing prohibited."},
        ])
        facts.extend([
            {"entity_type":"trip","entity_id":trip_id,"field_name":"formation.all_reserved","source_id":source_id,
             "page_or_locator":"車両設備情報: 普通車一部指定席","confidence":"high","verification_status":"verified"},
            {"entity_type":"trip","entity_id":trip_id,"field_name":"coupling.partner_train_number","source_id":source_id,
             "page_or_locator":f"併結運転: 宇多津－松山は{trip['coupling']['partner_train_number']}に併結",
             "confidence":"high","verification_status":"verified"},
            {"entity_type":"trip","entity_id":trip_id,"field_name":"provenance","source_id":source_id,
             "page_or_locator":"Exact-date official URL; source bytes not bundled","confidence":"medium","verification_status":"partial"},
        ])
        for dimension, status, note in (
            ("coupling_partner","open",f"Materialize しおかぜ{public}号 {trip['coupling']['partner_train_number']} before adding a relation."),
            ("operator","open","Find dated ordered train-operator segment boundaries."),
            ("route_lines","open","Find dated ordered physical line identities."),
            ("formation","open","Find green availability, car count, series, capacity, and actual-dispatch evidence."),
            ("provenance","license_blocked","Official page prohibits reproduction and processing."),
        ):
            research.append({"research_id":f"{trip_id}.{dimension}","entity_type":"trip","entity_id":trip_id,
                             "missing_dimension":dimension,"status":status,"notes":note})

    outputs = {
        source_target: candidate["sources"],
        station_target: station_rows,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        trip_target: trips,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_times,
        BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl": formations,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": facts,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": research,
    }
    for path, records in outputs.items():
        write(path, records)
    print(f"Staged {len(trips)} exact-date Ishizuchi trips and {len(stop_times)} printed passenger calls")


if __name__ == "__main__":
    main()
