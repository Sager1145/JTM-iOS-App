"""Printed s=151 Hokuto 10/12/14/16 columns on JR Hokkaido's 2026-09-30 page."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s151-hokuto10-12-14-16-20260930'
SOURCE = 'jr-' + SUFFIX
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151'
STATIONS = ('札幌', '新札幌', '南千歳', '苫小牧', '白老', '登別', '東室蘭',
            '伊達紋別', '洞爺', '長万部', '八雲', '森', '大沼公園',
            '新函館北斗', '五稜郭', '函館')
PRINTED = {
    '10D': ('10', '10:56 11:05 11:27 11:44 11:57 12:09 12:21/12:23 12:40 '
                  '12:50 13:16 13:36 13:58 14:16 14:26 14:36 14:40'),
    '12D': ('12', '12:09 12:19 12:46 13:02 13:16 13:28 13:39/13:41 13:57 '
                  '14:08 14:37 14:58 15:20 15:43 15:53 16:04 16:08'),
    '14D': ('14', '13:26 13:34 13:58 14:16 14:29 14:41 14:52/14:54 15:10 '
                  '15:21 15:47 16:07 16:30 16:48 16:59 17:09 17:13'),
    '16D': ('16', '14:46 14:54 15:17 15:34 15:47 15:59 16:11/16:12 16:28 '
                  '16:38 17:04 17:24 17:46 18:04 18:15 18:26 18:30'),
}


def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


def expected_stops(clocks):
    times = clocks.split()
    assert len(times) == len(STATIONS)
    result = []
    for index, (name, clock) in enumerate(zip(STATIONS, times)):
        if index == 0:
            result.append([name, None, clock])
        elif index == 6:
            arrival, departure = clock.split('/')
            result.append([name, arrival, departure])
        elif index == len(STATIONS) - 1:
            result.append([name, clock, None])
        else:
            result.append([name, None, clock])
    return result


class HokkaidoS151HokutoFourColumnsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / f'candidates/jr-{SUFFIX}.json').read_text(encoding='utf-8'))
        cls.trips = {r['train_number']: r for r in cls.candidate['trips']}
        cls.staged_trips = records(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        cls.staged_stops = records(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')

    def test_printed_clocks_platforms_day_and_icons(self):
        self.assertEqual(self.candidate['source_issue'], 'JR時刻表 令和8年10月号')
        self.assertEqual(set(self.trips), set(PRINTED))
        for number, (public, clocks) in PRINTED.items():
            trip = self.trips[number]
            self.assertEqual((trip['service_id'], trip['service_name'], trip['public_number'],
                              trip['service_date'], trip['operating_day_marker'],
                              trip['source_id'], trip['source_url']),
                             ('hokuto', '北斗', public, '2026-09-30', '毎日', SOURCE, URL))
            self.assertEqual((trip['origin'], trip['destination']), ('札幌', '函館'))
            self.assertEqual(trip['stops'], expected_stops(clocks))
            self.assertEqual(trip['printed_platforms'], {'札幌': '(8)'})
            self.assertEqual(trip['formation_icons'],
                             ['greensiteidai0.png', 'zensekisitei0.png'])
        self.assertEqual(sum(len(expected_stops(clocks)) for _, clocks in PRINTED.values()), 64)

    def test_staged_internal_numbers_stops_and_platforms(self):
        self.assertEqual(len(self.staged_trips), 4)
        self.assertEqual(len(self.staged_stops), 64)
        for number, (public, clocks) in PRINTED.items():
            trip = self.trips[number]
            staged = next(r for r in self.staged_trips if r['trip_id'] == trip['trip_id'])
            self.assertEqual((staged['train_number'], staged['public_number']), (number, public))
            actual = sorted((r for r in self.staged_stops if r['trip_id'] == trip['trip_id']),
                            key=lambda r: r['stop_sequence'])
            expected = expected_stops(clocks)
            self.assertEqual([(r['arrival_time'], r['departure_time'], r['platform'])
                              for r in actual],
                             [(arrival, departure, '(8)' if name == '札幌' else None)
                              for name, arrival, departure in expected])

    def test_source_calendar_standard_formation_and_unknown_routes(self):
        sources = records(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual({r['source_id']: r['url_or_locator'] for r in sources},
                         {SOURCE: URL,
                          SOURCE + '-train-guide':
                              'https://www.jrhokkaido.co.jp/train/tr003_01.html'})
        timetable_source = next(r for r in sources if r['source_id'] == SOURCE)
        self.assertEqual((timetable_source['issue'], timetable_source['effective_date']),
                         ('JR時刻表 令和8年10月号', '2026-09-30'))
        self.assertIn('earlier search cache rendered 9月号', timetable_source['notes'])
        calendars = records(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exceptions = records(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(calendars), 4)
        self.assertEqual({(r['valid_from'], r['valid_until']) for r in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({r['service_date'] for r in exceptions}, {'2026-09-30'})
        formations = records(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(formations), 4)
        self.assertTrue(all(r['all_reserved'] is True
                            and r['green_car_available'] is True
                            and r.get('car_count') is None
                            and r['vehicle_series'] == 'キハ261系1000代'
                            for r in formations))
        facts = records(BASE / f'normalized/fact-sources-{SUFFIX}.jsonl')
        self.assertEqual({r['source_id'] for r in facts
                          if r['field_name'] == 'formation.vehicle_series'},
                         {SOURCE + '-train-guide'})
        queue = records(BASE / f'normalized/research-queue-{SUFFIX}.jsonl')
        self.assertEqual({r['missing_dimension'] for r in queue},
                         {'times', 'formation', 'operator', 'route_lines', 'provenance'})
        for directory in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
