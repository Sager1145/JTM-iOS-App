#!/usr/bin/env python3
"""Guard: the bundled timetable data is stops only.

Fails when any departure/arrival time value is present in the bundled
train-service-timetable.sqlite (or its app/data/train-service-history copy) or
in the line-service-catalog.json trip excerpts, or when the credit metadata is
missing.  Run: python3 -I ios/tools/check-timetable-stops-only.py
"""

import importlib.util
import json
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "ios/RailKit/Sources/RailCore/Resources"
DATABASES = [
    RESOURCES / "train-service-timetable.sqlite",
    ROOT / "app/data/train-service-history/derived/train-service-timetable.sqlite",
]
CATALOG = RESOURCES / "line-service-catalog.json"

_spec = importlib.util.spec_from_file_location("train_timetable", Path(__file__).with_name("train_timetable.py"))
train_timetable = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(train_timetable)
CLOCK_TEXT = train_timetable.CLOCK_TEXT
ALLOWED_TEXT = set(train_timetable.CLOCK_TEXT_ALLOWED_TITLES)
JSON_FILES = ("train-service-patterns", "japan-through-services", "line-service-catalog", "train-service-branding")

STOP_TIME_SQL = """
    SELECT COUNT(*) FROM stop_times
    WHERE arrival_time IS NOT NULL OR departure_time IS NOT NULL
       OR arrival_seconds IS NOT NULL OR departure_seconds IS NOT NULL
       OR arrival_day_offset IS NOT NULL OR departure_day_offset IS NOT NULL
       OR time_accuracy != 'unknown'"""
OVERRIDE_SQL = """
    SELECT COUNT(*) FROM trip_stop_time_overrides
    WHERE arrival_override IS NOT NULL OR departure_override IS NOT NULL
       OR arrival_seconds_override IS NOT NULL OR departure_seconds_override IS NOT NULL
       OR arrival_day_offset_override IS NOT NULL OR departure_day_offset_override IS NOT NULL"""


def text_clock_offenders(connection):
    """Every TEXT value (ids, hashes and ISO timestamps are not clocks) with a clock."""
    offenders = []
    for (table,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'").fetchall():
        for column in [row[1] for row in connection.execute(f"PRAGMA table_info({table})")
                       if (row[2] or "").upper() == "TEXT"]:
            for (text,) in connection.execute(f"SELECT {column} FROM {table} WHERE {column} IS NOT NULL"):
                if text not in ALLOWED_TEXT and CLOCK_TEXT.search(text):
                    offenders.append(f"{table}.{column}: {text[:60]!r}")
    return offenders


def main():
    errors = []
    for path in DATABASES:
        if not path.exists():
            errors.append(f"{path}: missing")
            continue
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            timed = connection.execute(STOP_TIME_SQL).fetchone()[0]
            overrides = connection.execute(OVERRIDE_SQL).fetchone()[0]
            metadata = dict(connection.execute("SELECT key, value FROM metadata"))
            clock_text = text_clock_offenders(connection)
            queued = connection.execute(
                "SELECT COUNT(*) FROM research_queue WHERE missing_dimension = 'times'").fetchone()[0]
        finally:
            connection.close()
        for offender in clock_text[:5]:
            errors.append(f"{path.relative_to(ROOT)}: clock value in text {offender}")
        if len(clock_text) > 5:
            errors.append(f"{path.relative_to(ROOT)}: {len(clock_text)} text values carry a clock value")
        if queued:
            errors.append(f"{path.relative_to(ROOT)}: {queued} research_queue rows still ask for times")
        if timed:
            errors.append(f"{path.relative_to(ROOT)}: {timed} stop_times rows carry a time value")
        if overrides:
            errors.append(f"{path.relative_to(ROOT)}: {overrides} override rows carry a time value")
        for key, expected in (("time_policy", "stops_only"), ("schema_version", "1.3.0")):
            if metadata.get(key) != expected:
                errors.append(f"{path.relative_to(ROOT)}: metadata {key} is {metadata.get(key)!r}, expected {expected!r}")
        for key in ("credit_statement", "credit_sources"):
            if not metadata.get(key):
                errors.append(f"{path.relative_to(ROOT)}: metadata {key} is missing")
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    for trip in catalog["trips"]:
        for stop in trip["stops"]:
            if any(key in stop for key in ("arrivalSeconds", "departureSeconds")):
                errors.append(f"{CATALOG.name}: trip {trip['id']} stop {stop['stationName']} carries a time")
    for name in JSON_FILES:
        text = (RESOURCES / f"{name}.json").read_text(encoding="utf-8")
        match = CLOCK_TEXT.search(text)
        if match:
            errors.append(f"{name}.json: clock value near {text[max(0, match.start() - 20):match.end() + 10]!r}")
    if errors:
        print("timetable stops-only guard FAILED:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"ok: no time values in {len(DATABASES)} databases and {len(catalog['trips'])} catalog excerpts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
