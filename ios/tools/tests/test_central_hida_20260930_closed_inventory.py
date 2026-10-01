"""Guard all individually observed September 30 Hida trains and split numbers."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable


class HidaDatedInventoryTests(unittest.TestCase):
    def test_all_22_observed_trains_and_split_numbers_materialize(self):
        inventory = json.loads((BASE / "audits/jr-central-shinano-hida-nanki-20260930-inventory.json")
                               .read_text(encoding="utf-8"))
        observed = [row for row in inventory["trains"] if row["service_id"] == "hida"]
        self.assertEqual(len(observed), 22)
        self.assertEqual({row["public_number"] for row in observed},
                         {str(number) for number in range(1, 21)} | {"25", "36"})
        self.assertTrue(all(row["scheduled_on_date"] and row["source_url"] for row in observed))

        manifest = timetable.load_manifest(BASE)
        data, origins = timetable.load_dataset(BASE, manifest)
        self.assertEqual(timetable.validate_dataset(data, origins, manifest), [])
        trips = {trip["public_number"]: trip
                 for trip in timetable.materialize(data, "2026-09-30")
                 if trip["service_id"] == "hida"}
        self.assertEqual(set(trips), {row["public_number"] for row in observed})
        for row in observed:
            self.assertEqual(trips[row["public_number"]]["train_number"],
                             row["train_number"].split(" → ")[0])

        segments = [row for row in data["trip_number_segments"]
                    if row["trip_id"] in {trips["25"]["trip_id"], trips["36"]["trip_id"]}]
        self.assertEqual({row["train_number"] for row in segments
                          if row["trip_id"] == trips["25"]["trip_id"]},
                         {"2025D", "25D"})
        self.assertEqual({row["train_number"] for row in segments
                          if row["trip_id"] == trips["36"]["trip_id"]},
                         {"36D", "2036D"})


if __name__ == "__main__":
    unittest.main()
