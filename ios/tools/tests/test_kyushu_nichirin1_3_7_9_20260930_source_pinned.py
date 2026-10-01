"""Source-pinned selected-date Nichirin 1, 3, 7 and 9 checks."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-nichirin1-3-7-9-20260930'
SOURCE_PATHS = {
    '1': '0006/00068601', '3': '0008/00087201',
    '7': '0019/00193201', '9': '0009/00094101',
}
PRINTED = {
    '1': '''大分|-|07:01|2;鶴崎|07:08|07:09|-;幸崎|07:18|07:21|-;臼杵|07:41|07:42|-;津久見|07:51|07:52|-;佐伯|08:13|08:14|-;延岡|09:12|09:20|-;南延岡|09:24|09:25|-;日向市|09:41|09:42|-;高鍋|10:08|10:09|-;佐土原|10:18|10:20|-;宮崎|10:37|10:40|-;南宮崎|10:44|10:47|-;宮崎空港|10:52|-|-''',
    '3': '''小倉|-|06:39|3;行橋|06:56|06:56|-;宇島|07:11|07:11|-;中津|07:16|07:17|-;柳ケ浦|07:27|07:28|-;宇佐|07:33|07:33|-;杵築|07:48|07:49|-;亀川|08:00|08:01|-;別府|08:06|08:06|-;大分|08:17|08:19|4;鶴崎|08:29|08:30|-;幸崎|08:39|08:40|-;臼杵|08:57|08:58|-;津久見|09:07|09:08|-;佐伯|09:27|09:31|-;延岡|10:31|10:33|-;南延岡|10:36|10:37|-;日向市|10:50|10:50|-;高鍋|11:17|11:18|-;佐土原|11:27|11:28|-;宮崎|11:38|11:40|-;南宮崎|11:44|11:48|-;宮崎空港|11:52|-|-''',
    '7': '''大分|-|12:09|2;鶴崎|12:18|12:19|-;臼杵|12:44|12:47|-;津久見|12:56|12:59|-;佐伯|13:18|13:20|-;延岡|14:19|14:21|-;南延岡|14:25|14:26|-;日向市|14:40|14:41|-;高鍋|15:07|15:07|-;佐土原|15:17|15:20|-;宮崎|15:37|15:40|-;南宮崎|15:44|15:45|-;宮崎空港|15:51|-|-''',
    '9': '''大分|-|14:11|4;鶴崎|14:18|14:19|-;臼杵|14:43|14:47|-;津久見|14:56|15:00|-;佐伯|15:17|15:18|-;延岡|16:18|16:20|-;南延岡|16:24|16:24|-;日向市|16:37|16:38|-;高鍋|17:10|17:11|-;佐土原|17:20|17:21|-;宮崎|17:38|17:40|-;南宮崎|17:43|17:45|-;宮崎空港|17:52|-|-''',
}


def printed_rows(public):
    return [[None if value == '-' else value for value in entry.split('|')]
            for entry in PRINTED[public].split(';')]


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class KyushuNichirin1379SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / 'candidates/jr-kyushu-nichirin1-3-7-9-20260930.json').read_text(encoding='utf-8'))
        cls.trips = {trip['public_number']: trip for trip in cls.candidate['trips']}

    def test_official_identity_and_every_printed_call(self):
        self.assertEqual((self.candidate['candidate_status'], self.candidate['service_date']),
                         ('reviewed_official_html', '2026-09-30'))
        self.assertEqual(set(self.trips), set(PRINTED))
        for public, path in SOURCE_PATHS.items():
            trip = self.trips[public]
            url = f'https://www.jrkyushu-timetable.jp/sp/2610/{path}.html?t=2874201&d=20260930'
            self.assertEqual((trip['trip_id'], trip['service_id'], trip['service_name'],
                              trip['service_class'], trip['train_number'], trip['source_id'],
                              trip['source_url'], trip['operating_day_marker']),
                             (f'jr-kyushu.nichirin.{public}.2026-09-30', 'nichirin',
                              'にちりん', 'limited_express', f'500{public}M',
                              f'jr-kyushu-nichirin{public}-20260930', url, '毎日運転'))
            self.assertEqual(trip['origin'], '小倉' if public == '3' else '大分')
            self.assertEqual(trip['destination'], '宮崎空港')
            self.assertEqual(trip['formation_seat_text'],
                             ['グリーン車指定席', '普通車一部指定席'])
            self.assertEqual(trip['stops'], printed_rows(public))

    def test_staged_clocks_platforms_calendars_and_seats(self):
        staged = {row['public_number']: row for row in rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')}
        stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        self.assertEqual((len(staged), len(stops)), (4, 63))
        for public, trip in self.trips.items():
            self.assertEqual((staged[public]['trip_id'], staged[public]['train_number']),
                             (trip['trip_id'], f'500{public}M'))
            actual = sorted((row for row in stops if row['trip_id'] == trip['trip_id']),
                            key=lambda row: row['stop_sequence'])
            self.assertEqual([(row['arrival_time'], row['departure_time'], row['platform'])
                              for row in actual],
                             [(arr, dep, platform) for _, arr, dep, platform in printed_rows(public)])
        calendars = rows(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exceptions = rows(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual((len(calendars), len(exceptions)), (4, 4))
        self.assertEqual({(row['valid_from'], row['valid_until']) for row in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({row['service_date'] for row in exceptions}, {'2026-09-30'})
        formations = rows(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(formations), 4)
        for row in formations:
            self.assertEqual((row['all_reserved'], row['green_car_available'],
                              row.get('car_count'), row.get('vehicle_series')),
                             (False, True, None, None))
            self.assertIn('普通車一部指定席', row['notes'])

    def test_source_registry_and_unverified_routes(self):
        sources = rows(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual({row['url_or_locator'] for row in sources},
                         {trip['source_url'] for trip in self.trips.values()})
        self.assertTrue(all(row['effective_date'] == '2026-09-30'
                            and row['automated_extraction_allowed'] is False for row in sources))
        for kind in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{kind}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
