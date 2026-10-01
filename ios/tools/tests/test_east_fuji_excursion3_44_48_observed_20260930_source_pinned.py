"""Final Fuji branches, correct Azusa coupling, bounded eight-train closure."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=TOOLS.parents[1]/"app/data/train-service-history"
EXPECTED = {'3': [['千葉', None, None],
       ['船橋', None, None],
       ['錦糸町', None, None],
       ['新宿', None, None],
       ['立川', None, None],
       ['八王子', None, None],
       ['大月', None, '08:40'],
       ['都留文科大学前', '08:57', '08:57'],
       ['下吉田', '09:11', '09:13'],
       ['富士山', '09:18', '09:23'],
       ['富士急ハイランド', '09:25', '09:26'],
       ['河口湖', '09:28', None]],
 '44': [['河口湖', None, '16:48'],
        ['富士急ハイランド', '16:51', '16:51'],
        ['富士山', '16:54', '16:56'],
        ['下吉田', '17:00', '17:01'],
        ['都留文科大学前', '17:16', '17:17'],
        ['大月', '17:35', None],
        ['八王子', None, None],
        ['立川', None, None],
        ['新宿', None, None]],
 '48': [['河口湖', None, '17:41'],
        ['富士急ハイランド', '17:43', '17:44'],
        ['富士山', '17:46', '17:49'],
        ['下吉田', '17:53', '17:54'],
        ['都留文科大学前', '18:10', '18:10'],
        ['大月', '18:28', None],
        ['八王子', None, None],
        ['立川', None, None],
        ['新宿', None, None]]}
class FujiFinalTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE));cls.names={s['station_id']:s['name_snapshot'] for s in cls.data['station_identities']}
 def test_exact_branch_clocks_and_unknown_platforms(self):
  day=timetable.materialize(self.data,'2026-09-30')
  for n,expected in EXPECTED.items():
   tid=f'jr-east.fuji-excursion.{n}.exact-2026-09-30';t=next(t for t in day if t['trip_id']==tid)
   self.assertEqual(t['train_number'],{'3':'2103M','44':'2144M','48':'2148M'}[n]);self.assertEqual([[self.names[s['station_id']],s['arrival_time'],s['departure_time']] for s in t['stop_times']],expected)
   self.assertTrue(all(s['platform'] is None for s in t['stop_times']))
   f=next(f for f in self.data['trip_formations'] if f['trip_id']==tid);self.assertEqual(f['evidence_kind'],'planned');self.assertTrue(f['all_reserved'])
   for k in ['car_count','vehicle_series','green_car_available']:self.assertIsNone(f[k])
 def test_actual_coupled_service_and_deferred_reference(self):
  ids={t['trip_id'] for t in self.data['trips']}
  for n in EXPECTED:
   c=json.loads((BASE/f'candidates/jr-east-fuji-excursion{n}-20260930.json').read_text());target=f"jr-east.{'kaiji' if n=='48' else 'azusa'}.{n}.exact-2026-09-30"
   self.assertEqual(c['printed_coupled_number'],{'3':'5003M','44':'44M','48':'3148M'}[n])
   self.assertEqual(c['coupling_relations'][0]['related_trip_id'],target);self.assertEqual((c['coupling_relations'][0]['from_sequence'],c['coupling_relations'][0]['to_sequence']),(1,7) if n=='3' else (6,9))
   actual=[r for r in self.data['trip_relations'] if {r['trip_id'],r['related_trip_id']}=={c['trip_id'],target}]
   self.assertEqual(len(actual),2 if target in ids else 0)
   if target in ids:
    self.assertEqual({r['trip_id'] for r in actual},{c['trip_id'],target})
    shared_sections=[]
    for relation in actual:
     self.assertEqual(relation['relation_type'],'couples_with')
     self.assertEqual(relation['source_id'],c['source_id'])
     shared_sections.append([self.names[s['station_id']] for s in sorted(
      (s for s in self.data['stop_times'] if s['trip_id']==relation['trip_id']),
      key=lambda s:s['stop_sequence'])
      if relation['from_sequence']<=s['stop_sequence']<=relation['to_sequence']])
    expected_section=['千葉','船橋','錦糸町','新宿','立川','八王子','大月'] if n=='3' else ['大月','八王子','立川','新宿']
    self.assertEqual(shared_sections,[expected_section,expected_section])
    self.assertFalse(any(r['entity_id']==c['trip_id'] and r['missing_dimension']=='coupling'
                         and r['status']=='open' for r in self.data['research_queue']))
   if target not in ids:self.assertTrue(any(r['entity_id']==c['trip_id'] and r['missing_dimension']=='coupling' for r in self.data['research_queue']))
 def test_observed_eight_complete_and_sources_match(self):
  inv=json.loads((BASE/'candidates/jr-east-fuji-excursion-otsuki-observed-20260930.json').read_text());self.assertEqual(inv['remaining_proven_public_numbers'],[])
  sources={s['source_id']:s['url_or_locator'] for s in self.data['source_documents']};day=[t for t in timetable.materialize(self.data,'2026-09-30') if t['service_id']=='fuji-excursion']
  self.assertEqual({t['public_number'] for t in day},set(inv['proven_public_numbers']));self.assertEqual(len(day),8);self.assertEqual(sum(len(t['stop_times']) for t in day),75)
  for t in day:
   e=next(e for e in inv['trains'] if e['scheduled_on_date'] and e['public_number']==t['public_number']);self.assertEqual(t['train_number'],e['train_number']);self.assertTrue(all(sources[s['source_id']]==e['source_url'] for s in t['stop_times']))
  self.assertIn('No unseen-entrance exclusion claim',inv['scope'])
 def test_exact_day_only(self):
  tids={f'jr-east.fuji-excursion.{n}.exact-2026-09-30' for n in EXPECTED}
  for day in ['2026-09-29','2026-10-01']:self.assertFalse(tids & {t['trip_id'] for t in timetable.materialize(self.data,day)})
if __name__=='__main__':unittest.main()
