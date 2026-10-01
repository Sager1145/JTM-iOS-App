"""September 30 Haruka 3 retains the official weekday calls and platforms."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka3-20260930"
TRIP = "jr-west.haruka.3.2026-09-30"
DAY = "2026-09-30"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class Haruka3Tests(unittest.TestCase):
    def test_source_pinned_stops_platforms_and_seats(self):
        candidate = json.loads((BASE / "candidates/jr-west-haruka3-20260930.json")
                               .read_text(encoding="utf-8"))
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")[0]
        trip = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")[0]
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        formation = rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")[0]
        self.assertEqual((source["url_or_locator"], source["effective_date"]),
                         (candidate["source_url"], DAY))
        self.assertEqual((trip["trip_id"], trip["train_number"], trip["public_number"]),
                         (TRIP, "1003M", "3"))
        self.assertEqual(len(stops), 11)
        self.assertEqual([(s["stop_sequence"], s["platform"]) for s in stops if s["platform"]],
                         [(6, "7"), (8, "3"), (9, "21"), (10, "15")])
        self.assertEqual((stops[0]["departure_time"], stops[-1]["arrival_time"]),
                         ("05:58", "07:41"))
        self.assertEqual((formation["service_date"], formation["evidence_kind"],
                          formation["all_reserved"], formation["green_car_available"]),
                         (DAY, "planned", False, True))
        self.assertEqual(formation["car_count"], 9)
        self.assertNotIn("vehicle_series", formation)
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}").exists())

    def test_materializes_only_selected_day(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        selected = [t for t in timetable.materialize(data, DAY) if t["trip_id"] == TRIP]
        previous = [t for t in timetable.materialize(data, "2026-09-29") if t["trip_id"] == TRIP]
        self.assertEqual(len(selected), 1)
        self.assertEqual(previous, [])
        self.assertEqual(len(selected[0]["stop_times"]), 11)


if __name__ == "__main__":
    unittest.main()
