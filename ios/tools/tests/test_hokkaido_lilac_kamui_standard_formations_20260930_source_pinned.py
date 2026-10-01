"""Source-pinned standard formation overlay for all dated Lilac and Kamui trips."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-lilac-kamui-standard-formations-20260930'
EXPECTED_NUMBERS = {
    'lilac': {
        '3001M': '1', '3002M': '2', '3003M': '3', '3005M': '5', '3008M': '8',
        '3011M': '11', '3012M': '12', '3013M': '13', '3014M': '14',
        '3016M': '16', '3017M': '17', '3020M': '20', '3022M': '22',
        '3023M': '23', '3024M': '24', '3025M': '25', '3027M': '27',
        '3032M': '32', '3033M': '33', '3034M': '34', '3037M': '37',
        '3038M': '38', '3039M': '39', '3041M': '41', '3044M': '44',
        '3046M': '46',
    },
    'kamui': {
        '2004M': '4', '2006M': '6', '2007M': '7', '2010M': '10',
        '2018M': '18', '2019M': '19', '2021M': '21', '2028M': '28',
        '2029M': '29', '2030M': '30', '2031M': '31', '2035M': '35',
        '2040M': '40', '2042M': '42', '2043M': '43', '2045M': '45',
    },
}


def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class HokkaidoLilacKamuiStandardFormationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / f'candidates/jr-{SUFFIX}.json').read_text(encoding='utf-8'))
        cls.formations = [row for path in BASE.glob('normalized/trip-formations/*/*.jsonl')
                          for row in records(path)]
        cls.by_trip = {}
        for row in cls.formations:
            cls.by_trip.setdefault(row['trip_id'], []).append(row)

    def test_candidate_is_closed_26_lilac_16_kamui_inventory(self):
        actual = {}
        for family, family_row in self.candidate['families'].items():
            actual[family] = {row['train_number']: row['public_number']
                              for row in family_row['trains']}
        self.assertEqual(actual, EXPECTED_NUMBERS)
        self.assertEqual(sum(map(len, actual.values())), 42)

    def test_every_existing_formation_has_standard_planned_fields(self):
        for family, trains in EXPECTED_NUMBERS.items():
            for number, public in trains.items():
                tid = f'jr-hokkaido.{family}.{public}.exact-2026-09-30'
                self.assertEqual(len(self.by_trip.get(tid, [])), 1, number)
                row = self.by_trip[tid][0]
                expected = (('789系0代', 6, True) if family == 'lilac'
                            else ('789系1000代', 5, None))
                self.assertEqual((row['vehicle_series'], row['car_count'],
                                  row['green_car_available']), expected, number)
                self.assertTrue(row['all_reserved'])
                self.assertEqual(row['evidence_kind'], 'planned')
                marker = 'does not prove the actual 2026-09-30 dispatch'
                self.assertEqual(row['notes'].count(marker), 1, number)

    def test_sources_and_84_partial_field_facts_are_pinned(self):
        sources = records(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual({row['url_or_locator'] for row in sources}, {
            'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110',
            'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111',
            'https://www.jrhokkaido.co.jp/train/tr033_01.html',
            'https://www.jrhokkaido.co.jp/train/tr013_01.html',
        })
        self.assertEqual({row['issue'] for row in sources
                          if row['source_type'] == 'official_timetable'},
                         {'JR時刻表 令和8年10月号'})
        facts = records(BASE / f'normalized/fact-sources-{SUFFIX}.jsonl')
        expected_ids = {f'jr-hokkaido.{family}.{public}.exact-2026-09-30'
                        for family, trains in EXPECTED_NUMBERS.items()
                        for public in trains.values()}
        self.assertEqual(len(facts), 84)
        self.assertEqual({row['entity_id'] for row in facts}, expected_ids)
        self.assertEqual({row['field_name'] for row in facts},
                         {'formation.vehicle_series', 'formation.car_count'})
        self.assertTrue(all(row['verification_status'] == 'partial'
                            and row['confidence'] == 'medium' for row in facts))

    def test_no_duplicate_trip_or_timetable_rows_created(self):
        for directory in ('trips', 'stop-times', 'calendars', 'calendar-exceptions'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
