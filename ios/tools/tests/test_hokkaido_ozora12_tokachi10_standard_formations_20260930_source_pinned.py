"""Source-pinned guide-level formation tests for Ozora and Tokachi."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-ozora12-tokachi10-standard-formations-20260930'


def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class OzoraTokachiStandardFormationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / f'candidates/jr-{SUFFIX}.json').read_text())
        trips = [row for path in BASE.glob('normalized/trips/*/*.jsonl') for row in records(path)]
        cls.trips = {(row.get('service_id'), row['train_number']): row for row in trips}
        cls.formations = {row['trip_id']: row for row in records(
            BASE / 'normalized/trip-formations/reviewed-formations-20260930/seeds.jsonl')}
        cls.facts = records(BASE / f'normalized/fact-sources-{SUFFIX}.jsonl')

    def test_exact_closed_family_sets(self):
        self.assertEqual(self.candidate['families']['ozora']['train_numbers'],
                         [f'40{i:02d}D' for i in range(1, 13)])
        self.assertEqual(self.candidate['families']['tokachi']['train_numbers'],
                         [f'{i}D' for i in range(31, 41)])

    def test_22_existing_rows_have_qualified_standard_fields(self):
        seen = 0
        for service, family in self.candidate['families'].items():
            for number in family['train_numbers']:
                trip = self.trips[(service, number)]
                row = self.formations[trip['trip_id']]
                self.assertEqual((row['vehicle_series'], row['car_count']),
                                 ('キハ261系1000代', 4))
                self.assertEqual(row['evidence_kind'], 'planned')
                self.assertIn('does not prove the actual 2026-09-30 dispatch', row['notes'])
                seen += 1
        self.assertEqual(seen, 22)

    def test_guides_and_partial_facts_are_pinned(self):
        self.assertEqual(self.candidate['families']['ozora']['formation_image'],
                         'https://www.jrhokkaido.co.jp/train/img/hensei/tr007_261_h_2.gif')
        self.assertEqual(self.candidate['families']['tokachi']['formation_image'],
                         'https://www.jrhokkaido.co.jp/train/img/hensei/tr005_261_h.gif')
        self.assertEqual(len(self.facts), 44)
        self.assertEqual({row['field_name'] for row in self.facts},
                         {'formation.vehicle_series', 'formation.car_count'})
        self.assertTrue(all(row['confidence'] == 'medium' and
                            row['verification_status'] == 'partial' for row in self.facts))

    def test_no_duplicate_trip_or_clock_rows_created(self):
        for directory in ('trips', 'stop-times', 'calendars', 'calendar-exceptions'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
