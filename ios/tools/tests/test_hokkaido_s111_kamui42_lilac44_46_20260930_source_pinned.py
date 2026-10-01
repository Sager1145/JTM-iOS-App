"""Source-pinned checks for three JR Hokkaido 2026-09-30 s=111 columns."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s111-kamui42-lilac44-46-20260930'
SOURCE = 'jr-' + SUFFIX
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111'
PRINTED = {
    '2042M': (
        'kamui', '42', {'札幌': '(2)'}, False,
        [('旭川', None, '20:00'), ('深川', None, '20:19'),
         ('滝川', None, '20:32'), ('砂川', None, '20:38'),
         ('美唄', None, '20:50'), ('岩見沢', None, '21:00'),
         ('札幌', '21:25', None)]),
    '3044M': (
        'lilac', '44', {'札幌': '(3)'}, True,
        [('旭川', None, '21:00'), ('深川', None, '21:19'),
         ('滝川', None, '21:32'), ('砂川', None, '21:38'),
         ('美唄', None, '21:50'), ('岩見沢', None, '22:00'),
         ('札幌', '22:25', None)]),
    '3046M': (
        'lilac', '46', {'札幌': '(3)'}, True,
        [('旭川', None, '22:00'), ('深川', None, '22:19'),
         ('滝川', None, '22:33'), ('砂川', None, '22:38'),
         ('美唄', None, '22:50'), ('岩見沢', None, '23:00'),
         ('札幌', '23:25', None)]),
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class HokkaidoS111FinalThreeColumnsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / f'candidates/jr-{SUFFIX}.json').read_text(encoding='utf-8'))
        cls.trips = {r['train_number']: r for r in cls.candidate['trips']}
        cls.staged_trips = rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        cls.staged_stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')

    def test_exact_selected_date_and_printed_stop_chain(self):
        self.assertEqual(set(self.trips), set(PRINTED))
        for number, (service, public, platform, green, stops) in PRINTED.items():
            trip = self.trips[number]
            self.assertEqual((trip['service_id'], trip['public_number'], trip['service_date'],
                              trip['operating_day_marker'], trip['source_url'], trip['source_id']),
                             (service, public, '2026-09-30', '毎日', URL, SOURCE))
            self.assertEqual(trip['stops'], [list(s) for s in stops])
            self.assertEqual(trip['printed_platforms'], platform)
            self.assertEqual(trip['formation_icons'],
                             ['greensiteidai0.png', 'zensekisitei0.png'] if green
                             else ['zensekisitei0.png'])

    def test_staged_clocks_platforms_and_train_numbers(self):
        self.assertEqual(len(self.staged_trips), 3)
        self.assertEqual(len(self.staged_stops), 21)
        for number, (_, public, platforms, _, expected) in PRINTED.items():
            trip = self.trips[number]
            staged = next(r for r in self.staged_trips if r['trip_id'] == trip['trip_id'])
            self.assertEqual((staged['train_number'], staged['public_number']), (number, public))
            actual = sorted((r for r in self.staged_stops if r['trip_id'] == trip['trip_id']),
                            key=lambda r: r['stop_sequence'])
            self.assertEqual([(r['arrival_time'], r['departure_time'], r['platform']) for r in actual],
                             [(arrival, departure, platforms.get(name))
                              for name, arrival, departure in expected])

    def test_source_calendar_formation_and_unknown_routes(self):
        source = rows(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual((len(source), source[0]['url_or_locator'], source[0]['effective_date']),
                         (1, URL, '2026-09-30'))
        calendars = rows(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exceptions = rows(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(calendars), 3)
        self.assertEqual({(r['valid_from'], r['valid_until']) for r in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({r['service_date'] for r in exceptions}, {'2026-09-30'})
        formations = rows(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        by_trip = {trip['trip_id']: number for number, trip in self.trips.items()}
        self.assertEqual({by_trip[r['trip_id']]: (r['all_reserved'], r.get('green_car_available'),
                                                  r.get('car_count'), r.get('vehicle_series'))
                          for r in formations},
                         {'2042M': (True, None, 5, '789系1000代'),
                          '3044M': (True, True, 6, '789系0代'),
                          '3046M': (True, True, 6, '789系0代')})
        for kind in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{kind}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
