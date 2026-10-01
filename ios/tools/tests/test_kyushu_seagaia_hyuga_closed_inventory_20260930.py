"""Exact-day official closed-set and next-four timetable checks."""
import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-seagaia14-hyuga1-3-4-20260930'
PINNED = {
    '5014M': ('nichirin-seagaia','14','宮崎空港','博多',23,'16:15','22:04',{'大分':'3','小倉':'4','折尾':'3','博多':'6'}),
    '5071M': ('hyuga','1','延岡','宮崎空港',10,'05:23','06:47',{}),
    '5073M': ('hyuga','3','延岡','宮崎',8,'05:48','07:01',{}),
    '5074M': ('hyuga','4','宮崎空港','延岡',8,'13:15','14:44',{}),
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]


class ClosedInventoryTests(unittest.TestCase):
    def test_closed_inventory_numbers_and_missing(self):
        audit = json.loads((BASE / 'audits/jr-kyushu-seagaia-hyuga-20260930-closed-inventory.json').read_text(encoding='utf-8'))
        families = audit['families']
        self.assertEqual([(t['public_number'],t['train_number']) for t in families['nichirin-seagaia']['trips']],
                         [('5','5005M'),('14','5014M')])
        hyuga = [(t['public_number'],t['train_number']) for t in families['hyuga']['trips']]
        self.assertEqual(hyuga,[(str(n),f'{5070+n}M') for n in range(1,17) if n != 15])
        self.assertEqual(audit['total_published_count'],17)
        self.assertEqual(audit['candidate_present_count'],
                         sum(t['candidate_present'] for f in families.values() for t in f['trips']))
        self.assertEqual(audit['remaining_public_numbers']['hyuga'],
                         [t['public_number'] for t in families['hyuga']['trips'] if not t['candidate_present']])
        self.assertTrue(all(t['candidate_present'] for t in families['hyuga']['trips'] if t['public_number'] in {'1','2','3','4'}))
        self.assertEqual(audit['remaining_public_numbers']['nichirin-seagaia'],[])

    def test_four_source_pinned_candidates(self):
        for number,(service,public,origin,destination,count,first,last,platforms) in PINNED.items():
            candidate = json.loads((BASE / f'candidates/jr-kyushu-{service}{public}-20260930.json').read_text(encoding='utf-8'))
            trip, = candidate['trips']
            with self.subTest(number=number):
                self.assertEqual((candidate['candidate_status'],candidate['service_date']),('reviewed_official_html','2026-09-30'))
                self.assertEqual((trip['service_id'],trip['public_number'],trip['train_number'],trip['origin'],trip['destination']),
                                 (service,public,number,origin,destination))
                self.assertEqual((len(trip['stops']),trip['stops'][0][2],trip['stops'][-1][1]),(count,first,last))
                self.assertEqual({s[0]:s[3] for s in trip['stops'] if s[3] is not None},platforms)
                self.assertEqual(trip['operating_day_marker'],'毎日運転')
                self.assertTrue('d=20260930' in trip['source_url'])
                self.assertTrue('グリーン車指定席' in trip['formation_seat_text'])

    def test_normalized_calls_and_formations(self):
        trips = rows(BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')
        stops = rows(BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        formations = rows(BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual({t['train_number'] for t in trips},set(PINNED))
        self.assertEqual(len(stops),49)
        self.assertEqual(len(formations),4)
        self.assertTrue(all(f.get('vehicle_series') is None and f.get('car_count') is None for f in formations))
        for trip in trips:
            service,public,*_ = PINNED[trip['train_number']]
            ctrip, = json.loads((BASE / f'candidates/jr-kyushu-{service}{public}-20260930.json').read_text(encoding='utf-8'))['trips']
            calls = sorted((s for s in stops if s['trip_id']==trip['trip_id']),key=lambda s:s['stop_sequence'])
            self.assertEqual([(s['arrival_time'],s['departure_time'],s['platform']) for s in calls],
                             [(s[1],s[2],s[3]) for s in ctrip['stops']])
            self.assertEqual({s['day_offset'] for s in calls},{0})
        self.assertEqual({r['service_date'] for r in rows(BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl')},{'2026-09-30'})


if __name__ == '__main__':
    unittest.main()
