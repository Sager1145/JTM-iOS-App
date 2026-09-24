#!/usr/bin/env python3
"""Resolve service stops to the station identities shipped in EditorCatalog.

Run without arguments to migrate/rebuild refs; --check verifies committed refs.
The compact package already merges N02 station features into station groups, so
raw stations.json feature codes must not be used as catalog station identities.
"""

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
PATTERNS = ROOT / "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"
PACKAGE = ROOT / "app/public/rail/jp-2025.json"

# These patterns omit the endpoint's N02 line from their traversed line list.
# Tokyo's Central Line services use the main Tokyo station group (003766),
# not the separately represented Keiyo platforms (003785). Akagi's optional
# Ikebukuro stop uses the JR station group, not the Fukutoshin platforms.
# Key by pattern and field so new ambiguous routes require an explicit decision.
OVERRIDES = {
    ("hachioji-tokyo-hachioji", "stops", "東京"): "003766",
    ("ome-tokyo-ome", "stops", "東京"): "003766",
    ("azusa-shinjuku-matsumoto", "optionalStops", "東京"): "003766",
    ("kaiji-shinjuku-kofu", "optionalStops", "東京"): "003766",
    ("akagi-ueno-takasaki", "optionalStops", "池袋"): "003390",
}


def normalize_line(name):
    # N02 uses 東海道線/中央線/etc. where the patterns use the 本線 suffix.
    return name.replace("本線", "線")


def resolve(pattern, field, name, by_name, used_overrides):
    rows = by_name.get(name, [])
    codes = {row["code"] for row in rows}
    override_key = (pattern["patternId"], field, name)
    if override_key in OVERRIDES:
        code = OVERRIDES[override_key]
        if code not in codes:
            raise ValueError(f"stale override {override_key}: {code}")
        used_overrides.add(override_key)
        return code
    if len(codes) == 1:
        return next(iter(codes))
    lines = {normalize_line(line) for line in pattern["lines"]}
    line_rows = [row for row in rows if row["lines"] & lines]
    line_codes = {row["code"] for row in line_rows}
    if len(line_codes) == 1:
        return next(iter(line_codes))
    operators = set(pattern["company"].split("/"))
    operator_codes = {
        row["code"] for row in line_rows if row["operator"] in operators
    }
    if len(operator_codes) == 1:
        return next(iter(operator_codes))
    raise ValueError(
        f"{pattern['patternId']} {field} {name}: "
        f"{'missing station' if not codes else 'ambiguous station'}; "
        f"name candidates={sorted(codes)}, line candidates={sorted(line_codes)}, "
        f"operator candidates={sorted(operator_codes)}"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate without writing")
    args = parser.parse_args()
    patterns = json.loads(PATTERNS.read_text())
    package = json.loads(PACKAGE.read_text())
    by_name = {}
    for line in package["lines"]:
        names = {normalize_line(line["name"])}
        if line.get("nameNorm"):
            names.add(normalize_line(line["nameNorm"]))
        for station in line.get("stations", []):
            by_name.setdefault(station[1], []).append({
                "code": station[0], "lines": names, "operator": line.get("operator")
            })

    errors = []
    used_overrides = set()
    count = 0
    for pattern in patterns:
        for field in ("stops", "optionalStops"):
            resolved = []
            for stop in pattern[field]:
                name = stop if isinstance(stop, str) else stop["name"]
                try:
                    code = resolve(pattern, field, name, by_name, used_overrides)
                except ValueError as error:
                    errors.append(str(error))
                    continue
                ref = {"name": name, "sourceCode": code}
                if args.check and stop != ref:
                    errors.append(
                        f"{pattern['patternId']} {field} {name}: "
                        f"expected {ref!r}, found {stop!r}"
                    )
                resolved.append(ref)
                count += 1
            pattern[field] = resolved
    for key in OVERRIDES.keys() - used_overrides:
        errors.append(f"unused override: {key}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    if not args.check:
        PATTERNS.write_text(json.dumps(patterns, ensure_ascii=False, indent=1) + "\n")
    print(f"{'Checked' if args.check else 'Generated'} {count} station refs in {len(patterns)} patterns.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
