"""Check reviewed September 30 Hida 10–13 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {10: ('76951', '30D'), 11: ('75651', '1031D'), 12: ('76961', '32D'), 13: ('75181', '1033D')}
EXPECTED = {10: [('高山', None, '12:35', None), ('飛騨小坂', '13:01', '13:01', None), ('飛騨萩原', '13:11', '13:12', None), ('下呂', '13:20', '13:21', None), ('飛騨金山', '13:40', '13:41', None), ('白川口', '13:57', '13:57', None), ('美濃太田', '14:19', '14:19', None), ('鵜沼', '14:28', '14:28', None), ('岐阜', '14:40', '14:42', None), ('尾張一宮', '14:51', '14:51', None), ('名古屋', '15:04', None, '4')], 11: [('名古屋', None, '12:48', '11'), ('岐阜', '13:07', '13:08', None), ('美濃太田', '13:29', '13:29', None), ('下呂', '14:28', '14:29', None), ('高山', '15:12', '15:17', None), ('飛騨古川', '15:30', '15:31', None), ('猪谷', '16:07', '16:09', None), ('越中八尾', '16:27', '16:27', None), ('富山', '16:44', None, '2')], 12: [('飛騨古川', None, '13:12', None), ('高山', '13:27', '13:35', None), ('飛騨萩原', '14:12', '14:12', None), ('下呂', '14:21', '14:22', None), ('飛騨金山', '14:41', '14:42', None), ('白川口', '14:55', '14:55', None), ('美濃太田', '15:18', '15:19', None), ('岐阜', '15:40', '15:43', None), ('名古屋', '16:09', None, '11')], 13: [('名古屋', None, '14:48', '11'), ('岐阜', '15:07', '15:08', None), ('美濃太田', '15:29', '15:30', None), ('下呂', '16:28', '16:29', None), ('高山', '17:13', '17:18', None), ('飛騨古川', '17:31', '17:32', None), ('猪谷', '18:16', '18:17', None), ('越中八尾', '18:35', '18:36', None), ('速星', '18:44', '18:45', None), ('富山', '18:54', None, '3')]}
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
    self.assertEqual(c['calendar_observation']['visual_cell_color'],'blue')
    self.assertEqual(c['calendar_observation']['day'],30)
    self.assertEqual(t['equipment'],['グリーン車指定席','普通車一部指定席'])
    self.assertIsNone(t['formation'])
    spec=importlib.util.spec_from_file_location(f'hida{n}',ROOT/f'ios/tools/normalize-reviewed-central-hida{n}-20260930.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    source=json.loads((BASE/f'sources/source-registry-central-hida{n}-20260930.jsonl').read_text())
    mod.validate(c,source)
    c['calendar_observation']['visual_cell_color']='yellow'
    with self.assertRaises(ValueError): mod.validate(c,source)
 def test_only_one_added_day_and_unknown_route_boundaries(self):
  for n in PAGES:
   tid=f'jr-central.hida.{n}.2026-09-30'
   exceptions=[e for e in self.data['calendar_exceptions'] if e['calendar_id']==tid+'.calendar']
   self.assertEqual([(e['service_date'],e['exception_type']) for e in exceptions],[('2026-09-30','add')])
   facts={f['dimension']:f['status'] for f in self.data['fact_completeness'] if f['entity_id']==tid}
   self.assertEqual(facts['operator'],'unknown');self.assertEqual(facts['route_lines'],'unknown')
if __name__=='__main__': unittest.main()
