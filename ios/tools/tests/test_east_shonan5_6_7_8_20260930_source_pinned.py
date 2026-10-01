"""Official Shonan 5–8 columns and bounded observed station inventory."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'5': [('東京', None, '18:30', '９'),
       ('品川', '18:38', '18:39', '１２'),
       ('大船', '19:08', '19:09', '３'),
       ('藤沢', '19:13', '19:13', None),
       ('辻堂', '19:17', '19:17', None),
       ('茅ケ崎', '19:21', '19:21', '６'),
       ('平塚', '19:26', None, '３')],
 '6': [('小田原', None, '06:46', '５'),
       ('茅ケ崎', '07:03', '07:04', '３'),
       ('藤沢', '07:10', '07:11', None),
       ('品川', '07:49', '07:50', '８'),
       ('東京', '07:58', None, '８')],
 '7': [('東京', None, '19:00', '９'),
       ('品川', '19:08', '19:09', '１２'),
       ('大船', '19:36', '19:36', '３'),
       ('藤沢', '19:40', '19:41', None),
       ('辻堂', '19:44', '19:45', None),
       ('茅ケ崎', '19:48', '19:49', '６'),
       ('平塚', '19:53', '19:54', '４'),
       ('国府津', '20:03', '20:04', '１'),
       ('小田原', '20:10', None, '３')],
 '8': [('小田原', None, '06:58', '４'),
       ('茅ケ崎', '07:16', '07:17', '３'),
       ('藤沢', '07:22', '07:23', None),
       ('品川', '08:03', '08:04', '１３'),
       ('新橋', '08:09', '08:10', None),
       ('東京', '08:13', None, '総３')]}
class ShonanTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']};cls.inventory=json.loads((BASE/'audits/jr-east-shonan-fujisawa-observed-20260930-inventory.json').read_text())
 def test_all_four_exact_clock_platform_number_columns(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-shonan{n}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],{'5':'3075M','6':'3076M','7':'3077M','8':'3078M'}[n])
   observed=[(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']]
   self.assertEqual(observed,[(name.replace('茅ケ崎','茅ヶ崎'),a,d,p) for name,a,d,p in expected])
   self.assertEqual(c['source_url'],next(e['source_url'] for e in self.inventory['trains'] if e['public_number']==n))
   self.assertEqual(c['printed_operating_labels'],'平日運転')
 def test_seats_not_inferred_vehicle(self):
  for n in EXPECTED:
   tid=f'jr-east.shonan.{n}.exact-2026-09-30';f=next(f for f in self.data['trip_formations'] if f['trip_id']==tid)
   self.assertEqual(f['evidence_kind'],'planned');self.assertIs(f['all_reserved'],True);self.assertIs(f['green_car_available'],True)
   for key in ['car_count','vehicle_series','reserved_seat_capacity']:self.assertIsNone(f[key])
   self.assertFalse([s for s in self.data['trip_number_segments'] if s['trip_id']==tid])
 def test_observed_set_not_unseen_entrance_closure(self):
  self.assertEqual(self.inventory['observed_proven_count'],22);self.assertEqual(len(self.inventory['trains']),22)
  self.assertEqual({e['public_number'] for e in self.inventory['trains']},{str(n) for n in list(range(1,16))+[17,19,21,22,23,24,26]})
  for e in self.inventory['trains']:
   self.assertTrue(e['scheduled_on_date']);self.assertEqual(e['date_evidence'],dict(month='2026年9月',day=30,cell_class='ok'))
   self.assertIn('/tt1361/',e['discovery_url'])
  self.assertIn('no exclusion claim',self.inventory['scope'])
 def test_no_adjacent_day_promotion(self):
  tids={f'jr-east.shonan.{n}.exact-2026-09-30' for n in EXPECTED}
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(tids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
