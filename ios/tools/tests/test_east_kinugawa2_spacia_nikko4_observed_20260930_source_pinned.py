"""Official Nikko/Kinugawa individual dates, calls and vehicle remarks."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'kinugawa': [('鬼怒川温泉', None, '14:55', None),
              ('東武ワールドスクウェア', '14:57', '14:58', None),
              ('下今市', '15:19', '15:21', None),
              ('新鹿沼', '15:37', '15:37', None),
              ('栃木', '15:52', '15:53', None),
              ('大宮', '16:37', '16:38', '４'),
              ('浦和', '16:43', '16:44', None),
              ('池袋', '17:02', '17:03', '２'),
              ('新宿', '17:09', None, '６')],
 'spacia-nikko': [('東武日光', None, '16:38', None),
                  ('下今市', '16:45', '16:46', None),
                  ('新鹿沼', '17:01', '17:02', None),
                  ('栃木', '17:17', '17:19', None),
                  ('大宮', '18:03', '18:04', '４'),
                  ('浦和', '18:10', '18:11', None),
                  ('池袋', '18:29', '18:30', '２'),
                  ('新宿', '18:35', None, '６')]}
class NikkoKinugawaTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.inventory=json.loads((BASE/'audits/jr-east-nikko-kinugawa-omiya-observed-20260930-inventory.json').read_text());cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']}
 def test_new_exact_source_columns(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for service,expected in EXPECTED.items():
   n,number,vehicle=('2','1082M','253系') if service=='kinugawa' else ('4','1094M','100系');c=json.loads((BASE/f'candidates/jr-east-{service}{n}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],number);self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],expected)
   f=next(f for f in self.data['trip_formations'] if f['trip_id']==t['trip_id']);self.assertEqual(f['vehicle_series'],vehicle);self.assertEqual(f['evidence_kind'],'planned');self.assertTrue(f['all_reserved']);self.assertEqual(f['green_car_available'],None if service=='kinugawa' else True)
   self.assertIsNone(f['car_count']);self.assertIsNone(f['reserved_seat_capacity']);self.assertFalse([s for s in self.data['trip_number_segments'] if s['trip_id']==t['trip_id']])
 def test_observed_date_variants_and_bounded_closure(self):
  running=[e for e in self.inventory['trains'] if e['scheduled_on_date']];rejected=[e for e in self.inventory['trains'] if not e['scheduled_on_date']]
  self.assertEqual({e['printed_name'] for e in running},{'きぬがわ 2号','きぬがわ 3号','スペーシア日光 1号','スペーシア日光 4号'});self.assertEqual(len(rejected),7)
  for e in running:self.assertEqual(e['date_evidence']['cell_class'],'ok')
  for e in rejected:self.assertEqual(e['date_evidence']['cell_class'],'none')
  day=[t for t in timetable.materialize(self.data,'2026-09-30') if t['service_id'] in ['kinugawa','spacia-nikko']];self.assertEqual(len(day),4);self.assertEqual(sum(len(t['stop_times']) for t in day),34)
  sources={s['source_id']:s['url_or_locator'] for s in self.data['source_documents']}
  for t in day:
   e=next(e for e in running if e['train_number']==t['train_number']);self.assertTrue(all(sources[s['source_id']]==e['source_url'] for s in t['stop_times']))
  self.assertIn('no exclusion claim',self.inventory['scope'])
 def test_exact_day_only(self):
  tids={'jr-east.kinugawa.2.exact-2026-09-30','jr-east.spacia-nikko.4.exact-2026-09-30'}
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(tids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
