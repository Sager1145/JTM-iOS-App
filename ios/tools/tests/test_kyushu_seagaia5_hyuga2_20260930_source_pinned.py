"""Source-pinned selected-date Seagaia 5 and Hyuga 2 checks."""
import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-seagaia5-hyuga2-20260930'
EXPECTED = {
    '5005M': {
        'file': 'jr-kyushu-nichirin-seagaia5-20260930.json',
        'service': 'nichirin-seagaia', 'name': 'にちりんシーガイア', 'number': '5',
        'origin': '博多', 'destination': '宮崎空港', 'count': 26,
        'first': ('博多', None, '07:31', '2'), 'last': ('宮崎空港', '13:51', None, None),
        'platforms': [('博多','2'),('折尾','5'),('小倉','7'),('大分','2')],
        'seats': ['ＤＸグリーンがあります','グリーン車指定席','グリーン車指定席（４人用グリーン個室連結）','普通車一部指定席'],
        'marker': '毎日運転',
    },
    '5072M': {
        'file': 'jr-kyushu-hyuga2-20260930.json',
        'service': 'hyuga', 'name': 'ひゅうが', 'number': '2',
        'origin': '宮崎空港', 'destination': '延岡', 'count': 8,
        'first': ('宮崎空港', None, '11:15', None), 'last': ('延岡', '12:42', None, None),
        'platforms': [], 'seats': ['グリーン車指定席','普通車一部指定席'],
        'marker': '９月１９・２２・２３日は運休',
    },
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]


class KyushuPairTests(unittest.TestCase):
    def test_source_identity_and_printed_facts(self):
        for number, expected in EXPECTED.items():
            candidate = json.loads((BASE / 'candidates' / expected['file']).read_text(encoding='utf-8'))
            trip, = candidate['trips']
            with self.subTest(number=number):
                self.assertEqual((candidate['candidate_status'], candidate['service_date']), ('reviewed_official_html','2026-09-30'))
                self.assertEqual((trip['service_id'],trip['service_name'],trip['public_number'],trip['train_number'],
                                  trip['origin'],trip['destination'],trip['operating_day_marker']),
                                 (expected['service'],expected['name'],expected['number'],number,
                                  expected['origin'],expected['destination'],expected['marker']))
                self.assertEqual(len(trip['stops']),expected['count'])
                self.assertEqual(tuple(trip['stops'][0]),expected['first'])
                self.assertEqual(tuple(trip['stops'][-1]),expected['last'])
                self.assertEqual([(s[0],s[3]) for s in trip['stops'] if s[3] is not None],expected['platforms'])
                self.assertEqual(trip['formation_seat_text'],expected['seats'])
        seagaia = json.loads((BASE / 'candidates/jr-kyushu-nichirin-seagaia5-20260930.json').read_text(encoding='utf-8'))['trips'][0]
        self.assertEqual(seagaia['temporary_stop'], '朽網')
        self.assertEqual(seagaia['stops'][8], ['朽網','08:45','08:45',None])
        self.assertEqual(seagaia['stops'][13], ['大分','10:04','10:06','2'])

    def test_normalized_calls_calendars_and_source_reuse(self):
        trips = rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        formations = rows(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual({t['train_number'] for t in trips},set(EXPECTED))
        self.assertEqual(len(stops),34)
        self.assertEqual(len(formations),2)
        for trip in trips:
            source_file = EXPECTED[trip['train_number']]['file']
            candidate_trip, = json.loads((BASE / 'candidates' / source_file).read_text(encoding='utf-8'))['trips']
            calls = sorted((s for s in stops if s['trip_id'] == trip['trip_id']),key=lambda s:s['stop_sequence'])
            self.assertEqual([(s['arrival_time'],s['departure_time'],s['platform']) for s in calls],
                             [(s[1],s[2],s[3]) for s in candidate_trip['stops']])
            self.assertEqual({s['day_offset'] for s in calls},{0})
        self.assertEqual({r['service_date'] for r in rows(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')},{'2026-09-30'})
        self.assertTrue(all(r.get('car_count') is None and r.get('vehicle_series') is None for r in formations))
        discovery = {r['source_id']:r for r in rows(BASE / 'sources/source-registry-discovery-kyushu-2026.jsonl')}
        for number, expected in EXPECTED.items():
            trip, = json.loads((BASE / 'candidates' / expected['file']).read_text(encoding='utf-8'))['trips']
            self.assertEqual(discovery[trip['source_id']]['url_or_locator'],trip['source_url'])
        self.assertFalse((BASE / f'sources/source-registry-{SUFFIX}.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
