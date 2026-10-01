#!/usr/bin/env python3
"""Stage the source-pinned 2026-09-30 Shinano 10 schedule."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-central-shinano10-20260930"
DATE = "2026-09-30"
UNTIL = "2026-10-01"
SOURCE = "jr-east-shinano10-20260930"
URL = "https://timetables.jreast.co.jp/2610/train/000/000241.html"
TRIP = "jr-central.shinano.10.2026-09-30"
STATION_SOURCE = "jtm-current-station-directory"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED = [
    ("長野", "002031", None, "11:00", "６", "origin"),
    ("篠ノ井", "002096", "11:08", "11:08", None, "passenger_stop"),
    ("松本", "002506", "11:51", "11:53", "１", "passenger_stop"),
    ("塩尻", "002616", "12:01", "12:03", None, "passenger_stop"),
    ("木曽福島", "003015", "12:30", "12:30", None, "passenger_stop"),
    ("上松", "003139", "12:35", "12:36", None, "passenger_stop"),
    ("中津川", "004521", "13:05", "13:06", None, "passenger_stop"),
    ("多治見", "005009", "13:34", "13:34", None, "passenger_stop"),
    ("千種", "005450", "13:52", "13:53", None, "passenger_stop"),
    ("名古屋", "005451", "14:01", None, "１１", "destination"),
]


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


def validate(candidate):
    trip = candidate["trip"]
    source = trip["source"]
    if (candidate["candidate_status"], candidate["database_as_of_date"],
            candidate["canonical"]) != ("reviewed_official_html", DATE, False):
        raise ValueError("Candidate status or cutoff changed")
    if DATE > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Date exceeds database cutoff")
    if tuple(trip[key] for key in ("trip_id", "service_id", "service_name", "public_number",
                                     "train_number", "service_date")) != (
            TRIP, "shinano", "しなの", "10", "1010M", DATE):
        raise ValueError("Trip identity changed")
    if (source["source_id"], source["url_or_locator"], source["effective_date"],
            source["automated_extraction_allowed"]) != (SOURCE, URL, DATE, False):
        raise ValueError("Source contract changed")
    actual = [(r["name_snapshot"], r["arrival_time"], r["departure_time"],
               r["platform"], r["call_type"]) for r in trip["stop_times"]]
    expected = [(name, arr, dep, platform, kind) for name, _, arr, dep, platform, kind in EXPECTED]
    if actual != expected or [r["stop_sequence"] for r in trip["stop_times"]] != list(range(1, 11)):
        raise ValueError("Printed passenger timetable changed")
    if not any(r["service_id"] == "shinano" and r["canonical_name"] == "しなの"
               for r in rows("normalized/services*.jsonl")):
        raise ValueError("Shared Shinano service missing")
    own_trip_path = BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl"
    if any(r["trip_id"] == TRIP for r in rows("normalized/trips/*/*.jsonl", own_trip_path)):
        raise ValueError("Trip ID already normalized elsewhere")
    if any(r["source_id"] == SOURCE for r in rows("sources/source-registry*.jsonl",
                                                BASE / f"sources/source-registry-{SUFFIX}.jsonl")):
        raise ValueError("Source ID collision")


def stations():
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    wanted = {name: code for name, code, *_ in EXPECTED}
    for name, code in wanted.items():
        matches = {(s[0], s[1]) for line in package["lines"]
                   if line["operator"] in {"東海旅客鉄道", "東日本旅客鉄道"}
                   for s in line["stations"] if s[1] == name}
        if matches != {(code, name)}:
            raise ValueError(f"Ambiguous station {name}: {matches}")
    output = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing = {r["station_id"]: r for r in rows("normalized/station-identities*.jsonl", output)}
    additions = []
    for name, code in wanted.items():
        station_id = "jp.n02." + code
        old = existing.get(station_id)
        if old and old["name_snapshot"] != name:
            raise ValueError(f"Station identity conflict: {station_id}")
        if old is None:
            additions.append({"station_id": station_id, "name_snapshot": name,
                              "reference_kind": "current_n02", "current_source_code": code,
                              "rail_history_id": None})
    return wanted, additions


def main():
    candidate = json.loads((BASE / "candidates/jr-central-shinano10-20260930.json").read_text())
    validate(candidate)
    codes, new_stations = stations()
    source = candidate["trip"]["source"]
    version, calendar = TRIP + ".version", TRIP + ".calendar"
    dimensions = {
        "identity": ("verified", "high", "Official selected page prints しなの10号."),
        "train_number": ("verified", "high", "Official selected page prints 1010M."),
        "operator": ("unknown", "low", "Ordered operator boundaries not established."),
        "validity_calendar": ("verified", "high", "September 30 selects variant 000241."),
        "origin_destination": ("verified", "high", "Both terminal calls are printed."),
        "stops": ("verified", "high", "Ten passenger calls are printed."),
        "times": ("verified", "high", "Only printed arrival and departure sides are retained."),
        "route_lines": ("unknown", "low", "Dated ordered physical lines not established."),
        "station_refs": ("verified", "high", "Pinned names and codes match current N02 groups."),
        "provenance": ("partial", "medium", "Official page is verification-only."),
    }
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": [source],
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": new_stations,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": [{
            "timetable_version_id": version, "operator_scope": "jr-central",
            "effective_from": DATE, "effective_until": UNTIL,
            "edition_name": "JR時刻表2026年10月号; exact-date しなの10号",
            "revision_type": "source_snapshot", "completeness": "partial", "source_ids": [SOURCE]}],
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar, "valid_from": DATE, "valid_until": UNTIL,
            "holiday_policy": "none", **{day: 0 for day in WEEKDAYS}}],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar, "service_date": DATE, "exception_type": "add",
            "reason": "September 30 selects official variant 000241", "source_id": SOURCE}],
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP, "timetable_version_id": version, "service_id": "shinano",
            "calendar_id": calendar, "train_number": "1010M", "public_number": "10",
            "origin_station_id": "jp.n02.002031", "destination_station_id": "jp.n02.005451",
            "service_class": "limited_express",
            "notes": "Only September 30 selected. Operator segments and physical lines unknown."}],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP, "stop_sequence": r["stop_sequence"],
            "station_id": "jp.n02." + codes[r["name_snapshot"]],
            "arrival_time": r["arrival_time"], "departure_time": r["departure_time"],
            "day_offset": 0, "call_type": r["call_type"],
            "pickup_allowed": int(r["call_type"] != "destination"),
            "dropoff_allowed": int(r["call_type"] != "origin"),
            "platform": r["platform"], "time_accuracy": "minute", "source_id": SOURCE
        } for r in candidate["trip"]["stop_times"]],
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": [{
            "entity_type": "trip", "entity_id": TRIP, "dimension": dim,
            "status": status, "confidence": confidence, "notes": note
        } for dim, (status, confidence, note) in dimensions.items()],
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": [{
            "entity_type": "trip", "entity_id": TRIP, "field_name": dim,
            "source_id": STATION_SOURCE if dim == "station_refs" else SOURCE,
            "page_or_locator": note, "confidence": confidence, "verification_status": status
        } for dim, (status, confidence, note) in dimensions.items()
          if dim not in {"operator", "route_lines"}],
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": [{
            "research_id": f"{TRIP}.{dim}", "entity_type": "trip", "entity_id": TRIP,
            "missing_dimension": dim, "status": "license_blocked" if dim == "provenance" else "open",
            "notes": note
        } for dim, note in {
            "operator": "Obtain ordered JR Central / JR East operator boundary evidence.",
            "route_lines": "Obtain dated physical line identities and transitions.",
            "provenance": "Resolve permission to redistribute transcribed facts.",
        }.items()],
    }
    for path, data in outputs.items():
        write(path, data)
    print(f"Staged {TRIP}: 10 passenger calls, exact date only")


if __name__ == "__main__":
    main()
