#!/usr/bin/env python3
"""Stage September 30 Thunderbird 5 passenger calls and planned seats."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-thunderbird5-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
TRIP = "jr-west.thunderbird.5.2026-09-30"
SOURCE = "jr-west-odekake-thunderbird5-4005m-20260930"
URL = "https://timetable.jr-odekake.net/train-timetable/257671?date=20260930"
EXPECTED = [
    ("大阪", "007068", None, "07:40", "11", "origin"),
    ("新大阪", "006911", "07:43", "07:44", "4", "passenger_stop"),
    ("高槻", "006432", "07:54", "07:54", None, "passenger_stop"),
    ("京都", "006079", "08:08", "08:09", "0", "passenger_stop"),
    ("敦賀", "010186", "09:03", None, "32", "destination"),
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
    candidate = json.loads((BASE / "candidates/jr-west-thunderbird5-20260930.json").read_text(encoding="utf-8"))
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"],
            candidate["valid_until"], candidate["train_number"], candidate["public_number"],
            candidate["source_id"], candidate["source_url"], candidate["operation_label"] ) != (
            "visually_reviewed_official_train_page", False, DAY, UNTIL, "4005M", "5",
            SOURCE, URL, "土曜・休日運休"):
        raise ValueError("Date-selected train identity drift")
    if DAY > timetable.load_manifest(BASE)["as_of_date"]:
        raise ValueError("Trip exceeds dataset as-of date")
    actual = [(s["name"], s["code"], s["arrival"], s["departure"], s["platform"], s["call_type"])
              for s in candidate["stops"]]
    if actual != EXPECTED or candidate["printed_equipment"] != [
            "女性専用席があります", "グリーン車指定席", "普通車全車指定席"]:
        raise ValueError("Official call/equipment transcription drift")
    source_path = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    source = json.loads(source_path.read_text(encoding="utf-8").strip())
    if any(s["source_id"] == SOURCE for s in rows("sources/source-registry*.jsonl")):
        raise ValueError("Train source id collides with another registry")
    if source is None or (source["url_or_locator"], source["effective_date"],
                          source["redistribution_status"]) != (URL, DAY, "verification_only"):
        raise ValueError("Source provenance drift")
    if any(t["trip_id"] == TRIP for t in rows("normalized/trips/**/*.jsonl")):
        raise ValueError("Thunderbird 5 trip already staged")
    if not any(s["service_id"] == "thunderbird" for s in rows("normalized/services*.jsonl")):
        raise ValueError("Thunderbird service missing")
    station_by_code = {s.get("current_source_code"): s for s in rows("normalized/station-identities*.jsonl")}
    station_by_code.update({s.get("current_source_code"): s
                            for s in rows("normalized/station-identities/**/*.jsonl")})
    for name, code, *_ in EXPECTED:
        if station_by_code[code]["name_snapshot"] != name:
            raise ValueError(f"Station identity changed: {name}")

    version, calendar = TRIP + ".version", TRIP + ".calendar"
    weekdays = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
    write(BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl", [{
        "timetable_version_id": version, "operator_scope": "jr-west", "effective_from": DAY,
        "effective_until": UNTIL, "edition_name": "JR Odekake 2026-09-30 Thunderbird 5",
        "revision_type": "observed_date", "completeness": "partial", "source_ids": [SOURCE]}])
    write(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl", [{
        "calendar_id": calendar, "valid_from": DAY, "valid_until": UNTIL, "holiday_policy": "none",
        **{day: 0 for day in weekdays}}])
    write(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl", [{
        "calendar_id": calendar, "service_date": DAY, "exception_type": "add",
        "reason": "Selected weekday variant on exact official date", "source_id": SOURCE}])
    write(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl", [{
        "trip_id": TRIP, "timetable_version_id": version, "service_id": "thunderbird",
        "calendar_id": calendar, "train_number": "4005M", "public_number": "5",
        "origin_station_id": "jp.n02.007068", "destination_station_id": "jp.n02.010186",
        "service_class": "limited_express",
        "notes": "Date-selected scheduled train; physical-line validity and operation-company segments unresolved."}])
    write(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl", [{
        "trip_id": TRIP, "stop_sequence": n, "station_id": "jp.n02." + code,
        "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
        "platform": platform, "call_type": kind, "pickup_allowed": int(kind != "destination"),
        "dropoff_allowed": int(kind != "origin"), "time_accuracy": "minute", "source_id": SOURCE,
    } for n, (_, code, arrival, departure, platform, kind) in enumerate(EXPECTED, 1)])
    write(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl", [{
        "formation_id": f"{TRIP}.formation.{DAY}", "trip_id": TRIP, "service_date": DAY,
        "evidence_kind": "planned", "all_reserved": True, "green_car_available": True,
        "source_id": SOURCE,
        "notes": "Train page prints 女性専用席があります / グリーン車指定席 / 普通車全車指定席; actual car count, series, car assignment and dispatch unknown."}])
    verified = {"identity": "4005M and サンダーバード5号", "train_number": "4005M",
                "validity_calendar": "September 30 weekday selection", "origin_destination": "大阪 and 敦賀",
                "stops": "five timed passenger calls", "times": "printed minute clocks",
                "station_refs": "five current N02 station identities"}
    fact_rows = [{"entity_type": "trip", "entity_id": TRIP, "field_name": field,
                  "source_id": "jtm-current-station-directory" if field == "station_refs" else SOURCE,
                  "page_or_locator": locator, "confidence": "high", "verification_status": "verified"}
                 for field, locator in verified.items()]
    fact_rows.extend({"entity_type": "trip", "entity_id": TRIP, "field_name": f"formation.{field}",
                      "source_id": SOURCE, "page_or_locator": "2026-09-30 車両設備情報",
                      "confidence": "high", "verification_status": "verified"}
                     for field in ("all_reserved", "green_car_available"))
    fact_rows.append({"entity_type": "trip", "entity_id": TRIP,
                      "field_name": "formation.women_only_seats", "source_id": SOURCE,
                      "page_or_locator": "2026-09-30 車両設備情報: 女性専用席があります",
                      "confidence": "high", "verification_status": "verified"})
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", fact_rows)
    completeness = [{"entity_type": "trip", "entity_id": TRIP, "dimension": field,
                     "status": "verified", "confidence": "high", "notes": locator}
                    for field, locator in verified.items()]
    completeness.extend([
        {"entity_type": "trip", "entity_id": TRIP, "dimension": "formation", "status": "partial",
         "confidence": "high", "notes": "Planned seat categories only; actual consist unknown."},
        {"entity_type": "trip", "entity_id": TRIP, "dimension": "route_lines", "status": "unknown",
         "confidence": "low", "notes": "Daily physical-line validity and reroute status unverified."},
        {"entity_type": "trip", "entity_id": TRIP, "dimension": "operator", "status": "unknown",
         "confidence": "low", "notes": "Individual train-operation company segments unverified."},
    ])
    write(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", completeness)
    write(BASE / f"normalized/research-queue-{SUFFIX}.jsonl", [{
        "research_id": f"{TRIP}.{dimension}", "entity_type": "trip", "entity_id": TRIP,
        "missing_dimension": dimension, "status": "open", "notes": note}
        for dimension, note in (("route_lines", "Confirm September 30 physical route and line validity."),
                                ("operator", "Confirm train-operation company segments."))])
    print("Staged exact-date Thunderbird 5 candidate")


if __name__ == "__main__":
    main()
