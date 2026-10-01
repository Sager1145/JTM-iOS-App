"""Check reviewed September 30 Shinano 12/13/14/15 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {12: '000/000301', 13: '020/020031', 14: '000/000321', 15: '020/020041'}
EXPECTED = {12: [('長野', None, '12:00', '６'), ('篠ノ井', '12:08', '12:08', None), ('松本', '12:51', '12:53', '１'), ('塩尻', '13:01', '13:03', None), ('木曽福島', '13:30', '13:30', None), ('中津川', '14:05', '14:06', None), ('恵那', '14:14', '14:14', None), ('多治見', '14:34', '14:34', None), ('千種', '14:52', '14:53', None), ('名古屋', '15:01', None, '１１')], 13: [('名古屋', None, '13:00', '１０'), ('千種', '13:06', '13:06', None), ('多治見', '13:23', '13:23', None), ('恵那', '13:41', '13:42', None), ('中津川', '13:50', '13:50', None), ('木曽福島', '14:24', '14:25', None), ('塩尻', '14:54', '14:56', None), ('松本', '15:05', '15:06', '２'), ('篠ノ井', '15:51', '15:52', None), ('長野', '16:00', None, '２')], 14: [('長野', None, '13:00', '６'), ('篠ノ井', '13:08', '13:08', None), ('松本', '13:53', '13:56', '１'), ('塩尻', '14:04', '14:06', None), ('木曽福島', '14:33', '14:33', None), ('中津川', '15:09', '15:09', None), ('多治見', '15:37', '15:37', None), ('千種', '15:56', '15:57', None), ('名古屋', '16:07', None, '１０')], 15: [('名古屋', None, '14:00', '１０'), ('千種', '14:06', '14:06', None), ('多治見', '14:23', '14:23', None), ('中津川', '14:48', '14:49', None), ('木曽福島', '15:24', '15:25', None), ('塩尻', '15:53', '15:55', None), ('松本', '16:04', '16:05', '３'), ('明科', '16:16', '16:16', None), ('篠ノ井', '16:47', '16:47', None), ('長野', '16:56', None, '７')]}
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
