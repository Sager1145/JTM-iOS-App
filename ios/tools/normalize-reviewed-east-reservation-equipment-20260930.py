#!/usr/bin/env python3
"""Stage train-specific JR East reservation equipment for September 30 only."""

import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
SUFFIX = "reviewed-east-reservation-equipment-20260930"
CANDIDATE = BASE / "candidates/jr-east-reservation-equipment-20260930.json"

EXPECTED = {
    "jr-east.shiosai.6.exact-2026-09-30": ("4006M", "jr-east-shiosai6-20260930-discovery"),
    "jr-east.kaiji.2.exact-2026-09-30": ("5102M", "jr-east-kaiji2-20260930"),
    "jr-east.kaiji.6.exact-2026-09-30": ("5106M", "jr-east-kaiji6-20260930"),
    "jr-east.kaiji.10.exact-2026-09-30": ("5110M", "jr-east-kaiji10-20260930"),
    "jr-east.kaiji.11.exact-2026-09-30": ("3111M", "jr-east-kaiji11-20260930"),
    "jr-east.wakashio.17.weekday-requested-dates.2026-09-29": ("1067M", "jr-east-wakashio17-20260929-30"),
    "jr-east.odoriko.1.3021m-izukyu-shimoda.2026-09-29": ("3021M", "jr-east-odoriko1-20260929-30"),
    "jr-east.odoriko.1.4021m-shuzenji.2026-09-29": ("4021M", "jr-east-odoriko1-20260929-30"),
    "jr-east.akagi.3.20260930.2026-09-30": ("4003M", "jr-east-akagi3-20260930"),
    "jr-east.akagi.6.20260930.2026-09-30": ("4006M", "jr-east-akagi6-20260930"),
    "jr-east.akagi.9.20260930.2026-09-30": ("4009M", "jr-east-akagi9-20260930"),
}
GREEN_TRIPS = {
    "jr-east.kaiji.2.exact-2026-09-30",
    "jr-east.kaiji.6.exact-2026-09-30",
    "jr-east.kaiji.10.exact-2026-09-30",
    "jr-east.kaiji.11.exact-2026-09-30",
    "jr-east.odoriko.1.3021m-izukyu-shimoda.2026-09-29",
}


def read_rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern)
            if SUFFIX not in path.parts and SUFFIX not in path.name
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
                    encoding="utf-8")


def materialized_on(trip, calendars, versions, exceptions):
    calendar = calendars[trip["calendar_id"]]
    version = versions[trip["timetable_version_id"]]
    if not (calendar["valid_from"] <= DAY < calendar["valid_until"]
            and version["effective_from"] <= DAY < version["effective_until"]):
        return False
    return (trip["calendar_id"], DAY, "add") in exceptions


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"]) != (
            "reviewed_official_html", False, DAY):
        raise ValueError("Reservation equipment candidate/date drift")
    rows = candidate["trips"]
    if len(rows) != len(EXPECTED) or {row["trip_id"] for row in rows} != set(EXPECTED):
        raise ValueError("Expected exactly eleven JR East train columns")
    sources = {row["source_id"]: row for row in read_rows("sources/source-registry*.jsonl")}
    trips = {row["trip_id"]: row for row in read_rows("normalized/trips/**/*.jsonl")}
    calendars = {row["calendar_id"]: row for row in read_rows("normalized/calendars/**/*.jsonl")}
    versions = {row["timetable_version_id"]: row
                for row in read_rows("normalized/timetable-versions*.jsonl")}
    exceptions = {(row["calendar_id"], row["service_date"], row["exception_type"])
                  for row in read_rows("normalized/calendar-exceptions/**/*.jsonl")}
    existing = {row["trip_id"] for row in read_rows("normalized/trip-formations/**/*.jsonl")}
    formations, facts, completeness = [], [], []
    for row in rows:
        tid = row["trip_id"]
        number, source_id = EXPECTED[tid]
        source = sources[source_id]
        url = row["source_url"]
        if (row["train_number"], row["source_id"], row["all_reserved"],
            row["green_car_available"]) != (number, source_id, True, True if tid in GREEN_TRIPS else None):
            raise ValueError(f"Reservation equipment or column identity drift: {tid}")
        if (source["url_or_locator"] != url or urlparse(url).hostname != "timetables.jreast.co.jp"
                or "/2610/train/" not in url):
            raise ValueError(f"Source page drift: {tid}")
        trip = trips[tid]
        if trip["train_number"] != number or not materialized_on(trip, calendars, versions, exceptions):
            raise ValueError(f"No materialized 2026-09-30 trip with this train number: {tid}")
        if tid in existing:
            raise ValueError(f"Formation is already staged elsewhere: {tid}")
        formation = {
            "formation_id": f"{tid}.formation.{DAY}", "trip_id": tid, "service_date": DAY,
            "evidence_kind": "planned", "all_reserved": True,
            "green_car_available": row["green_car_available"], "source_id": source_id,
            "notes": "Exact-date train column prints 普通車全車指定席 and 座席未指定券"
                     + ("; this column also prints グリーン車指定席" if tid in GREEN_TRIPS else "")
                     + ". Vehicle series, car count, car assignments, and actual dispatch are unverified.",
        }
        formations.append(formation)
        for field, label in (("all_reserved", "普通車全車指定席"),
                             ("green_car_available", "グリーン車指定席")):
            if field == "green_car_available" and tid not in GREEN_TRIPS:
                continue
            facts.append({"entity_type": "trip", "entity_id": tid,
                          "field_name": f"formation.{field}", "source_id": source_id,
                          "page_or_locator": f"2026-09-30 {number} 設備: {label}",
                          "confidence": "high", "verification_status": "verified"})
        completeness.append({
            "entity_type": "trip", "entity_id": tid, "dimension": "formation",
            "status": "partial", "confidence": "high",
            "notes": "Train-specific ordinary reserved-seat equipment verified"
                     + (" with Green Car" if tid in GREEN_TRIPS else "")
                     + "; car count, series, and actual dispatch unknown.",
        })
    write(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl", formations)
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    write(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", completeness)
    print(f"Staged {len(formations)} exact-date JR East reservation equipment rows")


if __name__ == "__main__":
    main()
