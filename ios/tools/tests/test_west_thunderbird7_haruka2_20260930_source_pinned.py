"""September 30 Thunderbird 7 and Haruka 2 stay tied to official variants."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-thunderbird7-haruka2-20260930"
DAY = "2026-09-30"
EXPECTED = {
    "jr-west.thunderbird.7.2026-09-30": {
        "url": "https://timetable.jr-odekake.net/train-timetable/257691?date=20260930",
        "number": "4007M", "public": "7", "all_reserved": True,
        "calls": [
            (None, "08:10", "11"), ("08:13", "08:14", "4"),
            ("08:25", "08:25", None), ("08:39", "08:41", "0"),
            ("08:56", "08:56", None), ("09:14", "09:15", None),
            ("09:37", None, "32"),
        ],
    },
    "jr-west.haruka.2.2026-09-30": {
        "url": "https://timetable.jr-odekake.net/train-timetable/151?date=20260930",
        "number": "1002M", "public": "2", "all_reserved": False,
        "calls": [
            (None, "06:31", None), ("06:40", "06:41", None),
            ("06:55", "06:55", None), ("07:20", "07:21", "18"),
            ("07:37", "07:38", "24"), ("07:42", "07:46", "1"),
            ("08:11", None, "30"),
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
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        self.assertEqual(set(trips), set(EXPECTED))
        self.assertEqual(len(stops), 14)
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
                if tid.startswith("jr-west.haruka."):
                    self.assertEqual(formation["car_count"], 9)
                else:
                    self.assertEqual(formation["car_count"], 9)
                self.assertNotIn("vehicle_series", formation)
                if tid.startswith("jr-west.thunderbird."):
                    for label in entry["printed_equipment"]:
                        self.assertIn(label, formation["notes"])
                women = [row for row in facts if row["entity_id"] == tid
                         and row["field_name"] == "formation.women_only_seats"]
                self.assertEqual(len(women), 1 if tid.startswith("jr-west.thunderbird.") else 0)
                if women:
                    self.assertEqual(women[0]["source_id"], entry["source_id"])
                    self.assertIn("女性専用席があります", women[0]["page_or_locator"])
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
                self.assertEqual(len(selected[0]["stop_times"]), 7)
                self.assertEqual(previous, [])


if __name__ == "__main__":
    unittest.main()
