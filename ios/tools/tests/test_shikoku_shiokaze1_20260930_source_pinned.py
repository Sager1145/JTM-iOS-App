"""Exact-date source checks for JR Shikoku Uwakai 1."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-shikoku-shiokaze1-20260930"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class Shiokaze1SourcePinnedTests(unittest.TestCase):
    def test_official_exact_day_source_and_calendar(self):
        candidate = json.loads((BASE / "candidates/jr-shikoku-shiokaze1-20260930.json").read_text())
        self.assertEqual([source["url_or_locator"] for source in candidate["sources"]], [
            "https://timetable.jr-odekake.net/train-timetable/18541?date=20260930",
            "https://timetable.jr-odekake.net/station-timetable/3449041001?date=20260930",
        ])
        self.assertEqual(candidate["trip"]["train_number"], "1M")
        self.assertEqual(len(rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")), 2)
        self.assertEqual({row["service_date"] for row in rows(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")}, {"2026-09-30"})
        for calendar in rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl"):
            self.assertEqual(sum(calendar[day] for day in (
                "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")), 0)

    def test_fifteen_exact_calls_and_unprinted_sides(self):
        candidate = json.loads((BASE / "candidates/jr-shikoku-shiokaze1-20260930.json").read_text())
        stops = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"),
                       key=lambda row: row["stop_sequence"])
        expected = candidate["trip"]["stop_times"]
        self.assertEqual(len(stops), 15)
        self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in stops],
                         [(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in expected])
        self.assertIsNone(stops[0]["arrival_time"])
        self.assertIsNone(stops[-1]["departure_time"])
        self.assertEqual([row["stop_sequence"] for row in stops], list(range(1, 16)))

    def test_route_and_operator_segments_unresolved(self):
        completeness = {row["dimension"]: row["status"] for row in rows(
            BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")}
        self.assertEqual(completeness["operator"], "unknown")
        self.assertEqual(completeness["route_lines"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
