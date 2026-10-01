"""September 30 Haruka 5 and 6 stay tied to official weekday variants."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka5-6-20260930"
DAY = "2026-09-30"
EXPECTED = {
    "jr-west.haruka.5.2026-09-30": {
        "url": "https://timetable.jr-odekake.net/train-timetable/271?date=20260930",
        "number": "1005M", "public": "5", "all_reserved": False,
        "calls": [
            (None, "06:44", "30"), ("07:00", "07:00", None),
            ("07:14", "07:15", "3"), ("07:19", "07:20", "21"),
            ("07:35", "07:37", "15"), ("08:19", None, None),
        ],
    },
    "jr-west.haruka.6.2026-09-30": {
        "url": "https://timetable.jr-odekake.net/train-timetable/321?date=20260930",
        "number": "1006M", "public": "6", "all_reserved": False,
        "calls": [
            (None, "07:56", None), ("08:04", "08:05", None),
            ("08:17", "08:18", None), ("08:40", "08:42", "18"),
            ("09:00", "09:01", "24"), ("09:06", "09:08", "1"),
            ("09:34", None, "30"),
        ],
    },
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class WestSeptember30BatchTests(unittest.TestCase):
    def test_source_pinned_calls_and_planned_seats(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        sources = {row["source_id"]: row for row in rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        formations = {row["trip_id"]: row for row in rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")}
        self.assertEqual(set(trips), set(EXPECTED))
        self.assertEqual(len(stops), 13)
        self.assertEqual(candidate["service_date"], DAY)
        for entry in candidate["trips"]:
            tid = entry["trip_id"]
            spec = EXPECTED[tid]
            with self.subTest(trip=tid):
                source = sources[entry["source_id"]]
                trip = trips[tid]
                calls = sorted((s for s in stops if s["trip_id"] == tid), key=lambda s: s["stop_sequence"])
                formation = formations[tid]
                self.assertEqual((source["url_or_locator"], source["effective_date"]),
                                 (spec["url"], DAY))
                self.assertEqual((trip["train_number"], trip["public_number"]),
                                 (spec["number"], spec["public"]))
                self.assertEqual([(s["arrival_time"], s["departure_time"], s["platform"])
                                  for s in calls], spec["calls"])
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["all_reserved"], formation["green_car_available"]),
                                 (DAY, "planned", spec["all_reserved"], True))
                self.assertEqual(formation["car_count"], 9)
                self.assertNotIn("vehicle_series", formation)
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}").exists())

    def test_materializes_only_selected_date(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        for tid in EXPECTED:
            with self.subTest(trip=tid):
                selected = [t for t in timetable.materialize(data, DAY) if t["trip_id"] == tid]
                previous = [t for t in timetable.materialize(data, "2026-09-29") if t["trip_id"] == tid]
                self.assertEqual(len(selected), 1)
                self.assertEqual(len(selected[0]["stop_times"]), len(EXPECTED[tid]["calls"]))
                self.assertEqual(previous, [])


if __name__ == "__main__":
    unittest.main()
