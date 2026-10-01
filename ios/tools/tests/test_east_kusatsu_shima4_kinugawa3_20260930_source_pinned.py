"""Independently pinned official September30 calls, equipment and date scope."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/'app/data/train-service-history'
PINNED={
 'kusatsu-shima4':('kusatsu-shima','4','3004M','https://timetables.jreast.co.jp/2610/train/045/047071.html',[
 ('長野原草津口',None,'15:43',None),('中之条','16:05','16:06',None),('渋川','16:25','16:26',None),('新前橋','16:36','16:38',None),('高崎','16:44','16:46','７'),('熊谷','17:15','17:16',None),('大宮','17:43','17:44','６'),('浦和','17:50','17:50',None),('赤羽','17:58','17:59',None),('上野','18:09',None,'１４')]),
 'kinugawa3':('kinugawa','3','1083M','https://timetables.jreast.co.jp/2610/train/045/046941.html',[
 ('新宿',None,'10:31','６'),('池袋','10:36','10:37','３'),('浦和','10:54','10:54',None),('大宮','11:01','11:02','１１'),('栃木','11:44','11:45',None),('新鹿沼','12:00','12:01',None),('下今市','12:17','12:18',None),('東武ワールドスクウェア','12:33','12:33',None),('鬼怒川温泉','12:36',None,None)])}
class NewFamilyTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.day=timetable.materialize(cls.data,'2026-09-30');cls.names={r['station_id']:r['name_snapshot'] for r in cls.data['station_identities']}
 def test_every_printed_call_and_platform(self):
  for key,(service,n,number,url,stops) in PINNED.items():
   c=json.loads((BASE/f'candidates/jr-east-{key}-20260930.json').read_text());t=next(t for t in self.day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],number);self.assertEqual(c['source_url'],url)
   self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],stops)
   self.assertEqual(c['calendar_observation'],dict(month='2026年9月',day=30,cell_class='ok'))
 def test_only_printed_number_and_planned_formation(self):
  for key,(service,n,number,url,stops) in PINNED.items():
   tid=f'jr-east.{service}.{n}.exact-2026-09-30';f=next(f for f in self.data['trip_formations'] if f['trip_id']==tid)
   self.assertEqual(f['evidence_kind'],'planned');self.assertIs(f['all_reserved'],True)
   self.assertEqual(f['vehicle_series'],'253系' if service=='kinugawa' else None)
   for field in ['car_count','green_car_available','reserved_seat_capacity']:self.assertIsNone(f[field])
   self.assertFalse([s for s in self.data['trip_number_segments'] if s['trip_id']==tid])
   unknown={r['dimension'] for r in self.data['fact_completeness'] if r['entity_id']==tid and r['status']=='unknown'}
   self.assertTrue({'operator','route_lines'}<=unknown)
 def test_exact_day_only(self):
  tids={f'jr-east.{s}.{n}.exact-2026-09-30' for s,n,_,_,_ in PINNED.values()}
  for day in ['2026-09-29','2026-10-01']:
   self.assertFalse(tids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
