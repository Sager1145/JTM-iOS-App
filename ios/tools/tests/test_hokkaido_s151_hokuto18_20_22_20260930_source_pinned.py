"""Source-pinned checks for three dated JR Hokkaido s=151 Hokuto columns."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s151-hokuto18-20-22-20260930'
SOURCE = 'jr-' + SUFFIX
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151'
PRINTED = {
    '18D': [('札幌', None, '15:45'), ('新札幌', None, '15:53'),
            ('南千歳', None, '16:17'), ('苫小牧', None, '16:33'),
            ('白老', None, '16:47'), ('登別', None, '16:58'),
            ('東室蘭', '17:10', '17:11'), ('伊達紋別', None, '17:27'),
            ('洞爺', None, '17:38'), ('長万部', None, '18:04'),
            ('八雲', None, '18:23'), ('森', None, '18:46'),
            ('新函館北斗', None, '19:14'), ('五稜郭', None, '19:25'),
            ('函館', '19:29', None)],
    '20D': [('札幌', None, '16:51'), ('新札幌', None, '17:02'),
            ('南千歳', None, '17:26'), ('苫小牧', None, '17:43'),
            ('白老', None, '17:56'), ('登別', None, '18:08'),
            ('東室蘭', '18:20', '18:21'), ('伊達紋別', None, '18:37'),
            ('洞爺', None, '18:48'), ('長万部', None, '19:15'),
            ('八雲', None, '19:35'), ('森', None, '19:57'),
            ('新函館北斗', None, '20:24'), ('五稜郭', None, '20:34'),
            ('函館', '20:39', None)],
    '22D': [('札幌', None, '18:46'), ('新札幌', None, '18:54'),
            ('南千歳', None, '19:18'), ('苫小牧', None, '19:34'),
            ('白老', None, '19:48'), ('登別', None, '19:59'),
            ('東室蘭', '20:11', '20:12'), ('伊達紋別', None, '20:29'),
            ('洞爺', None, '20:39'), ('長万部', None, '21:05'),
            ('八雲', None, '21:25'), ('森', None, '21:48'),
            ('新函館北斗', None, '22:15'), ('五稜郭', None, '22:27'),
            ('函館', '22:31', None)],
}
PLATFORMS = {'18D': '(7)', '20D': '(8)', '22D': '(8)'}


def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class HokkaidoS151Hokuto18To22Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(
            (BASE / f'candidates/jr-{SUFFIX}.json').read_text(encoding='utf-8'))
        cls.trips = {row['train_number']: row for row in cls.candidate['trips']}
        cls.staged_trips = records(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        cls.staged_stops = records(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')

    def test_exact_selected_date_all_printed_clocks_and_markers(self):
        self.assertEqual(set(self.trips), set(PRINTED))
        for number, expected in PRINTED.items():
            trip = self.trips[number]
            self.assertEqual(trip['stops'], [list(row) for row in expected])
            self.assertEqual((trip['service_date'], trip['operating_day_marker'],
                              trip['source_url'], trip['source_id']),
                             ('2026-09-30', '毎日', URL, SOURCE + '-up'))
            self.assertEqual(trip['printed_platforms'], {'札幌': PLATFORMS[number]})
            self.assertEqual(trip['formation_icons'],
                             ['greensiteidai0.png', 'zensekisitei0.png'])
        self.assertEqual(sum(map(len, PRINTED.values())), 45)

    def test_staged_stops_platforms_internal_numbers_and_public_numbers(self):
        by_id = {row['trip_id']: row for row in self.staged_trips}
        self.assertEqual(len(by_id), 3)
        self.assertEqual(len(self.staged_stops), 45)
        for number, candidate in self.trips.items():
            trip_id = candidate['trip_id']
            self.assertEqual((by_id[trip_id]['train_number'], by_id[trip_id]['public_number']),
                             (number, number.removesuffix('D')))
            actual = sorted((row for row in self.staged_stops if row['trip_id'] == trip_id),
                            key=lambda row: row['stop_sequence'])
            self.assertEqual([(row['arrival_time'], row['departure_time']) for row in actual],
                             [(arrival, departure)
                              for _, arrival, departure in PRINTED[number]])
            self.assertEqual([row['platform'] for row in actual],
                             [PLATFORMS[number]] + [None] * 14)

    def test_sources_calendars_and_planned_standard_formation(self):
        sources = records(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual({row['source_id']: row['url_or_locator'] for row in sources}, {
            SOURCE + '-up': URL,
            SOURCE + '-train-guide': 'https://www.jrhokkaido.co.jp/train/tr003_01.html',
        })
        timetable_source = next(row for row in sources if row['source_id'] == SOURCE + '-up')
        self.assertEqual(timetable_source['issue'], 'JR時刻表 令和8年10月号')
        calendars = records(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exceptions = records(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(calendars), 3)
        self.assertEqual({(row['valid_from'], row['valid_until']) for row in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({row['service_date'] for row in exceptions}, {'2026-09-30'})
        formations = records(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(formations), 3)
        for formation in formations:
            self.assertEqual((formation['evidence_kind'], formation['all_reserved'],
                              formation['green_car_available'], formation['vehicle_series'],
                              formation.get('car_count')),
                             ('planned', True, True, 'キハ261系1000代', None))
            self.assertIn('not confirmation of the actual vehicle dispatched', formation['notes'])
        facts = records(BASE / f'normalized/fact-sources-{SUFFIX}.jsonl')
        vehicle_facts = [row for row in facts if row['field_name'] == 'formation.vehicle_series']
        self.assertEqual(len(vehicle_facts), 3)
        self.assertEqual({row['source_id'] for row in vehicle_facts}, {SOURCE + '-train-guide'})
        for directory in ('trip-lines', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
