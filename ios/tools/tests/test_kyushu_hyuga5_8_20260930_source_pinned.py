"""Exact-date official Hyuga 5–8 details and independent slices."""
import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / 'app/data/train-service-history'
SUFFIX = 'kyushu-hyuga5-8-20260930'
EXPECTED = {
    '5': ('5075M','延岡','宮崎空港',10,'06:52','08:09','毎日運転'),
    '6': ('5076M','宮崎空港','延岡',8,'15:15','16:45','９月１９・２２・２３日は運休'),
    '7': ('5077M','延岡','宮崎空港',10,'08:03','09:28','毎日運転'),
    '8': ('5078M','宮崎空港','延岡',10,'18:15','19:47','毎日運転'),
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]


class HyugaNextFourTests(unittest.TestCase):
    def test_printed_identity_clocks_and_seats(self):
        for number,(train,origin,destination,count,first,last,marker) in EXPECTED.items():
            candidate=json.loads((BASE/f'candidates/jr-kyushu-hyuga{number}-20260930.json').read_text(encoding='utf-8'))
            trip,=candidate['trips']
            with self.subTest(number=number):
                self.assertEqual((candidate['candidate_status'],candidate['service_date']),('reviewed_official_html','2026-09-30'))
                self.assertEqual((trip['service_id'],trip['service_name'],trip['public_number'],trip['train_number'],trip['origin'],trip['destination'],trip['operating_day_marker']),
                                 ('hyuga','ひゅうが',number,train,origin,destination,marker))
                self.assertEqual((len(trip['stops']),trip['stops'][0][2],trip['stops'][-1][1]),(count,first,last))
                self.assertTrue(all(stop[3] is None for stop in trip['stops']))
                self.assertTrue('d=20260930' in trip['source_url'])
        five=json.loads((BASE/'candidates/jr-kyushu-hyuga5-20260930.json').read_text(encoding='utf-8'))['trips'][0]
        self.assertEqual(five['formation_seat_text'],['ＤＸグリーンがあります','グリーン車指定席','グリーン車指定席（４人用グリーン個室連結）','普通車自由席'])
        self.assertEqual(five['stops'][4],['都農','07:26','07:29',None])
        eight=json.loads((BASE/'candidates/jr-kyushu-hyuga8-20260930.json').read_text(encoding='utf-8'))['trips'][0]
        self.assertEqual(eight['stops'][7],['門川','19:32','19:34',None])

    def test_normalized_and_closed_inventory(self):
        trips=rows(BASE/f'normalized/trips/{SUFFIX}/seeds.jsonl')
        stops=rows(BASE/f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
        formations=rows(BASE/f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
        self.assertEqual({trip['train_number'] for trip in trips},{x[0] for x in EXPECTED.values()})
        self.assertEqual((len(stops),len(formations)),(38,4))
        self.assertTrue(all(f.get('vehicle_series') is None and f.get('car_count') is None for f in formations))
        for number,(train,*_) in EXPECTED.items():
            trip,=json.loads((BASE/f'candidates/jr-kyushu-hyuga{number}-20260930.json').read_text(encoding='utf-8'))['trips']
            calls=sorted((s for s in stops if s['trip_id']==trip['trip_id']),key=lambda s:s['stop_sequence'])
            self.assertEqual([(s['arrival_time'],s['departure_time'],s['platform'],s['day_offset']) for s in calls],
                             [(s[1],s[2],s[3],0) for s in trip['stops']])
        audit=json.loads((BASE/'audits/jr-kyushu-seagaia-hyuga-20260930-closed-inventory.json').read_text(encoding='utf-8'))
        self.assertGreaterEqual(audit['candidate_present_count'],10)
        self.assertTrue(all(t['candidate_present'] for t in audit['families']['hyuga']['trips']
                            if t['public_number'] in EXPECTED))
        self.assertEqual(audit['remaining_public_numbers']['hyuga'],
                         [t['public_number'] for t in audit['families']['hyuga']['trips'] if not t['candidate_present']])


if __name__=='__main__':
    unittest.main()
