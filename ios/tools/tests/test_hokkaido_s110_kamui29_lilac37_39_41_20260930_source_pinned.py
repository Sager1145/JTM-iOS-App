"""Source-pinned checks for four selected-day JR Hokkaido s=110 columns."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s110-kamui29-lilac37-39-41-20260930'
SOURCE = 'jr-' + SUFFIX
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110'
STATIONS = ('札幌', '岩見沢', '美唄', '砂川', '滝川', '深川', '旭川')
PRINTED = {
    '2029M': ('kamui', '29', '(9)', False,
              ('16:30', '16:55', '17:06', '17:17', '17:22', '17:36', '17:55')),
    '3037M': ('lilac', '37', '(9)', True,
              ('18:30', '18:55', '19:06', '19:17', '19:22', '19:36', '19:55')),
    '3039M': ('lilac', '39', '(9)', True,
              ('19:00', '19:25', '19:36', '19:47', '19:52', '20:06', '20:25')),
    '3041M': ('lilac', '41', '(10)', True,
              ('20:00', '20:25', '20:36', '20:47', '20:52', '21:06', '21:25')),
}


def records(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class HokkaidoS110LateColumnsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / f'candidates/jr-{SUFFIX}.json').read_text(encoding='utf-8'))
        cls.trips = {r['train_number']: r for r in cls.candidate['trips']}
        cls.staged_trips = records(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        cls.staged_stops = records(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')

    def test_exact_selected_date_and_all_printed_clocks(self):
        self.assertEqual(set(self.trips), set(PRINTED))
        for number, (service, public, platform, green, clocks) in PRINTED.items():
            trip = self.trips[number]
            self.assertEqual((trip['service_id'], trip['public_number'],
                              trip['service_date'], trip['operating_day_marker']),
                             (service, public, '2026-09-30', '毎日'))
            self.assertEqual((trip['source_id'], trip['source_url'], trip['printed_platforms']),
                             (SOURCE, URL, {'札幌': platform}))
            self.assertEqual(trip['stops'], [[name, time if i == 6 else None,
                                              time if i < 6 else None]
                                             for i, (name, time) in enumerate(zip(STATIONS, clocks))])
            self.assertEqual(trip['formation_icons'],
                             ['greensiteidai0.png', 'zensekisitei0.png'] if green
                             else ['zensekisitei0.png'])

    def test_staged_train_numbers_stop_clocks_and_platforms(self):
        self.assertEqual(len(self.staged_trips), 4)
        self.assertEqual(len(self.staged_stops), 28)
        for number, (_, public, platform, _, clocks) in PRINTED.items():
            trip = self.trips[number]
            staged = next(r for r in self.staged_trips if r['trip_id'] == trip['trip_id'])
            self.assertEqual((staged['train_number'], staged['public_number']), (number, public))
            stops = sorted((r for r in self.staged_stops if r['trip_id'] == trip['trip_id']),
                           key=lambda r: r['stop_sequence'])
            self.assertEqual([(r['arrival_time'], r['departure_time']) for r in stops],
                             [(time if i == 6 else None, time if i < 6 else None)
                              for i, time in enumerate(clocks)])
            self.assertEqual([r['platform'] for r in stops], [platform] + [None] * 6)

    def test_source_scope_formations_and_unresolved_routes(self):
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
                         {'2029M': (True, None, 5, '789系1000代'),
                          '3037M': (True, True, 6, '789系0代'),
                          '3039M': (True, True, 6, '789系0代'),
                          '3041M': (True, True, 6, '789系0代')})
        for directory in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{directory}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
