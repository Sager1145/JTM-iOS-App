"""Final date-selected Hyuga columns and 17-train closed set."""
import json
from pathlib import Path
import sys
import unittest

BASE=Path(__file__).resolve().parents[3]/'app/data/train-service-history'
SUFFIX='kyushu-hyuga13-14-16-20260930'
EXPECTED={
 '13':('5083M','延岡','宮崎空港',10,'17:35','18:59','９月１９・２２・２３日は運休'),
 '14':('5084M','宮崎空港','延岡',10,'21:30','23:04','毎日運転'),
 '16':('5086M','南宮崎','延岡',9,'22:40','23:58','毎日運転'),
}


def rows(path):
 return [json.loads(line) for line in path.read_text(encoding='utf8').splitlines() if line.strip()]


class HyugaFinalTests(unittest.TestCase):
 def test_printed_identity_and_unprinted_platforms(self):
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
  thirteen=json.loads((BASE/'candidates/jr-kyushu-hyuga13-20260930.json').read_text(encoding='utf8'))['trips'][0]
  self.assertEqual(thirteen['stops'][6],['宮崎神宮','18:44','18:45',None])
  self.assertEqual(thirteen['formation_seat_text'],['グリーン車指定席','普通車自由席'])

 def test_normalized_final_batch_and_closed_inventory(self):
  trips=rows(BASE/f'normalized/trips/{SUFFIX}/seeds.jsonl')
  stops=rows(BASE/f'normalized/stop-times/{SUFFIX}/seeds.jsonl')
  formations=rows(BASE/f'normalized/trip-formations/{SUFFIX}/seeds.jsonl')
  sources=rows(BASE/f'sources/source-registry-{SUFFIX}.jsonl')
  self.assertEqual((len(trips),len(stops),len(formations),len(sources)),(3,29,3,3))
  self.assertTrue(all(f.get('vehicle_series') is None and f.get('car_count') is None for f in formations))
  for public in EXPECTED:
   ctrip,=json.loads((BASE/f'candidates/jr-kyushu-hyuga{public}-20260930.json').read_text(encoding='utf8'))['trips']
   calls=sorted((s for s in stops if s['trip_id']==ctrip['trip_id']),key=lambda s:s['stop_sequence'])
   self.assertEqual([(s['arrival_time'],s['departure_time'],s['platform'],s['day_offset']) for s in calls],
                    [(s[1],s[2],s[3],0) for s in ctrip['stops']])
  audit=json.loads((BASE/'audits/jr-kyushu-seagaia-hyuga-20260930-closed-inventory.json').read_text(encoding='utf8'))
  self.assertEqual((audit['total_published_count'],audit['candidate_present_count']),(17,17))
  self.assertEqual(audit['remaining_public_numbers'],{'nichirin-seagaia':[],'hyuga':[]})
  self.assertTrue(all(t['candidate_present'] for f in audit['families'].values() for t in f['trips']))

 def test_materialized_exact_date_closed_set(self):
  sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
  import train_timetable as timetable
  base=timetable.DEFAULT_CANONICAL
  manifest=timetable.load_manifest(base)
  data,origins=timetable.load_dataset(base,manifest)
  self.assertFalse(timetable.validate_dataset(data,origins,manifest))
  actual={(r['service_id'],r['public_number']) for r in timetable.materialize(data,'2026-09-30')
          if r['service_id'] in {'nichirin-seagaia','hyuga'}}
  expected={('nichirin-seagaia',str(n)) for n in (5,14)}|{('hyuga',str(n)) for n in range(1,17) if n!=15}
  self.assertEqual(actual,expected)


if __name__=='__main__': unittest.main()
