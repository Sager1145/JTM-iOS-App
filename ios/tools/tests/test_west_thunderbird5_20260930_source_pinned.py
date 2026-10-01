"""September 30 Thunderbird 5 stays tied to its weekday source variant."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-thunderbird5-20260930"
TRIP = "jr-west.thunderbird.5.2026-09-30"
DAY = "2026-09-30"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class Thunderbird5Tests(unittest.TestCase):
    def test_source_pinned_calls_platforms_and_planned_seats(self):
        candidate = json.loads((BASE / "candidates/jr-west-thunderbird5-20260930.json")
                               .read_text(encoding="utf-8"))
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")[0]
        trip = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")[0]
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        formation = rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")[0]
        self.assertEqual((source["url_or_locator"], source["effective_date"]),
                         (candidate["source_url"], DAY))
        self.assertEqual((trip["trip_id"], trip["train_number"], trip["public_number"]),
                         (TRIP, "4005M", "5"))
        self.assertEqual([(s["stop_sequence"], s["arrival_time"], s["departure_time"],
                           s["platform"]) for s in stops], [
                            (1, None, "07:40", "11"), (2, "07:43", "07:44", "4"),
                            (3, "07:54", "07:54", None), (4, "08:08", "08:09", "0"),
                            (5, "09:03", None, "32")])
        self.assertEqual((formation["service_date"], formation["evidence_kind"],
                          formation["all_reserved"], formation["green_car_available"]),
                         (DAY, "planned", True, True))
        self.assertEqual(formation["car_count"], 9)
        self.assertNotIn("vehicle_series", formation)
        self.assertIn("女性専用席があります", candidate["printed_equipment"])
        self.assertIn("女性専用席があります", formation["notes"])
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        women = [row for row in facts if row["field_name"] == "formation.women_only_seats"]
        self.assertEqual(len(women), 1)
        self.assertEqual((women[0]["entity_id"], women[0]["source_id"]),
                         (TRIP, source["source_id"]))
        self.assertIn("女性専用席があります", women[0]["page_or_locator"])
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}").exists())

    def test_materializes_only_selected_day(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        selected = [t for t in timetable.materialize(data, DAY) if t["trip_id"] == TRIP]
        previous = [t for t in timetable.materialize(data, "2026-09-29") if t["trip_id"] == TRIP]
        self.assertEqual(len(selected), 1)
        self.assertEqual(previous, [])
        self.assertEqual(len(selected[0]["stop_times"]), 5)


if __name__ == "__main__":
    unittest.main()
