"""Official Sep 30 Oita–Saiki Nichirin corridor columns have unique staged trips."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SLICES = (
    'reviewed-kyushu-south-20260930',
    'kyushu-nichirin4-6-8-20260930',
    'kyushu-nichirin10-12-16-20260930',
    'kyushu-nichirin102-20260930',
    'kyushu-nichirin1-3-7-9-20260930',
    'kyushu-nichirin11-13-15-17-20260930',
)
# Official 2026-09-30 station lists: Saiki northbound and Oita southbound.
NORTH = {'5092M', '5002M', '5004M', '5006M', '5008M', '5010M', '5012M', '5016M'}
SOUTH = {'5001M', '5003M', '5007M', '5009M', '5011M', '5013M', '5015M', '5017M'}


class KyushuNichirinOitaSaikiInventoryClosedTests(unittest.TestCase):
    def test_six_seed_slices_cover_all_sixteen_official_columns_once(self):
        matching = []
        for suffix in SLICES:
            path = BASE / f'normalized/trips/{suffix}/seeds.jsonl'
            self.assertTrue(path.exists(), suffix)
            for line in path.read_text(encoding='utf-8').splitlines():
                if not line.strip():
                    continue
                trip = json.loads(line)
                if (trip['service_id'] == 'nichirin' and
                        trip['trip_id'].endswith('.2026-09-30')):
                    matching.append(trip)
        self.assertEqual(len(matching), 16)
        self.assertEqual({trip['train_number'] for trip in matching}, NORTH | SOUTH)
        self.assertEqual(len({trip['trip_id'] for trip in matching}), 16)
        self.assertEqual(len({trip['train_number'] for trip in matching if trip['train_number'] in NORTH}), 8)
        self.assertEqual(len({trip['train_number'] for trip in matching if trip['train_number'] in SOUTH}), 8)


if __name__ == '__main__':
    unittest.main()
