"""September 30 Thunderbird 6, 9, and 10 stay tied to official variants."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-thunderbird6-9-10-20260930"
DAY = "2026-09-30"
EXPECTED = {
    "jr-west.thunderbird.6.2026-09-30": {
        "url": "https://timetable.jr-odekake.net/train-timetable/257981?date=20260930",
        "number": "4006M", "public": "6", "all_reserved": True,
        "calls": [
            (None, "08:07", "33"), ("09:02", "09:03", "7"),
            ("09:28", "09:29", "9"), ("09:33", None, "3"),
        ],
    },
    "jr-west.thunderbird.9.2026-09-30": {
        "url": "https://timetable.jr-odekake.net/train-timetable/257701?date=20260930",
        "number": "4009M", "public": "9", "all_reserved": True,
        "calls": [
            (None, "08:42", "11"), ("08:46", "08:47", "4"),
            ("09:09", "09:11", "0"), ("10:03", None, "31"),
        ],
    },
    "jr-west.thunderbird.10.2026-09-30": {
        "url": "https://timetable.jr-odekake.net/train-timetable/258001?date=20260930",
        "number": "4010M", "public": "10", "all_reserved": True,
        "calls": [
            (None, "09:07", "33"), ("10:06", "10:07", "7"),
            ("10:29", "10:29", "9"), ("10:33", None, "3"),
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
        self.assertEqual(len(stops), 12)
        self.assertEqual(candidate["service_date"], DAY)
        self.assertEqual(candidate["route_source_url"],
                         "https://timetable.jr-odekake.net/station-timetable/2635014001?date=20260930")
        self.assertIn("jr-west-odekake-tsuruga-kosei-20260930", sources)
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
                self.assertIn("近江塩津", entry["route_evidence"])
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
