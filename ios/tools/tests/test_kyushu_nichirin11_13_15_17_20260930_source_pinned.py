"""Source-pinned selected-date Nichirin 11, 13, 15 and 17 checks."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-nichirin11-13-15-17-20260930'
SOURCE_PATHS = {
    '11': '0009/00094201', '13': '0019/00193501',
    '15': '0019/00193301', '17': '0019/00193601',
}
PRINTED = {
    '11': '''大分|-|16:14|4;鶴崎|16:21|16:21|-;臼杵|16:48|16:52|-;津久見|17:01|17:03|-;佐伯|17:21|17:22|-;延岡|18:18|18:20|-;南延岡|18:23|18:24|-;日向市|18:40|18:41|-;高鍋|19:11|19:11|-;佐土原|19:20|19:21|-;宮崎神宮|19:30|19:33|-;宮崎|19:36|19:40|-;南宮崎|19:43|19:44|-;宮崎空港|19:51|-|-''',
    '13': '''大分|-|17:12|4;鶴崎|17:21|17:22|-;臼杵|17:49|17:49|-;津久見|17:58|17:59|-;佐伯|18:16|18:18|-;延岡|19:19|19:21|-;南延岡|19:25|19:26|-;日向市|19:40|19:41|-;高鍋|20:11|20:12|-;佐土原|20:21|20:22|-;宮崎|20:36|20:40|-;南宮崎|20:43|20:44|-;宮崎空港|20:51|-|-''',
    '15': '''大分|-|18:07|4;鶴崎|18:14|18:16|-;幸崎|18:25|18:27|-;臼杵|18:42|18:47|-;津久見|18:56|19:00|-;佐伯|19:19|19:20|-;延岡|20:17|20:21|-;南延岡|20:24|20:25|-;日向市|20:37|20:37|-;高鍋|21:01|21:01|-;佐土原|21:10|21:10|-;宮崎|21:20|21:21|-;南宮崎|21:25|-|-''',
    '17': '''大分|-|20:16|4;鶴崎|20:23|20:24|-;幸崎|20:33|20:37|-;臼杵|20:52|20:53|-;津久見|21:02|21:03|-;佐伯|21:25|21:26|-;延岡|22:23|22:25|-;南延岡|22:29|22:30|-;日向市|22:43|22:44|-;高鍋|23:10|23:11|-;佐土原|23:20|23:21|-;宮崎|23:31|23:32|-;南宮崎|23:35|-|-''',
}
DX = ['ＤＸグリーンがあります', 'グリーン車指定席',
      'グリーン車指定席（４人用グリーン個室連結）', '普通車一部指定席']
REGULAR = ['グリーン車指定席', '普通車一部指定席']


def printed_rows(public):
    return [[None if value == '-' else value for value in entry.split('|')]
            for entry in PRINTED[public].split(';')]


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class KyushuNichirin11131517SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / 'candidates/jr-kyushu-nichirin11-13-15-17-20260930.json').read_text(encoding='utf-8'))
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
                              'にちりん', 'limited_express', f'50{public}M',
                              f'jr-kyushu-nichirin{public}-20260930', url, '毎日運転'))
            self.assertEqual(trip['origin'], '大分')
            self.assertEqual(trip['destination'], '南宮崎' if public in {'15', '17'} else '宮崎空港')
            self.assertEqual(trip['formation_seat_text'], DX if public in {'11', '15'} else REGULAR)
            self.assertEqual(trip['stops'], printed_rows(public))

    def test_staged_clocks_platforms_calendars_and_seats(self):
        staged = {row['public_number']: row for row in rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')}
        stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        self.assertEqual((len(staged), len(stops)), (4, 53))
        for public, trip in self.trips.items():
            self.assertEqual((staged[public]['trip_id'], staged[public]['train_number']),
                             (trip['trip_id'], f'50{public}M'))
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
            public = next(p for p, trip in self.trips.items() if trip['trip_id'] == row['trip_id'])
            self.assertEqual((row['all_reserved'], row['green_car_available'],
                              row.get('car_count'), row.get('vehicle_series')),
                             (False, True, None, None))
            self.assertTrue(all(seat in row['notes'] for seat in (DX if public in {'11', '15'} else REGULAR)))

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
