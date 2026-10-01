"""The dated s=110 official columns form a closed limited-express inventory.

Source: https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110
The page has 26 limited-express columns; two 特快大雪 and one 快速きたみ
column are outside this inventory. Pass-through レ cells are not stops.
"""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable


class HokkaidoS110ClosedInventoryTests(unittest.TestCase):
    def test_september_30_limited_express_columns_match_exactly(self):
        base = ROOT / "app/data/train-service-history"
        manifest = timetable.load_manifest(base)
        data, origins = timetable.load_dataset(base, manifest)
        self.assertEqual(timetable.validate_dataset(data, origins, manifest), [])
        sapporo = "jp.n02.000227"
        asahikawa = "jp.n02.000095"
        relevant = [trip for trip in timetable.materialize(data, "2026-09-30")
                    if (trip["service_id"] in {"kamui", "lilac", "soya", "okhotsk"}
                        and trip["origin_station_id"] == sapporo)
                    or (trip["service_id"] == "sarobetsu"
                        and trip["origin_station_id"] == asahikawa)]
        expected = {
            "3001M", "71D", "3003M", "51D", "3005M", "2007M",
            "3011M", "3013M", "3017M", "61D", "2019M", "2021M",
            "3023M", "3025M", "73D", "3027M", "2029M", "2031M",
            "3033M", "2035M", "3037M", "6063D", "3039M", "3041M",
            "2043M", "2045M",
        }
        self.assertEqual(len(relevant), 26)
        self.assertEqual({trip["train_number"] for trip in relevant}, expected)
        self.assertTrue(all(trip["service_class"] == "limited_express" for trip in relevant))


if __name__ == "__main__":
    unittest.main()
