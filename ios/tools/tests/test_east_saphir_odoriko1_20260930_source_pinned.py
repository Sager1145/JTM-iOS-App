"""Distinct Saphir service, exact clocks and only printed premium equipment."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/'app/data/train-service-history'
TID='jr-east.saphir-odoriko.1.exact-2026-09-30'
EXPECTED=[('東京',None,'11:00','９'),('品川','11:07','11:08','１２'),('横浜','11:23','11:24','６'),('熱海','12:17','12:19','２'),('伊東','12:36','12:37','１'),('伊豆高原','12:55','12:56',None),('伊豆熱川','13:05','13:05',None),('伊豆稲取','13:12','13:13',None),('河津','13:18','13:18',None),('伊豆急下田','13:29',None,None)]
class SaphirTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.c=json.loads((BASE/'candidates/jr-east-saphir-odoriko1-20260930.json').read_text())
 def test_every_printed_call(self):
  t=next(t for t in timetable.materialize(self.data,'2026-09-30') if t['trip_id']==TID);names={r['station_id']:r['name_snapshot'] for r in self.data['station_identities']}
  self.assertEqual(t['train_number'],'3001M');self.assertEqual(t['public_number'],'1')
  self.assertEqual([(names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],EXPECTED)
  self.assertEqual(t['stop_times'][0]['station_id'],'jp.n02.003766')
 def test_separate_service_is_aligned_with_existing_branding(self):
  services={s['service_id']:s for s in self.data['services']}
  self.assertEqual(services['saphir-odoriko']['canonical_name'],'サフィール踊り子');self.assertEqual(services['odoriko']['canonical_name'],'踊り子')
  brand=json.loads((TOOLS.parents[1]/'ios/RailKit/Sources/RailCore/Resources/train-service-branding.json').read_text())
  if isinstance(brand,dict):brand=brand['services']
  self.assertIn('saphir-odoriko',{s['id'] for s in brand})
  audit=json.loads((BASE/'audits/jr-east-saphir-odoriko-service-identity-20260930.json').read_text());self.assertEqual(audit['decision'],'separate_service')
 def test_premium_equipment_without_inferred_cars(self):
  self.assertEqual(self.c['equipment'],['全車グリーン車指定席','プレミアムグリーン','グリーン車指定席','グリーン車指定席（６人用グリーン個室連結）','グリーン車指定席（４人用グリーン個室連結）'])
  f=next(f for f in self.data['trip_formations'] if f['trip_id']==TID)
  self.assertEqual(f['evidence_kind'],'planned');self.assertIs(f['all_reserved'],True);self.assertIs(f['green_car_available'],True)
  for key in ['car_count','vehicle_series','reserved_seat_capacity']:self.assertIsNone(f[key])
  self.assertFalse([s for s in self.data['trip_number_segments'] if s['trip_id']==TID])
 def test_exact_day_source(self):
  self.assertEqual(self.c['source_url'],'https://timetables.jreast.co.jp/2610/train/060/063451.html');self.assertEqual(self.c['calendar_observation'],dict(month='2026年9月',day=30,cell_class='ok'))
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(any(t['trip_id']==TID for t in timetable.materialize(self.data,day)))
if __name__=='__main__':unittest.main()
