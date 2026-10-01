"""Selected-date JR Kyushu Kirishima 11, 13, 15 and 17 source checks."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-kirishima11-13-15-17-20260930'
SOURCE_PATHS = {
    '11': '0006/00064901', '13': '0004/00047801',
    '15': '0006/00066201', '17': '0008/00087101',
}
PRINTED = {
    '11': '''宮崎|-|14:20|-;南宮崎|14:24|14:25|-;都城|15:06|15:07|-;西都城|15:10|15:11|-;霧島神宮|15:36|15:37|-;国分|15:49|15:49|-;隼人|15:53|15:54|-;加治木|16:00|16:00|-;鹿児島|16:19|16:20|-;鹿児島中央|16:24|-|4''',
    '13': '''宮崎|-|16:20|-;南宮崎|16:24|16:25|-;清武|16:30|16:31|-;都城|17:08|17:10|-;西都城|17:13|17:14|-;霧島神宮|17:41|17:42|-;国分|17:54|17:54|-;隼人|17:58|17:59|-;加治木|18:05|18:05|-;鹿児島|18:26|18:27|-;鹿児島中央|18:31|-|2''',
    '15': '''宮崎|-|17:20|-;南宮崎|17:23|17:24|-;清武|17:30|17:30|-;都城|18:13|18:15|-;西都城|18:19|18:21|-;霧島神宮|18:46|18:47|-;国分|18:58|18:59|-;隼人|19:03|19:03|-;加治木|19:09|19:10|-;鹿児島|19:29|19:30|-;鹿児島中央|19:35|-|3''',
    '17': '''宮崎|-|19:00|-;南宮崎|19:03|19:04|-;清武|19:10|19:10|-;都城|19:49|19:51|-;西都城|19:54|19:55|-;霧島神宮|20:24|20:26|-;国分|20:38|20:39|-;隼人|20:42|20:43|-;加治木|20:49|20:52|-;鹿児島|21:13|21:14|-;鹿児島中央|21:18|-|2''',
}
NOVEMBER_NOTE = '１１月４・１０・１１・１７・１８・２４・２５日は運休'


def printed_rows(public):
    return [[None if value == '-' else value for value in entry.split('|')]
            for entry in PRINTED[public].split(';')]


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


class KyushuKirishima11131517SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / 'candidates/jr-kyushu-kirishima11-13-15-17-20260930.json').read_text(encoding='utf-8'))
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
                              'きりしま', 'limited_express', f'60{public}M',
                              f'jr-kyushu-kirishima{public}-20260930', url))
            self.assertEqual((trip['origin'], trip['destination']), ('宮崎', '鹿児島中央'))
            self.assertEqual(trip['operating_day_marker'],
                             NOVEMBER_NOTE if public == '11' else '毎日運転')
            self.assertEqual(trip['formation_seat_text'],
                             ['グリーン車指定席', '普通車一部指定席'])
            self.assertEqual(trip['stops'], printed_rows(public))

    def test_staged_clocks_platforms_calendar_and_seats(self):
        staged = {row['public_number']: row for row in rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')}
        stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        self.assertEqual((len(staged), len(stops)), (4, 43))
        for public, trip in self.trips.items():
            self.assertEqual((staged[public]['trip_id'], staged[public]['train_number']),
                             (trip['trip_id'], f'60{public}M'))
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
