"""Selected-date JR Kyushu Kirishima 3, 5, 7 and 9 source checks."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-kirishima3-5-7-9-20260930'
SOURCE_PATHS = {
    '3': '0006/00064701', '5': '0004/00047401',
    '7': '0006/00064801', '9': '0004/00047601',
}
PRINTED = {
    '3': '''宮崎|-|07:07|-;南宮崎|07:11|07:13|-;清武|07:18|07:19|-;都城|08:05|08:06|-;西都城|08:09|08:10|-;霧島神宮|08:35|08:36|-;国分|08:48|08:49|-;隼人|08:52|08:53|-;加治木|08:59|09:00|-;帖佐|09:04|09:04|-;鹿児島|09:22|09:23|-;鹿児島中央|09:27|-|2''',
    '5': '''宮崎|-|09:20|-;南宮崎|09:24|09:25|-;都城|10:08|10:09|-;西都城|10:12|10:13|-;霧島神宮|10:38|10:39|-;国分|10:52|10:53|-;隼人|10:56|10:57|-;加治木|11:03|11:04|-;鹿児島|11:22|11:23|-;鹿児島中央|11:28|-|4''',
    '7': '''宮崎|-|10:20|-;南宮崎|10:24|10:25|-;都城|11:08|11:09|-;西都城|11:12|11:13|-;霧島神宮|11:38|11:39|-;国分|11:51|11:52|-;隼人|11:55|11:56|-;加治木|12:02|12:03|-;鹿児島|12:22|12:23|-;鹿児島中央|12:27|-|3''',
    '9': '''宮崎|-|12:20|-;南宮崎|12:24|12:26|-;都城|13:08|13:12|-;西都城|13:15|13:16|-;霧島神宮|13:41|13:42|-;国分|13:53|13:54|-;隼人|13:58|13:58|-;鹿児島|14:27|14:28|-;鹿児島中央|14:32|-|3''',
}
NOVEMBER_NOTE = '１１月４・１０・１１・１７・１８・２４・２５日は運休'


def printed_rows(public):
    return [[None if value == '-' else value for value in entry.split('|')]
            for entry in PRINTED[public].split(';')]


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class KyushuKirishima3579SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / 'candidates/jr-kyushu-kirishima3-5-7-9-20260930.json').read_text(encoding='utf-8'))
        cls.trips = {trip['public_number']: trip for trip in cls.candidate['trips']}

    def test_official_identity_and_every_printed_call(self):
        self.assertEqual((self.candidate['candidate_status'], self.candidate['service_date']),
                         ('reviewed_official_html', '2026-09-30'))
        self.assertEqual(set(self.trips), set(PRINTED))
        for public, path in SOURCE_PATHS.items():
            trip = self.trips[public]
            url = f'https://www.jrkyushu-timetable.jp/sp/2610/{path}.html?t=2890301&d=20260930'
            self.assertEqual((trip['trip_id'], trip['service_id'], trip['service_name'],
                              trip['service_class'], trip['train_number'], trip['source_id'],
                              trip['source_url']),
                             (f'jr-kyushu.kirishima.{public}.2026-09-30', 'kirishima',
                              'きりしま', 'limited_express', f'600{public}M',
                              f'jr-kyushu-kirishima{public}-20260930', url))
            self.assertEqual((trip['origin'], trip['destination']), ('宮崎', '鹿児島中央'))
            self.assertEqual(trip['operating_day_marker'],
                             NOVEMBER_NOTE if public in {'7', '9'} else '毎日運転')
            self.assertEqual(trip['formation_seat_text'],
                             ['グリーン車指定席', '普通車一部指定席'])
            self.assertEqual(trip['stops'], printed_rows(public))

    def test_staged_clocks_platforms_calendar_and_seats(self):
        staged = {row['public_number']: row for row in rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')}
        stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        self.assertEqual((len(staged), len(stops)), (4, 41))
        for public, trip in self.trips.items():
            self.assertEqual((staged[public]['trip_id'], staged[public]['train_number']),
                             (trip['trip_id'], f'600{public}M'))
            actual = sorted((row for row in stops if row['trip_id'] == trip['trip_id']),
                            key=lambda row: row['stop_sequence'])
            self.assertEqual([(row['arrival_time'], row['departure_time'], row['platform'])
                              for row in actual],
                             [(arrival, departure, platform)
                              for _, arrival, departure, platform in printed_rows(public)])
        calendars = rows(BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl')
        exceptions = rows(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')
        self.assertEqual((len(calendars), len(exceptions)), (4, 4))
        self.assertEqual({(row['valid_from'], row['valid_until']) for row in calendars},
                         {('2026-09-30', '2026-10-01')})
        self.assertEqual({row['service_date'] for row in exceptions}, {'2026-09-30'})
        formations = rows(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual(len(formations), 4)
        for formation in formations:
            self.assertEqual((formation['all_reserved'], formation['green_car_available'],
                              formation.get('vehicle_series'), formation.get('car_count')),
                             (False, True, None, None))
            self.assertIn('普通車一部指定席', formation['notes'])

    def test_sources_and_unknown_physical_route(self):
        sources = rows(BASE / f'sources/source-registry-{SUFFIX}.jsonl')
        self.assertEqual({source['url_or_locator'] for source in sources},
                         {trip['source_url'] for trip in self.trips.values()})
        self.assertTrue(all(source['effective_date'] == '2026-09-30'
                            and source['automated_extraction_allowed'] is False
                            for source in sources))
        for kind in ('trip-line-segments', 'trip-operator-segments'):
            self.assertFalse((BASE / f'normalized/{kind}/{SUFFIX}/seeds.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
