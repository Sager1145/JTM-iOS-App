"""Exact-date JR Kyushu Nichirin 10, 12 and 16 official detail checks."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-nichirin10-12-16-20260930'
URLS = {
    '5010M': 'https://www.jrkyushu-timetable.jp/sp/2610/0019/00193701.html?d=20260930&t=2890400',
    '5012M': 'https://www.jrkyushu-timetable.jp/sp/2610/0008/00087501.html?d=20260930&t=2890400',
    '5016M': 'https://www.jrkyushu-timetable.jp/sp/2610/0019/00193801.html?d=20260930&t=2890400',
}
PRINTED = {
    '5010M': ('10', '大分', ['グリーン車指定席', '普通車一部指定席'],
              [('宮崎空港', None, '12:15', None), ('南宮崎', '12:24', '12:25', None),
               ('宮崎', '12:29', '12:30', None), ('佐土原', '12:40', '12:40', None),
               ('高鍋', '12:55', '12:56', None), ('日向市', '13:20', '13:21', None),
               ('南延岡', '13:35', '13:38', None), ('延岡', '13:41', '13:45', None),
               ('佐伯', '14:40', '14:42', None), ('津久見', '15:00', '15:00', None),
               ('臼杵', '15:09', '15:10', None), ('鶴崎', '15:33', '15:34', None),
               ('大分', '15:41', None, '4')]),
    '5012M': ('12', '大分',
              ['ＤＸグリーンがあります', 'グリーン車指定席',
               'グリーン車指定席（４人用グリーン個室連結）', '普通車一部指定席'],
              [('宮崎空港', None, '14:15', None), ('南宮崎', '14:20', '14:25', None),
               ('宮崎', '14:29', '14:30', None), ('佐土原', '14:40', '14:40', None),
               ('高鍋', '14:54', '14:54', None), ('日向市', '15:20', '15:21', None),
               ('南延岡', '15:37', '15:38', None), ('延岡', '15:42', '15:43', None),
               ('佐伯', '16:40', '16:42', None), ('津久見', '17:01', '17:03', None),
               ('臼杵', '17:12', '17:13', None), ('鶴崎', '17:36', '17:36', None),
               ('大分', '17:43', None, '4')]),
    '5016M': ('16', '小倉', ['グリーン車指定席', '普通車一部指定席'],
              [('宮崎空港', None, '17:15', None), ('南宮崎', '17:20', '17:24', None),
               ('宮崎', '17:27', '17:30', None), ('佐土原', '17:40', '17:40', None),
               ('高鍋', '17:50', '17:51', None), ('都農', '18:01', '18:02', None),
               ('日向市', '18:20', '18:21', None), ('門川', '18:27', '18:28', None),
               ('南延岡', '18:36', '18:39', None), ('延岡', '18:42', '18:44', None),
               ('佐伯', '19:50', '19:51', None), ('津久見', '20:09', '20:10', None),
               ('臼杵', '20:19', '20:21', None), ('鶴崎', '20:45', '20:45', None),
               ('大分', '20:53', '20:55', '3'), ('別府', '21:04', '21:04', None),
               ('杵築', '21:19', '21:19', None), ('宇佐', '21:35', '21:36', None),
               ('柳ケ浦', '21:41', '21:41', None), ('中津', '21:52', '21:53', None),
               ('宇島', '21:58', '21:59', None), ('行橋', '22:11', '22:11', None),
               ('小倉', '22:27', None, '4')]),
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class KyushuNichirin101216SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / 'candidates/jr-kyushu-nichirin10-12-16-20260930.json').read_text(encoding='utf-8'))
        cls.trips = {trip['train_number']: trip for trip in cls.candidate['trips']}

    def test_selected_date_identity_clocks_platforms_and_seats(self):
        self.assertEqual((self.candidate['candidate_status'], self.candidate['service_date']),
                         ('reviewed_official_html', '2026-09-30'))
        self.assertEqual(set(self.trips), set(PRINTED))
        for number, (public, destination, seats, stops) in PRINTED.items():
            trip = self.trips[number]
            self.assertEqual((trip['trip_id'], trip['service_id'], trip['service_name'],
                              trip['public_number'], trip['service_class'], trip['source_id'],
                              trip['source_url'], trip['operating_day_marker'],
                              trip['origin'], trip['destination']),
                             (f'jr-kyushu.nichirin.{public}.2026-09-30', 'nichirin',
                              'にちりん', public, 'limited_express',
                              f'jr-kyushu-nichirin{public}-20260930', URLS[number],
                              '毎日運転', '宮崎空港', destination))
            self.assertEqual(trip['formation_seat_text'], seats)
            self.assertEqual(trip['stops'], [list(stop) for stop in stops])
        self.assertIn('１０月１３日・１１月１７日', self.trips['5012M']['source_note'])

    def test_staged_trip_stop_and_calendar_fields(self):
        staged_trips = rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        staged_stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        self.assertEqual((len(staged_trips), len(staged_stops)), (3, 49))
        for number, (public, _, _, stops) in PRINTED.items():
            trip = self.trips[number]
            staged = next(row for row in staged_trips if row['trip_id'] == trip['trip_id'])
            self.assertEqual((staged['train_number'], staged['public_number']), (number, public))
            actual = sorted((row for row in staged_stops if row['trip_id'] == trip['trip_id']),
                            key=lambda row: row['stop_sequence'])
            self.assertEqual([(row['arrival_time'], row['departure_time'], row['platform'])
                              for row in actual],
                             [(arrival, departure, platform) for _, arrival, departure, platform in stops])
        calendars = rows(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exceptions = rows(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(calendars), 3)
        self.assertEqual({(row['valid_from'], row['valid_until']) for row in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({row['service_date'] for row in exceptions}, {'2026-09-30'})

    def test_sources_formations_and_unknown_routes(self):
        sources = rows(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual({row['url_or_locator'] for row in sources}, set(URLS.values()))
        self.assertTrue(all(row['effective_date'] == '2026-09-30'
                            and row['automated_extraction_allowed'] is False for row in sources))
        formations = rows(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(formations), 3)
        for row in formations:
            number = next(number for number, trip in self.trips.items() if trip['trip_id'] == row['trip_id'])
            self.assertEqual((row['all_reserved'], row['green_car_available'],
                              row.get('car_count'), row.get('vehicle_series')),
                             (False, True, None, None))
            self.assertTrue(all(seat in row['notes'] for seat in PRINTED[number][2]))
        for kind in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{kind}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
