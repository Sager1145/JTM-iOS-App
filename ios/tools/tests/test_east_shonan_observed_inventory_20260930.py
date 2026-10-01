"""Close the Fujisawa observed set without asserting unseen entrances absent."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/'app/data/train-service-history'
class ObservedShonanTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.inventory=json.loads((BASE/'audits/jr-east-shonan-fujisawa-observed-20260930-inventory.json').read_text());cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE))
 def test_22_observed_candidates_match_every_normalized_field(self):
  day={t['trip_id']:t for t in timetable.materialize(self.data,'2026-09-30')};names={r['station_id']:r['name_snapshot'] for r in self.data['station_identities']};sources={r['source_id']:r for r in self.data['source_documents']}
  self.assertEqual(len(self.inventory['trains']),22);rows=platforms=0
  for e in self.inventory['trains']:
   n=e['public_number'];c=json.loads((BASE/f'candidates/jr-east-shonan{n}-20260930.json').read_text());t=day[c['trip_id']]
   self.assertEqual(e['date_evidence'],dict(month='2026年9月',day=30,cell_class='ok'));self.assertEqual(e['train_number'],t['train_number']);self.assertEqual(t['public_number'],n)
   self.assertEqual(c['source_url'],e['source_url']);self.assertEqual(sources[c['source_id']]['url_or_locator'],e['source_url'])
   expected=[(name.replace('茅ケ崎','茅ヶ崎'),a,d,c['printed_platforms'].get(name)) for name,a,d in c['stops']]
   self.assertEqual([(names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],expected)
   self.assertTrue(all(s['source_id']==c['source_id'] for s in t['stop_times']))
   self.assertEqual(c['train_number_segments'],[]);self.assertFalse([s for s in self.data['trip_number_segments'] if s['trip_id']==t['trip_id']])
   rows+=len(expected);platforms+=len(c['printed_platforms'])
  self.assertEqual((rows,platforms),(174,126))
 def test_bounded_closure_and_unknown_vehicle(self):
  self.assertEqual(self.inventory['staged_observed_count'],22);self.assertEqual(self.inventory['remaining_observed_public_numbers'],[])
  self.assertIn('no exclusion claim',self.inventory['scope'])
  for e in self.inventory['trains']:
   tid=f"jr-east.shonan.{e['public_number']}.exact-2026-09-30"
   f=next(f for f in self.data['trip_formations'] if f['trip_id']==tid)
   self.assertEqual(f['evidence_kind'],'planned');self.assertTrue(f['all_reserved']);self.assertTrue(f['green_car_available'])
   self.assertIsNone(f['car_count']);self.assertIsNone(f['vehicle_series'])
if __name__=='__main__':unittest.main()
