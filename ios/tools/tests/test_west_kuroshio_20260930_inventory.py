"""Kuroshio exact-date links form a 32-train closed set."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
PATH = BASE / "audits/jr-west-kuroshio-20260930-inventory.json"
RUNNING = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16,
           17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
           32, 33, 35, 36}


class KuroshioClosedSetInventoryTests(unittest.TestCase):
    def test_exact_day_sources_and_database_gap(self):
        inventory = json.loads(PATH.read_text(encoding="utf-8"))
        self.assertEqual(inventory["service_date"], "2026-09-30")
        self.assertEqual(inventory["counts"]["train_pages_running"], 32)
        self.assertEqual(inventory["counts"]["fully_reviewed_train_pages"], 32)
        self.assertEqual(inventory["counts"]["normalized_trips_at_completion"], 32)
        self.assertEqual(inventory["counts"]["normalized_timed_calls_at_completion"], 431)
        rows = inventory["trains"]
        self.assertEqual({row["public_number"] for row in rows}, RUNNING)
        self.assertEqual(len(rows), len({row["train_page_url"] for row in rows}))
        self.assertEqual(sum(row["db_present_at_audit"] for row in rows),
                         inventory["counts"]["db_present_at_audit"])
        self.assertEqual(inventory["counts"]["db_missing_at_audit"],
                         32 - inventory["counts"]["db_present_at_audit"])
        self.assertEqual({row["station_table_source"] for row in rows},
                         {"shin-osaka", "wakayama"})
        self.assertEqual({row["public_number"] for row in rows
                          if row["detail_status"] == "reviewed_full_page"},
                         set(range(1, 15)) | {16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 32, 33, 35, 36})
        for row in rows:
            with self.subTest(public=row["public_number"]):
                self.assertEqual(row["service_id"], "kuroshio")
                self.assertTrue(row["train_page_url"].endswith("?date=20260930"))
                self.assertIn(row["station_table_source"], inventory["source_station_tables"])
                self.assertRegex(row["train_number"], r"^\d+M$")

    def test_closed_set_materializes_on_selected_date(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable

        inventory = json.loads(PATH.read_text(encoding="utf-8"))
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        trips = [trip for trip in timetable.materialize(data, "2026-09-30")
                 if trip["service_id"] == "kuroshio"]
        actual = {int(trip["public_number"]): trip for trip in trips}
        self.assertEqual(len(trips), len(actual))
        self.assertEqual(set(actual), RUNNING)
        self.assertEqual(sum(len(trip["stop_times"]) for trip in trips), 431)
        for row in inventory["trains"]:
            trip = actual[row["public_number"]]
            self.assertEqual(trip["train_number"], row["train_number"])
            self.assertGreaterEqual(len(trip["stop_times"]), 2)


if __name__ == "__main__":
    unittest.main()
