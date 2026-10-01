#!/usr/bin/env python3
"""Apply the official standard nine-car Thunderbird plan to reviewed trains."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-thunderbird-planned-nine-car-20260930"
DAY = "2026-09-30"
GUIDE = "jr-west-thunderbird-current-nine-car-guide-20260930"
GUIDE_URL = "https://www.jr-odekake.net/railroad/train/thunderbird/"
NOTES = ("Date-selected train page prints 女性専用席があります / グリーン車指定席 / "
         "普通車全車指定席. Current official standard plan shows nine cars, 546 reserved seats, "
         "and women-only seats in car 3; planned layout only. Actual dispatch, vehicle series, "
         "actual-day capacity and exact seat assignments unverified.")


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in records), encoding="utf-8")


def main():
    candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
    expected = {f"jr-west.thunderbird.{number}.{DAY}" for number in range(1, 51)}
    layout = [dict(car_number=str(number), seat_class="green" if number == 1 else "ordinary",
                   reservation_type="reserved") for number in range(1, 10)]
    if (candidate["candidate_status"], candidate["service_date"],
            candidate["planned_car_count"], candidate["evidence_kind"],
            candidate["women_only_seat_car_number"], candidate["per_car_plan"],
            set(candidate["trip_ids"]), candidate["source"]) != (
            "reviewed_official_standard_service_formation_plan", DAY, 9, "planned", "3",
            layout, expected, {"source_id": GUIDE, "url": GUIDE_URL}):
        raise ValueError("Thunderbird standard plan drift")
    if (candidate["standard_seats_by_car"], candidate["standard_reserved_seat_capacity"]) != (
            [32, 64, 72, 50, 72, 64, 64, 64, 64], 546):
        raise ValueError("Thunderbird standard seat capacity drift")
    guide_rows = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
    if len(guide_rows) != 1 or (guide_rows[0]["source_id"], guide_rows[0]["url_or_locator"],
                                guide_rows[0]["redistribution_status"]) != (
                                GUIDE, GUIDE_URL, "verification_only"):
        raise ValueError("Official formation guide drift")
    sources = {row["source_id"]: row for path in BASE.glob("sources/source-registry*.jsonl")
               for row in rows(path)}
    locations = {}
    for path in BASE.glob("normalized/trip-formations/**/*.jsonl"):
        records = rows(path)
        for index, row in enumerate(records):
            if row["trip_id"] in expected:
                if row["trip_id"] in locations:
                    raise ValueError(f"Duplicate Thunderbird formation: {row['trip_id']}")
                locations[row["trip_id"]] = (path, index, records)
    if set(locations) != expected:
        raise ValueError(f"Missing Thunderbird formations: {sorted(expected - set(locations))}")
    touched = {}
    cars, facts = [], []
    for tid in sorted(expected, key=lambda value: int(value.split(".")[2])):
        path, index, records = locations[tid]
        row = records[index]
        train_source = sources.get(row["source_id"])
        if (row["service_date"], row["evidence_kind"], row["all_reserved"],
                row["green_car_available"]) != (DAY, "planned", True, True):
            raise ValueError(f"Formation evidence drift: {tid}")
        if row.get("car_count") not in (None, 9):
            raise ValueError(f"Conflicting car count: {tid}")
        if (not train_source or train_source["source_type"] != "official_train_timetable"
                or not train_source["url_or_locator"].endswith("?date=20260930")):
            raise ValueError(f"Missing exact-date train source: {tid}")
        if row.get("vehicle_series") or row.get("reserved_seat_capacity") not in (None, 546):
            raise ValueError(f"Unexpected train-specific consist claim: {tid}")
        row["car_count"] = 9
        row["reserved_seat_capacity"] = 546
        row["notes"] = NOTES
        touched[path] = records
        for number in range(1, 10):
            cars.append({"formation_id": row["formation_id"], "car_sequence": number,
                         "car_number": str(number),
                         "seat_class": "green" if number == 1 else "ordinary",
                         "reservation_type": "reserved", "source_id": GUIDE,
                         "notes": (f"Standard published plan: {candidate['standard_seats_by_car'][number - 1]} seats; "
                                   + ("car 3 contains women-only seats; " if number == 3 else "")
                                   + "actual dispatch unverified.")})
        for field, source_id, locator in (
                ("formation.car_count", GUIDE, "Current guide, cars 1–9"),
                ("formation.reserved_seat_capacity", GUIDE,
                 "Current guide, car counts 32+64+72+50+72+64+64+64+64=546"),
                ("formation.standard_per_car_classes", GUIDE, "Current guide, cars 1–9"),
                ("formation.women_only_seat_available", row["source_id"],
                 "2026-09-30 車両設備情報: 女性専用席があります"),
                ("formation.women_only_seat_car", GUIDE, "Current guide, car 3")):
            facts.append({"entity_type": "trip", "entity_id": tid, "field_name": field,
                          "source_id": source_id, "page_or_locator": locator,
                          "confidence": "medium" if source_id == GUIDE else "high",
                          "verification_status": "verified"})

    for path, records in touched.items():
        write(path, records)
    write(BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl", cars)
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    print(f"Annotated {len(expected)} Thunderbird formations, {len(cars)} planned car rows")


if __name__ == "__main__":
    main()
