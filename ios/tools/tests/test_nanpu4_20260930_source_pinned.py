"""Exact-date official Nanpu 4 passenger-call and calendar boundary checks."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-nanpu4-20260930"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class Nanpu4SourcePinnedTests(unittest.TestCase):
    def test_exact_date_two_sources_and_full_passenger_calls(self):
        candidate = json.loads((BASE / "candidates/jr-shikoku-nanpu4-20260930.json").read_text())
        self.assertEqual(candidate["trip"]["service_date"], "2026-09-30")
        self.assertEqual(candidate["trip"]["train_number"], "34D")
        self.assertEqual([source["url_or_locator"] for source in candidate["sources"]], [
            "https://timetable.jr-odekake.net/train-timetable/59421?date=20260930",
            "https://timetable.jr-odekake.net/line-timetable/2473?day=30&month=9&year=2026",
        ])
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(stops), 13)
        self.assertEqual([row["stop_sequence"] for row in stops], list(range(1, 14)))
        self.assertEqual([row["call_type"] for row in stops], ["origin"] + ["passenger_stop"] * 11 + ["destination"])
        self.assertEqual([(row["arrival_time"], row["departure_time"]) for row in stops], [
            (None, "07:00"), ("07:07", "07:07"), ("07:11", "07:12"),
            ("07:31", "07:32"), ("07:50", "07:52"), ("08:11", "08:13"),
            ("08:39", "08:40"), ("08:44", "08:45"), ("08:50", "08:51"),
            ("08:55", "08:55"), ("08:59", "09:00"), ("09:14", "09:15"),
            ("09:38", None),
        ])
        self.assertEqual([(row["platform"]) for row in stops],
                         ["1"] + [None] * 11 + ["8"])
        self.assertEqual({row["source_id"] for row in stops},
                         {"jr-odekake-nanpu4-20260930-train"})

    def test_only_september_30_is_materialized_by_calendar(self):
        calendar = rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        exceptions = rows(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(calendar), 1)
        self.assertTrue(all(calendar[0][day] == 0 for day in
                            ("monday", "tuesday", "wednesday", "thursday",
                             "friday", "saturday", "sunday")))
        self.assertEqual([(row["service_date"], row["exception_type"], row["source_id"])
                          for row in exceptions], [
            ("2026-09-30", "add", "jr-odekake-nanpu4-20260930-line")])
        trip = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(trip), 1)
        self.assertEqual(trip[0]["train_number"], "34D")
        self.assertEqual(trip[0]["public_number"], "4")
        self.assertEqual(trip[0]["service_id"], "nanpu")


if __name__ == "__main__":
    unittest.main()
