"""Source-pinned Sep30 weekday trains and Tokyo platform identity."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/'app/data/train-service-history'
PINNED={
 'shonan14':('shonan','14','3084M','https://timetables.jreast.co.jp/2610/train/095/098931.html',[
 ('平塚',None,'08:45','３'),('茅ヶ崎','08:50','08:50','５'),('辻堂','08:54','08:54',None),('藤沢','08:58','08:58',None),('大船','09:02','09:03','２'),('品川','09:29','09:30','６'),('東京','09:38',None,'８')]),
 'sazanami3':('sazanami','3','1003M','https://timetables.jreast.co.jp/2610/train/045/049711.html',[
 ('東京',None,'18:30','京１'),('蘇我','19:09','19:10','５'),('五井','19:17','19:17',None),('姉ヶ崎','19:22','19:22','１'),('木更津','19:33','19:34','３'),('君津','19:40',None,'２')])}
class NewFamilyTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.day=timetable.materialize(cls.data,'2026-09-30');cls.names={r['station_id']:r['name_snapshot'] for r in cls.data['station_identities']}
 def test_every_printed_call_platform_and_number(self):
  for key,(service,n,number,url,stops) in PINNED.items():
   c=json.loads((BASE/f'candidates/jr-east-{key}-20260930.json').read_text());t=next(t for t in self.day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],number);self.assertEqual(c['source_url'],url)
   self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],stops)
   self.assertEqual(c['calendar_observation'],dict(month='2026年9月',day=30,cell_class='ok'));self.assertEqual(c['printed_operating_labels'],'平日運転')
   tokyo=next(s for s in t['stop_times'] if self.names[s['station_id']]=='東京')
   self.assertEqual(tokyo['station_id'],'jp.n02.003785' if service=='sazanami' else 'jp.n02.003766')
 def test_equipment_and_unknowns(self):
  for key,(service,n,number,url,stops) in PINNED.items():
   tid=f'jr-east.{service}.{n}.exact-2026-09-30';f=next(f for f in self.data['trip_formations'] if f['trip_id']==tid)
   self.assertEqual(f['evidence_kind'],'planned');self.assertIs(f['all_reserved'],True)
   self.assertEqual(f['green_car_available'],True if service=='shonan' else None)
   for field in ['car_count','vehicle_series','reserved_seat_capacity']:self.assertIsNone(f[field])
   self.assertFalse([s for s in self.data['trip_number_segments'] if s['trip_id']==tid])
   unknown={r['dimension'] for r in self.data['fact_completeness'] if r['entity_id']==tid and r['status']=='unknown'}
   self.assertTrue({'operator','route_lines'}<=unknown)
 def test_exact_day_only(self):
  tids={f'jr-east.{s}.{n}.exact-2026-09-30' for s,n,_,_,_ in PINNED.values()}
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(tids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
