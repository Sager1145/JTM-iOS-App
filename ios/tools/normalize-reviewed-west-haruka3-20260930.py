#!/usr/bin/env python3
"""Stage September 30 Haruka 3 stops, platforms and planned seats."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka3-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
TRIP = "jr-west.haruka.3.2026-09-30"
SOURCE = "jr-west-odekake-haruka3-1003m-20260930"
URL = "https://timetable.jr-odekake.net/train-timetable/181?date=20260930"
EXPECTED = [
    ("草津", "005901", None, "05:58", None, "origin"),
    ("南草津", "005991", "06:01", "06:01", None, "passenger_stop"),
    ("石山", "006098", "06:05", "06:06", None, "passenger_stop"),
    ("大津", "006000", "06:09", "06:10", None, "passenger_stop"),
    ("山科", "006043", "06:14", "06:15", None, "passenger_stop"),
    ("京都", "006079", "06:19", "06:21", "7", "passenger_stop"),
    ("高槻", "006432", "06:33", "06:34", None, "passenger_stop"),
    ("新大阪", "006911", "06:46", "06:47", "3", "passenger_stop"),
    ("大阪", "007068", "06:51", "06:53", "21", "passenger_stop"),
    ("天王寺", "007439", "07:05", "07:07", "15", "passenger_stop"),
    ("関西空港", "007958", "07:41", None, None, "destination"),
]


def rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern)
            if SUFFIX not in str(path)
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in records), encoding="utf-8")


def main():
    candidate = json.loads((BASE / "candidates/jr-west-haruka3-20260930.json").read_text(encoding="utf-8"))
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"],
            candidate["train_number"], candidate["source_id"], candidate["source_url"],
            candidate["operation_label"], candidate["printed_equipment"]) != (
            "visually_reviewed_official_train_page", False, DAY, "1003M", SOURCE, URL,
            "土曜・休日運休", ["グリーン車指定席", "普通車一部指定席"]):
        raise ValueError("Date-selected Haruka 3 identity drift")
    if DAY > timetable.load_manifest(BASE)["as_of_date"]:
        raise ValueError("Trip exceeds dataset as-of date")
    actual = [(s["name"], s["code"], s["arrival"], s["departure"], s["platform"], s["call_type"])
              for s in candidate["stops"]]
    if actual != EXPECTED:
        raise ValueError("Printed stops/equipment transcription drift")
    source = json.loads((BASE / f"sources/source-registry-{SUFFIX}.jsonl").read_text(encoding="utf-8"))
    if (source["source_id"], source["url_or_locator"], source["effective_date"],
            source["redistribution_status"]) != (SOURCE, URL, DAY, "verification_only"):
        raise ValueError("Source provenance drift")
    if any(s["source_id"] == SOURCE for s in rows("sources/source-registry*.jsonl")):
        raise ValueError("Source id collision")
    if any(t["trip_id"] == TRIP for t in rows("normalized/trips/**/*.jsonl")):
        raise ValueError("Trip id collision")
    if not any(s["service_id"] == "haruka" for s in rows("normalized/services*.jsonl")):
        raise ValueError("Haruka service identity missing")
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    station_codes = {(station[0], station[1]) for line in package["lines"]
                     for station in line.get("stations", [])}
    existing = {s.get("current_source_code"): s for s in rows("normalized/station-identities*.jsonl")}
    existing.update({s.get("current_source_code"): s
                     for s in rows("normalized/station-identities/**/*.jsonl")})
    additions = []
    for name, code, *_ in EXPECTED:
        if (code, name) not in station_codes:
            raise ValueError(f"Current N02 station missing: {name}")
        prior = existing.get(code)
        if prior and prior["name_snapshot"] != name:
            raise ValueError(f"Station identity mismatch: {name}")
        if prior is None:
            additions.append({"station_id": "jp.n02." + code, "name_snapshot": name,
                              "reference_kind": "current_n02", "current_source_code": code})
    write(BASE / f"normalized/station-identities-{SUFFIX}.jsonl", additions)

    version, calendar = TRIP + ".version", TRIP + ".calendar"
    weekdays = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
    write(BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl", [{
        "timetable_version_id": version, "operator_scope": "jr-west", "effective_from": DAY,
        "effective_until": UNTIL, "edition_name": "JR Odekake 2026-09-30 Haruka 3",
        "revision_type": "observed_date", "completeness": "partial", "source_ids": [SOURCE]}])
    write(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl", [{
        "calendar_id": calendar, "valid_from": DAY, "valid_until": UNTIL, "holiday_policy": "none",
        **{day: 0 for day in weekdays}}])
    write(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl", [{
        "calendar_id": calendar, "service_date": DAY, "exception_type": "add",
        "reason": "Selected weekday variant on exact official date", "source_id": SOURCE}])
    write(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl", [{
        "trip_id": TRIP, "timetable_version_id": version, "service_id": "haruka",
        "calendar_id": calendar, "train_number": "1003M", "public_number": "3",
        "origin_station_id": "jp.n02.005901", "destination_station_id": "jp.n02.007958",
        "service_class": "limited_express", "notes": "Exact selected date; physical route unresolved."}])
    write(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl", [{
        "trip_id": TRIP, "stop_sequence": n, "station_id": "jp.n02." + code,
        "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
        "platform": platform, "call_type": kind, "pickup_allowed": int(kind != "destination"),
        "dropoff_allowed": int(kind != "origin"), "time_accuracy": "minute", "source_id": SOURCE,
    } for n, (_, code, arrival, departure, platform, kind) in enumerate(EXPECTED, 1)])
    write(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl", [{
        "formation_id": f"{TRIP}.formation.{DAY}", "trip_id": TRIP, "service_date": DAY,
        "evidence_kind": "planned", "all_reserved": False, "green_car_available": True,
        "source_id": SOURCE,
        "notes": "Page prints Green Car reserved and ordinary cars partly reserved; exact consist unverified."}])
    verified = {"identity": "1003M and はるか3号", "train_number": "1003M",
                "validity_calendar": "September 30 weekday selection", "origin_destination": "草津 and 関西空港",
                "stops": "eleven timed passenger calls", "times": "printed minute clocks",
                "station_refs": "eleven current N02 station identities"}
    fact_rows = [{"entity_type": "trip", "entity_id": TRIP, "field_name": field,
                  "source_id": "jtm-current-station-directory" if field == "station_refs" else SOURCE,
                  "page_or_locator": locator, "confidence": "high", "verification_status": "verified"}
                 for field, locator in verified.items()]
    fact_rows.extend({"entity_type": "trip", "entity_id": TRIP, "field_name": f"formation.{field}",
                      "source_id": SOURCE, "page_or_locator": "2026-09-30 車両設備情報",
                      "confidence": "high", "verification_status": "verified"}
                     for field in ("all_reserved", "green_car_available"))
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", fact_rows)
    write(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", [
        *({"entity_type": "trip", "entity_id": TRIP, "dimension": field,
           "status": "verified", "confidence": "high", "notes": locator}
          for field, locator in verified.items()),
        {"entity_type": "trip", "entity_id": TRIP, "dimension": "formation", "status": "partial",
         "confidence": "high", "notes": "Planned seat categories; car count/series unknown."},
        {"entity_type": "trip", "entity_id": TRIP, "dimension": "route_lines", "status": "unknown",
         "confidence": "low", "notes": "Osaka underground alignment and daily physical route not verified."},
        {"entity_type": "trip", "entity_id": TRIP, "dimension": "operator", "status": "unknown",
         "confidence": "low", "notes": "Individual train-operation company segments unverified."},
    ])
    write(BASE / f"normalized/research-queue-{SUFFIX}.jsonl", [{
        "research_id": f"{TRIP}.{dimension}", "entity_type": "trip", "entity_id": TRIP,
        "missing_dimension": dimension, "status": "open", "notes": note}
        for dimension, note in (("route_lines", "Confirm daily route, including Osaka underground alignment."),
                                ("operator", "Confirm train-operation company segments."))])
    print("Staged exact-date Haruka 3 candidate")


if __name__ == "__main__":
    main()
