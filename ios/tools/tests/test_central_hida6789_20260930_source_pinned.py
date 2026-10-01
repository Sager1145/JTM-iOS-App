"""Check reviewed September 30 Hida 6–9 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {6: ('75191', '1026D'), 7: ('75641', '1027D'), 8: ('124601', '1028D'), 9: ('76941', '29D')}
EXPECTED = {6: [('富山', None, '07:58', '3'), ('速星', '08:06', '08:07', None), ('越中八尾', '08:15', '08:16', None), ('猪谷', '08:35', '08:37', None), ('飛騨古川', '09:13', '09:14', None), ('高山', '09:28', '09:36', None), ('下呂', '10:26', '10:27', None), ('美濃太田', '11:18', '11:19', None), ('岐阜', '11:40', '11:43', None), ('名古屋', '12:04', None, '4')], 7: [('名古屋', None, '10:48', '11'), ('岐阜', '11:07', '11:08', None), ('美濃太田', '11:29', '11:30', None), ('下呂', '12:27', '12:29', None), ('高山', '13:12', '13:17', None), ('飛騨古川', '13:32', '13:32', None), ('猪谷', '14:12', '14:14', None), ('越中八尾', '14:32', '14:32', None), ('速星', '14:41', '14:41', None), ('富山', '14:51', None, '3')], 8: [('富山', None, '09:54', '1'), ('越中八尾', '10:10', '10:10', None), ('猪谷', '10:29', '10:31', None), ('飛騨古川', '11:07', '11:08', None), ('高山', '11:25', '11:35', None), ('下呂', '12:21', '12:22', None), ('美濃太田', '13:17', '13:19', None), ('岐阜', '13:40', '13:43', None), ('名古屋', '14:04', None, '4')], 9: [('名古屋', None, '11:43', '11'), ('尾張一宮', '11:54', '11:54', None), ('岐阜', '12:04', '12:05', None), ('美濃太田', '12:25', '12:25', None), ('飛騨金山', '13:01', '13:01', None), ('下呂', '13:26', '13:28', None), ('高山', '14:14', None, None)]}
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
