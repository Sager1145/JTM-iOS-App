#!/usr/bin/env python3
"""Record six individually reviewed September 19/22/27 JR Hokkaido columns."""

import json
from pathlib import Path


BASE = Path(__file__).resolve().parents[2] / "app/data/train-service-history"
CANDIDATES = (
    BASE / "candidates/jr-hokkaido-hokuto-20260919-stop-clocks.json",
    BASE / "candidates/jr-hokkaido-niseko-20260922-stop-clocks.json",
    BASE / "candidates/jr-hokkaido-niseko-20260927-stop-clocks.json",
)
OVERRIDES = BASE / "normalized/trip-stop-time-overrides/hokkaido-additional-202609/seeds.jsonl"
FACTS = BASE / "normalized/fact-sources-hokkaido-additional-stop-clocks-202609.jsonl"
EXPECTED = {
    "jr-hokkaido.hokuto.84-dated-20260919.2026-09-19": ("8022D", "151", 16, "jr-hokkaido-hokuto-84-20260919"),
    "jr-hokkaido.hokuto.91-dated-20260919.2026-09-19": ("8021D", "150", 16, "jr-hokkaido-hokuto-91-20260919"),
    "jr-hokkaido.niseko.sapporo-to-hakodate-dated-20260922.2026-09-22": ("8012D", "681", 14, "jr-hokkaido-niseko-sapporo-20260922"),
    "jr-hokkaido.niseko.hakodate-to-sapporo-dated-20260922.2026-09-22": ("9011D", "680", 15, "jr-hokkaido-niseko-hakodate-20260922"),
    "jr-hokkaido.niseko.sapporo-to-hakodate-dated-20260927.2026-09-27": ("8012D", "681", 14, "jr-hokkaido-niseko-sapporo-20260927"),
    "jr-hokkaido.niseko.hakodate-to-sapporo-dated-20260927.2026-09-27": ("9011D", "680", 15, "jr-hokkaido-niseko-hakodate-20260927"),
}


def rows(pattern):
    for path in sorted(BASE.glob(pattern)):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line)


def main():
    reviewed = []
    for path in CANDIDATES:
        candidate = json.loads(path.read_text(encoding="utf-8"))
        if candidate["candidate_status"] != "visually_reviewed":
            raise ValueError(f"Source columns have not been reviewed: {path}")
        reviewed.extend(candidate["trips"])
    if len(reviewed) != 6 or {trip["trip_id"] for trip in reviewed} != set(EXPECTED):
        raise ValueError("Expected six dated Hokuto/Niseko trips")
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    names = {row["station_id"]: row["name_snapshot"]
             for row in rows("normalized/station-identities*.jsonl")}
    trips = {row["trip_id"]: row for row in rows("normalized/trips/**/*.jsonl")}
    stops = {}
    for row in rows("normalized/stop-times/**/*.jsonl"):
        if row["trip_id"] in EXPECTED:
            stops.setdefault(row["trip_id"], []).append(row)
    sources = {row["source_id"]: row for row in rows("sources/source-registry-north-shikoku-batch.jsonl")}
    overrides = []
    facts = []
    for trip in reviewed:
        trip_id = trip["trip_id"]
        number, table_id, count, source_id = EXPECTED[trip_id]
        day = trip["service_date"]
        source_url = f"https://jrhokkaidonorikae.com/vtime/vtime.php?d={day.replace('-', '')}&s={table_id}"
        if day > manifest["as_of_date"] or (
            trip["train_number"], trip["source_id"], trip["source_url"]
        ) != (number, source_id, source_url):
            raise ValueError(f"Date, train number or URL changed for {trip_id}")
        if trips[trip_id]["train_number"] != number:
            raise ValueError(f"Dated train number missing for {trip_id}")
        if (sources[source_id]["effective_date"], sources[source_id]["url_or_locator"]) != (day, source_url):
            raise ValueError(f"Registered dated source changed for {trip_id}")
        for field in ("origin_destination", "times"):
            facts.append({"entity_type": "trip", "entity_id": trip_id,
                          "field_name": field, "source_id": source_id,
                          "page_or_locator": trip["source_locator"],
                          "confidence": "high", "verification_status": "verified"})
        baseline = sorted(stops[trip_id], key=lambda row: row["stop_sequence"])
        if len(baseline) != count or len(trip["stops"]) != count:
            raise ValueError(f"Station count changed for {trip_id}")
        for saved, (name, arrival, departure) in zip(baseline, trip["stops"]):
            if names[saved["station_id"]] != name:
                raise ValueError(f"Station order changed: {trip_id}:{saved['stop_sequence']}")
            override = {"trip_id": trip_id, "service_date": day,
                        "stop_sequence": saved["stop_sequence"], "source_id": source_id}
            for side, printed in (("arrival", arrival), ("departure", departure)):
                existing = saved.get(f"{side}_time")
                if printed is not None and existing is not None and existing != printed:
                    raise ValueError(f"Published endpoint time changed: {trip_id}:{name}:{side}")
                if printed is not None and existing is None:
                    override[f"{side}_override"] = printed
            if len(override) > 4:
                overrides.append(override)
    if len(overrides) != 78:
        raise ValueError(f"Expected 78 newly known intermediate calls, got {len(overrides)}")
    OVERRIDES.parent.mkdir(parents=True, exist_ok=True)
    OVERRIDES.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                                 for row in overrides), encoding="utf-8")
    FACTS.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                             for row in facts), encoding="utf-8")
    print("Normalized 78 exact-date Hokuto/Niseko stop-clock overrides")


if __name__ == "__main__":
    main()
