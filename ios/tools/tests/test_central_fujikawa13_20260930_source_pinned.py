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
PAGES = {13: ('33561', '4013M')}
EXPECTED = {13: [('静岡', None, '19:45', '2'), ('清水', '19:54', '19:55', None), ('富士', '20:12', '20:15', None), ('富士宮', '20:26', '20:27', None), ('内船', '20:58', '20:58', None), ('身延', '21:12', '21:13', None), ('下部温泉', '21:22', '21:23', None), ('甲斐岩間', '21:33', '21:33', None), ('鰍沢口', '21:40', '21:40', None), ('市川大門', '21:44', '21:44', None), ('東花輪', '21:51', '21:52', None), ('南甲府', '22:00', '22:01', None), ('甲府', '22:06', None, None)]}
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
    self.assertEqual(c['source_url'],f'https://timetable.jr-odekake.net/train-timetable/{page[0]}?date=20260930')
    self.assertEqual(c['calendar_observation']['cell_class'],'drivingday-01')
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
