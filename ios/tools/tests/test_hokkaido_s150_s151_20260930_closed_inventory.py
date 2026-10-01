"""The dated s=150/151 pages form a closed 34-train limited-express inventory.

Sources: https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=150
         https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151

This intentionally checks only count, internal train number, service category and
limited-express class. Source-pinned tests own the stop, clock and formation facts.
"""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable


class HokkaidoS150S151ClosedInventoryTests(unittest.TestCase):
    def test_september_30_hokuto_and_suzuran_columns_match_exactly(self):
        base = ROOT / 'app/data/train-service-history'
        manifest = timetable.load_manifest(base)
        data, origins = timetable.load_dataset(base, manifest)
        self.assertEqual(timetable.validate_dataset(data, origins, manifest), [])
        relevant = [trip for trip in timetable.materialize(data, '2026-09-30')
                    if trip['service_id'] in {'hokuto', 'suzuran'}]
        expected = {f'{number}D': 'hokuto' for number in range(1, 23)}
        expected.update({f'{1000 + number}M': 'suzuran' for number in range(1, 13)})
        self.assertEqual(len(relevant), 34)
        self.assertEqual({trip['train_number']: trip['service_id'] for trip in relevant}, expected)
        self.assertTrue(all(trip['service_class'] == 'limited_express' for trip in relevant))


if __name__ == '__main__':
    unittest.main()
