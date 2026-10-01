#!/usr/bin/env python3
"""Add only the printed, date-specific JR Hokkaido stop clocks for four trips."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-dated-stop-clocks-202609.json"
SOURCE_OUTPUT = BASE / "sources/source-registry-hokkaido-dated-stop-clocks-202609.jsonl"
OVERRIDE_OUTPUT = BASE / "normalized/trip-stop-time-overrides/hokkaido-dated-stop-clocks-202609/seeds.jsonl"
FACT_OUTPUT = BASE / "normalized/fact-sources-hokkaido-dated-stop-clocks-202609.jsonl"
COMPLETENESS_OUTPUT = BASE / "normalized/fact-completeness-north-shikoku-batch.jsonl"
RESEARCH_OUTPUT = BASE / "normalized/research-queue-north-shikoku-batch.jsonl"
NORTH_SOURCE_OUTPUT = BASE / "sources/source-registry-north-shikoku-batch.jsonl"
EXPECTED_TRIPS = {
    "jr-hokkaido.hokuto.84-dated-20260920.2026-09-20": ("2026-09-20", "8022D", "jr-hokkaido-hokuto-84-20260920", "s=151"),
    "jr-hokkaido.hokuto.91-dated-20260920.2026-09-20": ("2026-09-20", "8021D", "jr-hokkaido-hokuto-91-20260920", "s=150"),
    "jr-hokkaido.niseko.sapporo-to-hakodate-dated-20260923.2026-09-23": ("2026-09-23", "8012D", "jr-hokkaido-niseko-sapporo-20260923", "s=681"),
    "jr-hokkaido.niseko.hakodate-to-sapporo-dated-20260926.2026-09-26": ("2026-09-26", "9011D", "jr-hokkaido-niseko-hakodate-full-20260926", "s=680"),
}


def jsonl_rows(pattern):
    for path in sorted(BASE.glob(pattern)):
        for raw in path.read_text(encoding="utf-8").splitlines():
            if raw.strip():
                yield json.loads(raw)


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if candidate["candidate_status"] != "visually_reviewed":
        raise ValueError("Selected train columns must be visually reviewed")
    trips = candidate["trips"]
    if {row["trip_id"] for row in trips} != set(EXPECTED_TRIPS) or len(trips) != 4:
        raise ValueError("The four reviewed dated trips have changed")

    as_of = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]
    stations = {row["station_id"]: row["name_snapshot"] for row in jsonl_rows("normalized/station-identities*.jsonl")}
    base_trips = {row["trip_id"]: row for row in jsonl_rows("normalized/trips/**/*.jsonl")}
    base_stops = {}
    for row in jsonl_rows("normalized/stop-times/**/*.jsonl"):
        base_stops.setdefault(row["trip_id"], []).append(row)
    sources = {row["source_id"]: row for row in jsonl_rows("sources/source-registry*.jsonl")
               if row["source_id"] != "jr-hokkaido-niseko-hakodate-full-20260926"}

    new_source = {
        "source_id": "jr-hokkaido-niseko-hakodate-full-20260926",
        "publisher": "北海道旅客鉄道株式会社 / 株式会社交通新聞社",
        "title": "特急ニセコ号 函館―札幌 下り 2026年9月26日",
        "source_type": "official_timetable",
        "url_or_locator": "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260926&s=680",
        "issue": "JR時刻表 令和8年9月号",
        "publication_date": None,
        "effective_date": "2026-09-26",
        "accessed_at": "2026-09-29",
        "license_status": "terms_published_no_reuse_grant_identified",
        "redistribution_status": "verification_only",
        "automated_extraction_allowed": False,
        "notes": "Visually reviewed the selected 9011D full-length column for September 26 only; printed arrival and departure sides are preserved separately. This page disallows unauthorized reproduction or processing.",
    }
    sources[new_source["source_id"]] = new_source

    north_sources = [json.loads(raw) for raw in NORTH_SOURCE_OUTPUT.read_text(encoding="utf-8").splitlines() if raw.strip()]
    reviewed_source_notes = {
        "jr-hokkaido-hokuto-84-20260920": "Selected 8022D / 北斗84 column establishes the train number and every printed station clock for September 20 only.",
        "jr-hokkaido-hokuto-91-20260920": "Selected 8021D / 北斗91 column establishes the train number and every printed station clock for September 20 only.",
        "jr-hokkaido-niseko-sapporo-20260923": "Selected 8012D / 特急ニセコ号 column establishes the train number and every printed station clock for September 23 only; 大沼公園 is marked pass-through.",
    }
    for row in north_sources:
        if row["source_id"] in reviewed_source_notes:
            row["notes"] = reviewed_source_notes[row["source_id"]]
            row["title"] = row["title"].replace("列車番号", "逐站時刻")

    overrides = []
    facts = []
    for trip in trips:
        trip_id = trip["trip_id"]
        day, number, source_id, suffix = EXPECTED_TRIPS[trip_id]
        if (trip["service_date"], trip["train_number"], trip["source_id"]) != (day, number, source_id):
            raise ValueError(f"Date, train number or source changed: {trip_id}")
        if day > as_of or trip["source_url"] != sources[source_id]["url_or_locator"] or not trip["source_url"].endswith(suffix):
            raise ValueError(f"Source URL or as-of boundary changed: {trip_id}")
        if base_trips[trip_id]["train_number"] != number:
            raise ValueError(f"Canonical train number changed: {trip_id}")
        existing = sorted(base_stops[trip_id], key=lambda row: row["stop_sequence"])
        if len(existing) != len(trip["stops"]):
            raise ValueError(f"Passenger stop count changed: {trip_id}")
        for baseline, (station, arrival, departure) in zip(existing, trip["stops"]):
            if stations[baseline["station_id"]] != station:
                raise ValueError(f"Station order changed: {trip_id}:{baseline['stop_sequence']}")
            row = {"trip_id": trip_id, "service_date": day,
                   "stop_sequence": baseline["stop_sequence"], "source_id": source_id}
            for side, published in (("arrival", arrival), ("departure", departure)):
                old = baseline.get(f"{side}_time")
                if published is None:
                    continue
                if old is not None and old != published:
                    raise ValueError(f"Announcement and daily timetable disagree: {trip_id}:{baseline['stop_sequence']} {side}")
                if old is None:
                    row[f"{side}_override"] = published
            if "arrival_override" in row or "departure_override" in row:
                overrides.append(row)
        facts.append({
            "entity_type": "trip", "entity_id": trip_id, "field_name": "times",
            "source_id": source_id, "page_or_locator": trip["source_locator"],
            "confidence": "high", "verification_status": "verified",
        })

    if len(overrides) != 53:
        raise ValueError(f"Expected 53 previously blank dated stops, got {len(overrides)}")
    completeness = [json.loads(raw) for raw in COMPLETENESS_OUTPUT.read_text(encoding="utf-8").splitlines() if raw.strip()]
    research = [json.loads(raw) for raw in RESEARCH_OUTPUT.read_text(encoding="utf-8").splitlines() if raw.strip()]
    for row in completeness:
        if row["entity_id"] in EXPECTED_TRIPS and row["dimension"] == "times":
            if row["status"] != "partial":
                raise ValueError(f"Unexpected baseline time completeness: {row['entity_id']}")
            row["notes"] = (
                "Every clock printed in the exact-date operator column is captured. "
                "Most intermediate rows print departure only; their unprinted arrival sides remain unknown."
            )
    for row in research:
        if row["entity_id"] in EXPECTED_TRIPS and row["missing_dimension"] == "times":
            row["notes"] = (
                "Find dated evidence for unprinted arrival/departure sides. The exact-date "
                "operator column now supplies at least one clock at every passenger call."
            )
    write_jsonl(SOURCE_OUTPUT, [new_source])
    write_jsonl(NORTH_SOURCE_OUTPUT, north_sources)
    write_jsonl(OVERRIDE_OUTPUT, overrides)
    write_jsonl(FACT_OUTPUT, facts)
    write_jsonl(COMPLETENESS_OUTPUT, completeness)
    write_jsonl(RESEARCH_OUTPUT, research)
    print("Normalized four date-specific JR Hokkaido train columns with 53 stop overrides")


if __name__ == "__main__":
    main()
