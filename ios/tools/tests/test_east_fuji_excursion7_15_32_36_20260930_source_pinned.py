"""Pinned Fuji branch columns, coupling and alternate operating-date pages."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'15': [['新宿', None, None],
        ['立川', None, None],
        ['八王子', None, None],
        ['大月', None, '11:36'],
        ['都留文科大学前', '11:55', '11:56'],
        ['下吉田', '12:11', '12:12'],
        ['富士山', '12:17', '12:19'],
        ['富士急ハイランド', '12:21', '12:22'],
        ['河口湖', '12:24', None]],
 '32': [['河口湖', None, '14:08'],
        ['富士急ハイランド', '14:11', '14:11'],
        ['富士山', '14:14', '14:16'],
        ['下吉田', '14:21', '14:21'],
        ['都留文科大学前', '14:36', '14:37'],
        ['大月', '14:56', None],
        ['八王子', None, None],
        ['立川', None, None],
        ['新宿', None, None]],
 '36': [['河口湖', None, '14:58'],
        ['富士急ハイランド', '15:01', '15:01'],
        ['富士山', '15:04', '15:06'],
        ['下吉田', '15:11', '15:12'],
        ['都留文科大学前', '15:26', '15:27'],
        ['大月', '15:48', None],
        ['八王子', None, None],
        ['立川', None, None],
        ['新宿', None, None]],
 '7': [['新宿', None, None],
       ['立川', None, None],
       ['八王子', None, None],
       ['大月', None, '09:42'],
       ['都留文科大学前', '09:58', '09:58'],
       ['下吉田', '10:12', '10:13'],
       ['富士山', '10:18', '10:21'],
       ['富士急ハイランド', '10:23', '10:23'],
       ['河口湖', '10:26', None]]}
class FujiTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']}
 def test_printed_fuji_columns_and_blank_platforms(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   tid=f'jr-east.fuji-excursion.{n}.exact-2026-09-30';t=next(t for t in day if t['trip_id']==tid)
   self.assertEqual(t['train_number'],{'7':'2107M','15':'2115M','32':'2132M','36':'2136M'}[n]);self.assertEqual([[self.names[s['station_id']],s['arrival_time'],s['departure_time']] for s in t['stop_times']],expected)
   self.assertTrue(all(s['platform'] is None for s in t['stop_times']))
   if n in ['7','15']:self.assertTrue(all(s['arrival_time'] is None and s['departure_time'] is None for s in t['stop_times'][:3]));self.assertIsNone(t['stop_times'][3]['arrival_time'])
   else:self.assertTrue(all(s['arrival_time'] is None and s['departure_time'] is None for s in t['stop_times'][-3:]));self.assertIsNone(t['stop_times'][5]['departure_time'])
 def test_coupled_number_identity_and_shared_ranges(self):
  for n in EXPECTED:
   tid=f'jr-east.fuji-excursion.{n}.exact-2026-09-30';related=f'jr-east.kaiji.{n}.exact-2026-09-30';r=next(r for r in self.data['trip_relations'] if r['trip_id']==tid and r['related_trip_id']==related)
   self.assertEqual((r['from_sequence'],r['to_sequence']),(1,4) if n in ['7','15'] else (6,9));self.assertEqual(r['relation_type'],'couples_with')
   self.assertTrue(any(r['trip_id']==related and r['related_trip_id']==tid for r in self.data['trip_relations']))
   self.assertFalse([r for r in self.data['trip_number_segments'] if r['trip_id']==tid])
   f=next(f for f in self.data['trip_formations'] if f['trip_id']==tid);self.assertTrue(f['all_reserved']);self.assertEqual(f['evidence_kind'],'planned')
   for field in ['vehicle_series','car_count','green_car_available']:self.assertIsNone(f[field])
 def test_observed_date_variant_inventory(self):
  c=json.loads((BASE/'candidates/jr-east-fuji-excursion-otsuki-observed-20260930.json').read_text());self.assertEqual(c['proven_public_numbers'],['3','7','11','15','32','36','44','48'])
  e=next(e for e in c['trains'] if e['source_url'].endswith('/054802.html'));self.assertEqual(e['date_evidence']['cell_class'],'other');self.assertTrue(e['alternate_date_url'].endswith('/054801.html'))
  self.assertEqual(len([e for e in c['trains'] if e['scheduled_on_date']]),8)
 def test_exact_day_only(self):
  tids={f'jr-east.fuji-excursion.{n}.exact-2026-09-30' for n in EXPECTED}
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(tids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
