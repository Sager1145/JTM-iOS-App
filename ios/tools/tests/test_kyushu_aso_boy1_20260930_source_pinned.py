"""Official selected-day Aso Boy 1: exact six calls and operation legend."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/'app/data/train-service-history'
TID='jr-kyushu.aso-boy.1.exact-2026-09-30'
EXPECTED=[('熊本',None,'09:57','３'),('新水前寺','10:03','10:04',None),('肥後大津','10:25','10:32',None),('立野','10:51','10:56',None),('阿蘇','11:22','11:27',None),('宮地','11:32',None,None)]
class AsoBoyTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.c=json.loads((BASE/'candidates/jr-kyushu-aso-boy1-20260930.json').read_text())
 def test_printed_calls_platforms_and_identity(self):
  t=next(t for t in timetable.materialize(self.data,'2026-09-30') if t['trip_id']==TID);names={s['station_id']:s['name_snapshot'] for s in self.data['station_identities']}
  self.assertEqual(t['train_number'],'8091D');self.assertEqual(t['service_id'],'aso-boy');self.assertEqual(t['public_number'],'1')
  self.assertEqual([(names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],EXPECTED)
  self.assertEqual(next(s['canonical_name'] for s in self.data['services'] if s['service_id']=='aso-boy'),'あそぼーい！')
 def test_exact_operating_day_evidence(self):
  self.assertEqual(self.c['source_url'],'https://www.jrkyushu-timetable.jp/jr-k_time/2610/0026/00262201.html?c=28626&ym=202609&d=30')
  self.assertEqual(self.c['calendar_observation'],dict(month='2026年 9月',day=30,cell_bgcolor='#d0f0ff',bold=True,legend='運転日'))
  self.assertEqual(self.c['printed_operating_labels'],'１１月１４・２４～２７日は運休')
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(any(t['trip_id']==TID for t in timetable.materialize(self.data,day)))
 def test_planned_seats_and_unknown_formation(self):
  f=next(f for f in self.data['trip_formations'] if f['trip_id']==TID)
  self.assertEqual(f['evidence_kind'],'planned');self.assertIs(f['all_reserved'],True)
  for key in ['vehicle_series','car_count','reserved_seat_capacity','green_car_available']:self.assertIsNone(f[key])
  self.assertFalse([s for s in self.data['trip_number_segments'] if s['trip_id']==TID])
  unknown={r['dimension'] for r in self.data['fact_completeness'] if r['entity_id']==TID and r['status']=='unknown'}
  self.assertTrue({'operator','route_lines'}<=unknown)
if __name__=='__main__':unittest.main()
