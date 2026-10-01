#!/usr/bin/env python3
"""Keep exact-date planned seat categories and supported Sonic formations."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
SUFFIX = "reviewed-kyushu-shikoku-seat-equipment-20260930"
SONIC_GUIDE = "jr-kyushu-sonic-configuration-guide-20260930"
EQUIPMENT_GUIDE = "jr-kyushu-sonic-equipment-guide-20260930"
DIAGRAM_SOURCES = {"883": "jr-kyushu-sonic-883-diagram-20260930",
                   "885": "jr-kyushu-sonic-885-diagram-20260930"}
SONIC_SERIES = {"2": ("883", 7), "4": ("883", 7), "6": ("885", 6),
                "8": ("883", 7), "10": ("885", 6), "12": ("885", 6)}
FILES = (
    ("jr-kyushu-yufu6-20260930.json", "jr-kyushu.yufu.6.2026-09-30", "86D", ["普通車一部指定席"], None, "jr-kyushu-yufu6-20260930"),
    ("jr-kyushu-sonic2-20260930.json", "jr-kyushu.sonic.2.2026-09-30", "3002M", ["グリーン車指定席", "普通車一部指定席"], True, "jr-kyushu-sonic2-20260930"),
    ("jr-kyushu-sonic4-20260930.json", "jr-kyushu.sonic.4.2026-09-30", "3004M", ["グリーン車指定席", "普通車一部指定席"], True, "jr-kyushu-sonic4-20260930"),
    ("jr-kyushu-sonic6-20260930.json", "jr-kyushu.sonic.6.2026-09-30", "3006M", ["グリーン車指定席", "普通車一部指定席"], True, "jr-kyushu-sonic6-20260930"),
    ("jr-kyushu-sonic8-20260930.json", "jr-kyushu.sonic.8.2026-09-30", "3008M", ["グリーン車指定席", "普通車一部指定席"], True, "jr-kyushu-sonic8-20260930"),
    ("jr-kyushu-sonic10-20260930.json", "jr-kyushu.sonic.10.2026-09-30", "3010M", ["グリーン車指定席", "普通車一部指定席"], True, "jr-kyushu-sonic10-20260930"),
    ("jr-kyushu-sonic12-20260930.json", "jr-kyushu.sonic.12.2026-09-30", "3012M", ["グリーン車指定席", "普通車一部指定席"], True, "jr-kyushu-sonic12-20260930"),
    ("jr-shikoku-shiokaze1-20260930.json", "jr-shikoku.shiokaze.1.2026-09-30", "1M", ["普通車一部指定席"], None, "jr-odekake-shiokaze1-20260930-train"),
    ("jr-shikoku-uwakai3-20260930.json", "jr-shikoku.uwakai.3.2026-09-30", "1053D", ["普通車一部指定席"], None, "jr-odekake-uwakai3-20260930-train"),
    ("jr-shikoku-uwakai5-20260930.json", "jr-shikoku.uwakai.5.2026-09-30", "1055D", ["普通車一部指定席"], None, "jr-odekake-uwakai5-20260930-train"),
    ("jr-shikoku-uwakai7-20260930.json", "jr-shikoku.uwakai.7.2026-09-30", "1057D", ["普通車一部指定席"], None, "jr-odekake-uwakai7-20260930-train"),
    ("jr-shikoku-uwakai9-20260930.json", "jr-shikoku.uwakai.9.2026-09-30", "1059D", ["普通車一部指定席"], None, "jr-odekake-uwakai9-20260930-train"),
    ("jr-shikoku-uwakai11-20260930.json", "jr-shikoku.uwakai.11.2026-09-30", "1061D", ["普通車一部指定席"], None, "jr-odekake-uwakai11-20260930-train"),
)


def read_rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern) if SUFFIX not in str(path)
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def main():
    dataset, origins = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
    errors = timetable.validate_dataset(dataset, origins, timetable.load_manifest(BASE))
    if errors:
        raise ValueError(errors)
    daily = {row["trip_id"]: row for row in timetable.materialize(dataset, DAY)}
    sources = {row["source_id"]: row for row in dataset["source_documents"]}
    if (sources[SONIC_GUIDE]["url_or_locator"] != "https://www.jrkyushu.co.jp/english/train/sonic.html" or
            sources[EQUIPMENT_GUIDE]["url_or_locator"] !=
            "https://www.jrkyushu.co.jp/train/kids/guardian/train_equipment/index.html"):
        raise ValueError("Official Sonic formation guide changed")
    for series, diagram_source in DIAGRAM_SOURCES.items():
        if sources[diagram_source]["url_or_locator"] != (
                f"https://www.jrkyushu.co.jp/lang/assets/img/train/sonic/"
                f"img_configuration0{1 if series == '883' else 2}_pc.png"):
            raise ValueError(f"Official {series} diagram changed")
    existing = {row["trip_id"] for row in read_rows("normalized/trip-formations/**/*.jsonl")}
    formations, cars, facts, completeness = [], [], [], []
    for filename, tid, number, labels, green, source_id in FILES:
        candidate = json.loads((BASE / "candidates" / filename).read_text(encoding="utf-8"))
        trip = candidate["trip"]
        source = sources[source_id]
        if (candidate["canonical"] is not False or trip["trip_id"] != tid or
                trip["train_number"] != number or daily[tid]["train_number"] != number or
                tid in existing or source["effective_date"] != DAY or
                not source["url_or_locator"].startswith("https://") or
                "date=20260930" not in source["url_or_locator"] and "d=20260930" not in source["url_or_locator"]):
            raise ValueError(f"Date, trip, or source changed: {tid}")
        observed = trip.get("seat_description_snapshot") or trip.get("equipment_note")
        if isinstance(observed, str):
            if not all(label in observed for label in labels):
                raise ValueError(f"Printed equipment changed: {tid}")
        elif not (isinstance(observed, list) and all(label in observed for label in labels)
                  and all(label in labels or "白いソニック" in label for label in observed)):
            raise ValueError(f"Printed equipment changed: {tid}")
        branding = ("アンパンマン列車で運転" if "アンパンマン列車" in str(observed) else
                    "「白いソニック」で運転" if "白いソニック" in str(observed) else None)
        formation = {"formation_id": f"{tid}.formation.{DAY}", "trip_id": tid,
                     "service_date": DAY, "evidence_kind": "planned", "all_reserved": False,
                     "source_id": source_id,
                     "notes": "Exact-date train page prints " + " / ".join(labels)
                              + (" / " + branding if branding else "")
                              + "; actual consist unverified."}
        sonic_number = tid.split(".")[2] if ".sonic." in tid else None
        if sonic_number:
            series, car_count = SONIC_SERIES[sonic_number]
            formation["vehicle_series"] = series
            formation["car_count"] = car_count
            formation["notes"] += (f" JR Kyushu guide assigns Sonic {sonic_number} to {series} series; "
                                   f"equipment guide lists {car_count} cars. Car-specific seat allocation unverified.")
        else:
            formation["notes"] += " Car count and series unverified."
        if green:
            formation["green_car_available"] = True
        formations.append(formation)
        if sonic_number:
            for car_number in range(1, car_count + 1):
                car = {"formation_id": formation["formation_id"],
                       "car_sequence": car_number, "car_number": str(car_number),
                       "vehicle_series": series, "source_id": DIAGRAM_SOURCES[series]}
                if car_number == 1:
                    car["notes"] = ("Diagram shows Green and reserved ordinary seats in car 1; "
                                    "seat_class left unset because the car is mixed.")
                elif car_number == 2:
                    car["seat_class"] = "ordinary"
                    car["reservation_type"] = "reserved"
                elif car_number >= 5:
                    car["seat_class"] = "ordinary"
                    car["reservation_type"] = "non_reserved"
                else:
                    car["notes"] = "Car 3/4 reserved versus non-reserved allocation varies by train."
                cars.append(car)
        for field, label in (("all_reserved", "普通車一部指定席"),
                             ("green_car_available", "グリーン車指定席")):
            if field == "green_car_available" and not green:
                continue
            facts.append({"entity_type": "trip", "entity_id": tid,
                          "field_name": f"formation.{field}", "source_id": source_id,
                          "page_or_locator": f"2026-09-30 {number} 列車設備: {label}",
                          "confidence": "high", "verification_status": "verified"})
        if branding:
            facts.append({"entity_type": "trip", "entity_id": tid,
                          "field_name": "formation.service_branding", "source_id": source_id,
                          "page_or_locator": f"2026-09-30 {number} 列車設備: {branding}",
                          "confidence": "high", "verification_status": "verified"})
        if sonic_number:
            facts.extend([
                {"entity_type": "trip", "entity_id": tid,
                 "field_name": "formation.vehicle_series", "source_id": SONIC_GUIDE,
                 "page_or_locator": f"Train Configuration / {series} Series / No. {sonic_number}; "
                                    f"exact-date occurrence: {source_id}",
                 "confidence": "high", "verification_status": "verified"},
                {"entity_type": "trip", "entity_id": tid,
                 "field_name": "formation.car_count", "source_id": EQUIPMENT_GUIDE,
                 "page_or_locator": f"列車の設備 / {series}系 {car_count}両; "
                                    f"series assignment: {SONIC_GUIDE}",
                 "confidence": "high", "verification_status": "verified"},
            ])
        completeness.append({"entity_type": "trip", "entity_id": tid,
                             "dimension": "formation", "status": "partial", "confidence": "high",
                             "notes": ("Printed planned seats, series, and car count recorded; actual consist "
                                       "and car-specific seat allocation unknown." if sonic_number else
                                       "Printed planned seat categories recorded; actual consist, car count and series unknown.")})
    write(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl", formations)
    write(BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl", cars)
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    write(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", completeness)
    print(f"Staged {len(formations)} exact-date seat-equipment records")


if __name__ == "__main__":
    main()
