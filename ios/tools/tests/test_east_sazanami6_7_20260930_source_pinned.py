"""Official Sazanami columns and bounded Soga station inventory."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'6': [('君津', None, '07:39', '３'),
       ('木更津', '07:45', '07:46', '１'),
       ('姉ケ崎', '07:57', '07:57', '３'),
       ('五井', '08:02', '08:02', None),
       ('蘇我', '08:10', '08:11', '２'),
       ('東京', '08:48', None, '京１')],
 '7': [('東京', None, '20:30', '京１'),
       ('蘇我', '21:06', '21:07', '５'),
       ('五井', '21:14', '21:15', None),
       ('姉ケ崎', '21:20', '21:21', '１'),
       ('木更津', '21:34', '21:35', '３'),
       ('君津', '21:41', None, '２')]}
class SazanamiTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']};cls.inventory=json.loads((BASE/'audits/jr-east-sazanami-soga-observed-20260930-inventory.json').read_text())
 def test_all_four_exact_clock_platform_number_columns(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-sazanami{n}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],{'6':'1006M','7':'1007M'}[n])
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
