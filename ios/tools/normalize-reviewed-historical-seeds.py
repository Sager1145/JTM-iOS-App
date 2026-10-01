#!/usr/bin/env python3
"""Materialize reviewed historical research metadata without promoting gaps.

The reviewed batch contains directly inspected source leads, but none has both
an explicit operating calendar and dated station identities.  This normalizer
therefore emits only source-registry and research-queue inputs.  Candidate
times remain outside the canonical manifest inputs.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "sources/candidates/reviewed-historical-batch.json"
SOURCE_OUTPUT = BASE / "sources/source-registry-historical-batch.jsonl"
QUEUE_OUTPUT = BASE / "normalized/research-queue-historical-batch.jsonl"


def jsonl(rows: list[dict]) -> str:
    ordered = sorted(rows, key=lambda row: row.get("source_id", row.get("research_id", "")))
    return "".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
        for row in ordered
    )


def expected_outputs() -> dict[Path, str]:
    payload = json.loads(CANDIDATE.read_text())
    if payload.get("canonical_promotion_allowed") is not False:
        raise ValueError("historical batch must remain non-canonical until gaps are resolved")
    for candidate in payload.get("timetable_candidates", []):
        if not candidate.get("why_not_canonical"):
            raise ValueError(f"candidate lacks promotion blocker: {candidate.get('candidate_id')}")
    return {
        SOURCE_OUTPUT: jsonl(payload["source_documents"]),
        QUEUE_OUTPUT: jsonl(payload["research_queue"]),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when generated files are stale")
    args = parser.parse_args()
    outputs = expected_outputs()
    if args.check:
        stale = [str(path.relative_to(ROOT)) for path, text in outputs.items()
                 if not path.exists() or path.read_text() != text]
        if stale:
            raise SystemExit("stale historical batch outputs: " + ", ".join(stale))
        print("Historical batch outputs are current; 0 canonical timetable facts promoted.")
        return 0
    for path, text in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    print("Wrote 3 source records and 4 research items; 0 canonical timetable facts promoted.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
