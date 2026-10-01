"""Source-pinned checks for four dated JR Hokkaido s=110 Kamui columns."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s110-kamui31-35-43-45-20260930'
SOURCE = 'jr-' + SUFFIX
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110'
PRINTED = {
    '2031M': [('札幌', None, '17:00'), ('岩見沢', None, '17:25'),
              ('美唄', None, '17:36'), ('砂川', None, '17:47'),
              ('滝川', None, '17:52'), ('深川', None, '18:06'),
              ('旭川', '18:25', None)],
    '2035M': [('札幌', None, '18:00'), ('岩見沢', None, '18:25'),
              ('美唄', None, '18:36'), ('砂川', None, '18:47'),
              ('滝川', None, '18:52'), ('深川', None, '19:06'),
              ('旭川', '19:25', None)],
    '2043M': [('札幌', None, '21:00'), ('岩見沢', None, '21:25'),
              ('美唄', None, '21:36'), ('砂川', None, '21:47'),
              ('滝川', None, '21:52'), ('深川', None, '22:06'),
              ('旭川', '22:25', None)],
    '2045M': [('札幌', None, '22:00'), ('岩見沢', None, '22:25'),
              ('美唄', None, '22:36'), ('砂川', None, '22:47'),
              ('滝川', None, '22:52'), ('深川', None, '23:06'),
              ('旭川', '23:25', None)],
}


def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class HokkaidoS110FourKamuiTests(unittest.TestCase):
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
        self.assertEqual(sum(map(len, PRINTED.values())), 28)
        self.assertTrue(all(r['pass_through_names'] == [] for r in self.trips.values()))
        self.assertEqual({number: trip['printed_platforms']['札幌']
                          for number, trip in self.trips.items()},
                         {'2031M': '(8)', '2035M': '(9)',
                          '2043M': '(9)', '2045M': '(9)'})
        self.assertTrue(all(trip['formation_icons'] == ['zensekisitei0.png']
                            for trip in self.trips.values()))

    def test_staged_stops_platforms_and_numbers(self):
        by_id = {r['trip_id']: r for r in self.staged_trips}
        self.assertEqual(len(by_id), 4)
        self.assertEqual(len(self.staged_stops), 28)
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
        self.assertEqual(len(calendars), 4)
        self.assertEqual({(r['valid_from'], r['valid_until']) for r in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({r['service_date'] for r in exceptions}, {'2026-09-30'})
        formations = records(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        by_number = {self.trips[number]['trip_id']: number for number in PRINTED}
        self.assertEqual({by_number[r['trip_id']]: (r['all_reserved'], r.get('green_car_available'),
                                                      r.get('car_count'), r.get('vehicle_series'))
                          for r in formations},
                         {number: (True, None, 5, '789系1000代') for number in PRINTED})
        for directory in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
