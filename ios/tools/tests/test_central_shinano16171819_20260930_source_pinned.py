"""Check reviewed September 30 Shinano 16/17/18/19 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {16: '040/044921', 17: '000/000381', 18: '020/020081', 19: '000/000411'}
EXPECTED = {16: [('長野', None, '14:00', '６'), ('篠ノ井', '14:09', '14:09', None), ('松本', '14:51', '14:54', '１'), ('塩尻', '15:02', '15:03', None), ('木曽福島', '15:30', '15:31', None), ('南木曽', '15:55', '15:55', None), ('中津川', '16:08', '16:09', None), ('多治見', '16:37', '16:37', None), ('千種', '16:56', '16:57', None), ('名古屋', '17:07', None, '１０')], 17: [('名古屋', None, '15:00', '１０'), ('千種', '15:06', '15:06', None), ('多治見', '15:23', '15:23', None), ('中津川', '15:48', '15:49', None), ('南木曽', '16:00', '16:00', None), ('木曽福島', '16:25', '16:25', None), ('塩尻', '16:54', '16:55', None), ('松本', '17:04', '17:05', '２'), ('篠ノ井', '17:51', '17:52', None), ('長野', '18:00', None, '５')], 18: [('長野', None, '15:00', '６'), ('篠ノ井', '15:08', '15:09', None), ('松本', '15:51', '15:53', '１'), ('塩尻', '16:01', '16:03', None), ('木曽福島', '16:30', '16:30', None), ('南木曽', '16:55', '16:55', None), ('中津川', '17:08', '17:09', None), ('多治見', '17:37', '17:37', None), ('千種', '17:58', '17:59', None), ('名古屋', '18:10', None, '１０')], 19: [('名古屋', None, '16:00', '１０'), ('千種', '16:06', '16:06', None), ('多治見', '16:22', '16:23', None), ('中津川', '16:48', '16:49', None), ('木曽福島', '17:24', '17:25', None), ('塩尻', '17:54', '17:55', None), ('松本', '18:04', '18:05', '３'), ('明科', '18:16', '18:16', None), ('篠ノ井', '18:50', '18:51', None), ('長野', '18:59', None, '２')]}
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
