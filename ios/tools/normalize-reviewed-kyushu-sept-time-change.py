#!/usr/bin/env python3
"""Normalize the dated Ibusuki 5 one-minute timetable correction."""

from datetime import date, timedelta
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-kyushu-ibusuki-5-september-2026-minute-change.json"
SOURCE_OUTPUT = BASE / "sources/source-registry-kyushu-sept-time-change.jsonl"
OVERRIDE_OUTPUT = BASE / "normalized/trip-stop-time-overrides/reviewed-kyushu-sept-time-change/seeds.jsonl"
FACT_OUTPUT = BASE / "normalized/fact-sources-kyushu-sept-time-change.jsonl"
BASE_STOPS = BASE / "normalized/stop-times/reviewed-kyushu-next-batch/seeds-kyushu-next-batch.jsonl"


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if candidate["candidate_status"] != "visually_reviewed":
        raise ValueError("The minute change must be visually reviewed")
    source = candidate["source"]
    if (source["source_id"], source["url_or_locator"], candidate["trip_id"],
            candidate["base_departure"], candidate["revised_departure"],
            candidate["from"], candidate["through"]) != (
            "jr-kyushu-ibusuki-5-20260918-minute-change",
            "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0016/00167901.html?c=29007&d=20&ym=202609",
            "jr-kyushu.ibusuki-no-tamatebako.5.2026-07-01",
            "13:56", "13:57", "2026-09-18", "2026-09-30"):
        raise ValueError("Dated Ibusuki 5 evidence changed from the reviewed source")
    stops = [json.loads(line) for line in BASE_STOPS.read_text(encoding="utf-8").splitlines() if line]
    matches = [row for row in stops if row["trip_id"] == candidate["trip_id"] and row["stop_sequence"] == candidate["stop_sequence"]]
    if len(matches) != 1 or matches[0]["departure_time"] != candidate["base_departure"]:
        raise ValueError("Ibusuki 5 baseline departure does not match the reviewed timetable")
    as_of = date.fromisoformat(json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"])
    first, last = date.fromisoformat(candidate["from"]), min(date.fromisoformat(candidate["through"]), as_of)
    days = [first + timedelta(days=i) for i in range((last - first).days + 1)] if last >= first else []
    write_jsonl(SOURCE_OUTPUT, [source])
    write_jsonl(OVERRIDE_OUTPUT, [{
        "trip_id": candidate["trip_id"], "service_date": day.isoformat(),
        "stop_sequence": candidate["stop_sequence"], "departure_override": candidate["revised_departure"],
        "source_id": source["source_id"],
    } for day in days])
    write_jsonl(FACT_OUTPUT, [{
        "entity_type": "trip", "entity_id": candidate["trip_id"], "field_name": "times",
        "source_id": source["source_id"],
        "page_or_locator": "2026 September calendar changed cells for September 18–30; 鹿児島中央 departure 13:57",
        "confidence": "high", "verification_status": "verified",
    }])
    print(f"Normalized Ibusuki 5 dated departure change on {len(days)} service dates")


if __name__ == "__main__":
    main()
