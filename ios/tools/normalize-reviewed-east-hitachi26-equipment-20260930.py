#!/usr/bin/env python3
"""Stage source-pinned planned seat equipment for Hitachi 26 on 2026-09-30."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
SUFFIX = "east-hitachi26-equipment-20260930"
TRIP = "jr-east.hitachi.26.2026-09-18"
SOURCE = "jr-east-hitachi26-202609"
URL = "https://timetables.jreast.co.jp/2610/train/095/098731.html"
CANDIDATE = BASE / "candidates/jr-east-hitachi26-equipment-20260930.json"


def read_rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern)
            if SUFFIX not in path.parts and SUFFIX not in path.name
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
                    encoding="utf-8")


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    expected = (SUFFIX.replace("east", "jr-east"), "reviewed_official_html", False, DAY,
                TRIP, "26M", SOURCE, URL,
                ["座席未指定券", "グリーン車指定席", "普通車全車指定席"])
    actual = tuple(candidate[key] for key in (
        "candidate_id", "candidate_status", "canonical", "service_date", "trip_id",
        "train_number", "source_id", "source_url", "printed_equipment"))
    if actual != expected or "td.ok" not in candidate["source_locator"]:
        raise ValueError("Hitachi 26 exact-day equipment evidence changed")
    sources = {row["source_id"]: row for row in read_rows("sources/source-registry*.jsonl")}
    if sources[SOURCE]["url_or_locator"] != URL:
        raise ValueError("Hitachi 26 source URL drift")
    trips = {row["trip_id"]: row for row in read_rows("normalized/trips/**/*.jsonl")}
    if (trips[TRIP]["service_id"], trips[TRIP]["train_number"]) != ("hitachi", "26M"):
        raise ValueError("Hitachi 26 trip identity drift")
    if any(row["trip_id"] == TRIP and row["service_date"] == DAY
           for row in read_rows("normalized/trip-formations/**/seeds.jsonl")):
        raise ValueError("Hitachi 26 already has a planned formation for this day")
    write(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl", [{
        "formation_id": f"{TRIP}.formation.{DAY}", "trip_id": TRIP, "service_date": DAY,
        "evidence_kind": "planned", "all_reserved": True, "green_car_available": True,
        "source_id": SOURCE,
        "notes": "Official exact-day page prints reserved ordinary and Green seats; car count, series, car assignments and actual consist unverified.",
    }])
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", [
        {"entity_type": "trip", "entity_id": TRIP, "field_name": f"formation.{field}",
         "source_id": SOURCE, "page_or_locator": f"2026-09-30 26M 設備: {label}",
         "confidence": "high", "verification_status": "verified"}
        for field, label in (("all_reserved", "普通車全車指定席"),
                             ("green_car_available", "グリーン車指定席"))
    ])
    write(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", [{
        "entity_type": "trip", "entity_id": TRIP, "dimension": "formation", "status": "partial",
        "confidence": "high", "notes": "Planned seat classes verified; exact vehicles and actual consist unknown.",
    }])
    print("Staged Hitachi 26 exact-day planned seat equipment")


if __name__ == "__main__":
    main()
