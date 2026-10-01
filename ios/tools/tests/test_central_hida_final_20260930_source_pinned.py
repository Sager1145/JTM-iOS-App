"""Check reviewed September 30 Hida 18/19/20/25/36 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {18: ('124611', '38D'), 19: ('33251', '39D'), 20: ('75201', '1040D'), 25: ('76781', '2025D'), 36: ('76971', '36D')}
EXPECTED = {18: [('高山', None, '16:33', None), ('飛騨萩原', '17:12', '17:13', None), ('下呂', '17:21', '17:22', None), ('飛騨金山', '17:44', '17:45', None), ('美濃太田', '18:18', '18:19', None), ('岐阜', '18:39', '18:41', None), ('名古屋', '19:06', None, '11')], 19: [('名古屋', None, '20:17', '11'), ('尾張一宮', '20:29', '20:29', None), ('岐阜', '20:38', '20:43', None), ('美濃太田', '21:02', '21:03', None), ('白川口', '21:24', '21:24', None), ('飛騨金山', '21:38', '21:38', None), ('下呂', '22:02', '22:02', None), ('飛騨萩原', '22:10', '22:11', None), ('飛騨小坂', '22:22', '22:22', None), ('高山', '22:49', None, None)], 20: [('富山', None, '17:14', '2'), ('越中八尾', '17:30', '17:30', None), ('猪谷', '17:49', '17:50', None), ('飛騨古川', '18:27', '18:27', None), ('高山', '18:41', '18:48', None), ('下呂', '19:29', '19:30', None), ('美濃太田', '20:21', '20:22', None), ('岐阜', '20:42', '20:44', None), ('名古屋', '21:03', None, '4')], 25: [('大阪', None, '07:58', '11'), ('新大阪', '08:03', '08:04', '4'), ('京都', '08:29', '08:31', '0'), ('草津', '08:50', '08:51', None), ('米原', '09:20', '09:22', '8'), ('大垣', '09:46', '09:46', None), ('岐阜', '09:56', '10:12', None), ('美濃太田', '10:31', '10:32', None), ('下呂', '11:29', '11:30', None), ('高山', '12:14', None, None)], 36: [('高山', None, '15:34', None), ('下呂', '16:17', '16:18', None), ('美濃太田', '17:17', '17:17', None), ('岐阜', '17:37', '17:45', None), ('大垣', '17:53', '17:54', None), ('米原', '18:22', '18:23', '2'), ('草津', '19:01', '19:02', None), ('京都', '19:17', '19:18', '6'), ('新大阪', '19:44', '19:45', '9'), ('大阪', '19:50', None, '3')]}
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
    self.assertEqual(t['equipment'],['普通車一部指定席'] if n in (25,36) else ['グリーン車指定席','普通車一部指定席'])
    self.assertIsNone(t['formation'])
    spec=importlib.util.spec_from_file_location(f'hida{n}',ROOT/f'ios/tools/normalize-reviewed-central-hida{n}-20260930.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    source=json.loads((BASE/f'sources/source-registry-central-hida{n}-20260930.jsonl').read_text())
    mod.validate(c,source)
    c['calendar_observation']['cell_class']='drivingday-02'
    with self.assertRaises(ValueError): mod.validate(c,source)
 def test_coupled_public_services_and_number_segments(self):
  today={t['trip_id']:t for t in timetable.materialize(self.data,'2026-09-30')}
  for n,expected in [(25,[(1,7,'2025D'),(7,10,'25D')]),(36,[(1,4,'36D'),(4,10,'2036D')])]:
   tid=f'jr-central.hida.{n}.2026-09-30'
   rows=[r for r in self.data['trip_number_segments'] if r['trip_id']==tid]
   self.assertEqual([(r['from_sequence'],r['to_sequence'],r['train_number']) for r in rows],expected)
   self.assertEqual(len(today[tid]['stop_times']),10)
   relations=[r for r in self.data['trip_relations'] if r['trip_id']==tid]
   self.assertEqual([(r['related_trip_id'],r['relation_type'],r['from_sequence'],r['to_sequence']) for r in relations],[(f'jr-central.hida.{5 if n==25 else 16}.2026-09-30','couples_with',7 if n==25 else 1,10 if n==25 else 4)])
 def test_only_one_added_day_and_unknown_route_boundaries(self):
  for n in PAGES:
   tid=f'jr-central.hida.{n}.2026-09-30'
   exceptions=[e for e in self.data['calendar_exceptions'] if e['calendar_id']==tid+'.calendar']
   self.assertEqual([(e['service_date'],e['exception_type']) for e in exceptions],[('2026-09-30','add')])
   facts={f['dimension']:f['status'] for f in self.data['fact_completeness'] if f['entity_id']==tid}
   self.assertEqual(facts['operator'],'unknown');self.assertEqual(facts['route_lines'],'unknown')
if __name__=='__main__': unittest.main()
