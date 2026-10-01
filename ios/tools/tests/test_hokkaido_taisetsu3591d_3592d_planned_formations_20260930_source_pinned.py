"""Source-pinned tests for the two missing Taisetsu planned formations."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-taisetsu3591d-3592d-planned-formations-20260930'
TIDS = {
    '3591D': 'jr-hokkaido.taisetsu.3591d.exact-2026-09-30',
    '3592D': 'jr-hokkaido.taisetsu.3592d.exact-2026-09-30',
}


def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class TaisetsuPlannedFormationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / f'candidates/jr-{SUFFIX}.json').read_text(encoding='utf-8'))
        cls.formations = records(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        cls.facts = records(BASE / f'normalized/fact-sources-{SUFFIX}.jsonl')
        cls.sources = records(BASE / f'sources/source-registry-{SUFFIX}.jsonl')

    def test_exact_existing_trips_and_blank_date_page_cells(self):
        trips = {row['train_number']: row for row in self.candidate['trips']}
        self.assertEqual(set(trips), set(TIDS))
        for number, tid in TIDS.items():
            row = trips[number]
            self.assertEqual(row['existing_trip_id'], tid)
            self.assertEqual(row['formation_icons'], [])
            self.assertFalse(row['all_reserved'])
            self.assertIsNone(row['vehicle_series'])
            self.assertIsNone(row['car_count'])
            self.assertIsNone(row['green_car_available'])

    def test_only_two_missing_planned_formations_are_added(self):
        self.assertEqual({row['trip_id'] for row in self.formations}, set(TIDS.values()))
        self.assertEqual(len(self.formations), 2)
        for row in self.formations:
            self.assertEqual(row['service_date'], '2026-09-30')
            self.assertEqual(row['evidence_kind'], 'planned')
            self.assertFalse(row['all_reserved'])
            self.assertNotIn('vehicle_series', row)
            self.assertNotIn('car_count', row)
            self.assertNotIn('green_car_available', row)
            self.assertIn('remain unknown', row['notes'])

    def test_current_official_guide_and_fact_are_pinned(self):
        self.assertEqual(len(self.sources), 1)
        self.assertEqual(self.sources[0]['url_or_locator'],
                         'https://www.jrhokkaido.co.jp/global/cn/train/guide/abashiri.html')
        self.assertEqual(self.sources[0]['issue'], '掲載内容は2026年3月現在')
        self.assertEqual(len(self.facts), 2)
        self.assertEqual({row['entity_id'] for row in self.facts}, set(TIDS.values()))
        self.assertEqual({row['field_name'] for row in self.facts}, {'formation.all_reserved'})
        self.assertTrue(all(row['verification_status'] == 'verified'
                            and row['confidence'] == 'high' for row in self.facts))

    def test_no_trip_or_clock_rows_created(self):
        for directory in ('trips', 'stop-times', 'calendars', 'calendar-exceptions',
                          'timetable-versions'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
