"""The dated s=111 official columns form a closed limited-express inventory.

Source: https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111
The page prints 26 limited-express columns. Two 特快大雪 and one 快速きたみ
columns are outside this inventory. This test covers train identity and date,
not the accuracy of every stop time or formation field.
"""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable


class HokkaidoS111ClosedInventoryTests(unittest.TestCase):
    def test_september_30_limited_express_columns_match_exactly(self):
        base = ROOT / "app/data/train-service-history"
        manifest = timetable.load_manifest(base)
        data, origins = timetable.load_dataset(base, manifest)
        self.assertEqual(timetable.validate_dataset(data, origins, manifest), [])
        sapporo = "jp.n02.000227"
        asahikawa = "jp.n02.000095"
        relevant = [trip for trip in timetable.materialize(data, "2026-09-30")
                    if (trip["service_id"] in {"kamui", "lilac", "soya", "okhotsk"}
                        and trip["destination_station_id"] == sapporo)
                    or (trip["service_id"] == "sarobetsu"
                        and trip["destination_station_id"] == asahikawa)]
        expected = {
            "3002M", "2004M", "2006M", "3008M", "2010M", "3012M",
            "3014M", "62D", "3016M", "72D", "2018M", "3020M",
            "3022M", "3024M", "2028M", "2030M", "3032M", "6064D",
            "3034M", "3038M", "74D", "2040M", "2042M", "3044M",
            "52D", "3046M",
        }
        self.assertEqual(len(relevant), 26)
        self.assertEqual({trip["train_number"] for trip in relevant}, expected)
        self.assertTrue(all(trip["service_class"] == "limited_express" for trip in relevant))


if __name__ == "__main__":
    unittest.main()
