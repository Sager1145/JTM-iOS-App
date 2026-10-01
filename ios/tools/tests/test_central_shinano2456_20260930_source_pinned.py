"""Check reviewed September 30 Shinano 2/4/5/6 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {2:'000/000071',4:'000/000111',5:'020/020021',6:'000/000151'}
# Independent pinned passenger-call expectations from reviewed official tables.
EXPECTED = {
2:[('長野',None,'06:09','６'),('篠ノ井','06:17','06:17',None),('明科','06:49','06:49',None),('松本','07:03','07:04','１'),('塩尻','07:13','07:14',None),('木曽福島','07:42','07:43',None),('上松','07:49','07:49',None),('南木曽','08:08','08:09',None),('中津川','08:21','08:22',None),('恵那','08:30','08:30',None),('多治見','08:50','08:51',None),('千種','09:08','09:08',None),('金山','09:13','09:13',None),('名古屋','09:18',None,'１１')],
4:[('長野',None,'07:44','６'),('篠ノ井','07:53','07:53',None),('聖高原','08:11','08:12',None),('松本','08:37','08:38','１'),('塩尻','08:46','08:49',None),('木曽福島','09:17','09:19',None),('中津川','09:56','09:57',None),('多治見','10:24','10:24',None),('千種','10:42','10:43',None),('名古屋','10:53',None,'１１')],
5:[('名古屋',None,'09:00','１０'),('千種','09:06','09:06',None),('多治見','09:23','09:23',None),('中津川','09:49','09:50',None),('木曽福島','10:25','10:25',None),('塩尻','10:54','10:55',None),('松本','11:05','11:06','３'),('篠ノ井','11:51','11:51',None),('長野','11:59',None,'７')],
6:[('長野',None,'09:01','６'),('篠ノ井','09:09','09:09',None),('明科','09:38','09:39',None),('松本','09:51','09:52','１'),('塩尻','10:00','10:03',None),('木曽福島','10:30','10:30',None),('中津川','11:05','11:06',None),('多治見','11:34','11:34',None),('千種','11:52','11:53',None),('名古屋','12:01',None,'１１')]}
class SourcePinnedTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  manifest=timetable.load_manifest(timetable.DEFAULT_CANONICAL)
  cls.data,origins=timetable.load_dataset(timetable.DEFAULT_CANONICAL,manifest)
  errors=timetable.validate_dataset(cls.data,origins,manifest)
  if errors: raise AssertionError(errors)
  cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']}
 def test_date_materialization_and_every_printed_call(self):
  today={t['trip_id']:t for t in timetable.materialize(self.data,'2026-09-30')}
  yesterday={t['trip_id'] for t in timetable.materialize(self.data,'2026-09-29')}
  for n,expected in EXPECTED.items():
   with self.subTest(number=n):
    tid=f'jr-central.shinano.{n}.2026-09-30'; t=today[tid]
    self.assertNotIn(tid,yesterday)
    self.assertEqual((t['public_number'],t['train_number']),(str(n),f'{1000+n}M'))
    self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],expected)
    self.assertEqual(self.names[t['origin_station_id']],expected[0][0])
    self.assertEqual(self.names[t['destination_station_id']],expected[-1][0])
 def test_sources_day_cells_equipment_and_rejection_of_wrong_variant(self):
  for n,page in PAGES.items():
   with self.subTest(number=n):
    c=json.loads((BASE/f'candidates/jr-central-shinano{n}-20260930.json').read_text()); t=c['trip']
    self.assertFalse(c['canonical'])
    self.assertEqual(t['source']['url_or_locator'],f'https://timetables.jreast.co.jp/2610/train/{page}.html')
    self.assertEqual(t['calendar_observation']['cell_class'],'ok')
    self.assertEqual(t['calendar_observation']['month'],'2026年9月')
    self.assertEqual(t['calendar_observation']['day'],30)
    self.assertEqual(t['equipment'],['グリーン車指定席','普通車一部指定席'])
    spec=importlib.util.spec_from_file_location(f'shinano{n}',ROOT/f'ios/tools/normalize-reviewed-central-shinano{n}-20260930.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    mod.validate_candidate(c)
    t['source']['url_or_locator']='https://timetables.jreast.co.jp/2610/train/000/000083.html'
    with self.assertRaises(ValueError): mod.validate_candidate(c)
 def test_only_one_added_day_and_unknown_route_boundaries(self):
  for n in PAGES:
   tid=f'jr-central.shinano.{n}.2026-09-30'
   exceptions=[e for e in self.data['calendar_exceptions'] if e['calendar_id']==tid+'.calendar']
   self.assertEqual([(e['service_date'],e['exception_type']) for e in exceptions],[('2026-09-30','add')])
   facts={f['dimension']:f['status'] for f in self.data['fact_completeness'] if f['entity_id']==tid}
   self.assertEqual(facts['operator'],'unknown');self.assertEqual(facts['route_lines'],'unknown')
if __name__=='__main__': unittest.main()
