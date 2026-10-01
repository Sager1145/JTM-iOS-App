#!/usr/bin/env python3
"""Stage the two 2026-09-30 Narita Express 5 reservation equipment facts."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
SUFFIX = "reviewed-east-nex5-formation-20260930"
SOURCE = "jr-east-narita-express5-20260930"
CANDIDATE = BASE / "candidates/jr-east-narita-express5-20260930.json"


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
    if (candidate["service_date"], candidate["source_id"], candidate["canonical"],
        [row["train_number"] for row in candidate["trips"]]) != (
            DAY, SOURCE, False, ["2005M", "2205M"]):
        raise ValueError("Narita Express 5 source/date/branch identity changed")
    sources = {row["source_id"]: row for row in read_rows("sources/source-registry*.jsonl")}
    source = sources[SOURCE]
    if source["effective_date"] != DAY or source["url_or_locator"] != candidate["source_url"]:
        raise ValueError("Narita Express 5 formation source is not exact-date page")
    trips = {row["trip_id"]: row for row in read_rows("normalized/trips/**/*.jsonl")}
    formations, facts, completeness = [], [], []
    for row in candidate["trips"]:
        tid = row["trip_id"]
        trip = trips[tid]
        if (trip["train_number"], trip["service_id"]) != (row["train_number"], "narita-express"):
            raise ValueError(f"Narita Express 5 branch mismatch: {tid}")
        formations.append({
            "formation_id": f"{tid}.formation.{DAY}", "trip_id": tid, "service_date": DAY,
            "evidence_kind": "planned", "all_reserved": True, "green_car_available": True,
            "source_id": SOURCE,
            "notes": "Official train page lists all ordinary seats designated and Green Car reserved; no car count or actual consist published.",
        })
        for field, locator in (("all_reserved", "設備: 普通車全車指定席"),
                               ("green_car_available", "設備: グリーン車指定席")):
            facts.append({"entity_type": "trip", "entity_id": tid,
                          "field_name": f"formation.{field}", "source_id": SOURCE,
                          "page_or_locator": f"2026-09-30 {row['train_number']} {locator}",
                          "confidence": "high", "verification_status": "verified"})
        completeness.append({"entity_type": "trip", "entity_id": tid,
                             "dimension": "formation", "status": "partial", "confidence": "high",
                             "notes": "Ordinary and Green reserved-seat equipment verified; car count, series and actual dispatch unknown."})
    write(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl", formations)
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    write(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", completeness)
    print("Staged 2 Narita Express 5 planned reservation equipment rows")


if __name__ == "__main__":
    main()
