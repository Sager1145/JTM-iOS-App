"""Official Shonan 13/15/17/19 and bounded observed station inventory."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'13': [('東京', None, '20:30', '９'),
        ('品川', '20:37', '20:39', '１２'),
        ('大船', '21:05', '21:06', '３'),
        ('藤沢', '21:10', '21:11', None),
        ('辻堂', '21:14', '21:15', None),
        ('茅ケ崎', '21:18', '21:19', '６'),
        ('平塚', '21:23', '21:23', '４'),
        ('国府津', '21:33', '21:34', '１'),
        ('小田原', '21:39', None, '３')],
 '15': [('東京', None, '21:00', '９'),
        ('品川', '21:07', '21:09', '１２'),
        ('大船', '21:35', '21:36', '３'),
        ('藤沢', '21:40', '21:40', None),
        ('辻堂', '21:44', '21:44', None),
        ('茅ケ崎', '21:48', '21:48', '６'),
        ('平塚', '21:52', '21:53', '４'),
        ('国府津', '22:02', '22:03', '１'),
        ('小田原', '22:09', None, '４')],
 '17': [('東京', None, '21:35', '９'),
        ('品川', '21:43', '21:45', '１２'),
        ('大船', '22:12', '22:13', '３'),
        ('藤沢', '22:17', '22:18', None),
        ('辻堂', '22:21', '22:22', None),
        ('茅ケ崎', '22:25', '22:26', '６'),
        ('平塚', '22:31', None, '４')],
 '19': [('東京', None, '22:00', '９'),
        ('品川', '22:07', '22:09', '１２'),
        ('大船', '22:35', '22:36', '３'),
        ('藤沢', '22:40', '22:40', None),
        ('辻堂', '22:44', '22:44', None),
        ('茅ケ崎', '22:48', '22:48', '６'),
        ('平塚', '22:53', '22:53', '４'),
        ('国府津', '23:03', '23:04', '１'),
        ('小田原', '23:10', None, '４')]}
class ShonanTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']};cls.inventory=json.loads((BASE/'audits/jr-east-shonan-fujisawa-observed-20260930-inventory.json').read_text())
 def test_all_four_exact_clock_platform_number_columns(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-shonan{n}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],{'13':'3083M','15':'3085M','17':'3087M','19':'3089M'}[n])
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
