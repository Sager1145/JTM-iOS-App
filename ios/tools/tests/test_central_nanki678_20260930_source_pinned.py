"""Check reviewed September 30 Nanki 6–8 identities, calendars and calls."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
sys.path.insert(0, str(ROOT / 'ios/tools'))
import train_timetable as timetable
PAGES = {6: ('28111', '3006D'), 7: ('60401', '3007D'), 8: ('59561', '3008D')}
EXPECTED = {6: [('紀伊勝浦', None, '12:25', None), ('新宮', '12:43', '12:45', None), ('熊野市', '13:04', '13:05', None), ('尾鷲', '13:32', '13:32', None), ('紀伊長島', '13:53', '13:54', None), ('三瀬谷', '14:21', '14:21', None), ('多気', '14:47', '14:48', None), ('松阪', '14:55', '14:56', None), ('津', '15:12', '15:12', None), ('鈴鹿', '15:25', '15:25', None), ('四日市', '15:34', '15:34', None), ('桑名', '15:46', '15:46', None), ('名古屋', '16:12', None, '12')], 7: [('名古屋', None, '19:45', '12'), ('桑名', '20:06', '20:07', None), ('四日市', '20:18', '20:19', None), ('鈴鹿', '20:27', '20:27', None), ('津', '20:41', '20:42', None), ('松阪', '20:57', '20:57', None), ('多気', '21:03', '21:05', None), ('三瀬谷', '21:28', '21:28', None), ('紀伊長島', '21:57', '21:57', None), ('尾鷲', '22:23', '22:24', None), ('熊野市', '22:53', '22:54', None), ('新宮', '23:14', None, None)], 8: [('紀伊勝浦', None, '17:11', None), ('新宮', '17:29', '17:31', None), ('熊野市', '17:50', '17:50', None), ('尾鷲', '18:18', '18:18', None), ('紀伊長島', '18:39', '18:40', None), ('三瀬谷', '19:08', '19:08', None), ('多気', '19:30', '19:32', None), ('松阪', '19:38', '19:39', None), ('津', '19:53', '19:54', None), ('鈴鹿', '20:06', '20:07', None), ('四日市', '20:15', '20:15', None), ('桑名', '20:26', '20:26', None), ('名古屋', '20:49', None, '13')]}
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
 def test_all_eight_proven_inventory_trips_are_staged(self):
  # Closes the persisted proven set only; does not assert unseen extras never exist.
  inventory=json.loads((BASE/'audits/jr-central-shinano-hida-nanki-20260930-inventory.json').read_text())
  expected=[r for r in inventory['trains'] if r['service_id']=='nanki']
  self.assertEqual({r['public_number'] for r in expected},{str(n) for n in range(1,9)})
  actual=[r for r in timetable.materialize(self.data,'2026-09-30') if r['service_id']=='nanki']
  self.assertEqual({(r['public_number'],r['train_number']) for r in actual},{(r['public_number'],r['train_number']) for r in expected})
  self.assertEqual(len(actual),8)
  sources={r['source_id']:r for r in self.data['source_documents']}
  for item in expected:
   trip=next(r for r in actual if r['public_number']==item['public_number'])
   self.assertTrue(item['scheduled_on_date'])
   self.assertTrue(trip['stop_times'])
   for stop in trip['stop_times']:
    self.assertEqual(sources[stop['source_id']]['url_or_locator'],item['source_url'])
 def test_only_one_added_day_and_unknown_route_boundaries(self):
  for n in PAGES:
   tid=f'jr-central.nanki.{n}.2026-09-30'
   exceptions=[e for e in self.data['calendar_exceptions'] if e['calendar_id']==tid+'.calendar']
   self.assertEqual([(e['service_date'],e['exception_type']) for e in exceptions],[('2026-09-30','add')])
   facts={f['dimension']:f['status'] for f in self.data['fact_completeness'] if f['entity_id']==tid}
   self.assertEqual(facts['operator'],'unknown');self.assertEqual(facts['route_lines'],'unknown')
if __name__=='__main__': unittest.main()
