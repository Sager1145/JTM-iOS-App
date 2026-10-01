#!/usr/bin/env python3
"""Stage the source-pinned September 27 Yakumo 16 timetable."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo16-20260927"
DATE, UNTIL = "2026-09-27", "2026-09-28"
TRIP = "jr-west.yakumo.16.2026-09-27"
SOURCE = "jr-west-odekake-yakumo16-1016m-20260927"
URL = "https://timetable.jr-odekake.net/train-timetable/278911?date=20260927"
STOPS = [
    ("出雲市","004943",None,"11:44",None,"origin"),
    ("宍道","004793","11:54","11:55",None,"passenger_stop"),
    ("玉造温泉","004736","12:03","12:04",None,"passenger_stop"),
    ("松江","004638","12:10","12:11",None,"passenger_stop"),
    ("安来","004748","12:26","12:27",None,"passenger_stop"),
    ("米子","004758","12:34","12:35","1","passenger_stop"),
    ("根雨","005255","12:59","13:03",None,"passenger_stop"),
    ("新見","006070","13:45","13:46",None,"passenger_stop"),
    ("備中高梁","006686","14:13","14:14",None,"passenger_stop"),
    ("倉敷","007598","14:35","14:36",None,"passenger_stop"),
    ("岡山","007310","14:47",None,"3","destination"),
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
    path.write_text("".join(json.dumps(row,ensure_ascii=False,sort_keys=True)+"\n"
                            for row in data), encoding="utf-8")


def validate(candidate, source):
    trip = candidate["trip"]
    if (candidate["candidate_status"],candidate["canonical"],
            candidate["selected_service_date"],candidate["valid_until"],
            candidate["service_id"]) != ("visually_reviewed",False,DATE,UNTIL,"yakumo"):
        raise ValueError("Candidate status/date changed")
    if DATE > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Date exceeds cutoff")
    if (candidate["source_id"],candidate["source_url"],trip["trip_id"],
            trip["public_number"],trip["train_number"],trip["origin"],trip["destination"]) != (
            SOURCE,URL,TRIP,"16","1016M","出雲市","岡山"):
        raise ValueError("Identity/source changed")
    if (source["source_id"],source["url_or_locator"],source["effective_date"],
            source["redistribution_status"],source["automated_extraction_allowed"]) != (
            SOURCE,URL,DATE,"verification_only",False):
        raise ValueError("Source registry changed")
    expected = [(n,a,d,p,k) for n,_,a,d,p,k in STOPS]
    actual = [(r["name_snapshot"],r["arrival_time"],r["departure_time"],
               r["platform"],r["call_type"]) for r in trip["stop_times"]]
    if actual != expected or [r["stop_sequence"] for r in trip["stop_times"]] != list(range(1,12)):
        raise ValueError("Printed passenger timetable changed")
    if len([r for r in rows("normalized/services*.jsonl") if r["service_id"]=="yakumo"]) != 1:
        raise ValueError("Shared Yakumo service identity missing or duplicate")
    if any(r["trip_id"]==TRIP for r in rows("normalized/trips/*/*.jsonl",
                    BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")):
        raise ValueError("Trip ID duplicate")
    if any(r["source_id"]==SOURCE for r in rows("sources/source-registry*.jsonl",
                    BASE / f"sources/source-registry-{SUFFIX}.jsonl")):
        raise ValueError("Source ID duplicate")


def station_additions():
    package=json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    existing={r["station_id"]:r for r in rows("normalized/station-identities*.jsonl",
                    BASE / f"normalized/station-identities-{SUFFIX}.jsonl")}
    additions=[]
    for name,code,*_ in STOPS:
        found={(s[0],s[1]) for line in package["lines"]
               if line["operator"]=="西日本旅客鉄道" for s in line["stations"]
               if s[1]==name}
        if found!={(code,name)}:
            raise ValueError(f"Ambiguous station: {name} {found}")
        station_id="jp.n02."+code
        prior=existing.get(station_id)
        if prior and prior["name_snapshot"]!=name:
            raise ValueError(f"Station identity conflict: {station_id}")
        if prior is None:
            additions.append({"station_id":station_id,"name_snapshot":name,
                              "reference_kind":"current_n02","current_source_code":code,
                              "rail_history_id":None})
    return additions


def main():
    candidate=json.loads((BASE / "candidates/jr-west-yakumo16-20260927.json").read_text())
    source=json.loads((BASE / f"sources/source-registry-{SUFFIX}.jsonl").read_text().strip())
    validate(candidate,source)
    additions=station_additions()
    version,calendar=TRIP+".version",TRIP+".calendar"
    facts={
        "identity":("verified","high","Official selected page prints やくも16号."),
        "train_number":("verified","high","Official selected page prints 1016M."),
        "operator":("unknown","low","Ordered operator segments not established."),
        "validity_calendar":("verified","high","Only September 27 is promoted."),
        "origin_destination":("verified","high","Both terminal calls printed."),
        "stops":("verified","high","Eleven timed passenger calls; レ rows excluded."),
        "times":("verified","high","Only printed minute clocks and sides retained."),
        "route_lines":("unknown","low","Dated physical line identities not established."),
        "station_refs":("verified","high","Pinned current JR West N02 codes match."),
        "provenance":("partial","medium","Official page is verification-only."),
    }
    outputs={
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl":[{
            "service_id":"yakumo","name":"やくも","language":"ja",
            "valid_from":DATE,"valid_until":UNTIL,"name_type":"canonical","source_id":SOURCE}],
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl":additions,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl":[{
            "timetable_version_id":version,"operator_scope":"jr-west",
            "effective_from":DATE,"effective_until":UNTIL,
            "edition_name":"JR Odekake 2026-09-27 Yakumo 16 selected timetable",
            "revision_type":"observed_date","publication_date":None,
            "completeness":"partial","source_ids":[SOURCE]}],
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl":[{
            "calendar_id":calendar,"valid_from":DATE,"valid_until":UNTIL,
            "holiday_policy":"none",**{d:0 for d in WEEKDAYS}}],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl":[{
            "calendar_id":calendar,"service_date":DATE,"exception_type":"add",
            "reason":"September 27 selected in official dated page 278911","source_id":SOURCE}],
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl":[{
            "trip_id":TRIP,"timetable_version_id":version,"service_id":"yakumo",
            "calendar_id":calendar,"train_number":"1016M","public_number":"16",
            "origin_station_id":"jp.n02.004943","destination_station_id":"jp.n02.007310",
            "service_class":"limited_express",
            "notes":"Exact September 27 date only; operator and route lines unknown."}],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl":[{
            "trip_id":TRIP,"stop_sequence":i,"station_id":"jp.n02."+code,
            "arrival_time":a,"departure_time":d,"day_offset":0,"call_type":kind,
            "pickup_allowed":int(kind!="destination"),"dropoff_allowed":int(kind!="origin"),
            "platform":platform,"time_accuracy":"minute","source_id":SOURCE
        } for i,(_,code,a,d,platform,kind) in enumerate(STOPS,1)],
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl":[{
            "entity_type":"trip","entity_id":TRIP,"dimension":dim,
            "status":status,"confidence":confidence,"notes":note
        } for dim,(status,confidence,note) in facts.items()],
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl":[{
            "entity_type":"trip","entity_id":TRIP,"field_name":dim,
            "source_id":"jtm-current-station-directory" if dim=="station_refs" else SOURCE,
            "page_or_locator":note,"confidence":confidence,"verification_status":status
        } for dim,(status,confidence,note) in facts.items()
          if dim not in {"operator","route_lines"}],
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl":[{
            "research_id":f"{TRIP}.{dim}","entity_type":"trip","entity_id":TRIP,
            "missing_dimension":dim,"status":"license_blocked" if dim=="provenance" else "open",
            "notes":note
        } for dim,note in {
            "operator":"Obtain ordered operator segments.",
            "route_lines":"Obtain dated physical line identities.",
            "provenance":"Resolve timetable fact redistribution permission.",
        }.items()],
    }
    for path,data in outputs.items():
        write(path,data)
    print(f"Staged {TRIP}: 11 passenger calls, exact date only")


if __name__=="__main__":
    main()
