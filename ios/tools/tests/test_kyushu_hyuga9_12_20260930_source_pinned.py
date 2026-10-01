"""Exact-date official Hyuga 9–12 details and independent slices."""
import json
from pathlib import Path
import unittest

BASE=Path(__file__).resolve().parents[3]/'app/data/train-service-history'
SUFFIX='kyushu-hyuga9-12-20260930'
EXPECTED={
 '9':('5079M','延岡','宮崎空港',8,'13:20','14:52','９月１９・２２・２３日は運休'),
 '10':('5080M','宮崎空港','延岡',10,'19:15','20:45','毎日運転'),
 '11':('5081M','延岡','宮崎空港',8,'15:20','16:51','毎日運転'),
 '12':('5082M','宮崎空港','延岡',10,'20:15','21:51','毎日運転'),
}


def rows(path):
 return [json.loads(line) for line in path.read_text(encoding='utf8').splitlines() if line.strip()]


class HyugaNineToTwelveTests(unittest.TestCase):
 def test_exact_date_identity_and_printed_fields(self):
  for public,(number,origin,destination,count,first,last,marker) in EXPECTED.items():
   candidate=json.loads((BASE/f'candidates/jr-kyushu-hyuga{public}-20260930.json').read_text(encoding='utf8'))
   trip,=candidate['trips']
   with self.subTest(public=public):
    self.assertEqual((candidate['candidate_status'],candidate['service_date']),('reviewed_official_html','2026-09-30'))
    self.assertEqual((trip['service_id'],trip['service_name'],trip['public_number'],trip['train_number'],trip['origin'],trip['destination'],trip['operating_day_marker']),
                     ('hyuga','ひゅうが',public,number,origin,destination,marker))
    self.assertEqual((len(trip['stops']),trip['stops'][0][2],trip['stops'][-1][1]),(count,first,last))
    self.assertTrue(all(stop[3] is None for stop in trip['stops']))
    self.assertIn('d=20260930',trip['source_url'])
  twelve=json.loads((BASE/'candidates/jr-kyushu-hyuga12-20260930.json').read_text(encoding='utf8'))['trips'][0]
  self.assertEqual(twelve['formation_seat_text'],['ＤＸグリーンがあります','グリーン車指定席','グリーン車指定席（４人用グリーン個室連結）','普通車自由席'])
  self.assertEqual(twelve['stops'][4],['高鍋','20:52','21:01',None])
  ten=json.loads((BASE/'candidates/jr-kyushu-hyuga10-20260930.json').read_text(encoding='utf8'))['trips'][0]
  self.assertEqual(ten['stops'][7],['門川','20:27','20:32',None])

 def test_normalized_calls_and_audit(self):
  trips=rows(BASE/f'normalized/trips/{SUFFIX}/seeds.jsonl')
  stops=rows(BASE/f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
  formations=rows(BASE/f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
  sources=rows(BASE/f'sources/source-registry-{SUFFIX}.jsonl')
  self.assertEqual({t['train_number'] for t in trips},{x[0] for x in EXPECTED.values()})
  self.assertEqual((len(stops),len(formations),len(sources)),(36,4,4))
  self.assertTrue(all(f.get('vehicle_series') is None and f.get('car_count') is None for f in formations))
  for public in EXPECTED:
   candidate=json.loads((BASE/f'candidates/jr-kyushu-hyuga{public}-20260930.json').read_text(encoding='utf8'))
   trip,=candidate['trips']
   calls=sorted((s for s in stops if s['trip_id']==trip['trip_id']),key=lambda s:s['stop_sequence'])
   self.assertEqual([(s['arrival_time'],s['departure_time'],s['platform'],s['day_offset']) for s in calls],
                    [(s[1],s[2],s[3],0) for s in trip['stops']])
  audit=json.loads((BASE/'audits/jr-kyushu-seagaia-hyuga-20260930-closed-inventory.json').read_text(encoding='utf8'))
  self.assertGreaterEqual(audit['candidate_present_count'],14)
  self.assertTrue(all(t['candidate_present'] for t in audit['families']['hyuga']['trips'] if t['public_number'] in EXPECTED))
  self.assertEqual(audit['remaining_public_numbers']['hyuga'],
                   [t['public_number'] for t in audit['families']['hyuga']['trips'] if not t['candidate_present']])


if __name__=='__main__': unittest.main()
