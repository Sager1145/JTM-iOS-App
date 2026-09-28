#!/usr/bin/env python3
"""Audit timetable service dates against the rail-history service intervals."""

import json

from train_timetable import (
    DEFAULT_CANONICAL,
    RAIL_HISTORY,
    DatasetError,
    audit_history_alignment,
    file_sha256,
    load_dataset,
    load_manifest,
    validate_dataset,
    write_json,
)


def main():
    manifest = load_manifest(DEFAULT_CANONICAL)
    data, origins = load_dataset(DEFAULT_CANONICAL, manifest)
    errors = validate_dataset(data, origins, manifest)
    if errors:
        raise DatasetError(
            "canonical timetable validation failed:\n"
            + "\n".join(f"- {error}" for error in errors)
        )
    rail_history = json.loads(RAIL_HISTORY.read_text(encoding="utf-8"))
    report = audit_history_alignment(data, manifest, rail_history)
    report["railHistoryHash"] = file_sha256(RAIL_HISTORY)
    output = DEFAULT_CANONICAL / "audits/train-timetable-history-alignment.json"
    write_json(output, report)
    print(
        f"history alignment: {report['alignedChecks']} aligned, "
        f"{report['unverifiedChecks']} unverified, {report['errorChecks']} errors; "
        f"wrote {output}"
    )
    return 1 if report["errorChecks"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
