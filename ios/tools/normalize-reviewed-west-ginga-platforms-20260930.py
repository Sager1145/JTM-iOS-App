#!/usr/bin/env python3
"""Stage date-specific WEST EXPRESS GINGA platform overrides."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
SUFFIX = "reviewed-west-ginga-platforms-20260930"
CANDIDATE = BASE / "candidates/jr-west-ginga-8078m-platforms-20260930.json"
EXPECTED = [(11, "和歌山", "1"), (13, "天王寺", "18"), (14, "大阪", "24"),
            (15, "新大阪", "1"), (16, "京都", "31")]


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
    tid, source_id = candidate["trip_id"], candidate["source_id"]
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"],
            candidate["train_number"]) != ("reviewed_official_train_page", False, DAY, "8078M"):
        raise ValueError("Candidate/date drift")
    if [(p["stop_sequence"], p["station_name"], p["platform"])
            for p in candidate["platforms"]] != EXPECTED:
        raise ValueError("Five official platform cells changed")
    trips = {row["trip_id"]: row for row in read_rows("normalized/trips/**/*.jsonl")}
    sources = {row["source_id"]: row for row in read_rows("sources/source-registry*.jsonl")}
    stops = {row["stop_sequence"]: row for row in read_rows("normalized/stop-times/**/*.jsonl")
             if row["trip_id"] == tid}
    stations = {row["station_id"]: row for row in read_rows("normalized/station-identities*.jsonl")}
    stations.update({row["station_id"]: row for row in read_rows("normalized/station-identities/**/*.jsonl")})
    if trips[tid]["train_number"] != "8078M" or sources[source_id]["url_or_locator"] != candidate["source_url"]:
        raise ValueError("Train/source identity drift")
    dataset, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
    if tid not in {trip["trip_id"] for trip in timetable.materialize(dataset, DAY)}:
        raise ValueError("Train does not materialize on September 30")
    existing = {(row["trip_id"], row["service_date"], row["stop_sequence"])
                for row in read_rows("normalized/trip-stop-time-overrides/**/*.jsonl")}
    overrides, facts = [], []
    for sequence, name, platform in EXPECTED:
        if stations[stops[sequence]["station_id"]]["name_snapshot"] != name:
            raise ValueError(f"Station at stop {sequence} changed")
        if (tid, DAY, sequence) in existing:
            raise ValueError(f"Date-specific override already exists at stop {sequence}")
        overrides.append({"trip_id": tid, "service_date": DAY, "stop_sequence": sequence,
                          "platform_override_present": 1, "platform_override": platform,
                          "source_id": source_id})
        facts.append({"entity_type": "stop_time", "entity_id": f"{tid}:{sequence}",
                      "field_name": "platform", "source_id": source_id,
                      "page_or_locator": f"2026-09-30 8078M のりば: {name} {platform}",
                      "confidence": "high", "verification_status": "verified"})
    write(BASE / f"normalized/trip-stop-time-overrides/{SUFFIX}/seeds.jsonl", overrides)
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    print(f"Staged {len(overrides)} dated platform overrides")


if __name__ == "__main__":
    main()
