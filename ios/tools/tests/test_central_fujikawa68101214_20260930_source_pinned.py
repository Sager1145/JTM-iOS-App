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
PAGES = {6: ('010/011081', '4006M'), 8: ('010/011091', '4008M'), 10: ('010/011111', '4010M'), 12: ('010/011121', '4012M'), 14: ('010/011131', '4014M')}
EXPECTED = {6: [('甲府', None, '10:44', None), ('南甲府', '10:48', '10:49', None), ('東花輪', '10:57', '10:57', None), ('市川大門', '11:05', '11:05', None), ('鰍沢口', '11:09', '11:10', None), ('甲斐岩間', '11:17', '11:17', None), ('下部温泉', '11:27', '11:27', None), ('身延', '11:36', '11:38', None), ('内船', '11:50', '11:50', None), ('富士宮', '12:20', '12:21', None), ('富士', '12:32', '12:34', None), ('清水', '12:51', '12:52', None), ('静岡', '13:02', None, '３')], 8: [('甲府', None, '12:37', None), ('南甲府', '12:42', '12:42', None), ('東花輪', '12:51', '12:52', None), ('市川大門', '12:59', '12:59', None), ('鰍沢口', '13:03', '13:03', None), ('甲斐岩間', '13:10', '13:11', None), ('下部温泉', '13:21', '13:21', None), ('身延', '13:30', '13:32', None), ('内船', '13:44', '13:44', None), ('富士宮', '14:14', '14:14', None), ('富士', '14:26', '14:29', None), ('清水', '14:46', '14:46', None), ('静岡', '14:56', None, '３')], 10: [('甲府', None, '14:35', None), ('南甲府', '14:39', '14:40', None), ('東花輪', '14:48', '14:48', None), ('市川大門', '14:55', '14:56', None), ('鰍沢口', '14:59', '15:00', None), ('甲斐岩間', '15:06', '15:07', None), ('下部温泉', '15:16', '15:20', None), ('身延', '15:29', '15:30', None), ('内船', '15:42', '15:43', None), ('富士宮', '16:13', '16:13', None), ('富士', '16:25', '16:29', None), ('清水', '16:48', '16:48', None), ('静岡', '16:58', None, '４')], 12: [('甲府', None, '16:35', None), ('南甲府', '16:39', '16:40', None), ('東花輪', '16:48', '16:48', None), ('市川大門', '16:55', '16:56', None), ('鰍沢口', '16:59', '17:00', None), ('甲斐岩間', '17:06', '17:07', None), ('下部温泉', '17:16', '17:19', None), ('身延', '17:28', '17:29', None), ('内船', '17:42', '17:43', None), ('富士宮', '18:12', '18:13', None), ('富士', '18:24', '18:28', None), ('清水', '18:46', '18:46', None), ('静岡', '18:56', None, '３')], 14: [('甲府', None, '18:36', None), ('南甲府', '18:40', '18:41', None), ('東花輪', '18:49', '18:49', None), ('市川大門', '18:56', '18:56', None), ('鰍沢口', '19:00', '19:00', None), ('甲斐岩間', '19:07', '19:07', None), ('下部温泉', '19:17', '19:20', None), ('身延', '19:30', '19:31', None), ('内船', '19:45', '19:45', None), ('富士宮', '20:16', '20:16', None), ('富士', '20:27', '20:31', None), ('清水', '20:50', '20:51', None), ('静岡', '21:00', None, '４')]}
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
