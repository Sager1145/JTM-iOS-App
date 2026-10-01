"""Exact-date train-detail checks for Uwakai 13."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-shikoku-uwakai13-20260930"
URL = "https://timetable.jr-odekake.net/train-timetable/1391?date=20260930"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class Uwakai13SourcePinnedTests(unittest.TestCase):
    def test_source_date_number_and_calls(self):
        candidate = json.loads((BASE / "candidates/jr-shikoku-uwakai13-20260930.json").read_text())
        self.assertEqual((candidate["sources"][0]["url_or_locator"],
                          candidate["trip"]["train_number"], candidate["trip"]["service_date"]),
                         (URL, "1063D", "2026-09-30"))
        self.assertEqual(candidate["sources"][1]["url_or_locator"],
                         "https://timetable.jr-odekake.net/line-timetable/2469?day=30&month=9&year=2026")
        self.assertTrue(all(source["automated_extraction_allowed"] is False for source in candidate["sources"]))
        self.assertEqual(len(rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")), 2)
        stops = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"),
                       key=lambda row: row["stop_sequence"])
        self.assertEqual(len(stops), 8)
        self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"]) for row in stops],
                         [(stop["arrival_time"], stop["departure_time"], stop["platform"])
                          for stop in candidate["trip"]["stop_times"]])
        self.assertEqual((stops[0]["departure_time"], stops[-1]["arrival_time"]), ("12:30", "14:03"))
        self.assertEqual([row["platform"] for row in stops], ["2"] + [None] * 7)

    def test_seat_category_with_unknown_series_and_routes(self):
        formation = rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(formation), 1)
        self.assertEqual((formation[0]["evidence_kind"], formation[0]["all_reserved"]),
                         ("planned", False))
        self.assertNotIn("vehicle_series", formation[0])
        self.assertNotIn("car_count", formation[0])
        completeness = {row["dimension"]: row["status"] for row in
                        rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")}
        self.assertEqual((completeness["operator"], completeness["route_lines"]), ("unknown", "unknown"))
        self.assertEqual({row["service_date"] for row in
                          rows(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")},
                         {"2026-09-30"})
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
