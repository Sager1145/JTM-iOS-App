"""Printed s=151 Suzuran columns on JR Hokkaido's selected 2026-09-30 page."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s151-suzuran4-6-8-10-12-20260930'
SOURCE = 'jr-' + SUFFIX
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151'
STATIONS = ('札幌', '新札幌', '千歳', '南千歳', '沼ノ端', '苫小牧', '白老', '登別',
            '幌別', '鷲別', '東室蘭', '輪西', '御崎', '母恋', '室蘭')
PRINTED = {
    '1004M': ('4', '(9)', '09:21 09:30 09:53 09:57 10:08 10:14 10:28 10:40 '
                         '10:46 10:51 10:54/10:55 10:58 11:01 11:04 11:06'),
    '1006M': ('6', '(7)', '13:46 13:54 14:14 14:18 14:30 14:37 14:51 15:03 '
                         '15:09 15:15 15:18/15:19 15:22 15:25 15:28 15:30'),
    '1008M': ('8', '(7)', '16:07 16:15 16:36 16:39 16:50 16:57 17:10 17:22 '
                         '17:28 17:34 17:36/17:37 17:41 17:44 17:46 17:49'),
    '1010M': ('10', '(7)', '19:14 19:23 19:45 19:48 20:00 20:07 20:23 20:36 '
                          '20:42 20:48 20:51/20:52 20:55 20:58 21:01 21:03'),
    '1012M': ('12', '(9)', '21:12 21:20 21:39 21:43 21:54 22:01 22:14 22:26 '
                          '22:31 22:37 22:39/22:41 22:44 22:47 22:50 22:52'),
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


def expected_stops(clocks):
    times = clocks.split()
    assert len(times) == len(STATIONS)
    result = []
    for index, (name, clock) in enumerate(zip(STATIONS, times)):
        if index == 0:
            result.append([name, None, clock])
        elif index == 10:
            arrival, departure = clock.split('/')
            result.append([name, arrival, departure])
        elif index == len(STATIONS) - 1:
            result.append([name, clock, None])
        else:
            result.append([name, None, clock])
    return result


class HokkaidoS151SuzuranFiveColumnsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / f'candidates/jr-{SUFFIX}.json').read_text(encoding='utf-8'))
        cls.trips = {r['train_number']: r for r in cls.candidate['trips']}
        cls.staged_trips = rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        cls.staged_stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')

    def test_printed_clocks_platforms_and_icons(self):
        self.assertEqual(set(self.trips), set(PRINTED))
        for number, (public, platform, clocks) in PRINTED.items():
            trip = self.trips[number]
            self.assertEqual((trip['service_id'], trip['service_name'], trip['public_number'],
                              trip['service_date'], trip['operating_day_marker'],
                              trip['source_id'], trip['source_url']),
                             ('suzuran', 'すずらん', public, '2026-09-30', '毎日', SOURCE, URL))
            self.assertEqual((trip['origin'], trip['destination']), ('札幌', '室蘭'))
            self.assertEqual(trip['stops'], expected_stops(clocks))
            self.assertEqual(trip['printed_platforms'], {'札幌': platform})
            self.assertEqual(trip['formation_icons'], ['zensekisitei0.png'])
            self.assertEqual(trip['pass_through_names'], [])

    def test_staged_train_numbers_and_stop_fields(self):
        self.assertEqual(len(self.staged_trips), 5)
        self.assertEqual(len(self.staged_stops), 75)
        for number, (public, platform, clocks) in PRINTED.items():
            trip = self.trips[number]
            staged = next(r for r in self.staged_trips if r['trip_id'] == trip['trip_id'])
            self.assertEqual((staged['train_number'], staged['public_number']), (number, public))
            actual = sorted((r for r in self.staged_stops if r['trip_id'] == trip['trip_id']),
                            key=lambda r: r['stop_sequence'])
            expected = expected_stops(clocks)
            self.assertEqual([(r['arrival_time'], r['departure_time'], r['platform']) for r in actual],
                             [(arrival, departure, platform if name == '札幌' else None)
                              for name, arrival, departure in expected])

    def test_source_calendar_formation_and_unknown_route(self):
        source = rows(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual((len(source), source[0]['url_or_locator'], source[0]['effective_date']),
                         (1, URL, '2026-09-30'))
        calendars = rows(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exceptions = rows(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(calendars), 5)
        self.assertEqual({(r['valid_from'], r['valid_until']) for r in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({r['service_date'] for r in exceptions}, {'2026-09-30'})
        formations = rows(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(formations), 5)
        self.assertEqual({r['trip_id'] for r in formations},
                         {trip['trip_id'] for trip in self.trips.values()})
        self.assertTrue(all(r['all_reserved'] is True
                            and r['green_car_available'] is None
                            and r.get('car_count') == (5 if self.trips['1012M']['trip_id'] == r['trip_id'] else None)
                            and r.get('vehicle_series') is None for r in formations))
        for kind in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{kind}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
