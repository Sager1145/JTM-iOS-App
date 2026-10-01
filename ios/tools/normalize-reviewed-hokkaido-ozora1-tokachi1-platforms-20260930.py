#!/usr/bin/env python3
"""Stage two printed Sapporo platforms from the dated s=130 timetable."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
SUFFIX = "reviewed-hokkaido-ozora1-tokachi1-platforms-20260930"
SOURCE_URL = "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130"
CANDIDATE = BASE / "candidates/jr-hokkaido-ozora1-tokachi1-sapporo-platforms-20260930.json"
EXPECTED = (
    ("jr-hokkaido.ozora.1.2026-09-30", "4001D", 1, "6:48", "(6)",
     "jr-hokkaido-ozora1-20260930-timetable"),
    ("jr-hokkaido.tokachi.1.2026-09-29-30", "31D", 1, "7:58", "(8)",
     "jr-hokkaido-tokachi1-20260930-timetable"),
)


def write_rows(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in rows), encoding="utf-8")


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"],
            candidate["source_url"]) != (
            "visually_reviewed_official_exact_date", False, DAY, SOURCE_URL):
        raise ValueError("Selected official date/source changed")
    rows = candidate["platforms"]
    observed = tuple((row["trip_id"], row["train_number"], row["stop_sequence"],
                      row["departure_time"], row["platform"], row["source_id"])
                     for row in rows)
    if observed != EXPECTED or any(row["station_name"] != "札幌" for row in rows):
        raise ValueError("First two s=130 platform cells changed")

    manifest = timetable.load_manifest(BASE)
    dataset, origins = timetable.load_dataset(BASE, manifest)
    errors = timetable.validate_dataset(dataset, origins, manifest)
    if errors:
        raise ValueError(errors)
    daily = {row["trip_id"]: row for row in timetable.materialize(dataset, DAY)}
    sources = {row["source_id"]: row for row in dataset["source_documents"]}
    stations = {row["station_id"]: row["name_snapshot"] for row in dataset["station_identities"]}
    existing = {(row["trip_id"], row["service_date"], row["stop_sequence"])
                for index, row in enumerate(dataset["trip_stop_time_overrides"])
                if SUFFIX not in origins[("trip_stop_time_overrides", index)]}
    overrides, facts = [], []
    for tid, number, sequence, departure, platform, source_id in EXPECTED:
        source = sources[source_id]
        if (source["url_or_locator"], source["effective_date"]) != (SOURCE_URL, DAY):
            raise ValueError(f"Dated official source changed: {source_id}")
        trip = daily[tid]
        stop = next(row for row in trip["stop_times"] if row["stop_sequence"] == sequence)
        if (trip["train_number"], trip["service_class"], stations[stop["station_id"]],
                stop["departure_time"], stop.get("platform")) != (
                number, "limited_express", "札幌", departure, None):
            # Reruns see their own platform override in the materialized day.
            if (trip["train_number"], trip["service_class"], stations[stop["station_id"]],
                    stop["departure_time"], stop.get("platform")) != (
                    number, "limited_express", "札幌", departure, platform):
                raise ValueError(f"Sapporo stop changed: {tid}")
        if (tid, DAY, sequence) in existing:
            raise ValueError(f"Another source already overrides Sapporo: {tid}")
        overrides.append({"trip_id": tid, "service_date": DAY, "stop_sequence": sequence,
                          "platform_override_present": 1, "platform_override": platform,
                          "source_id": source_id})
        facts.append({"entity_type": "stop_time", "entity_id": f"{tid}:{sequence}",
                      "field_name": "platform", "source_id": source_id,
                      "page_or_locator": (f"2026-09-30 s=130 {number} 番線 row / 札幌 {departure}発: "
                                          f"{platform}"),
                      "confidence": "high", "verification_status": "verified"})
    write_rows(BASE / f"normalized/trip-stop-time-overrides/{SUFFIX}/seeds.jsonl", overrides)
    write_rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    print("Staged two dated Sapporo platform overrides")


if __name__ == "__main__":
    main()
