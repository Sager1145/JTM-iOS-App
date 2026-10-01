"""Four official Shonan columns and bounded observed station inventory."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'1': [('東京', None, '17:30', '９'),
       ('品川', '17:37', '17:39', '１２'),
       ('大船', '18:05', '18:06', '３'),
       ('藤沢', '18:10', '18:10', None),
       ('辻堂', '18:14', '18:14', None),
       ('茅ケ崎', '18:18', '18:18', '６'),
       ('平塚', '18:23', None, '３')],
 '2': [('平塚', None, '06:25', '１'),
       ('茅ケ崎', '06:29', '06:30', '５'),
       ('辻堂', '06:33', '06:34', None),
       ('藤沢', '06:37', '06:38', None),
       ('大船', '06:42', '06:42', '２'),
       ('品川', '07:10', '07:11', '６'),
       ('東京', '07:18', None, '９')],
 '3': [('東京', None, '18:00', '９'),
       ('品川', '18:08', '18:09', '１２'),
       ('大船', '18:36', '18:37', '３'),
       ('藤沢', '18:41', '18:42', None),
       ('辻堂', '18:45', '18:46', None),
       ('茅ケ崎', '18:49', '18:50', '６'),
       ('平塚', '18:54', '18:55', '４'),
       ('国府津', '19:04', '19:05', '１'),
       ('小田原', '19:11', None, '４')],
 '4': [('小田原', None, '06:20', '６'),
       ('平塚', '06:39', '06:40', '１'),
       ('茅ケ崎', '06:44', '06:45', '５'),
       ('辻堂', '06:49', '06:50', None),
       ('藤沢', '06:54', '06:55', None),
       ('大船', '06:59', '07:00', '２'),
       ('品川', '07:26', '07:27', '６'),
       ('東京', '07:35', None, '８')]}
class ShonanTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']};cls.inventory=json.loads((BASE/'audits/jr-east-shonan-fujisawa-observed-20260930-inventory.json').read_text())
 def test_all_four_exact_clock_platform_number_columns(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-shonan{n}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],{'1':'3071M','2':'3072M','3':'3073M','4':'3074M'}[n])
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
