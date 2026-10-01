"""Source pinned checks for September 30 Nichirin 2 and Kirishima 1."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-south-20260930"
CANDIDATES = ("jr-kyushu-nichirin2-20260930.json", "jr-kyushu-kirishima1-20260930.json")


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class KyushuSouthSourcePinnedTests(unittest.TestCase):
    def test_exact_date_and_source_urls(self):
        nichirin, kirishima = [json.loads((BASE / "candidates" / name).read_text()) for name in CANDIDATES]
        self.assertEqual(nichirin["source_url"],
                         "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0007/00075401.html?c=28903&ym=202609&d=30")
        self.assertEqual(kirishima["source_url"],
                         "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0006/00064501.html?c=28903&ym=202609&d=30")
        self.assertEqual(nichirin["service_date"], "2026-09-30")
        self.assertEqual(kirishima["service_date"], "2026-09-30")
        self.assertEqual({row["service_date"] for row in rows(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")}, {"2026-09-30"})
        for calendar in rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl"):
            self.assertEqual(sum(calendar[day] for day in (
                "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")), 0)
        self.assertEqual(rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl"), [])

    def test_full_route_calls_and_null_sides(self):
        trips = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        self.assertEqual({trip["train_number"] for trip in trips}, {"5002M", "6001M"})
        self.assertEqual(len(stops), 27)
        for candidate_name in CANDIDATES:
            candidate = json.loads((BASE / "candidates" / candidate_name).read_text())
            trip = candidate["trip"]
            actual = sorted((row for row in stops if row["trip_id"] == trip["trip_id"]),
                            key=lambda row: row["stop_sequence"])
            expected = trip["stop_times"]
            self.assertEqual(len(actual), len(expected))
            self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                              for row in actual],
                             [(row["arrival_time"], row["departure_time"], row["platform"])
                              for row in expected])
            self.assertIsNone(actual[0]["arrival_time"])
            self.assertIsNone(actual[-1]["departure_time"])
            self.assertEqual([row["stop_sequence"] for row in actual], list(range(1, len(actual) + 1)))

    def test_route_and_operator_boundaries_remain_open(self):
        completeness = rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        by_trip = {}
        for row in completeness:
            by_trip.setdefault(row["entity_id"], {})[row["dimension"]] = row["status"]
        self.assertEqual(len(by_trip), 2)
        for dimensions in by_trip.values():
            self.assertEqual(dimensions["operator"], "unknown")
            self.assertEqual(dimensions["route_lines"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
