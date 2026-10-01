#!/usr/bin/env python3
"""Promote reviewed Akagi 3/6/9 timetables for 2026-09-30 only."""

import importlib.util
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "reviewed_east_train_seed", HERE / "normalize-reviewed-east-next-batch-seeds.py"
)
normalizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(normalizer)

normalizer.CANDIDATE = (
    normalizer.BASE / "candidates/jr-east-akagi-20260930.json"
)
normalizer.SUFFIX = "akagi-20260930"
normalizer.EXPECTED = {
    "jr-east-akagi3-20260930": {
        "dates": ["2026-09-30"],
        "stops": 11,
        "url": "https://timetables.jreast.co.jp/2610/train/030/034771.html",
        "hash": None,
    },
    "jr-east-akagi6-20260930": {
        "dates": ["2026-09-30"],
        "stops": 12,
        "url": "https://timetables.jreast.co.jp/2610/train/075/076101.html",
        "hash": None,
    },
    "jr-east-akagi9-20260930": {
        "dates": ["2026-09-30"],
        "stops": 13,
        "url": "https://timetables.jreast.co.jp/2610/train/065/068071.html",
        "hash": None,
    },
}


def main():
    normalizer.main()
    candidate = json.loads(normalizer.CANDIDATE.read_text())
    english_source = candidate["english_name_source"]
    if english_source["url_or_locator"] != (
        "https://timetables.jreast.co.jp/en/2610/train/075/076101.html"
    ):
        raise ValueError("Akagi English name source changed")
    source_file = normalizer.BASE / f"sources/source-registry-{normalizer.SUFFIX}.jsonl"
    with source_file.open("a") as output:
        output.write(json.dumps(english_source, ensure_ascii=False, sort_keys=True) + "\n")
    name_file = normalizer.BASE / f"normalized/service-name-periods-{normalizer.SUFFIX}.jsonl"
    with name_file.open("a") as output:
        output.write(json.dumps({
            "service_id": "akagi", "name": "Akagi", "language": "en",
            "valid_from": "2026-09-30", "valid_until": "2026-10-01",
            "name_type": "display", "source_id": english_source["source_id"],
        }, ensure_ascii=False, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
