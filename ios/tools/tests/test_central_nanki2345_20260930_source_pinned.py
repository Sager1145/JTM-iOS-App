"""Check reviewed September 30 Nanki 2–5 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {2: ('28031', '3002D'), 3: ('59551', '3003D'), 4: ('28071', '3004D'), 5: ('28091', '3005D')}
EXPECTED = {2: [('新宮', None, '06:20', None), ('熊野市', '06:39', '06:40', None), ('尾鷲', '07:07', '07:07', None), ('紀伊長島', '07:28', '07:29', None), ('三瀬谷', '07:55', '07:56', None), ('多気', '08:18', '08:19', None), ('松阪', '08:25', '08:26', None), ('津', '08:40', '08:41', None), ('鈴鹿', '08:54', '08:54', None), ('四日市', '09:02', '09:04', None), ('桑名', '09:15', '09:16', None), ('名古屋', '09:42', None, '12')], 3: [('名古屋', None, '10:01', '12'), ('桑名', '10:23', '10:23', None), ('四日市', '10:36', '10:37', None), ('鈴鹿', '10:45', '10:45', None), ('津', '10:59', '11:01', None), ('松阪', '11:17', '11:18', None), ('多気', '11:27', '11:29', None), ('三瀬谷', '11:51', '11:51', None), ('紀伊長島', '12:19', '12:21', None), ('尾鷲', '12:42', '12:44', None), ('熊野市', '13:17', '13:18', None), ('新宮', '13:37', '13:39', None), ('紀伊勝浦', '13:58', None, None)], 4: [('紀伊勝浦', None, '08:54', None), ('新宮', '09:11', '09:13', None), ('熊野市', '09:33', '09:33', None), ('尾鷲', '10:01', '10:01', None), ('紀伊長島', '10:22', '10:25', None), ('三瀬谷', '10:51', '10:52', None), ('多気', '11:14', '11:16', None), ('松阪', '11:26', '11:26', None), ('津', '11:41', '11:41', None), ('鈴鹿', '11:54', '11:54', None), ('四日市', '12:03', '12:04', None), ('桑名', '12:16', '12:16', None), ('名古屋', '12:41', None, '12')], 5: [('名古屋', None, '12:58', '12'), ('桑名', '13:22', '13:22', None), ('四日市', '13:36', '13:37', None), ('鈴鹿', '13:45', '13:45', None), ('津', '14:00', '14:00', None), ('松阪', '14:16', '14:16', None), ('多気', '14:22', '14:23', None), ('三瀬谷', '14:45', '14:46', None), ('紀伊長島', '15:12', '15:14', None), ('尾鷲', '15:36', '15:36', None), ('熊野市', '16:04', '16:05', None), ('新宮', '16:24', '16:26', None), ('紀伊勝浦', '16:44', None, None)]}
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
    tid=f'jr-central.nanki.{n}.2026-09-30'; t=today[tid]
    self.assertNotIn(tid,yesterday)
    self.assertEqual((t['public_number'],t['train_number']),(str(n),PAGES[n][1]))
    self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],expected)
    self.assertEqual(self.names[t['origin_station_id']],expected[0][0])
    self.assertEqual(self.names[t['destination_station_id']],expected[-1][0])
 def test_sources_day_cells_equipment_and_rejection_of_wrong_variant(self):
  for n,page in PAGES.items():
   with self.subTest(number=n):
    c=json.loads((BASE/f'candidates/jr-central-nanki{n}-20260930.json').read_text()); t=c['trip']
    self.assertFalse(c['canonical'])
    self.assertEqual(c['source_url'],f'https://timetable.jr-odekake.net/train-timetable/{page[0]}?date=20260930')
    self.assertEqual(c['calendar_observation']['cell_class'],'drivingday-01')
    self.assertEqual(c['calendar_observation']['day'],30)
    self.assertEqual(t['equipment'],['普通車一部指定席'])
    self.assertIsNone(t['formation'])
    spec=importlib.util.spec_from_file_location(f'nanki{n}',ROOT/f'ios/tools/normalize-reviewed-central-nanki{n}-20260930.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    source=json.loads((BASE/f'sources/source-registry-central-nanki{n}-20260930.jsonl').read_text())
    mod.validate(c,source)
    c['calendar_observation']['cell_class']='drivingday-02'
    with self.assertRaises(ValueError): mod.validate(c,source)
 def test_only_one_added_day_and_unknown_route_boundaries(self):
  for n in PAGES:
   tid=f'jr-central.nanki.{n}.2026-09-30'
   exceptions=[e for e in self.data['calendar_exceptions'] if e['calendar_id']==tid+'.calendar']
   self.assertEqual([(e['service_date'],e['exception_type']) for e in exceptions],[('2026-09-30','add')])
   facts={f['dimension']:f['status'] for f in self.data['fact_completeness'] if f['entity_id']==tid}
   self.assertEqual(facts['operator'],'unknown');self.assertEqual(facts['route_lines'],'unknown')
if __name__=='__main__': unittest.main()
