#!/usr/bin/env python3
"""Apply the reviewed AFR English evidence to Taiwan readings, offline.

Run after rebuilding station-readings-tw.json. --check fails if repair is needed.
This changes English fields only, and does not change package station identities.
"""
import argparse
import copy
import json
from pathlib import Path

DATA = Path(__file__).resolve().parents[2] / "data"
SOURCE = DATA / "tw-station-english-afr-source.json"
READINGS = DATA / "station-readings-tw.json"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def apply_evidence(readings, evidence):
    """Return a copy; require code/group identity before changing an English name."""
    output = copy.deepcopy(readings)
    by_code = output["byCode"]
    updated = {"byCode": 0, "byName": 0}
    for code, item in evidence["byCode"].items():
        group = item["stationGroupCode"]
        english = item["en"]
        if code not in by_code:
            raise ValueError(f"AFR identity missing from readings: {code}")
        aliases = [key for key in by_code if key in (code, group)
                   or key.endswith(":" + group)]
        for key in aliases:
            row = by_code[key]
            if row["name"] != item["name"]:
                raise ValueError(f"AFR identity mismatch: {key}: {row['name']}")
            if row.get("en") not in (None, "", english):
                raise ValueError(f"Conflicting English name: {key}: {row['en']}")
            if row.get("en") != english:
                row["en"] = english
                updated["byCode"] += 1
        # A global native-name fallback may identify an unrelated station.
        # Update it only when every corresponding code agrees on English.
        name = item["name"]
        same_name = [row for row in by_code.values() if row.get("name") == name]
        fallback = output.get("byName", {}).get(name)
        if (fallback and fallback.get("name") == name
                and all(row.get("en") == english for row in same_name)):
            if fallback.get("en") not in (None, "", english):
                raise ValueError(f"Conflicting fallback English name: {name}")
            if fallback.get("en") != english:
                fallback["en"] = english
                updated["byName"] += 1
    output["note"] = ("Taiwan official station names for the four UI languages. "
                      "Zh-Hant/English/Japanese come from official TDX/PTX StationName; "
                      "AFR English names come from reviewed official bilingual station pages "
                      "in tw-station-english-afr-source.json. Missing translations are empty. "
                      "Zh-Hans uses an official field when available, otherwise a deterministic "
                      "conversion of Zh-Hant.")
    output["englishSupplement"] = {
        "sourceFile": SOURCE.name,
        "retrievedAt": evidence["retrievedAt"],
        "stationCodes": len(evidence["byCode"]),
    }
    return output, updated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--readings", type=Path, default=READINGS)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    original = read(args.readings)
    output, updated = apply_evidence(original, read(args.source))
    if args.check:
        if output != original:
            raise SystemExit("Taiwan AFR English readings require repair")
    elif output != original:
        args.readings.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n",
                                 encoding="utf-8")
    print(json.dumps(updated))


if __name__ == "__main__":
    main()
