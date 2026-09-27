#!/usr/bin/env python3
"""Audit the v2 validTo -> v3 exclusive validUntil migration.

By default the v2 catalog is read from the commit immediately before the v3
migration. A JSON file can be supplied instead for shallow checkouts or an
archived baseline. This tool is read-only.
"""

import argparse
from copy import deepcopy
from datetime import date, timedelta
import json
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
CURRENT = ROOT / "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"
DEFAULT_BASELINE_REF = "e5b51fa^"
CATALOG_PATH = "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"
DAY_PATTERN = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")


def parse_day(value, context):
    if not isinstance(value, str) or DAY_PATTERN.fullmatch(value) is None:
        raise ValueError(f"{context}: expected strict YYYY-MM-DD, found {value!r}")
    try:
        parsed = date.fromisoformat(value)
    except ValueError as error:
        raise ValueError(f"{context}: invalid Gregorian day {value!r}") from error
    if parsed.isoformat() != value:
        raise ValueError(f"{context}: non-canonical Gregorian day {value!r}")
    return parsed


def migrated_validity(pattern):
    result = {
        "validFrom": pattern.get("validFrom"),
        "validUntil": pattern.get("validUntil"),
    }
    if "validTo" not in pattern:
        return result

    valid_to = pattern.get("validTo")
    if valid_to is None:
        result["validUntil"] = None
    else:
        result["validUntil"] = (
            parse_day(valid_to, f"{pattern.get('patternId')} validTo") + timedelta(days=1)
        ).isoformat()
    return result


def indexed(patterns, label):
    result = {}
    for pattern in patterns:
        pattern_id = pattern.get("patternId")
        if not isinstance(pattern_id, str) or not pattern_id:
            raise ValueError(f"{label}: missing patternId")
        if pattern_id in result:
            raise ValueError(f"{label}: duplicate patternId {pattern_id}")
        result[pattern_id] = pattern
    return result


def load_baseline(path, git_ref):
    if path is not None:
        return json.loads(path.read_text())
    try:
        content = subprocess.run(
            ["git", "show", f"{git_ref}:{CATALOG_PATH}"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or str(error)
        raise ValueError(
            f"could not read v2 baseline from {git_ref}: {detail}; "
            "pass --baseline /path/to/v2-catalog.json"
        ) from error
    return json.loads(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--baseline", type=Path, help="path to the v2 JSON catalog")
    source.add_argument(
        "--baseline-git-ref",
        default=DEFAULT_BASELINE_REF,
        help=f"git revision containing the v2 catalog (default: {DEFAULT_BASELINE_REF})",
    )
    parser.add_argument("--current", type=Path, default=CURRENT, help="v3 JSON catalog")
    args = parser.parse_args()

    try:
        baseline = indexed(
            load_baseline(args.baseline, args.baseline_git_ref), "v2 baseline")
        current = indexed(json.loads(args.current.read_text()), "v3 catalog")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1

    errors = []
    if baseline.keys() != current.keys():
        errors.extend(f"missing from v3: {item}" for item in sorted(baseline.keys() - current.keys()))
        errors.extend(f"new in v3: {item}" for item in sorted(current.keys() - baseline.keys()))

    for pattern_id in sorted(baseline.keys() & current.keys()):
        old = baseline[pattern_id]
        new = current[pattern_id]
        if "validTo" in new:
            errors.append(f"{pattern_id}: v3 still contains validTo")
            continue
        try:
            once = migrated_validity(old)
            idempotence_probe = deepcopy(new)
            twice = migrated_validity(idempotence_probe)
            if twice != {
                "validFrom": new.get("validFrom"),
                "validUntil": new.get("validUntil"),
            }:
                errors.append(f"{pattern_id}: rerunning conversion changes v3 validity")
            if once["validFrom"] != new.get("validFrom"):
                errors.append(
                    f"{pattern_id}: validFrom changed from {once['validFrom']!r} "
                    f"to {new.get('validFrom')!r}")
            if once["validUntil"] != new.get("validUntil"):
                errors.append(
                    f"{pattern_id}: expected validUntil {once['validUntil']!r}, "
                    f"found {new.get('validUntil')!r}")
            if new.get("validFrom") is not None:
                parse_day(new["validFrom"], f"{pattern_id} validFrom")
            if new.get("validUntil") is not None:
                parse_day(new["validUntil"], f"{pattern_id} validUntil")
            if new.get("validFrom") is not None and new.get("validUntil") is not None:
                if new["validFrom"] >= new["validUntil"]:
                    errors.append(f"{pattern_id}: empty or reversed v3 validity interval")
        except ValueError as error:
            errors.append(str(error))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"Audited {len(current)} pattern validity migrations; exclusive conversion is exact and idempotent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
