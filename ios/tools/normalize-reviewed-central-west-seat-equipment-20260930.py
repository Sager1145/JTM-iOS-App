#!/usr/bin/env python3
"""Stage planned seat equipment from date-selected Central/West train pages."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
SUFFIX = "reviewed-central-west-seat-equipment-20260930"
CANDIDATE = BASE / "candidates/jr-central-west-seat-equipment-20260930.json"
EXPECTED = {
    "jr-central.shinano.1.2026-09-18": "1001M",
    "jr-central.shinano.3.2026-09-30": "1003M",
    "jr-central.shinano.10.2026-09-30": "1010M",
    "jr-central.nanki.1.2026-09-30": "3001D",
    "jr-west.haruka.1.2026-09-30": "1001M",
    "jr-west.kuroshio.1.2026-09-30": "51M",
    "jr-west.thunderbird.1.2026-09-30": "4001M",
    "jr-west.thunderbird.3.2026-09-30": "4003M",
    "jr-west.yakumo.15.2026-09-30": "1015M",
    "jr-west.west-express-ginga.kumano-day.2026-07-05": "8078M",
    "jr-central.hida.1.2026-09-30": "21D",
    "jr-west.kinosaki.1.2026-09-30": "5001M",
    "jr-west.kinosaki.2.2026-09-30": "5002M",
    "jr-west.thunderbird.2.2026-09-30": "4002M",
    "jr-west.thunderbird.4.2026-09-30": "4004M",
}


def read_rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern)
            if SUFFIX not in str(path)
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in rows), encoding="utf-8")


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"]) != (
            "reviewed_official_train_pages", False, DAY):
        raise ValueError("Candidate date/status drift")
    rows = candidate["trips"]
    if len(rows) != len(EXPECTED) or {row["trip_id"] for row in rows} != set(EXPECTED):
        raise ValueError("Expected precisely fifteen individually reviewed trips")

    manifest = timetable.load_manifest(BASE)
    dataset, _ = timetable.load_dataset(BASE, manifest)
    daily = {trip["trip_id"] for trip in timetable.materialize(dataset, DAY)}
    trips = {row["trip_id"]: row for row in read_rows("normalized/trips/**/*.jsonl")}
    sources = {row["source_id"]: row for row in read_rows("sources/source-registry*.jsonl")}
    existing = {row["trip_id"] for row in read_rows("normalized/trip-formations/**/*.jsonl")}

    formations, facts, completeness = [], [], []
    for row in rows:
        tid, source_id = row["trip_id"], row["source_id"]
        labels = row["printed_equipment"]
        if tid not in daily or tid in existing or trips[tid]["train_number"] != EXPECTED[tid]:
            raise ValueError(f"Trip missing, already formed, or train number changed: {tid}")
        if row["train_number"] != EXPECTED[tid] or sources[source_id]["url_or_locator"] != row["source_url"]:
            raise ValueError(f"Candidate/source identity changed: {tid}")
        if not (row["source_url"].startswith("https://timetables.jreast.co.jp/2610/train/")
                or row["source_url"].startswith("https://timetable.jr-odekake.net/train-timetable/")
                and "date=20260930" in row["source_url"]):
            raise ValueError(f"Unexpected official page or service date: {tid}")
        all_reserved = "普通車全車指定席" in labels
        partly_reserved = "普通車一部指定席" in labels
        has_green = "グリーン車指定席" in labels
        if (all_reserved == partly_reserved or row["all_reserved"] != all_reserved
                or row["green_car_available"] != (True if has_green else None)):
            raise ValueError(f"Printed equipment drift: {tid}")
        formation = {
            "formation_id": f"{tid}.formation.{DAY}", "trip_id": tid, "service_date": DAY,
            "evidence_kind": "planned", "all_reserved": all_reserved,
            "source_id": source_id,
            "notes": "Date-selected train page prints " + " / ".join(labels)
                     + "; actual dispatch, car count, series, and per-car assignments unverified.",
        }
        if has_green:
            formation["green_car_available"] = True
        formations.append(formation)
        for field, locator in (("all_reserved", "普通車全車指定席" if all_reserved else "普通車一部指定席"),
                               ("green_car_available", "グリーン車指定席")):
            if field == "green_car_available" and not has_green:
                continue
            facts.append({"entity_type": "trip", "entity_id": tid,
                          "field_name": f"formation.{field}", "source_id": source_id,
                          "page_or_locator": f"2026-09-30 {row['train_number']} 車両設備情報: {locator}",
                          "confidence": "high", "verification_status": "verified"})
        completeness.append({"entity_type": "trip", "entity_id": tid,
                             "dimension": "formation", "status": "partial", "confidence": "high",
                             "notes": "Seat categories are planned train-page facts; actual consist, car count and vehicle series unknown."})

    write(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl", formations)
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    write(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", completeness)
    print(f"Staged {len(formations)} planned seat-equipment records")


if __name__ == "__main__":
    main()
