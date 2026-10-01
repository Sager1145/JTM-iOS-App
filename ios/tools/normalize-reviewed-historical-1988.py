#!/usr/bin/env python3
"""Register reviewed 1988 timetable research without inventing daily trips."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "sources/candidates/reviewed-historical-1988-batch.json"
SOURCE_OUTPUT = BASE / "sources/source-registry-historical-1988.jsonl"
QUEUE_OUTPUT = BASE / "normalized/research-queue-historical-1988.jsonl"


def jsonl(rows, key):
    return "".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
        for row in sorted(rows, key=lambda row: row[key])
    )


def expected_outputs():
    payload = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if payload.get("canonical_promotion_allowed") is not False:
        raise ValueError("1988 research must not become canonical without reviewed gaps")
    candidates = payload.get("timetable_candidates", [])
    if len(candidates) != 2 or any(
        item.get("canonical_record_count") != 0 or not item.get("why_not_canonical")
        for item in candidates
    ):
        raise ValueError("1988 candidates must document why no trip is promoted")
    return {
        SOURCE_OUTPUT: jsonl(payload["source_documents"], "source_id"),
        QUEUE_OUTPUT: jsonl(payload["research_queue"], "research_id"),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = expected_outputs()
    if args.check:
        stale = [str(path.relative_to(ROOT)) for path, expected in outputs.items()
                 if not path.exists() or path.read_text(encoding="utf-8") != expected]
        if stale:
            raise SystemExit("stale historical 1988 outputs: " + ", ".join(stale))
        print("Historical 1988 research outputs current; 0 canonical trips promoted.")
        return
    for path, content in outputs.items():
        path.write_text(content, encoding="utf-8")
    print("Registered 1 historical source and 3 research items; 0 canonical trips promoted.")


if __name__ == "__main__":
    main()
