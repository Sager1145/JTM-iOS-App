#!/usr/bin/env python3
"""Stage JR West Kuroshio 1 for the reviewed September 30 service day."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio1-20260930"
DATE, UNTIL = "2026-09-30", "2026-10-01"
TRIP = "jr-west.kuroshio.1.2026-09-30"
SOURCE = "jr-west-odekake-kuroshio1-51m-20260930"
URL = "https://timetable.jr-odekake.net/train-timetable/38921?date=20260930"
STATIONS = [
    ("新大阪","006911",None,"07:34","2","origin"),
    ("大阪","007068","07:38","07:39","21","passenger_stop"),
    ("天王寺","007439","07:56","07:59","15","passenger_stop"),
    ("日根野","008072","08:25","08:25",None,"passenger_stop"),
    ("和歌山","008365","08:45","08:48","4","passenger_stop"),
    ("海南","008442","08:57","08:57",None,"passenger_stop"),
    ("御坊","008657","09:29","09:30",None,"passenger_stop"),
    ("紀伊田辺","008867","09:58","10:00",None,"passenger_stop"),
    ("白浜","008915","10:10","10:12",None,"passenger_stop"),
    ("周参見","009191","10:33","10:33",None,"passenger_stop"),
    ("串本","009265","11:06","11:07",None,"passenger_stop"),
    ("古座","009224","11:15","11:15",None,"passenger_stop"),
    ("太地","009025","11:33","11:33",None,"passenger_stop"),
    ("紀伊勝浦","008974","11:40","11:40",None,"passenger_stop"),
    ("新宮","008874","11:59",None,None,"destination"),
]
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude:
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line)


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in data), encoding="utf-8")


def validate(candidate, source):
    if (candidate["candidate_status"], candidate["canonical"],
            candidate["selected_service_date"], candidate["valid_until"]) != (
            "reviewed_official_html", False, DATE, UNTIL):
        raise ValueError("Candidate date/status changed")
    if DATE > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Date exceeds cutoff")
    service, trip = candidate["service"], candidate["trip"]
    if (service["service_id"], service["canonical_name"], trip["trip_id"],
            trip["public_number"], trip["train_number"], candidate["source_id"],
            candidate["source_calendar_label"]) != (
            "kuroshio", "くろしお", TRIP, "1", "51M", SOURCE, "土曜・休日運休"):
        raise ValueError("Identity or source label changed")
    expected = [(n, arr, dep, platform, kind) for n, _, arr, dep, platform, kind in STATIONS]
    actual = [(r["name_snapshot"], r["arrival_time"], r["departure_time"],
               r["platform"], r["call_type"]) for r in trip["stop_times"]]
    if actual != expected or [r["stop_sequence"] for r in trip["stop_times"]] != list(range(1, 16)):
        raise ValueError("Printed passenger calls changed")
    if (source["source_id"], source["url_or_locator"], source["effective_date"],
            source["automated_extraction_allowed"], source["redistribution_status"]) != (
            SOURCE, URL, DATE, False, "verification_only"):
        raise ValueError("Source contract changed")
    if any(r["service_id"] == "kuroshio" for r in rows("normalized/services*.jsonl",
                   BASE / f"normalized/services-{SUFFIX}.jsonl")):
        raise ValueError("Service already defined elsewhere")
    if any(r["trip_id"] == TRIP for r in rows("normalized/trips/*/*.jsonl",
                   BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")):
        raise ValueError("Trip already defined elsewhere")


def station_rows():
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    output = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing = {r["station_id"]: r for r in rows("normalized/station-identities*.jsonl", output)}
    additions = []
    for name, code, *_ in STATIONS:
        found = {(s[0], s[1]) for line in package["lines"]
                 if line["operator"] == "西日本旅客鉄道"
                 for s in line["stations"] if s[1] == name}
        if found != {(code, name)}:
            raise ValueError(f"Station code mismatch: {name} {found}")
        station_id = "jp.n02." + code
        if station_id in existing and existing[station_id]["name_snapshot"] != name:
            raise ValueError(f"Station identity conflict: {station_id}")
        if station_id not in existing:
            additions.append({"station_id": station_id, "name_snapshot": name,
                              "reference_kind": "current_n02", "current_source_code": code,
                              "rail_history_id": None})
    return additions


def main():
    candidate = json.loads((BASE / "candidates/jr-west-kuroshio1-20260930.json").read_text())
    source_path = BASE / "sources/source-registry-west-kuroshio1-20260930.jsonl"
    source = json.loads(source_path.read_text().strip())
    validate(candidate, source)
    additions = station_rows()
    version, calendar = TRIP + ".version", TRIP + ".calendar"
    dimensions = {
        "identity": ("verified", "high", "The dated page prints Kuroshio 1."),
        "train_number": ("verified", "high", "The dated page prints 51M."),
        "operator": ("unknown", "low", "No ordered operator-segment evidence."),
        "validity_calendar": ("verified", "high", "Only September 30 is promoted."),
        "origin_destination": ("verified", "high", "Both termini printed."),
        "stops": ("verified", "high", "Fifteen passenger calls; pass rows excluded."),
        "times": ("verified", "high", "Printed minute clocks and side blanks retained."),
        "route_lines": ("unknown", "low", "No dated physical-line mapping."),
        "station_refs": ("verified", "high", "Exact West operator N02 name-code matches."),
        "provenance": ("partial", "medium", "Source page is verification-only."),
    }
    service = candidate["service"]
    outputs = {
        BASE / f"normalized/services-{SUFFIX}.jsonl": [{
            **service, "first_verified_date": DATE, "last_verified_date": DATE}],
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": [{
            "service_id": "kuroshio", "name": "くろしお", "language": "ja",
            "valid_from": DATE, "valid_until": UNTIL, "name_type": "canonical", "source_id": SOURCE}],
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": additions,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": [{
            "timetable_version_id": version, "operator_scope": "jr-west",
            "effective_from": DATE, "effective_until": UNTIL,
            "edition_name": "JR Odekake 2026-09-30 Kuroshio 1 selected timetable",
            "revision_type": "observed_date", "publication_date": None,
            "completeness": "partial", "source_ids": [SOURCE]}],
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar, "valid_from": DATE, "valid_until": UNTIL,
            "holiday_policy": "none", **{day: 0 for day in WEEKDAYS}}],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar, "service_date": DATE, "exception_type": "add",
            "reason": "Exact-date page and selected September 30 calendar cell", "source_id": SOURCE}],
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP, "timetable_version_id": version, "service_id": "kuroshio",
            "calendar_id": calendar, "train_number": "51M", "public_number": "1",
            "origin_station_id": "jp.n02.006911", "destination_station_id": "jp.n02.008874",
            "service_class": "limited_express",
            "notes": "Exact date only; source weekday label does not expand calendar."}],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP, "stop_sequence": index, "station_id": "jp.n02." + code,
            "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
            "call_type": kind, "pickup_allowed": int(kind != "destination"),
            "dropoff_allowed": int(kind != "origin"), "platform": platform,
            "time_accuracy": "minute", "source_id": SOURCE
        } for index, (_, code, arrival, departure, platform, kind) in enumerate(STATIONS, 1)],
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": [{
            "entity_type": "trip", "entity_id": TRIP, "dimension": dim,
            "status": status, "confidence": confidence, "notes": note
        } for dim, (status, confidence, note) in dimensions.items()],
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": [{
            "entity_type": "trip", "entity_id": TRIP, "field_name": dim,
            "source_id": "jtm-current-station-directory" if dim == "station_refs" else SOURCE,
            "page_or_locator": note, "confidence": confidence, "verification_status": status
        } for dim, (status, confidence, note) in dimensions.items()
          if dim not in {"operator", "route_lines"}],
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": [{
            "research_id": f"{TRIP}.{dim}", "entity_type": "trip", "entity_id": TRIP,
            "missing_dimension": dim, "status": "license_blocked" if dim == "provenance" else "open",
            "notes": note
        } for dim, note in {
            "operator": "Obtain ordered operator segments.",
            "route_lines": "Obtain dated physical-line identities.",
            "provenance": "Resolve timetable fact redistribution permission.",
        }.items()],
    }
    for path, data in outputs.items():
        write(path, data)
    print(f"Staged {TRIP}: 15 timed passenger calls, exact date only")


if __name__ == "__main__":
    main()
