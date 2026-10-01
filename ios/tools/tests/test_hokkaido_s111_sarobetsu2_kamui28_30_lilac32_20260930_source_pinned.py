"""Source-pinned checks for four JR Hokkaido 2026-09-30 s=111 columns."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s111-sarobetsu2-kamui28-30-lilac32-20260930'
SOURCE = 'jr-' + SUFFIX
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111'
PRINTED = {
    '62D': (
        'sarobetsu', '2', {}, True,
        [('稚内', None, '06:36'), ('南稚内', None, '06:40'),
         ('豊富', None, '07:18'), ('幌延', None, '07:32'),
         ('天塩中川', None, '08:06'), ('音威子府', None, '08:38'),
         ('美深', None, '09:04'), ('名寄', None, '09:25'),
         ('士別', None, '09:40'), ('和寒', None, '09:53'),
         ('旭川', '10:19', None)]),
    '2028M': (
        'kamui', '28', {'札幌': '(2)'}, False,
        [('旭川', None, '15:00'), ('深川', None, '15:19'),
         ('滝川', None, '15:32'), ('砂川', None, '15:38'),
         ('美唄', None, '15:50'), ('岩見沢', None, '16:00'),
         ('札幌', '16:25', None)]),
    '2030M': (
        'kamui', '30', {'札幌': '(5)'}, False,
        [('旭川', None, '16:00'), ('深川', None, '16:19'),
         ('滝川', None, '16:32'), ('砂川', None, '16:38'),
         ('美唄', None, '16:50'), ('岩見沢', None, '17:00'),
         ('札幌', '17:25', None)]),
    '3032M': (
        'lilac', '32', {'札幌': '(2)'}, True,
        [('旭川', None, '16:30'), ('深川', None, '16:49'),
         ('滝川', None, '17:02'), ('砂川', None, '17:08'),
         ('美唄', None, '17:20'), ('岩見沢', None, '17:30'),
         ('札幌', '17:55', None)]),
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class HokkaidoS111FourColumnsTests(unittest.TestCase):
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
        self.assertEqual(self.trips['62D']['pass_through_names'], ['剣淵', '比布'])

    def test_staged_clocks_platforms_and_train_numbers(self):
        self.assertEqual(len(self.staged_trips), 4)
        self.assertEqual(len(self.staged_stops), 32)
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
        self.assertEqual(len(calendars), 4)
        self.assertEqual({(r['valid_from'], r['valid_until']) for r in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({r['service_date'] for r in exceptions}, {'2026-09-30'})
        formations = rows(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        by_trip = {trip['trip_id']: number for number, trip in self.trips.items()}
        self.assertEqual({by_trip[r['trip_id']]: (r['all_reserved'], r.get('green_car_available'),
                                                  r.get('car_count'), r.get('vehicle_series'))
                          for r in formations},
                         {'62D': (True, True, None, None),
                          '2028M': (True, None, 5, '789系1000代'),
                          '2030M': (True, None, 5, '789系1000代'),
                          '3032M': (True, True, 6, '789系0代')})
        for kind in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{kind}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
