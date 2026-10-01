"""Exact-date official Nanpu 2 passenger-call and calendar boundary checks."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-nanpu2-20260930"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class Nanpu2SourcePinnedTests(unittest.TestCase):
    def test_exact_date_two_sources_and_full_passenger_calls(self):
        candidate = json.loads((BASE / "candidates/jr-shikoku-nanpu2-20260930.json").read_text())
        self.assertEqual(candidate["trip"]["service_date"], "2026-09-30")
        self.assertEqual(candidate["trip"]["train_number"], "32D")
        self.assertEqual([source["url_or_locator"] for source in candidate["sources"]], [
            "https://timetable.jr-odekake.net/train-timetable/30871?date=20260930",
            "https://timetable.jr-odekake.net/line-timetable/2473?day=30&month=9&year=2026",
        ])
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(stops), 13)
        self.assertEqual([row["stop_sequence"] for row in stops], list(range(1, 14)))
        self.assertEqual([row["call_type"] for row in stops], ["origin"] + ["passenger_stop"] * 11 + ["destination"])
        self.assertEqual([(row["arrival_time"], row["departure_time"]) for row in stops], [
            (None, "06:00"), ("06:07", "06:07"), ("06:11", "06:12"),
            ("06:31", "06:31"), ("06:48", "06:48"), ("07:06", "07:08"),
            ("07:31", "07:32"), ("07:36", "07:37"), ("07:41", "07:49"),
            ("07:53", "07:54"), ("07:57", "07:58"), ("08:12", "08:14"),
            ("08:38", None),
        ])
        self.assertEqual([(row["platform"]) for row in stops],
                         ["1"] + [None] * 11 + ["6"])
        self.assertEqual({row["source_id"] for row in stops},
                         {"jr-odekake-nanpu2-20260930-train"})

    def test_only_september_30_is_materialized_by_calendar(self):
        calendar = rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        exceptions = rows(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(calendar), 1)
        self.assertTrue(all(calendar[0][day] == 0 for day in
                            ("monday", "tuesday", "wednesday", "thursday",
                             "friday", "saturday", "sunday")))
        self.assertEqual([(row["service_date"], row["exception_type"], row["source_id"])
                          for row in exceptions], [
            ("2026-09-30", "add", "jr-odekake-nanpu2-20260930-line")])
        trip = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(trip), 1)
        self.assertEqual(trip[0]["train_number"], "32D")
        self.assertEqual(trip[0]["service_id"], "nanpu")


if __name__ == "__main__":
    unittest.main()
