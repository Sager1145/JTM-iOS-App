#!/usr/bin/env python3
"""Stage the official 2026-09-29 Sunrise Izumo and its Seto coupling."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-sunrise-izumo-20260929"
DATE, UNTIL = "2026-09-29", "2026-09-30"
TRIP = "jr-west.sunrise-izumo.5031m-4031m.2026-09-29"
SETO = "jr-west.sunrise-seto.5031m.2026-09-29"
SOURCE = "jr-west-sunrise-seto-20260929"
URL = "https://timetable.jr-odekake.net/train-timetable/38492?date=20260929"
HASH = "sha256:8c47b02e1a5fda8e8f5a6080037869a1c95896b2a32d328b7d9bdbf3ab8afa1c"
CODES = {
    "東京":"003766", "横浜":"004633", "熱海":"005685", "沼津":"005689",
    "富士":"005522", "静岡":"006128", "浜松":"007059", "姫路":"006509",
    "岡山":"007310", "倉敷":"007598", "備中高梁":"006686", "新見":"006070",
    "米子":"004758", "安来":"004748", "松江":"004638", "宍道":"004793",
    "出雲市":"004943",
}
EXPECTED = [
    ("東京",None,"21:26",0,"9"),("横浜","21:51","21:52",0,"6"),
    ("熱海","22:55","22:57",0,"2"),("沼津","23:15","23:16",0,None),
    ("富士","23:31","23:32",0,None),("静岡","23:57","23:59",0,"4"),
    ("浜松","00:53","00:54",1,"4"),("姫路","05:25","05:26",1,"8"),
    ("岡山","06:27","06:34",1,"8"),("倉敷","06:46","06:47",1,None),
    ("備中高梁","07:14","07:14",1,None),("新見","07:43","07:44",1,None),
    ("米子","09:05","09:08",1,"2"),("安来","09:16","09:17",1,None),
    ("松江","09:33","09:34",1,None),("宍道","09:47","09:48",1,None),
    ("出雲市","10:00",None,1,None),
]
WEEKDAYS = ("monday","tuesday","wednesday","thursday","friday","saturday","sunday")


def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude:
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            if raw.strip():
                yield json.loads(raw)


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True)+"\n"
                            for row in data), encoding="utf-8")


def validate(candidate):
    trip = candidate["trip"]
    if (candidate["candidate_status"], candidate["canonical"],
            candidate["selected_service_date"], candidate["valid_until"],
            candidate["promotion_scope"]) != (
            "reviewed_official_html", False, DATE, UNTIL,
            "scheduled_service_departing_2026-09-29_only"):
        raise ValueError("Candidate date/status changed")
    if DATE > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Date exceeds cutoff")
    if (candidate["source_id"], candidate["source_url"], candidate["source_sha256"]) != (
            SOURCE, URL, HASH):
        raise ValueError("Source reference changed")
    sources = [r for r in rows("sources/source-registry*.jsonl") if r["source_id"] == SOURCE]
    if len(sources) != 1 or (sources[0]["url_or_locator"], sources[0]["content_hash"],
                             sources[0]["effective_date"]) != (URL,HASH,DATE):
        raise ValueError("Reviewed shared official source missing or changed")
    if (candidate["service"]["service_id"], candidate["service"]["canonical_name"],
            trip["trip_id"], trip["train_number"], trip["public_number"],
            trip["origin"], trip["destination"], trip["coupled_trip_id"],
            trip["coupled_from_sequence"], trip["coupled_to_sequence"]) != (
            "sunrise-izumo","サンライズ出雲",TRIP,"5031M",None,
            "東京","出雲市",SETO,1,9):
        raise ValueError("Train identity or coupling changed")
    if trip["number_segments"] != [
            {"from_sequence":1,"to_sequence":9,"train_number":"5031M"},
            {"from_sequence":9,"to_sequence":17,"train_number":"4031M"}]:
        raise ValueError("Train number transition changed")
    stops = trip["stop_times"]
    actual = [(r["name_snapshot"],r["arrival_time"],r["departure_time"],
               r["day_offset"],r["platform"]) for r in stops]
    if actual != EXPECTED or [r["stop_sequence"] for r in stops] != list(range(1,18)):
        raise ValueError("Printed stop table changed")
    if stops[0]["call_type"] != "origin" or stops[-1]["call_type"] != "destination" or any(
            r["call_type"] != "passenger_stop" for r in stops[1:-1]):
        raise ValueError("Call types changed")
    if not any(r["trip_id"] == SETO for r in rows("normalized/trips/*/*.jsonl")):
        raise ValueError("Reviewed Sunrise Seto counterpart missing")
    if any(r["trip_id"] == TRIP for r in rows("normalized/trips/*/*.jsonl",
                    BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")):
        raise ValueError("Duplicate Sunrise Izumo trip")
    if any(r["service_id"] == "sunrise-izumo" for r in rows("normalized/services*.jsonl",
                    BASE / f"normalized/services-{SUFFIX}.jsonl")):
        raise ValueError("Duplicate Sunrise Izumo service")


def stations():
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    available = {(s[0],s[1]) for line in package["lines"] for s in line["stations"]}
    existing = {r["station_id"]:r for r in rows("normalized/station-identities*.jsonl",
                    BASE / f"normalized/station-identities-{SUFFIX}.jsonl")}
    additions = []
    for name, code in CODES.items():
        if (code,name) not in available:
            raise ValueError(f"Pinned current station missing: {name}")
        station_id = "jp.n02."+code
        prior = existing.get(station_id)
        if prior and prior["name_snapshot"] != name:
            raise ValueError(f"Station identity conflict: {station_id}")
        if prior is None:
            additions.append({"station_id":station_id,"name_snapshot":name,
                              "reference_kind":"current_n02","current_source_code":code,
                              "rail_history_id":None})
    return additions


def main():
    candidate = json.loads((BASE / "candidates/jr-west-sunrise-izumo-20260929.json").read_text())
    validate(candidate)
    additions = stations()
    version, calendar = TRIP+".version", TRIP+".calendar"
    dimensions = {
        "identity":("verified","high","Official page names サンライズ出雲."),
        "train_number":("verified","high","5031M to Okayama; 4031M after Okayama."),
        "operator":("unknown","low","Ordered operator boundaries not established."),
        "validity_calendar":("verified","high","Selected September 29 page only."),
        "origin_destination":("verified","high","Tokyo to Izumoshi endpoints printed."),
        "stops":("verified","high","17 timed passenger calls printed in Izumo columns."),
        "times":("verified","high","Printed clocks and midnight offset retained."),
        "route_lines":("unknown","low","Dated physical line identities not established."),
        "station_refs":("verified","high","Pinned current N02 code-name matches."),
        "provenance":("partial","high","Official page is verification-only."),
    }
    service = candidate["service"]
    outputs = {
        BASE / f"normalized/services-{SUFFIX}.jsonl":[{
            **service,"first_verified_date":DATE,"last_verified_date":DATE}],
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl":[{
            "service_id":"sunrise-izumo","name":"サンライズ出雲","language":"ja",
            "valid_from":DATE,"valid_until":UNTIL,"name_type":"canonical","source_id":SOURCE}],
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl":additions,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl":[{
            "timetable_version_id":version,"operator_scope":"jr-through",
            "effective_from":DATE,"effective_until":UNTIL,
            "edition_name":"JR時刻表2026年10月号; dated Sunrise Izumo 5031M/4031M",
            "revision_type":"source_snapshot","completeness":"partial","source_ids":[SOURCE]}],
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl":[{
            "calendar_id":calendar,"valid_from":DATE,"valid_until":UNTIL,
            "holiday_policy":"none",**{day:0 for day in WEEKDAYS}}],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl":[{
            "calendar_id":calendar,"service_date":DATE,"exception_type":"add",
            "reason":"September 29 selected in official dated page 38492","source_id":SOURCE}],
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl":[{
            "trip_id":TRIP,"timetable_version_id":version,"service_id":"sunrise-izumo",
            "calendar_id":calendar,"train_number":"5031M","public_number":None,
            "origin_station_id":"jp.n02.003766","destination_station_id":"jp.n02.004943",
            "service_class":"limited_express",
            "notes":"September 29 Tokyo departure; branch departure at Okayama on September 30."}],
        BASE / f"normalized/trip-number-segments/{SUFFIX}/seeds.jsonl":[{
            "trip_id":TRIP,**r} for r in candidate["trip"]["number_segments"]],
        BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl":[
            {"trip_id":TRIP,"related_trip_id":SETO,"relation_type":"couples_with",
             "from_sequence":1,"to_sequence":9,"source_id":SOURCE},
            {"trip_id":SETO,"related_trip_id":TRIP,"relation_type":"couples_with",
             "from_sequence":1,"to_sequence":9,"source_id":SOURCE}],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl":[{
            "trip_id":TRIP,"stop_sequence":r["stop_sequence"],
            "station_id":"jp.n02."+CODES[r["name_snapshot"]],
            "arrival_time":r["arrival_time"],"departure_time":r["departure_time"],
            "day_offset":r["day_offset"],"call_type":r["call_type"],
            "pickup_allowed":int(r["call_type"]!="destination"),
            "dropoff_allowed":int(r["call_type"]!="origin"),
            "platform":r["platform"],"time_accuracy":"minute","source_id":SOURCE
        } for r in candidate["trip"]["stop_times"]],
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl":[{
            "entity_type":"trip","entity_id":TRIP,"dimension":dim,
            "status":status,"confidence":confidence,"notes":note
        } for dim,(status,confidence,note) in dimensions.items()],
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl":[{
            "entity_type":"trip","entity_id":TRIP,"field_name":dim,
            "source_id":"jtm-current-station-directory" if dim=="station_refs" else SOURCE,
            "page_or_locator":note,"confidence":confidence,"verification_status":status
        } for dim,(status,confidence,note) in dimensions.items()
          if dim not in {"operator","route_lines"}],
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl":[{
            "research_id":f"{TRIP}.{dim}","entity_type":"trip","entity_id":TRIP,
            "missing_dimension":dim,"status":"license_blocked" if dim=="provenance" else "open",
            "notes":note
        } for dim,note in {
            "operator":"Obtain train-specific ordered operator boundaries.",
            "route_lines":"Obtain dated physical-line identities and boundaries.",
            "provenance":"Resolve timetable fact redistribution permission.",
        }.items()],
    }
    for path,data in outputs.items():
        write(path,data)
    print(f"Staged {TRIP}: 17 calls, 2 number segments, coupled to {SETO}")


if __name__ == "__main__":
    main()
