"""Both dated Obihiro/Kushiro tables contain every represented limited express.

Sources: https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130
         https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=131
"""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable


class HokkaidoS130S131ClosedInventoryTests(unittest.TestCase):
    def test_september_30_ozora_and_tokachi_match_both_tables(self):
        base = ROOT / "app/data/train-service-history"
        manifest = timetable.load_manifest(base)
        data, origins = timetable.load_dataset(base, manifest)
        self.assertEqual(timetable.validate_dataset(data, origins, manifest), [])
        relevant = [trip for trip in timetable.materialize(data, "2026-09-30")
                    if trip["service_id"] in {"ozora", "tokachi"}]
        expected = {f"{number}D" for number in range(4001, 4013)}
        expected.update(f"{number}D" for number in range(31, 41))
        self.assertEqual(len(relevant), 22)
        self.assertEqual({trip["train_number"] for trip in relevant}, expected)
        self.assertTrue(all(trip["service_class"] == "limited_express" for trip in relevant))


if __name__ == "__main__":
    unittest.main()
