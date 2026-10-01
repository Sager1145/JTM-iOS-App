"""Official Sazanami columns and bounded Soga station inventory."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'1': [('東京', None, '17:30', '京１'),
       ('蘇我', '18:03', '18:04', '５'),
       ('五井', '18:11', '18:11', None),
       ('姉ケ崎', '18:16', '18:16', '１'),
       ('木更津', '18:28', '18:29', '３'),
       ('君津', '18:36', None, '３')],
 '2': [('君津', None, '05:52', '３'),
       ('木更津', '05:58', '05:59', '１'),
       ('姉ケ崎', '06:10', '06:10', '３'),
       ('五井', '06:15', '06:15', None),
       ('蘇我', '06:23', '06:24', '２'),
       ('東京', '06:57', None, '京１')],
 '4': [('木更津', None, '07:03', '１'),
       ('姉ケ崎', '07:14', '07:14', '３'),
       ('五井', '07:19', '07:20', None),
       ('蘇我', '07:28', '07:29', '２'),
       ('東京', '08:12', None, '京１')],
 '5': [('東京', None, '19:30', '京１'),
       ('蘇我', '20:04', '20:05', '５'),
       ('五井', '20:13', '20:14', None),
       ('姉ケ崎', '20:18', '20:19', '１'),
       ('木更津', '20:30', '20:30', '３'),
       ('君津', '20:37', None, '３')]}
class SazanamiTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']};cls.inventory=json.loads((BASE/'audits/jr-east-sazanami-soga-observed-20260930-inventory.json').read_text())
 def test_all_four_exact_clock_platform_number_columns(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-sazanami{n}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],{'1':'1001M','2':'1002M','4':'1004M','5':'1005M'}[n])
   observed=[(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']]
   self.assertEqual(observed,[(name.replace('姉ケ崎','姉ヶ崎'),a,d,p) for name,a,d,p in expected])
   self.assertEqual(c['source_url'],next(e['source_url'] for e in self.inventory['trains'] if e['public_number']==n))
   self.assertEqual(c['printed_operating_labels'],'平日運転')
   tokyo=next(s for s in t['stop_times'] if self.names[s['station_id']]=='東京')
   self.assertEqual((tokyo['station_id'],tokyo['platform']),('jp.n02.003785','京１'))
 def test_seats_not_inferred_vehicle(self):
  for n in EXPECTED:
   tid=f'jr-east.sazanami.{n}.exact-2026-09-30';f=next(f for f in self.data['trip_formations'] if f['trip_id']==tid)
   self.assertEqual(f['evidence_kind'],'planned');self.assertIs(f['all_reserved'],True);self.assertIsNone(f['green_car_available'])
   for key in ['car_count','vehicle_series','reserved_seat_capacity']:self.assertIsNone(f[key])
   self.assertFalse([s for s in self.data['trip_number_segments'] if s['trip_id']==tid])
 def test_observed_set_not_unseen_entrance_closure(self):
  self.assertEqual(self.inventory['observed_proven_count'],7);self.assertEqual(len(self.inventory['trains']),7)
  self.assertEqual({e['public_number'] for e in self.inventory['trains']},{str(n) for n in range(1,8)})
  for e in self.inventory['trains']:
   self.assertTrue(e['scheduled_on_date']);self.assertEqual(e['date_evidence'],dict(month='2026年9月',day=30,cell_class='ok'))
   self.assertIn('/tt0920/',e['discovery_url'])
  self.assertIn('no exclusion claim',self.inventory['scope'])
 def test_no_adjacent_day_promotion(self):
  tids={f'jr-east.sazanami.{n}.exact-2026-09-30' for n in EXPECTED}
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(tids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
