#!/usr/bin/env python3
"""Add the current official nine-car plan to sixty reviewed Haruka formations."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka-planned-nine-car-20260930"
DAY = "2026-09-30"
GUIDE = "jr-west-haruka-current-nine-car-guide-20260930"
POLICY = "jr-west-2024-haruka-all-nine-car-policy"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in records), encoding="utf-8")


def main():
    candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
    expected = {f"jr-west.haruka.{number}.{DAY}" for number in range(1, 61)}
    if (candidate["candidate_status"], candidate["service_date"],
            candidate["planned_car_count"], candidate["evidence_kind"],
            set(candidate["trip_ids"])) != (
            "reviewed_official_service_formation_plan", DAY, 9, "planned", expected):
        raise ValueError("Haruka nine-car plan drift")
    sources = {row["source_id"]: row for row in rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
    if set(sources) != {GUIDE, POLICY}:
        raise ValueError("Expected current guide and published continuation policy")
    for cited in candidate["sources"]:
        if sources[cited["source_id"]]["url_or_locator"] != cited["url"]:
            raise ValueError("Formation source URL drift")
    locations = {}
    for path in BASE.glob("normalized/trip-formations/**/*.jsonl"):
        records = rows(path)
        for index, row in enumerate(records):
            if row["trip_id"] in expected:
                if row["trip_id"] in locations:
                    raise ValueError(f"Duplicate Haruka formation: {row['trip_id']}")
                locations[row["trip_id"]] = (path, index, records)
    if set(locations) != expected:
        raise ValueError(f"Missing Haruka formations: {sorted(expected - set(locations))}")
    touched = {}
    for tid in sorted(expected):
        path, index, records = locations[tid]
        row = records[index]
        if row["service_date"] != DAY or row["evidence_kind"] != "planned":
            raise ValueError(f"Formation date or evidence drift: {tid}")
        if row.get("car_count") not in (None, 9):
            raise ValueError(f"Conflicting car count: {tid}")
        row["car_count"] = 9
        touched[path] = records
    for path, records in touched.items():
        write(path, records)
    facts = [{"entity_type": "trip", "entity_id": tid,
              "field_name": "formation.car_count", "source_id": source_id,
              "page_or_locator": locator, "confidence": "medium",
              "verification_status": "verified"}
             for tid in sorted(expected)
             for source_id, locator in ((GUIDE, "Current guide, cars 1–9"),
                                        (POLICY, "2023-12-15 release, PDF p.16"))]
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    # Formation completeness is already partial for these trips; a verified
    # planned car count does not certify the actual dispatched consist.
    write(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", [])
    print(f"Annotated {len(expected)} planned Haruka formations with nine cars")


if __name__ == "__main__":
    main()
