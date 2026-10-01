"""Check reviewed September 30 Hida 14–17 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {14: ('75701', '1034D'), 15: ('32271', '35D'), 16: ('76971', '36D'), 17: ('33011', '37D')}
EXPECTED = {14: [('富山', None, '13:08', '2'), ('速星', '13:16', '13:17', None), ('越中八尾', '13:25', '13:26', None), ('猪谷', '13:45', '13:46', None), ('飛騨古川', '14:24', '14:24', None), ('高山', '14:39', '14:46', None), ('下呂', '15:31', '15:32', None), ('美濃太田', '16:23', '16:23', None), ('岐阜', '16:43', '16:45', None), ('名古屋', '17:05', None, '11')], 15: [('名古屋', None, '16:03', '11'), ('岐阜', '16:22', '16:25', None), ('鵜沼', '16:46', '16:47', None), ('美濃太田', '16:56', '16:58', None), ('白川口', '17:23', '17:23', None), ('飛騨金山', '17:36', '17:37', None), ('下呂', '17:58', '17:59', None), ('飛騨萩原', '18:08', '18:09', None), ('高山', '18:45', None, None)], 16: [('高山', None, '15:34', None), ('下呂', '16:17', '16:18', None), ('美濃太田', '17:17', '17:17', None), ('岐阜', '17:37', '17:43', None), ('名古屋', '18:06', None, '12')], 17: [('名古屋', None, '18:12', '11'), ('岐阜', '18:35', '18:40', None), ('鵜沼', '18:51', '18:51', None), ('美濃太田', '19:00', '19:01', None), ('白川口', '19:23', '19:23', None), ('飛騨金山', '19:37', '19:37', None), ('下呂', '20:04', '20:05', None), ('飛騨萩原', '20:12', '20:13', None), ('飛騨小坂', '20:23', '20:24', None), ('久々野', '20:38', '20:39', None), ('高山', '20:51', None, None)]}
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
    tid=f'jr-central.hida.{n}.2026-09-30'; t=today[tid]
    self.assertNotIn(tid,yesterday)
    self.assertEqual((t['public_number'],t['train_number']),(str(n),PAGES[n][1]))
    self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],expected)
    self.assertEqual(self.names[t['origin_station_id']],expected[0][0])
    self.assertEqual(self.names[t['destination_station_id']],expected[-1][0])
 def test_sources_day_cells_equipment_and_rejection_of_wrong_variant(self):
  for n,page in PAGES.items():
   with self.subTest(number=n):
    c=json.loads((BASE/f'candidates/jr-central-hida{n}-20260930.json').read_text()); t=c['trip']
    self.assertFalse(c['canonical'])
    self.assertEqual(c['source_url'],f'https://timetable.jr-odekake.net/train-timetable/{page[0]}?date=20260930')
    self.assertEqual(c['calendar_observation']['cell_class'],'drivingday-01')
    self.assertEqual(c['calendar_observation']['day'],30)
    self.assertEqual(t['equipment'],['グリーン車指定席','普通車一部指定席'])
    self.assertIsNone(t['formation'])
    spec=importlib.util.spec_from_file_location(f'hida{n}',ROOT/f'ios/tools/normalize-reviewed-central-hida{n}-20260930.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    source=json.loads((BASE/f'sources/source-registry-central-hida{n}-20260930.jsonl').read_text())
    mod.validate(c,source)
    c['calendar_observation']['cell_class']='drivingday-02'
    with self.assertRaises(ValueError): mod.validate(c,source)
 def test_hida36_is_a_separate_segmented_service(self):
  c=json.loads((BASE/'candidates/jr-central-hida16-20260930.json').read_text())
  self.assertEqual(c['trip']['train_number'],'36D')
  other=c['related_service_observation']
  self.assertEqual(other['public_number'],'36')
  self.assertEqual([(r['train_number'],r['origin'],r['destination']) for r in other['train_number_segments']],[('36D','高山','岐阜'),('2036D','岐阜','大阪')])
  self.assertEqual((other['gifu_arrival'],other['gifu_departure']),('17:37','17:45'))
 def test_only_one_added_day_and_unknown_route_boundaries(self):
  for n in PAGES:
   tid=f'jr-central.hida.{n}.2026-09-30'
   exceptions=[e for e in self.data['calendar_exceptions'] if e['calendar_id']==tid+'.calendar']
   self.assertEqual([(e['service_date'],e['exception_type']) for e in exceptions],[('2026-09-30','add')])
   facts={f['dimension']:f['status'] for f in self.data['fact_completeness'] if f['entity_id']==tid}
   self.assertEqual(facts['operator'],'unknown');self.assertEqual(facts['route_lines'],'unknown')
if __name__=='__main__': unittest.main()
