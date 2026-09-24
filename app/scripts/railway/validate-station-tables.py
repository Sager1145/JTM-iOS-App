#!/usr/bin/env python3
"""Validate the jp/tw/hk/mo station tables against ADR 0010 (exit 1 on any failure).

See docs/decisions/0010-unified-station-tables.md. Stdlib only.
"""
import json
import os
import re
import sys

DATA = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data"))

SCHEMA_KEYS = [
    "railway_class_code", "institution_type_code", "line_name", "operator",
    "station_name", "n02_station_code", "n02_group_code", "display_point",
]
OPTIONAL_KEYS = {"display_line_id"}
READING_KEYS = ["name", "zh_Hant", "zh_Hans", "en", "ja", "kana", "katakana", "romaji"]

REGIONS = {
    "jp": ("stations.json", "station-readings.json", r"^\d{6}$", r"^\d{6}$"),
    "tw": ("stations-tw.json", "station-readings-tw.json", r"^[A-Z]+-[A-Za-z0-9]+$", r"^tw-official-[a-z0-9-]+$"),
    "hk": ("stations-hk.json", "station-readings-hk.json", r"^(MTR|LR|TRAM)-[A-Z0-9]+$", r"^hk-official-[a-z0-9-]+$"),
    "mo": ("stations-mo.json", "station-readings-mo.json", r"^MLM-[A-Z]+$", r"^mo-official-[a-z0-9-]+$"),
}

failures = []


def fail(fname, station, msg):
    failures.append(f"{fname}: {station}: {msg}")


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def check_region(region, stations_file, readings_file, code_re, group_re):
    code_rx, group_rx = re.compile(code_re), re.compile(group_re)
    with open(os.path.join(DATA, stations_file), encoding="utf-8") as fh:
        stations = json.load(fh)
    codes = set()
    for i, feat in enumerate(stations.get("features", [])):
        props = feat.get("properties", {})
        label = f"#{i} {props.get('station_name', '?')} {props.get('n02_station_code', '?')}"
        keys = set(props)
        missing = [k for k in SCHEMA_KEYS if k not in keys]
        extra = sorted(keys - set(SCHEMA_KEYS) - OPTIONAL_KEYS)
        if missing:
            fail(stations_file, label, f"missing keys {missing}")
        if extra:
            fail(stations_file, label, f"unexpected keys {extra}")
        for k, v in props.items():
            if v == "":
                fail(stations_file, label, f"empty value for {k}")
        dp = props.get("display_point")
        if not (isinstance(dp, list) and len(dp) == 2 and all(is_number(x) for x in dp)):
            fail(stations_file, label, f"display_point is not [lon,lat]: {dp!r}")
        code = props.get("n02_station_code")
        group = props.get("n02_group_code")
        if not isinstance(code, str) or not code_rx.match(code):
            fail(stations_file, label, f"n02_station_code {code!r} does not match {code_re}")
        if not isinstance(group, str) or not group_rx.match(group):
            fail(stations_file, label, f"n02_group_code {group!r} does not match {group_re}")
        if region in ("hk", "mo") and isinstance(group, str) and isinstance(code, str):
            tail = group[len(f"{region}-official-"):].upper()
            if code != tail:
                fail(stations_file, label, f"code {code!r} != group tail {tail!r}")
        if isinstance(code, str):
            codes.add(code)

    with open(os.path.join(DATA, readings_file), encoding="utf-8") as fh:
        readings = json.load(fh)
    for section in ("byCode", "byName"):
        for key, row in readings.get(section, {}).items():
            if not isinstance(row, dict) or list(row) != READING_KEYS:
                got = list(row) if isinstance(row, dict) else row
                fail(readings_file, f"{section}[{key}]", f"row keys {got} != {READING_KEYS}")
    by_code = readings.get("byCode", {})
    bare = {k for k in by_code if ":" not in k}
    for key in sorted(bare):
        if not code_rx.match(key):
            fail(readings_file, f"byCode[{key}]", f"key does not match {code_re}")
    if region == "jp":
        for key in sorted(bare - codes):
            fail(readings_file, f"byCode[{key}]", f"no such station code in {stations_file}")
    else:
        for code in sorted(codes - bare):
            fail(readings_file, code, f"station code from {stations_file} has no byCode row")
    # tw is exempt: its bare byCode keys include AFR UIDs that are not stations.
    if region in ("hk", "mo"):
        for key in sorted(bare - codes):
            fail(readings_file, f"byCode[{key}]", f"no such station code in {stations_file}")


def main():
    for region, spec in REGIONS.items():
        check_region(region, *spec)
    for line in failures:
        print(line)
    if failures:
        print(f"validate-station-tables: {len(failures)} failure(s)")
        return 1
    print("validate-station-tables: jp/tw/hk/mo OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
