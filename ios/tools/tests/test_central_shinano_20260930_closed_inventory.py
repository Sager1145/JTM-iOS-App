"""Keep the dated Shinano inventory aligned with the official train pages."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable


class ShinanoDatedInventoryTests(unittest.TestCase):
    def test_all_26_individually_observed_trains_materialize_on_september_30(self):
        inventory = json.loads((BASE / "audits/jr-central-shinano-hida-nanki-20260930-inventory.json")
                               .read_text(encoding="utf-8"))
        self.assertEqual(inventory["service_date"], "2026-09-30")
        observed = [row for row in inventory["trains"] if row["service_id"] == "shinano"]
        self.assertEqual(len(observed), 26)
        self.assertEqual({row["public_number"] for row in observed},
                         {str(number) for number in range(1, 27)})
        self.assertTrue(all(row["scheduled_on_date"] and row["source_url"]
                            and "individually inspected" in row["date_evidence"]
                            for row in observed))

        manifest = timetable.load_manifest(BASE)
        data, origins = timetable.load_dataset(BASE, manifest)
        self.assertEqual(timetable.validate_dataset(data, origins, manifest), [])
        materialized = [trip for trip in timetable.materialize(data, "2026-09-30")
                        if trip["service_id"] == "shinano"]
        self.assertEqual(len(materialized), 26)
        self.assertEqual({(trip["public_number"], trip["train_number"])
                          for trip in materialized},
                         {(row["public_number"], row["train_number"])
                          for row in observed})


if __name__ == "__main__":
    unittest.main()
