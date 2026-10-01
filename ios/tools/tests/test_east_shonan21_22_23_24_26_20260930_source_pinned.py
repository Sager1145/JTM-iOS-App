"""Official final five Shonan and bounded observed station inventory."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'21': [('新宿', None, '18:25', '６'),
        ('渋谷', '18:31', '18:32', None),
        ('大崎', '18:37', '18:38', '５'),
        ('藤沢', '19:20', '19:21', None),
        ('茅ケ崎', '19:27', '19:28', '４'),
        ('平塚', '19:32', '19:33', '４'),
        ('二宮', '19:40', '19:40', None),
        ('国府津', '19:44', '19:45', '１'),
        ('小田原', '19:51', None, '５')],
 '22': [('小田原', None, '06:30', '６'),
        ('茅ケ崎', '06:47', '06:48', '３'),
        ('藤沢', '06:53', '06:54', None),
        ('大崎', '07:32', '07:33', '８'),
        ('渋谷', '07:39', '07:40', None),
        ('新宿', '07:44', None, '５')],
 '23': [('新宿', None, '19:30', '６'),
        ('渋谷', '19:35', '19:36', None),
        ('大崎', '19:41', '19:42', '５'),
        ('藤沢', '20:20', '20:21', None),
        ('茅ケ崎', '20:26', '20:27', '４'),
        ('平塚', '20:32', '20:33', '４'),
        ('二宮', '20:39', '20:40', None),
        ('国府津', '20:44', '20:45', '１'),
        ('小田原', '20:50', None, '４')],
 '24': [('小田原', None, '07:09', '４'),
        ('国府津', '07:14', '07:15', '５'),
        ('二宮', '07:19', '07:20', None),
        ('平塚', '07:29', '07:32', '１'),
        ('茅ケ崎', '07:37', '07:38', '３'),
        ('藤沢', '07:44', '07:45', None),
        ('大崎', '08:23', '08:24', '８'),
        ('渋谷', '08:30', '08:30', None),
        ('新宿', '08:35', None, '６')],
 '26': [('小田原', None, '07:45', '４'),
        ('茅ケ崎', '08:04', '08:05', '３'),
        ('藤沢', '08:10', '08:11', None),
        ('大崎', '08:49', '08:49', '８'),
        ('渋谷', '08:54', '08:55', None),
        ('新宿', '09:00', None, '６')]}
class ShonanTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']};cls.inventory=json.loads((BASE/'audits/jr-east-shonan-fujisawa-observed-20260930-inventory.json').read_text())
 def test_all_four_exact_clock_platform_number_columns(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-shonan{n}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],{'21':'3091M','22':'3092M','23':'3093M','24':'3094M','26':'3096M'}[n])
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
