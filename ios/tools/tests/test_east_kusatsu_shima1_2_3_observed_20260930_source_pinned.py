"""Official Kusatsu-Shima exact-day columns and bounded seasonal exclusions."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'1': [('上野', None, '10:00', '１４'),
       ('赤羽', '10:09', '10:10', None),
       ('浦和', '10:18', '10:19', None),
       ('大宮', '10:25', '10:26', '８'),
       ('熊谷', '10:51', '10:51', None),
       ('高崎', '11:18', '11:19', '２'),
       ('新前橋', '11:25', '11:27', None),
       ('渋川', '11:36', '11:37', None),
       ('中之条', '11:57', '11:58', None),
       ('長野原草津口', '12:18', None, None)],
 '2': [('長野原草津口', None, '13:07', None),
       ('中之条', '13:28', '13:29', None),
       ('渋川', '13:48', '13:49', None),
       ('新前橋', '13:58', '13:59', None),
       ('高崎', '14:05', '14:06', '７'),
       ('熊谷', '14:33', '14:34', None),
       ('大宮', '14:59', '15:00', '６'),
       ('浦和', '15:06', '15:07', None),
       ('赤羽', '15:15', '15:15', None),
       ('上野', '15:26', None, '１６')],
 '3': [('上野', None, '12:10', '１４'),
       ('赤羽', '12:18', '12:19', None),
       ('浦和', '12:27', '12:28', None),
       ('大宮', '12:34', '12:35', '７'),
       ('熊谷', '13:01', '13:02', None),
       ('高崎', '13:31', '13:33', '２'),
       ('新前橋', '13:39', '13:40', None),
       ('渋川', '13:50', '13:51', None),
       ('中之条', '14:12', '14:13', None),
       ('長野原草津口', '14:34', None, None)]}
class KusatsuTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.inventory=json.loads((BASE/'audits/jr-east-kusatsu-shima-nakanojo-observed-20260930-inventory.json').read_text());cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']}
 def test_new_source_columns(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-kusatsu-shima{n}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],{'1':'3001M','2':'3002M','3':'3003M'}[n]);self.assertEqual(c['printed_operating_labels'],[])
   self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],expected)
   f=next(f for f in self.data['trip_formations'] if f['trip_id']==t['trip_id']);self.assertEqual(f['evidence_kind'],'planned');self.assertTrue(f['all_reserved'])
   for key in ['vehicle_series','car_count','reserved_seat_capacity','green_car_available']:self.assertIsNone(f[key])
 def test_bounded_four_running_and_five_nonrunning(self):
  running=[e for e in self.inventory['trains'] if e['scheduled_on_date']];rejected=[e for e in self.inventory['trains'] if not e['scheduled_on_date']]
  self.assertEqual({e['public_number'] for e in running},{'1','2','3','4'});self.assertEqual({e['public_number'] for e in rejected},{'31','34','71','82','83'})
  for e in running:self.assertEqual(e['date_evidence']['cell_class'],'ok')
  for e in rejected:self.assertEqual(e['date_evidence']['cell_class'],'none')
  for n in ['31','34']:self.assertEqual(next(e['printed_operating_labels'] for e in rejected if e['public_number']==n),['土曜・休日運転'])
  self.assertEqual(next(e['printed_operating_labels'] for e in rejected if e['public_number']=='71'),['１１月１２・１３・１９・２０・２６・２７日運転'])
  day=[t for t in timetable.materialize(self.data,'2026-09-30') if t['service_id']=='kusatsu-shima'];self.assertEqual({t['public_number'] for t in day},{'1','2','3','4'});self.assertEqual(sum(len(t['stop_times']) for t in day),40)
  sources={s['source_id']:s['url_or_locator'] for s in self.data['source_documents']}
  for t in day:
   e=next(e for e in running if e['public_number']==t['public_number']);self.assertEqual(t['train_number'],e['train_number']);self.assertTrue(all(sources[s['source_id']]==e['source_url'] for s in t['stop_times']))
  self.assertIn('No exclusion claim',self.inventory['scope'])
 def test_exact_day_only(self):
  tids={f'jr-east.kusatsu-shima.{n}.exact-2026-09-30' for n in EXPECTED}
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(tids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
