"""Exact published columns; coupled blanks never copied from Kaiji."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/'app/data/train-service-history'
PINNED={
 'spacia-nikko1':('spacia-nikko','1','1091M','https://timetables.jreast.co.jp/2610/train/045/046931.html',[
 ('新宿',None,'09:34','５'),('池袋','09:39','09:40','３'),('浦和','09:57','09:58',None),('大宮','10:03','10:04','１１'),('栃木','10:50','10:51',None),('新鹿沼','11:06','11:06',None),('下今市','11:22','11:24',None),('東武日光','11:31',None,None)]),
 'fuji-excursion11':('fuji-excursion','11','2111M','https://timetables.jreast.co.jp/2610/train/050/054801.html',[
 ('新宿',None,None,None),('立川',None,None,None),('八王子',None,None,None),('大月',None,'10:42',None),('都留文科大学前','10:58','10:59',None),('下吉田','11:14','11:14',None),('富士山','11:19','11:23',None),('富士急ハイランド','11:25','11:25',None),('河口湖','11:28',None,None)])}
class NewFamilyTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.day=timetable.materialize(cls.data,'2026-09-30');cls.names={r['station_id']:r['name_snapshot'] for r in cls.data['station_identities']}
 def test_all_published_clocks_and_platforms(self):
  for key,(service,n,number,url,stops) in PINNED.items():
   c=json.loads((BASE/f'candidates/jr-east-{key}-20260930.json').read_text());t=next(t for t in self.day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],number);self.assertEqual(c['source_url'],url)
   self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],stops)
   self.assertEqual(c['calendar_observation'],dict(month='2026年9月',day=30,cell_class='ok'))
 def test_direct_formation_only(self):
  for key,(service,n,number,url,stops) in PINNED.items():
   tid=f'jr-east.{service}.{n}.exact-2026-09-30';f=next(f for f in self.data['trip_formations'] if f['trip_id']==tid)
   self.assertEqual(f['evidence_kind'],'planned');self.assertIs(f['all_reserved'],True)
   self.assertEqual(f['vehicle_series'],'100系' if service=='spacia-nikko' else None)
   self.assertEqual(f['green_car_available'],True if service=='spacia-nikko' else None)
   for field in ['car_count','reserved_seat_capacity']:self.assertIsNone(f[field])
   self.assertFalse([s for s in self.data['trip_number_segments'] if s['trip_id']==tid])
 def test_coupling_and_partial_timing(self):
  tid='jr-east.fuji-excursion.11.exact-2026-09-30';kaiji='jr-east.kaiji.11.exact-2026-09-30'
  relations=[r for r in self.data['trip_relations'] if {r['trip_id'],r['related_trip_id']}=={tid,kaiji}]
  self.assertEqual(len(relations),2)
  for r in relations:self.assertEqual((r['relation_type'],r['from_sequence'],r['to_sequence']),('couples_with',1,4))
  self.assertEqual(next(r['status'] for r in self.data['fact_completeness'] if r['entity_id']==tid and r['dimension']=='times'),'partial')
  c=json.loads((BASE/'candidates/jr-east-fuji-excursion11-20260930.json').read_text())
  self.assertEqual(c['printed_operating_labels'],'平日運転');self.assertIn('座席の指定はできません',c['printed_remarks'])
 def test_exact_day_only(self):
  tids={f'jr-east.{s}.{n}.exact-2026-09-30' for s,n,_,_,_ in PINNED.values()}
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(tids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
