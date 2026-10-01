"""Check reviewed September 30 Fujikawa 2–5 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {2: ('010/011061', '4002M'), 4: ('010/011071', '4004M')}
EXPECTED = {2: [('甲府', None, '06:20', None), ('南甲府', '06:24', '06:25', None), ('東花輪', '06:33', '06:34', None), ('市川大門', '06:41', '06:42', None), ('鰍沢口', '06:45', '06:46', None), ('甲斐岩間', '06:53', '06:53', None), ('下部温泉', '07:04', '07:04', None), ('身延', '07:14', '07:15', None), ('内船', '07:27', '07:28', None), ('富士宮', '07:59', '08:00', None), ('富士', '08:11', '08:14', None), ('清水', '08:32', '08:33', None), ('静岡', '08:43', None, '３')], 4: [('甲府', None, '08:45', None), ('南甲府', '08:49', '08:50', None), ('東花輪', '08:58', '08:58', None), ('市川大門', '09:05', '09:06', None), ('鰍沢口', '09:09', '09:10', None), ('甲斐岩間', '09:16', '09:17', None), ('下部温泉', '09:26', '09:27', None), ('身延', '09:36', '09:39', None), ('内船', '09:52', '09:53', None), ('富士宮', '10:23', '10:23', None), ('富士', '10:34', '10:37', None), ('清水', '10:53', '10:53', None), ('静岡', '11:02', None, '３')]}
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
    tid=f'jr-central.fujikawa.{n}.2026-09-30'; t=today[tid]
    self.assertNotIn(tid,yesterday)
    self.assertEqual((t['public_number'],t['train_number']),(str(n),PAGES[n][1]))
    self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],expected)
    self.assertEqual(self.names[t['origin_station_id']],expected[0][0])
    self.assertEqual(self.names[t['destination_station_id']],expected[-1][0])
 def test_sources_day_cells_equipment_and_rejection_of_wrong_variant(self):
  for n,page in PAGES.items():
   with self.subTest(number=n):
    c=json.loads((BASE/f'candidates/jr-central-fujikawa{n}-20260930.json').read_text()); t=c['trip']
    self.assertFalse(c['canonical'])
    self.assertEqual(c['source_url'],f'https://timetables.jreast.co.jp/2610/train/{page[0]}.html')
    self.assertEqual(c['calendar_observation']['cell_class'],'ok')
    self.assertEqual(c['calendar_observation']['day'],30)
    self.assertEqual(t['equipment'],['普通車一部指定席'])
    self.assertIsNone(t['formation'])
    spec=importlib.util.spec_from_file_location(f'fujikawa{n}',ROOT/f'ios/tools/normalize-reviewed-central-fujikawa{n}-20260930.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    source=json.loads((BASE/f'sources/source-registry-central-fujikawa{n}-20260930.jsonl').read_text())
    mod.validate(c,source)
    c['calendar_observation']['cell_class']='drivingday-02'
    with self.assertRaises(ValueError): mod.validate(c,source)
 def test_only_one_added_day_and_unknown_route_boundaries(self):
  for n in PAGES:
   tid=f'jr-central.fujikawa.{n}.2026-09-30'
   exceptions=[e for e in self.data['calendar_exceptions'] if e['calendar_id']==tid+'.calendar']
   self.assertEqual([(e['service_date'],e['exception_type']) for e in exceptions],[('2026-09-30','add')])
   facts={f['dimension']:f['status'] for f in self.data['fact_completeness'] if f['entity_id']==tid}
   self.assertEqual(facts['operator'],'unknown');self.assertEqual(facts['route_lines'],'unknown')
if __name__=='__main__': unittest.main()
