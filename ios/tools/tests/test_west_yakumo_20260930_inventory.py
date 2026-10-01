"""Pin the 30-departure inventory checkpoint and later reviewed trips 1–16."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
PATH = BASE / "audits/jr-west-yakumo-20260930-inventory.json"
SOUTH = ["76231", "76241", "76251", "76261", "76271", "541", "278871", "681",
         "278881", "811", "921", "961", "1001", "1041", "278891"]
NORTH = ["76332", "76281", "76291", "76301", "76321", "278901", "631", "278911",
         "771", "891", "941", "971", "1021", "278921", "1101"]


class YakumoSeptember30InventoryTests(unittest.TestCase):
    def test_closed_official_page_inventory(self):
        # This audit preserves what was reviewed when the inventory was captured.
        audit = json.loads(PATH.read_text(encoding="utf-8"))
        self.assertEqual(audit["service_date"], "2026-09-30")
        self.assertEqual(audit["counts"], {"train_pages_running": 30,
                                            "normalized_at_inventory": 1,
                                            "fully_reviewed_train_pages": 12})
        self.assertEqual(set(audit["source_station_tables"]), {"okayama", "izumoshi"})
        rows = audit["trains"]
        self.assertEqual(len(rows), 30)
        self.assertEqual({row["public_number"] for row in rows}, set(range(1, 31)))
        self.assertEqual(len({row["train_page_url"] for row in rows}), 30)
        self.assertEqual({row["public_number"] for row in rows if row["normalized_at_inventory"]}, {15})
        self.assertEqual({row["public_number"] for row in rows
                          if row["detail_status"] == "reviewed_full_page"}, set(range(1, 13)))
        for row in rows:
            public = row["public_number"]
            page = (SOUTH[(public-1)//2] if public % 2 else NORTH[(public-2)//2])
            with self.subTest(public=public):
                self.assertEqual(row["train_number"], f"{1000+public}M")
                self.assertEqual(row["train_page_url"],
                                 f"https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930")
                self.assertEqual(row["station_table_source"], "okayama" if public % 2 else "izumoshi")

    def test_reviewed_batches_materialize_one_through_sixteen(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable

        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        trips = [trip for trip in timetable.materialize(data, "2026-09-30")
                 if trip["service_id"] == "yakumo"]
        self.assertEqual(len(trips), 16)
        self.assertEqual({int(trip["public_number"]) for trip in trips}, set(range(1, 17)))
        expected_ids = {f"jr-west.yakumo.{number}.2026-09-30" for number in range(1, 17)}
        self.assertEqual({trip["trip_id"] for trip in trips}, expected_ids)
        sources = {row["source_id"]: row for row in data["source_documents"]}
        for trip in trips:
            public = int(trip["public_number"])
            page = SOUTH[(public-1)//2] if public % 2 else NORTH[(public-2)//2]
            source_id = f"jr-west-odekake-yakumo{public}-{1000+public}m-20260930"
            with self.subTest(public=public):
                self.assertEqual(trip["train_number"], f"{1000+public}M")
                self.assertEqual(sources[source_id]["effective_date"], "2026-09-30")
                self.assertEqual(sources[source_id]["url_or_locator"],
                                 f"https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930")
                self.assertEqual({row["source_id"] for row in data["fact_sources"]
                                  if row["entity_id"] == trip["trip_id"]
                                  and row["field_name"] == "train_number"}, {source_id})
        for day in ("2026-09-29", "2026-10-01"):
            self.assertFalse(expected_ids & {trip["trip_id"] for trip in timetable.materialize(data, day)})


if __name__ == "__main__":
    unittest.main()
