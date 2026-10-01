"""NEX1/7 coupled columns and NEX11/42 single columns, exact September30."""
import json,sys,unittest,importlib.util
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=Path(__file__).resolve().parents[3]/'app/data/train-service-history'
EXPECTED = {'1': {'candidate_id': 'jr-east-narita-express1-20260930', 'candidate_status': 'reviewed_official_html', 'canonical': False, 'service_date': '2026-09-30', 'source_id': 'jr-east-narita-express1-20260930', 'source_url': 'https://timetables.jreast.co.jp/2610/train/030/031131.html', 'source_locator': '2026年9月30日 td.ok; full printed numbered columns', 'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'}, 'coupling_note': '東京－成田空港は2201Mを併結 / 東京－成田空港は2001Mに併結', 'printed_operating_labels': ['１１月７日は運休 １１月８日は運休', '１１月７日は運休 １１月８日は運休'], 'printed_remarks': ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です', '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です'], 'trips': [{'trip_id': 'jr-east.narita-express.1.2001m.exact-2026-09-30', 'train_number': '2001M', 'origin': '大船', 'destination': '成田空港', 'stops': [['大船', None, '05:28', '５', 'origin'], ['戸塚', '05:32', '05:33', None, 'passenger_stop'], ['横浜', '05:43', '05:44', '１０', 'passenger_stop'], ['武蔵小杉', '05:54', '05:55', None, 'passenger_stop'], ['品川', '06:04', '06:05', '１３', 'passenger_stop'], ['東京', '06:12', '06:18', '４', 'passenger_stop'], ['千葉', '06:43', '06:44', '１０', 'passenger_stop'], ['空港第２ビル', '07:15', '07:17', None, 'passenger_stop'], ['成田空港', '07:19', None, None, 'destination']], 'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'], 'formation': None}, {'trip_id': 'jr-east.narita-express.1.2201m.exact-2026-09-30', 'train_number': '2201M', 'origin': '新宿', 'destination': '成田空港', 'stops': [['新宿', None, '05:55', '６', 'origin'], ['渋谷', '06:00', '06:01', None, 'passenger_stop'], ['品川', None, None, None, 'pass'], ['東京', '06:16', None, '４', 'passenger_stop'], ['千葉', None, None, None, 'passenger_stop'], ['空港第２ビル', None, None, None, 'passenger_stop'], ['成田空港', None, None, None, 'destination']], 'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'], 'formation': None}]}, '7': {'candidate_id': 'jr-east-narita-express7-20260930', 'candidate_status': 'reviewed_official_html', 'canonical': False, 'service_date': '2026-09-30', 'source_id': 'jr-east-narita-express7-20260930', 'source_url': 'https://timetables.jreast.co.jp/2610/train/030/031151.html', 'source_locator': '2026年9月30日 td.ok; full printed numbered columns', 'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'}, 'coupling_note': '東京－成田空港は2207Mを併結 / 東京－成田空港は2007Mに併結', 'printed_operating_labels': ['１１月７日は運休', '１１月７日は運休'], 'printed_remarks': ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です', '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です'], 'trips': [{'trip_id': 'jr-east.narita-express.7.2007m.exact-2026-09-30', 'train_number': '2007M', 'origin': '大船', 'destination': '成田空港', 'stops': [['大船', None, '07:00', '６', 'origin'], ['戸塚', '07:05', '07:06', None, 'passenger_stop'], ['横浜', '07:16', '07:17', '１０', 'passenger_stop'], ['武蔵小杉', '07:28', '07:29', None, 'passenger_stop'], ['品川', '07:38', '07:39', '１３', 'passenger_stop'], ['東京', '07:48', '07:56', '４', 'passenger_stop'], ['千葉', '08:29', '08:30', '１０', 'passenger_stop'], ['空港第２ビル', '08:58', '09:00', None, 'passenger_stop'], ['成田空港', '09:02', None, None, 'destination']], 'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'], 'formation': None}, {'trip_id': 'jr-east.narita-express.7.2207m.exact-2026-09-30', 'train_number': '2207M', 'origin': '新宿', 'destination': '成田空港', 'stops': [['新宿', None, '07:27', '６', 'origin'], ['渋谷', '07:33', '07:33', None, 'passenger_stop'], ['品川', None, None, None, 'pass'], ['東京', '07:52', None, '４', 'passenger_stop'], ['千葉', None, None, None, 'passenger_stop'], ['空港第２ビル', None, None, None, 'passenger_stop'], ['成田空港', None, None, None, 'destination']], 'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'], 'formation': None}]}, '11': {'candidate_id': 'jr-east-narita-express11-20260930', 'candidate_status': 'reviewed_official_html', 'canonical': False, 'service_date': '2026-09-30', 'source_id': 'jr-east-narita-express11-20260930', 'source_url': 'https://timetables.jreast.co.jp/2610/train/095/098841.html', 'source_locator': '2026年9月30日 td.ok; full printed numbered columns', 'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'}, 'coupling_note': '', 'printed_operating_labels': ['１１月７日は運休'], 'printed_remarks': ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です'], 'trips': [{'trip_id': 'jr-east.narita-express.11.2011m.exact-2026-09-30', 'train_number': '2011M', 'origin': '大船', 'destination': '成田空港', 'stops': [['大船', None, '08:08', '６', 'origin'], ['戸塚', '08:13', '08:14', None, 'passenger_stop'], ['横浜', '08:24', '08:26', '１０', 'passenger_stop'], ['武蔵小杉', '08:38', '08:38', None, 'passenger_stop'], ['品川', '08:48', '08:49', '１３', 'passenger_stop'], ['東京', '08:57', '09:00', '４', 'passenger_stop'], ['千葉', '09:28', '09:29', '１０', 'passenger_stop'], ['空港第２ビル', '09:54', '09:56', None, 'passenger_stop'], ['成田空港', '09:58', None, None, 'destination']], 'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'], 'formation': None}]}, '42': {'candidate_id': 'jr-east-narita-express42-20260930', 'candidate_status': 'reviewed_official_html', 'canonical': False, 'service_date': '2026-09-30', 'source_id': 'jr-east-narita-express42-20260930', 'source_url': 'https://timetables.jreast.co.jp/2610/train/025/029081.html', 'source_locator': '2026年9月30日 td.ok; full printed numbered columns', 'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'}, 'coupling_note': '', 'printed_operating_labels': ['１１月７日は運休'], 'printed_remarks': ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です'], 'trips': [{'trip_id': 'jr-east.narita-express.42.2042m.exact-2026-09-30', 'train_number': '2042M', 'origin': '成田空港', 'destination': '大船', 'stops': [['成田空港', None, '17:45', None, 'origin'], ['空港第２ビル', '17:46', '17:48', None, 'passenger_stop'], ['千葉', '18:19', '18:20', '７', 'passenger_stop'], ['東京', '18:48', '18:50', '１', 'passenger_stop'], ['品川', '18:56', '18:57', '１５', 'passenger_stop'], ['武蔵小杉', '19:06', '19:07', None, 'passenger_stop'], ['横浜', '19:19', '19:20', '９', 'passenger_stop'], ['戸塚', '19:31', '19:32', None, 'passenger_stop'], ['大船', '19:38', None, '７', 'destination']], 'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'], 'formation': None}]}}
class SourcePinnedTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE))
  cls.names={r['station_id']:r['name_snapshot'] for r in cls.data['station_identities']}
 def test_all_printed_columns_clocks_platforms_and_nulls(self):
  day={r['trip_id']:r for r in timetable.materialize(self.data,'2026-09-30')}
  for n,c in EXPECTED.items():
   for t in c['trips']:
    actual=day[t['trip_id']]
    self.assertEqual(actual['train_number'],t['train_number'])
    expected=[['空港第2ビル' if r[0]=='空港第２ビル' else r[0]]+r[1:] for r in t['stops']]
    self.assertEqual([[self.names[r['station_id']],r['arrival_time'],r['departure_time'],r['platform'],r['call_type']] for r in actual['stop_times']],expected)
 def test_source_and_exact_day(self):
  for n,c in EXPECTED.items():
   source=next(r for r in self.data['source_documents'] if r['source_id']==c['source_id'])
   self.assertEqual(source['url_or_locator'],c['source_url'])
   for d in ['2026-09-29','2026-10-01']:
    day={r['trip_id'] for r in timetable.materialize(self.data,d)}
    self.assertFalse(day.intersection(t['trip_id'] for t in c['trips']))
 def test_coupling_relations_and_unknowns(self):
  for n,c in EXPECTED.items():
   ids={t['trip_id'] for t in c['trips']}
   relations=[r for r in self.data['trip_relations'] if r['trip_id'] in ids]
   self.assertEqual(len(relations),2 if n in ['1','7'] else 0)
   if n in ['1','7']:
    self.assertEqual(sorted((r['from_sequence'],r['to_sequence']) for r in relations),[(4,7),(6,9)])
    for r in relations:self.assertEqual(r['relation_type'],'couples_with')
   for t in c['trips']:self.assertIsNone(t['formation'])
 def test_source_pinned_normalizers(self):
  for n,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-narita-express{n}-20260930.json').read_text())
   self.assertEqual(c,expected)
   spec=importlib.util.spec_from_file_location('nex',TOOLS/f'normalize-reviewed-east-narita-express{n}-20260930.py')
   mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);mod.validate(c)
   c['calendar_observation']['cell_class']='none'
   with self.assertRaises(ValueError):mod.validate(c)
if __name__=='__main__':unittest.main()
