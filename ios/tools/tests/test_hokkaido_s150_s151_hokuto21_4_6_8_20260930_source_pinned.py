"""Source-pinned checks for four dated JR Hokkaido s=150/151 Hokuto columns."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s150-s151-hokuto21-4-6-8-20260930'
SOURCE = 'jr-' + SUFFIX
URLS = {'21D': 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=150',
        **{number: 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151'
           for number in ('4D', '6D', '8D')}}
PRINTED = {'21D': [('函館', None, '18:43'),
         ('五稜郭', None, '18:48'),
         ('新函館北斗', None, '19:01'),
         ('森', None, '19:33'),
         ('八雲', None, '19:54'),
         ('長万部', None, '20:14'),
         ('洞爺', None, '20:40'),
         ('伊達紋別', None, '20:51'),
         ('東室蘭', '21:07', '21:08'),
         ('登別', None, '21:21'),
         ('苫小牧', None, '21:48'),
         ('南千歳', None, '22:06'),
         ('新札幌', None, '22:32'),
         ('札幌', '22:41', None)],
 '4D': [('札幌', None, '06:53'),
        ('新札幌', None, '07:02'),
        ('南千歳', None, '07:23'),
        ('苫小牧', None, '07:40'),
        ('登別', None, '08:03'),
        ('東室蘭', '08:15', '08:16'),
        ('伊達紋別', None, '08:33'),
        ('洞爺', None, '08:43'),
        ('長万部', None, '09:10'),
        ('八雲', None, '09:30'),
        ('森', None, '09:53'),
        ('大沼公園', None, '10:12'),
        ('新函館北斗', None, '10:24'),
        ('五稜郭', None, '10:34'),
        ('函館', '10:38', None)],
 '6D': [('札幌', None, '08:43'),
        ('新札幌', None, '08:51'),
        ('南千歳', None, '09:12'),
        ('苫小牧', None, '09:28'),
        ('白老', None, '09:42'),
        ('登別', None, '09:54'),
        ('東室蘭', '10:07', '10:08'),
        ('伊達紋別', None, '10:27'),
        ('洞爺', None, '10:39'),
        ('長万部', None, '11:06'),
        ('八雲', None, '11:26'),
        ('森', None, '11:49'),
        ('大沼公園', None, '12:07'),
        ('新函館北斗', None, '12:18'),
        ('五稜郭', None, '12:28'),
        ('函館', '12:33', None)],
 '8D': [('札幌', None, '09:45'),
        ('新札幌', None, '09:54'),
        ('南千歳', None, '10:16'),
        ('苫小牧', None, '10:34'),
        ('白老', None, '10:48'),
        ('登別', None, '11:00'),
        ('東室蘭', '11:11', '11:12'),
        ('伊達紋別', None, '11:28'),
        ('洞爺', None, '11:39'),
        ('長万部', None, '12:05'),
        ('八雲', None, '12:25'),
        ('森', None, '12:47'),
        ('大沼公園', None, '13:09'),
        ('新函館北斗', None, '13:19'),
        ('五稜郭', None, '13:31'),
        ('函館', '13:35', None)]}

def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class HokkaidoS150S151FourHokutoTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / f'candidates/jr-{SUFFIX}.json').read_text(encoding='utf-8'))
        cls.trips = {r['train_number']: r for r in cls.candidate['trips']}
        cls.staged_trips = records(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        cls.staged_stops = records(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')

    def test_exact_selected_date_and_all_printed_clocks(self):
        self.assertEqual(set(self.trips), set(PRINTED))
        for number, expected in PRINTED.items():
            trip = self.trips[number]
            self.assertEqual(trip['stops'], [list(row) for row in expected])
            self.assertEqual((trip['service_date'], trip['operating_day_marker'],
                              trip['source_url'], trip['source_id']),
                             ('2026-09-30', '毎日', URLS[number],
                              SOURCE + ('-down' if number == '21D' else '-up')))
        self.assertEqual(sum(map(len, PRINTED.values())), 61)
        self.assertEqual({number: trip['printed_platforms']['札幌']
                          for number, trip in self.trips.items()},
                         {'21D': '(3)', '4D': '(4)', '6D': '(7)', '8D': '(8)'})
        self.assertTrue(all(trip['formation_icons'] == ['greensiteidai0.png', 'zensekisitei0.png']
                            for trip in self.trips.values()))

    def test_staged_stops_platforms_and_numbers(self):
        by_id = {r['trip_id']: r for r in self.staged_trips}
        self.assertEqual(len(by_id), 4)
        self.assertEqual(len(self.staged_stops), 61)
        for number, candidate in self.trips.items():
            tid = candidate['trip_id']
            self.assertEqual(by_id[tid]['train_number'], number)
            actual = sorted((r for r in self.staged_stops if r['trip_id'] == tid),
                            key=lambda r: r['stop_sequence'])
            self.assertEqual([(r['arrival_time'], r['departure_time']) for r in actual],
                             [(a, d) for _, a, d in PRINTED[number]])
            self.assertEqual([r['platform'] for r in actual],
                             [candidate['printed_platforms'].get(name) for name, _, _ in PRINTED[number]])

    def test_source_scope_formations_and_unknown_routes(self):
        sources = records(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual({r['source_id']: r['url_or_locator'] for r in sources},
                         {SOURCE + '-down': URLS['21D'],
                          SOURCE + '-up': URLS['4D'],
                          SOURCE + '-train-guide': 'https://www.jrhokkaido.co.jp/train/tr003_01.html'})
        calendars = records(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exceptions = records(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(calendars), 4)
        self.assertEqual({(r['valid_from'], r['valid_until']) for r in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({r['service_date'] for r in exceptions}, {'2026-09-30'})
        formations = records(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        by_number = {self.trips[number]['trip_id']: number for number in PRINTED}
        self.assertEqual({by_number[r['trip_id']]: (r['all_reserved'], r.get('green_car_available'),
                                                      r.get('car_count'), r.get('vehicle_series'))
                          for r in formations},
                         {number: (True, True, None, 'キハ261系1000代') for number in PRINTED})
        facts = records(BASE / f'normalized/fact-sources-{SUFFIX}.jsonl')
        self.assertEqual({r['entity_id'] for r in facts
                          if r['field_name'] == 'formation.vehicle_series'},
                         {self.trips[number]['trip_id'] for number in PRINTED})
        self.assertEqual({r['source_id'] for r in facts
                          if r['field_name'] == 'formation.vehicle_series'},
                         {SOURCE + '-train-guide'})
        for directory in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
