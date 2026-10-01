"""Check reviewed September 30 Shinano 7/8/9/11 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {7: '000/000171', 8: '000/000201', 9: '040/044911', 11: '000/000271'}
EXPECTED = {7: [('名古屋', None, '10:00', '１０'), ('千種', '10:06', '10:06', None), ('多治見', '10:22', '10:22', None), ('中津川', '10:48', '10:48', None), ('南木曽', '10:59', '11:00', None), ('木曽福島', '11:24', '11:25', None), ('塩尻', '11:54', '11:55', None), ('松本', '12:04', '12:06', '３'), ('篠ノ井', '12:51', '12:51', None), ('長野', '12:59', None, '２')], 8: [('長野', None, '10:00', '６'), ('篠ノ井', '10:08', '10:08', None), ('松本', '10:50', '10:51', '１'), ('塩尻', '10:59', '11:02', None), ('木曽福島', '11:29', '11:30', None), ('中津川', '12:05', '12:06', None), ('多治見', '12:34', '12:34', None), ('千種', '12:52', '12:53', None), ('名古屋', '13:01', None, '１１')], 9: [('名古屋', None, '11:00', '１０'), ('千種', '11:06', '11:06', None), ('多治見', '11:23', '11:23', None), ('中津川', '11:48', '11:49', None), ('木曽福島', '12:24', '12:25', None), ('塩尻', '12:53', '12:55', None), ('松本', '13:05', '13:06', '２'), ('篠ノ井', '13:51', '13:51', None), ('長野', '13:59', None, '７')], 11: [('名古屋', None, '12:00', '１０'), ('千種', '12:06', '12:06', None), ('多治見', '12:23', '12:23', None), ('中津川', '12:48', '12:49', None), ('木曽福島', '13:24', '13:25', None), ('塩尻', '13:53', '13:54', None), ('松本', '14:03', '14:06', '２'), ('篠ノ井', '14:51', '14:52', None), ('長野', '15:00', None, '２')]}
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
