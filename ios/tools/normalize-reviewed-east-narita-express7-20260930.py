#!/usr/bin/env python3
"""Thin entry for the Narita Express 7 coupled-column profile.

Direct execution still stages that profile. The maintained rebuild runner
calls normalize-reviewed-timetable.py --profile … --write instead.
"""

import importlib.util
import json
from pathlib import Path

import reviewed_timetable_staging as staging

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
PROFILE = BASE / "candidates/jr-east-narita-express7-20260930.profile.json"


def _cli():
    spec = importlib.util.spec_from_file_location(
        "normalize_reviewed_timetable",
        Path(__file__).resolve().parent / "normalize-reviewed-timetable.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _profile():
    return json.loads(PROFILE.read_text(encoding="utf-8"))


_DATA = _profile()
SUFFIX = _DATA["suffix"]
CANDIDATE = BASE / _DATA["candidate"]
DAY, NEXT_DAY = _DATA["day"], _DATA["next_day"]
SOURCE = _DATA["source_id"]
URL = _DATA["url"]
SERVICE = _DATA["service"]
STATION_NAME_ALIASES = _DATA["station_name_aliases"]
WEEKDAYS = tuple(_DATA["weekdays"])
PINNED = _DATA["pinned"]
STAGING_FACTS = _DATA["copy"]


def validate(candidate):
    return staging.reject_unless_pinned(candidate, PINNED)


def station_ids(trips):
    forced = {name: set(codes) for name, codes in _DATA["forced_station_codes"].items()}
    return staging.jr_east_forced_station_ids(ROOT, trips, STATION_NAME_ALIASES, forced)


def main():
    cli = _cli()
    cli.stage_profile(cli.load_profile(PROFILE), root=ROOT, base=BASE,
                      candidate_path=CANDIDATE, write=True)


if __name__ == "__main__":
    main()
