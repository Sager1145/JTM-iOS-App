"""Four source-pinned Niigata departures and date-specific Green-car remark."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'inaho1': [('新潟', None, '08:23', '５'),
            ('豊栄', '08:34', '08:35', None),
            ('新発田', '08:44', '08:44', '１'),
            ('中条', '08:53', '08:54', None),
            ('坂町', '09:00', '09:00', '３'),
            ('村上', '09:08', '09:09', '３'),
            ('府屋', '09:38', '09:38', None),
            ('あつみ温泉', '09:50', '09:51', None),
            ('鶴岡', '10:13', '10:13', None),
            ('余目', '10:23', '10:24', '２'),
            ('酒田', '10:32', '10:34', '１'),
            ('遊佐', '10:44', '10:44', None),
            ('象潟', '11:04', '11:04', None),
            ('仁賀保', '11:13', '11:13', None),
            ('羽後本荘', '11:24', '11:24', None),
            ('秋田', '11:57', None, '３')],
 'inaho3': [('新潟', None, '10:50', '５'),
            ('豊栄', '11:03', '11:04', None),
            ('新発田', '11:13', '11:13', '１'),
            ('中条', '11:22', '11:23', None),
            ('坂町', '11:29', '11:30', '３'),
            ('村上', '11:38', '11:38', '３'),
            ('府屋', '12:08', '12:08', None),
            ('あつみ温泉', '12:20', '12:21', None),
            ('鶴岡', '12:43', '12:44', None),
            ('余目', '12:54', '12:55', '２'),
            ('酒田', '13:03', None, '１')],
 'shirayuki2': [('新潟', None, '07:35', '３'),
                ('新津', '07:49', '07:50', '２'),
                ('加茂', '08:03', '08:03', None),
                ('東三条', '08:09', '08:10', '３'),
                ('見附', '08:18', '08:18', None),
                ('長岡', '08:27', '08:29', '４'),
                ('柏崎', '08:54', '08:54', '３'),
                ('柿崎', '09:09', '09:10', None),
                ('直江津', '09:23', '09:25', '３'),
                ('高田', '09:32', '09:33', None),
                ('上越妙高', '09:39', '09:39', None),
                ('新井', '09:46', None, None)],
 'shirayuki4': [('新潟', None, '10:23', '５'),
                ('新津', '10:36', '10:37', '２'),
                ('加茂', '10:49', '10:50', None),
                ('東三条', '10:56', '10:57', '３'),
                ('見附', '11:05', '11:06', None),
                ('長岡', '11:16', '11:17', '４'),
                ('柏崎', '11:42', '11:42', '３'),
                ('柿崎', '11:57', '11:57', None),
                ('直江津', '12:09', '12:11', '３'),
                ('高田', '12:18', '12:18', None),
                ('上越妙高', '12:24', None, None)]}
class NiigataTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']}
 def test_all_printed_calls_and_platforms(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for key,expected in EXPECTED.items():
   c=json.loads((BASE/f'candidates/jr-east-{key}-20260930.json').read_text());t=next(t for t in day if t['trip_id']==c['trip_id'])
   self.assertEqual(t['train_number'],{'inaho1':'1M','inaho3':'3M','shirayuki2':'52M','shirayuki4':'54M'}[key]);self.assertEqual([(self.names[s['station_id']],s['arrival_time'],s['departure_time'],s['platform']) for s in t['stop_times']],expected)
   self.assertEqual(c['calendar_observation'],dict(month='2026年9月',day=30,cell_class='ok'));self.assertEqual(c['train_number_segments'],[])
 def test_partial_reservation_and_dated_green(self):
  for key in EXPECTED:
   c=json.loads((BASE/f'candidates/jr-east-{key}-20260930.json').read_text());f=next(f for f in self.data['trip_formations'] if f['trip_id']==c['trip_id'])
   self.assertEqual(f['evidence_kind'],'planned');self.assertIs(f['all_reserved'],False);self.assertEqual(f['green_car_available'],True if key.startswith('inaho') else None)
   for field in ['car_count','vehicle_series','reserved_seat_capacity']:self.assertIsNone(f[field])
  c=json.loads((BASE/'candidates/jr-east-inaho3-20260930.json').read_text());self.assertEqual(c['printed_equipment'],['普通車一部指定席']);self.assertEqual(c['dated_green_evidence']['valid_from'],'2026-09-18');self.assertEqual(c['dated_green_evidence']['valid_through'],'2026-10-16')
  self.assertEqual(c['printed_remarks'],'９月１８日～１０月１６・１９～２２日・１１月４～６・９・２１～２４・２８・２９日はグリーン車指定席連結')
  fact=next(f for f in self.data['fact_sources'] if f['entity_id']==c['trip_id'] and f['field_name']=='formation.green_car_available');self.assertIn(c['printed_remarks'],fact['page_or_locator'])
 def test_bounded_departure_inventory(self):
  a=json.loads((BASE/'audits/jr-east-inaho-shirayuki-niigata-departures-observed-20260930.json').read_text());running=[e['printed_name'] for e in a['trains'] if e['scheduled_on_date']]
  self.assertEqual(set(running),{f'いなほ {n}号' for n in [1,3,5,7,9,11,13]}|{f'しらゆき {n}号' for n in [2,4,6,8]});self.assertEqual({e['printed_name'] for e in a['trains'] if not e['scheduled_on_date']},{'いなほ 55号','いなほ 83号'})
  self.assertIn('Opposite-direction arrivals',a['scope'])
 def test_exact_day_only(self):
  ids={json.loads((BASE/f'candidates/jr-east-{k}-20260930.json').read_text())['trip_id'] for k in EXPECTED}
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(ids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
