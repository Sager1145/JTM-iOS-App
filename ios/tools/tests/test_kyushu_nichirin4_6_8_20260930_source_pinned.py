"""Exact-date JR Kyushu Nichirin 4, 6 and 8 official detail checks."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-nichirin4-6-8-20260930'
URLS = {
    '5004M': 'https://www.jrkyushu-timetable.jp/sp/2610/0016/00165901.html?d=20260930&t=2877600',
    '5006M': 'https://www.jrkyushu-timetable.jp/sp/2610/0031/00310201.html?d=20260930&t=2890400',
    '5008M': 'https://www.jrkyushu-timetable.jp/sp/2610/0008/00087401.html?d=20260930&t=2890400',
}
PRINTED = {
    '5004M': ('4', '平日運転',
              ['ＤＸグリーンがあります', 'グリーン車指定席',
               'グリーン車指定席（４人用グリーン個室連結）', '普通車自由席'],
              [('宮崎空港', None, '06:38', None), ('南宮崎', '06:42', '06:47', None),
               ('宮崎', '06:50', '06:53', None), ('宮崎神宮', '06:55', '06:59', None),
               ('佐土原', '07:07', '07:07', None), ('高鍋', '07:16', '07:17', None),
               ('日向市', '07:43', '07:44', None), ('門川', '07:50', '07:51', None),
               ('南延岡', '07:58', '07:59', None), ('延岡', '08:03', '08:06', None),
               ('佐伯', '09:06', '09:07', None), ('津久見', '09:25', '09:26', None),
               ('臼杵', '09:35', '09:37', None), ('鶴崎', '09:58', '09:59', None),
               ('大分', '10:06', None, '4')]),
    '5006M': ('6', '毎日運転', ['グリーン車指定席', '普通車一部指定席'],
              [('宮崎空港', None, '07:45', None), ('南宮崎', '07:51', '08:02', None),
               ('宮崎', '08:06', '08:10', None), ('佐土原', '08:20', '08:21', None),
               ('高鍋', '08:30', '08:30', None), ('日向市', '08:55', '08:56', None),
               ('南延岡', '09:08', '09:09', None), ('延岡', '09:13', '09:15', None),
               ('佐伯', '10:11', '10:12', None), ('津久見', '10:29', '10:30', None),
               ('臼杵', '10:39', '10:40', None), ('鶴崎', '11:02', '11:02', None),
               ('大分', '11:10', None, '4')]),
    '5008M': ('8', '毎日運転', ['グリーン車指定席', '普通車一部指定席'],
              [('宮崎空港', None, '10:15', None), ('南宮崎', '10:21', '10:25', None),
               ('宮崎', '10:28', '10:30', None), ('佐土原', '10:39', '10:40', None),
               ('高鍋', '10:49', '10:50', None), ('日向市', '11:18', '11:19', None),
               ('南延岡', '11:31', '11:32', None), ('延岡', '11:36', '11:44', None),
               ('佐伯', '12:40', '12:41', None), ('津久見', '12:59', '13:00', None),
               ('臼杵', '13:09', '13:10', None), ('鶴崎', '13:32', '13:33', None),
               ('大分', '13:41', None, '4')]),
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class KyushuNichirin468SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / 'candidates/jr-kyushu-nichirin4-6-8-20260930.json').read_text(encoding='utf-8'))
        cls.trips = {trip['train_number']: trip for trip in cls.candidate['trips']}

    def test_official_selected_date_identity_clocks_and_seats(self):
        self.assertEqual((self.candidate['candidate_status'], self.candidate['service_date']),
                         ('reviewed_official_html', '2026-09-30'))
        self.assertEqual(set(self.trips), set(PRINTED))
        for number, (public, marker, seats, stops) in PRINTED.items():
            trip = self.trips[number]
            self.assertEqual((trip['trip_id'], trip['service_id'], trip['service_name'],
                              trip['public_number'], trip['service_class'], trip['source_id'],
                              trip['source_url'], trip['operating_day_marker']),
                             (f'jr-kyushu.nichirin.{public}.2026-09-30', 'nichirin',
                              'にちりん', public, 'limited_express',
                              f'jr-kyushu-nichirin{public}-20260930', URLS[number], marker))
            self.assertEqual(trip['formation_seat_text'], seats)
            self.assertEqual(trip['stops'], [list(stop) for stop in stops])

    def test_staged_trip_stop_and_calendar_fields(self):
        staged_trips = rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        staged_stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        self.assertEqual((len(staged_trips), len(staged_stops)), (3, 41))
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

    def test_source_registry_formation_and_unknown_lines(self):
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
