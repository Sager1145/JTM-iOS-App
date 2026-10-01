"""Source-pinned checks for three dated JR Hokkaido s=110 columns."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s110-sarobetsu1-okhotsk3-lilac33-20260930'
SOURCE = 'jr-' + SUFFIX
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110'
PRINTED = {
    '61D': [('旭川', None, '13:35'), ('和寒', None, '14:04'),
            ('士別', None, '14:15'), ('名寄', None, '14:31'),
            ('美深', None, '14:51'), ('音威子府', None, '15:25'),
            ('天塩中川', None, '15:56'), ('幌延', None, '16:30'),
            ('豊富', None, '16:44'), ('南稚内', None, '17:21'),
            ('稚内', '17:25', None)],
    '73D': [('札幌', None, '15:30'), ('岩見沢', None, '15:57'),
            ('美唄', None, '16:09'), ('砂川', None, '16:22'),
            ('滝川', None, '16:28'), ('深川', None, '16:43'),
            ('旭川', '17:05', '17:08'), ('上川', None, '17:54'),
            ('白滝', None, '18:30'), ('丸瀬布', None, '18:48'),
            ('遠軽', None, '19:08'), ('生田原', None, '19:24'),
            ('留辺蘂', None, '19:44'), ('北見', None, '20:02'),
            ('美幌', None, '20:25'), ('女満別', None, '20:36'),
            ('網走', '20:52', None)],
    '3033M': [('札幌', None, '17:30'), ('岩見沢', None, '17:55'),
              ('美唄', None, '18:06'), ('砂川', None, '18:17'),
              ('滝川', None, '18:22'), ('深川', None, '18:36'),
              ('旭川', '18:55', None)],
}


def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class HokkaidoS110ThreeTrainsTests(unittest.TestCase):
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
                             ('2026-09-30', '毎日', URL, SOURCE))
        self.assertEqual(sum(map(len, PRINTED.values())), 35)
        self.assertEqual(self.trips['61D']['pass_through_names'], ['比布', '剣淵'])
        self.assertEqual(self.trips['73D']['stops'][6], ['旭川', '17:05', '17:08'])

    def test_staged_stops_platforms_and_numbers(self):
        by_id = {r['trip_id']: r for r in self.staged_trips}
        self.assertEqual(len(by_id), 3)
        self.assertEqual(len(self.staged_stops), 35)
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
        self.assertEqual((len(sources), sources[0]['url_or_locator'], sources[0]['effective_date']),
                         (1, URL, '2026-09-30'))
        calendars = records(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exceptions = records(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(calendars), 3)
        self.assertEqual({(r['valid_from'], r['valid_until']) for r in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({r['service_date'] for r in exceptions}, {'2026-09-30'})
        formations = records(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        by_number = {self.trips[number]['trip_id']: number for number in PRINTED}
        self.assertEqual({by_number[r['trip_id']]: (r['all_reserved'], r.get('green_car_available'),
                                                      r.get('car_count'), r.get('vehicle_series'))
                          for r in formations},
                         {'61D': (True, True, None, None),
                          '73D': (True, None, None, None),
                          '3033M': (True, True, 6, '789系0代')})
        for directory in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
