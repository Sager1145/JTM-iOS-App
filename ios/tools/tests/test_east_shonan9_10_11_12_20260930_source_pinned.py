"""Official Shonan 9–12 columns and bounded observed station inventory."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'10': [('小田原', None, '07:27', '５'),
        ('国府津', '07:32', '07:33', '５'),
        ('二宮', '07:37', '07:37', None),
        ('平塚', '07:44', '07:45', '１'),
        ('茅ケ崎', '07:52', '07:52', '３'),
        ('藤沢', '07:59', '08:00', None),
        ('品川', '08:38', '08:39', '１３'),
        ('新橋', '08:44', '08:45', None),
        ('東京', '08:48', None, '総３')],
 '11': [('東京', None, '20:00', '９'),
        ('品川', '20:07', '20:09', '１２'),
        ('大船', '20:35', '20:36', '３'),
        ('藤沢', '20:40', '20:41', None),
        ('辻堂', '20:44', '20:45', None),
        ('茅ケ崎', '20:48', '20:49', '６'),
        ('平塚', '20:53', '20:53', '４'),
        ('二宮', '21:00', '21:01', None),
        ('国府津', '21:04', '21:05', '１'),
        ('小田原', '21:11', None, '４')],
 '12': [('小田原', None, '08:02', '５'),
        ('平塚', '08:19', '08:19', '１'),
        ('茅ケ崎', '08:24', '08:24', '５'),
        ('辻堂', '08:28', '08:28', None),
        ('藤沢', '08:32', '08:32', None),
        ('大船', '08:36', '08:37', '２'),
        ('品川', '09:06', '09:07', '６'),
        ('東京', '09:15', None, '８')],
 '9': [('東京', None, '19:30', '９'),
       ('品川', '19:37', '19:39', '１２'),
       ('大船', '20:05', '20:06', '３'),
       ('藤沢', '20:10', '20:11', None),
       ('辻堂', '20:15', '20:15', None),
       ('茅ケ崎', '20:19', '20:19', '６'),
       ('平塚', '20:23', '20:24', '４'),
       ('国府津', '20:33', '20:34', '１'),
       ('小田原', '20:40', None, '５')]}
class ShonanTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']};cls.inventory=json.loads((BASE/'audits/jr-east-shonan-fujisawa-observed-20260930-inventory.json').read_text())
 def test_all_four_exact_clock_platform_number_columns(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-shonan{n}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],{'9':'3079M','10':'3080M','11':'3081M','12':'3082M'}[n])
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
