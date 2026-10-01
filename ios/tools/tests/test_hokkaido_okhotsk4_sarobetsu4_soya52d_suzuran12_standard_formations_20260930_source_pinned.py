"""Source-pinned standard formation overlay for four Hokkaido dated trips."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-okhotsk4-sarobetsu4-soya52d-suzuran12-standard-formations-20260930'
EXPECTED = {
    'okhotsk': ('74D', '4', 'jr-hokkaido.okhotsk.4.exact-2026-09-30',
                 'キハ283系', 3, None),
    'sarobetsu': ('6064D', '4',
                  'jr-hokkaido.sarobetsu.4-dated-20260930.2026-09-30',
                  'キハ261系0代', 4, True),
    'soya': ('52D', None, 'jr-hokkaido.soya.52d.exact-2026-09-30',
             'キハ261系0代', 4, True),
    'suzuran': ('1012M', '12', 'jr-hokkaido.suzuran.12.exact-2026-09-30',
                None, 5, None),
}


def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class HokkaidoFourStandardFormationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(
            (BASE / f'candidates/jr-{SUFFIX}.json').read_text(encoding='utf-8'))
        cls.formations = [row for path in BASE.glob('normalized/trip-formations/*/*.jsonl')
                          for row in records(path)]
        cls.by_trip = {}
        for row in cls.formations:
            cls.by_trip.setdefault(row['trip_id'], []).append(row)

    def test_candidate_pins_four_exact_train_identities(self):
        self.assertEqual(set(self.candidate['families']), set(EXPECTED))
        for family, (number, public, trip_id, series, cars, _) in EXPECTED.items():
            family_row = self.candidate['families'][family]
            self.assertEqual((family_row['vehicle_series'],
                              family_row['standard_car_count']), (series, cars))
            self.assertEqual(family_row['trains'], [{
                'train_number': number, 'public_number': public, 'trip_id': trip_id}])
        self.assertEqual(self.candidate['families']['suzuran']['published_vehicle_series'],
                         ['785系', '789系1000代'])

    def test_existing_formations_have_only_supported_standard_fields(self):
        for family, (_, _, trip_id, series, cars, green) in EXPECTED.items():
            self.assertEqual(len(self.by_trip.get(trip_id, [])), 1, family)
            row = self.by_trip[trip_id][0]
            self.assertEqual((row.get('vehicle_series'), row.get('car_count'),
                              row.get('green_car_available')),
                             (series, cars, green), family)
            self.assertTrue(row['all_reserved'])
            self.assertEqual(row['evidence_kind'], 'planned')
            marker = 'does not prove the actual 2026-09-30 dispatch'
            self.assertEqual(row['notes'].count(marker), 1, family)

    def test_sources_and_seven_partial_field_facts_are_pinned(self):
        sources = records(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual({row['url_or_locator'] for row in sources}, {
            'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111',
            'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151',
            'https://www.jrhokkaido.co.jp/train/tr008_01.html',
            'https://www.jrhokkaido.co.jp/train/tr010_01.html',
            'https://www.jrhokkaido.co.jp/train/tr011_01.html',
            'https://www.jrhokkaido.co.jp/train/tr012_01.html',
        })
        self.assertEqual({row['issue'] for row in sources
                          if row['source_type'] == 'official_timetable'},
                         {'JR時刻表 令和8年10月号'})
        facts = records(BASE / f'normalized/fact-sources-{SUFFIX}.jsonl')
        self.assertEqual(len(facts), 7)
        self.assertEqual({row['entity_id'] for row in facts},
                         {item[2] for item in EXPECTED.values()})
        self.assertEqual([row['field_name'] for row in facts
                          if row['entity_id'] == EXPECTED['suzuran'][2]],
                         ['formation.car_count'])
        self.assertTrue(all(row['verification_status'] == 'partial'
                            and row['confidence'] == 'medium' for row in facts))

    def test_no_new_trip_or_timetable_rows_created(self):
        for directory in ('trips', 'stop-times', 'calendars', 'calendar-exceptions'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
