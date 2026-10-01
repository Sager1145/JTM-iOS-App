#!/usr/bin/env python3
"""Stage exact-date published seat equipment omitted from reviewed train trips."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
SUFFIX = "reviewed-kyushu-shikoku-reservations-audit-20260930"
REVIEW = BASE / "candidates/jr-kyushu-shikoku-reservation-audit-20260930.json"
GREEN = "グリーン車指定席"
PARTIAL = "普通車一部指定席"
FREE = "普通車自由席"
DX = "ＤＸグリーンがあります"
COMPARTMENT = "グリーン車指定席（４人用グリーン個室連結）"
ANPANMAN = "アンパンマン列車で運転"
DATED_SOURCE_IDS = {
    "jr-odekake-nanpu2-20260930-train",
    "jr-odekake-nanpu4-20260930-train",
}


def write_rows(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in rows), encoding="utf-8")


def main():
    review = json.loads(REVIEW.read_text(encoding="utf-8"))
    rows = review["trips"]
    if (review["candidate_status"] != "visually_reviewed_official_exact_date"
            or review["canonical"] is not False or review["service_date"] != DAY
            or len(rows) != 24 or len({row["trip_id"] for row in rows}) != 24):
        raise ValueError("Reviewed exact-date seat-equipment scope changed")

    manifest = timetable.load_manifest(BASE)
    dataset, origins = timetable.load_dataset(BASE, manifest)
    errors = timetable.validate_dataset(dataset, origins, manifest)
    if errors:
        raise ValueError(errors)
    daily = {row["trip_id"]: row for row in timetable.materialize(dataset, DAY)}
    sources = {row["source_id"]: row for row in dataset["source_documents"]}
    existing = {row["trip_id"] for index, row in enumerate(dataset["trip_formations"])
                if SUFFIX not in origins[("trip_formations", index)]}
    new_sources, formations, facts, completeness = [], [], [], []

    for row in rows:
        tid, number, source_id = (row["trip_id"], row["train_number"], row["source_id"])
        source_url = row["source_url"]
        labels = row["printed_equipment"]
        date_token = ("date=20260930", "d=20260930", "ym=202609&d=30", "d=30&ym=202609")
        if (tid not in daily or tid in existing or daily[tid]["train_number"] != number
                or daily[tid]["service_class"] != "limited_express"
                or not tid.endswith(DAY) or source_id not in sources
                or sources[source_id]["url_or_locator"] != source_url
                or not source_url.startswith("https://")
                or not any(token in source_url for token in date_token)):
            raise ValueError(f"Trip or dated source changed: {tid}")
        if source_id not in DATED_SOURCE_IDS and sources[source_id]["effective_date"] != DAY:
            raise ValueError(f"Source lost its effective date: {source_id}")

        candidate = json.loads((BASE / "candidates" / row["candidate_file"]).read_text(encoding="utf-8"))
        trip = candidate.get("trip")
        candidate_url = (candidate.get("source_url") or trip.get("source_url")
                         if isinstance(trip, dict) else candidate.get("source_url"))
        if not candidate_url:
            candidate_url = next((item["url_or_locator"] for item in candidate.get("sources", [])
                                  if item["source_id"] == source_id), None)
        candidate_dates = candidate.get("service_dates") or [candidate.get("service_date")
                            or candidate.get("database_as_of_date") or (trip or {}).get("service_date")]
        if (candidate.get("canonical") is not False or not isinstance(trip, dict)
                or trip.get("train_number") != number
                or trip.get("trip_id", tid) != tid or candidate_url != source_url
                or DAY not in candidate_dates):
            raise ValueError(f"Underlying reviewed candidate changed: {tid}")
        if not isinstance(labels, list) or len(labels) != len(set(labels)) or not labels:
            raise ValueError(f"Equipment snapshot changed: {tid}")
        if any(label not in {GREEN, PARTIAL, FREE, DX, COMPARTMENT, ANPANMAN} for label in labels):
            raise ValueError(f"Unknown equipment label: {tid}")
        if (PARTIAL in labels) == (FREE in labels):
            raise ValueError(f"Expected exactly one ordinary-seat label: {tid}")

        formation_source_id = source_id
        if source_id in DATED_SOURCE_IDS:
            if sources[source_id].get("effective_date") not in (None, DAY):
                raise ValueError(f"Conflicting source effective date: {source_id}")
            formation_source_id = source_id + "-seat-audit"
            new_source = {**sources[source_id], "source_id": formation_source_id,
                          "effective_date": DAY,
                          "notes": (sources[source_id].get("notes") or "")
                                   + " Exact 2026-09-30 train-detail equipment column visually reviewed."}
            if formation_source_id in sources and sources[formation_source_id] != new_source:
                raise ValueError(f"Dated seat source changed: {formation_source_id}")
            new_sources.append(new_source)

        formation = {"formation_id": f"{tid}.formation.{DAY}", "trip_id": tid,
                     "service_date": DAY, "evidence_kind": "planned", "all_reserved": False,
                     "source_id": formation_source_id,
                     "notes": "Exact-date train page prints " + " / ".join(labels)
                              + "; actual consist, car count, vehicle series and car layout unverified."}
        if GREEN in labels:
            formation["green_car_available"] = True
        formations.append(formation)

        for field, label in (("all_reserved", PARTIAL if PARTIAL in labels else FREE),
                             ("green_car_available", GREEN),
                             ("dx_green_available", DX),
                             ("green_private_compartment", COMPARTMENT),
                             ("service_branding", ANPANMAN)):
            if label not in labels:
                continue
            facts.append({"entity_type": "trip", "entity_id": tid,
                          "field_name": f"formation.{field}", "source_id": formation_source_id,
                          "page_or_locator": f"2026-09-30 {number} 列車設備／車両設備情報: {label}",
                          "confidence": "high", "verification_status": "verified"})
        completeness.append({"entity_type": "trip", "entity_id": tid,
                             "dimension": "formation", "status": "partial", "confidence": "high",
                             "notes": "Published exact-date planned seat/equipment labels recorded; actual consist, car count, series and car diagram unverified."})

    if {row["source_id"].removesuffix("-seat-audit") for row in new_sources} != DATED_SOURCE_IDS:
        raise ValueError("Expected two exact-date seat source rows")
    write_rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl", new_sources)
    write_rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl", formations)
    write_rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    write_rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", completeness)
    print(f"Staged {len(formations)} exact-date reservation records and {len(new_sources)} dated sources")


if __name__ == "__main__":
    main()
