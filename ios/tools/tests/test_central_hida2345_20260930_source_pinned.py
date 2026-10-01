"""Check reviewed September 30 Hida 2–5 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {2: ('21501', '22D'), 3: ('75631', '1023D'), 4: ('23961', '24D'), 5: ('76781', '25D')}
EXPECTED = {2: [('高山', None, '06:45', None), ('久々野', '06:57', '06:57', None), ('飛騨小坂', '07:11', '07:11', None), ('飛騨萩原', '07:22', '07:22', None), ('下呂', '07:30', '07:31', None), ('飛騨金山', '07:50', '07:50', None), ('白川口', '08:03', '08:04', None), ('美濃太田', '08:26', '08:27', None), ('鵜沼', '08:36', '08:37', None), ('岐阜', '08:49', '08:51', None), ('尾張一宮', '09:00', '09:00', None), ('名古屋', '09:12', None, '4')], 3: [('名古屋', None, '08:43', '11'), ('岐阜', '09:02', '09:03', None), ('美濃太田', '09:22', '09:23', None), ('下呂', '10:14', '10:15', None), ('高山', '10:58', '11:03', None), ('飛騨古川', '11:17', '11:18', None), ('猪谷', '11:55', '11:57', None), ('越中八尾', '12:15', '12:15', None), ('富山', '12:32', None, '2')], 4: [('高山', None, '08:00', None), ('久々野', '08:11', '08:12', None), ('飛騨小坂', '08:25', '08:26', None), ('飛騨萩原', '08:36', '08:36', None), ('下呂', '08:44', '08:45', None), ('飛騨金山', '09:05', '09:06', None), ('白川口', '09:19', '09:20', None), ('美濃太田', '09:47', '09:48', None), ('鵜沼', '09:57', '09:57', None), ('岐阜', '10:09', '10:11', None), ('尾張一宮', '10:21', '10:21', None), ('名古屋', '10:34', None, '4')], 5: [('名古屋', None, '09:39', '11'), ('岐阜', '10:00', '10:12', None), ('美濃太田', '10:31', '10:32', None), ('下呂', '11:29', '11:30', None), ('高山', '12:14', '12:20', None), ('飛騨古川', '12:35', None, None)]}
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
 def test_hida25_is_a_separate_segmented_service(self):
  c=json.loads((BASE/'candidates/jr-central-hida5-20260930.json').read_text())
  self.assertEqual(c['trip']['train_number'],'25D')
  other=c['related_service_observation']
  self.assertEqual(other['public_number'],'25')
  self.assertEqual([(r['train_number'],r['origin'],r['destination']) for r in other['train_number_segments']],[('2025D','大阪','岐阜'),('25D','岐阜','高山')])
 def test_only_one_added_day_and_unknown_route_boundaries(self):
  for n in PAGES:
   tid=f'jr-central.hida.{n}.2026-09-30'
   exceptions=[e for e in self.data['calendar_exceptions'] if e['calendar_id']==tid+'.calendar']
   self.assertEqual([(e['service_date'],e['exception_type']) for e in exceptions],[('2026-09-30','add')])
   facts={f['dimension']:f['status'] for f in self.data['fact_completeness'] if f['entity_id']==tid}
   self.assertEqual(facts['operator'],'unknown');self.assertEqual(facts['route_lines'],'unknown')
if __name__=='__main__': unittest.main()
