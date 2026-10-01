"""Check reviewed September 30 Shinano 20–26 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {20: '020/020091', 21: '000/000421', 22: '000/000431', 23: '000/000441', 24: '020/020101', 25: '000/000451', 26: '000/000461'}
EXPECTED = {20: [('長野', None, '16:00', '６'), ('篠ノ井', '16:08', '16:09', None), ('松本', '16:53', '16:54', '１'), ('塩尻', '17:02', '17:03', None), ('木曽福島', '17:30', '17:31', None), ('南木曽', '17:55', '17:55', None), ('中津川', '18:08', '18:09', None), ('多治見', '18:37', '18:37', None), ('千種', '18:56', '18:57', None), ('名古屋', '19:07', None, '１０')], 21: [('名古屋', None, '17:40', '１０'), ('金山', '17:43', '17:44', None), ('千種', '17:47', '17:47', None), ('多治見', '18:04', '18:04', None), ('中津川', '18:30', '18:30', None), ('木曽福島', '19:07', '19:07', None), ('塩尻', '19:35', '19:37', None), ('松本', '19:46', '19:47', '２'), ('聖高原', '20:14', '20:15', None), ('篠ノ井', '20:32', '20:32', None), ('長野', '20:40', None, '２')], 22: [('長野', None, '17:00', '６'), ('篠ノ井', '17:08', '17:08', None), ('松本', '17:51', '17:52', '１'), ('塩尻', '18:01', '18:03', None), ('木曽福島', '18:30', '18:30', None), ('中津川', '19:08', '19:09', None), ('多治見', '19:37', '19:37', None), ('千種', '19:56', '19:57', None), ('名古屋', '20:07', None, '１０')], 23: [('名古屋', None, '18:40', '１０'), ('金山', '18:43', '18:44', None), ('千種', '18:47', '18:47', None), ('多治見', '19:04', '19:04', None), ('中津川', '19:30', '19:30', None), ('木曽福島', '20:05', '20:07', None), ('塩尻', '20:34', '20:36', None), ('松本', '20:45', '20:48', '２'), ('明科', '20:59', '21:00', None), ('篠ノ井', '21:28', '21:29', None), ('長野', '21:37', None, '２')], 24: [('長野', None, '18:11', '６'), ('篠ノ井', '18:19', '18:20', None), ('明科', '18:53', '18:54', None), ('松本', '19:06', '19:07', '１'), ('塩尻', '19:16', '19:19', None), ('木曽福島', '19:48', '19:48', None), ('上松', '19:54', '19:54', None), ('中津川', '20:25', '20:26', None), ('恵那', '20:34', '20:34', None), ('多治見', '20:54', '20:54', None), ('千種', '21:13', '21:14', None), ('名古屋', '21:21', None, '１０')], 25: [('名古屋', None, '19:40', '１０'), ('金山', '19:43', '19:44', None), ('千種', '19:47', '19:47', None), ('多治見', '20:04', '20:04', None), ('恵那', '20:23', '20:23', None), ('中津川', '20:31', '20:32', None), ('南木曽', '20:43', '20:43', None), ('上松', '21:03', '21:03', None), ('木曽福島', '21:09', '21:09', None), ('塩尻', '21:37', '21:39', None), ('松本', '21:49', '21:51', '２'), ('篠ノ井', '22:30', '22:31', None), ('長野', '22:39', None, '２')], 26: [('長野', None, '19:40', '６'), ('篠ノ井', '19:48', '19:48', None), ('明科', '20:19', '20:19', None), ('松本', '20:31', '20:32', '１'), ('塩尻', '20:40', '20:43', None), ('木曽福島', '21:10', '21:11', None), ('中津川', '21:47', '21:48', None), ('多治見', '22:16', '22:17', None), ('千種', '22:34', '22:34', None), ('名古屋', '22:42', None, '１０')]}
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
