"""Exact-date JR Kyushu Nichirin 102 official detail checks."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-nichirin102-20260930'
URL = 'https://www.jrkyushu-timetable.jp/sp/2610/0011/00117001.html?t=2876000&d=20260930'
PRINTED = [
    ('佐伯', None, '07:33', None),
    ('津久見', '07:50', '07:51', None),
    ('臼杵', '08:00', '08:01', None),
    ('幸崎', '08:17', '08:18', None),
    ('大在', '08:25', '08:26', None),
    ('鶴崎', '08:30', '08:31', None),
    ('大分', '08:39', None, '4'),
]


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class KyushuNichirin102SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / 'candidates/jr-kyushu-nichirin102-20260930.json').read_text(encoding='utf-8'))
        cls.trip, = cls.candidate['trips']

    def test_selected_date_identity_clocks_platform_and_seats(self):
        self.assertEqual((self.candidate['candidate_status'], self.candidate['service_date']),
                         ('reviewed_official_html', '2026-09-30'))
        self.assertEqual((self.trip['trip_id'], self.trip['service_id'], self.trip['service_name'],
                          self.trip['public_number'], self.trip['train_number'],
                          self.trip['service_class'], self.trip['source_id'],
                          self.trip['source_url'], self.trip['operating_day_marker'],
                          self.trip['origin'], self.trip['destination']),
                         ('jr-kyushu.nichirin.102.2026-09-30', 'nichirin', 'にちりん',
                          '102', '5092M', 'limited_express',
                          'jr-kyushu-nichirin102-20260930', URL, '毎日運転', '佐伯', '大分'))
        self.assertEqual(self.trip['formation_seat_text'], ['グリーン車指定席', '普通車自由席'])
        self.assertEqual(self.trip['stops'], [list(stop) for stop in PRINTED])

    def test_staged_trip_stop_and_calendar_fields(self):
        trip, = rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        self.assertEqual((trip['train_number'], trip['public_number']), ('5092M', '102'))
        self.assertEqual(len(stops), 7)
        self.assertEqual([(row['arrival_time'], row['departure_time'], row['platform'])
                          for row in sorted(stops, key=lambda row: row['stop_sequence'])],
                         [(arrival, departure, platform)
                          for _, arrival, departure, platform in PRINTED])
        calendar, = rows(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exception, = rows(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual((calendar['valid_from'], calendar['valid_until'],
                          exception['service_date'], exception['exception_type']),
                         ('2026-09-30', '2026-10-01', '2026-09-30', 'add'))

    def test_source_formation_and_unknown_routes(self):
        source, = rows(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        formation, = rows(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual((source['url_or_locator'], source['effective_date']),
                         (URL, '2026-09-30'))
        self.assertEqual((formation['all_reserved'], formation['green_car_available'],
                          formation.get('car_count'), formation.get('vehicle_series')),
                         (False, True, None, None))
        self.assertIn('普通車自由席', formation['notes'])
        for kind in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{kind}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
