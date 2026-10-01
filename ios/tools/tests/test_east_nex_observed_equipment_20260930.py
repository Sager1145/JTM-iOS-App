"""Direct exact-day equipment and complete observed-candidate parity."""
import copy,importlib.util,json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
spec=importlib.util.spec_from_file_location('nex_equipment',TOOLS/'normalize-reviewed-east-nex-observed-equipment-20260930.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class EquipmentTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.c=json.loads(module.CANDIDATE.read_text());cls.data,_=timetable.load_dataset(module.BASE,timetable.load_manifest(module.BASE))
 def test_all_printed_calls_platforms_and_number_segments(self):
  result=module.audit(self.data,self.c)
  self.assertEqual(result['counts'],dict(public_numbers=54,trips=84,stop_rows=665,printed_platforms=308,number_segments=44))
  self.assertEqual(result['mismatches'],[])
 def test_direct_equipment_and_unknowns(self):
  tids={tid for e in self.c['page_evidence'] for tid in e['trip_ids']}
  formations=[f for f in self.data['trip_formations'] if f['trip_id'] in tids and f['service_date']=='2026-09-30']
  self.assertEqual(len(formations),84);self.assertEqual(len({f['trip_id'] for f in formations}),84)
  for f in formations:
   self.assertEqual(f['evidence_kind'],'planned');self.assertIs(f['all_reserved'],True);self.assertIs(f['green_car_available'],True)
   for key in ['car_count','vehicle_series','reserved_seat_capacity']:self.assertIsNone(f.get(key))
  for e in self.c['page_evidence']:
   self.assertEqual(e['date_evidence'],dict(month='2026年9月',day=30,cell_class='ok'))
   self.assertEqual(len(e['equipment_columns']),len(e['printed_train_numbers']))
   for col in e['equipment_columns']:self.assertEqual(col,['座席未指定券','グリーン車指定席','普通車全車指定席'])
 def test_parity_detects_platform_and_segment_corruption(self):
  data=copy.deepcopy(self.data)
  next(s for s in data['stop_times'] if s['trip_id']=='jr-east.narita-express.4.exact-2026-09-30' and s['platform'])['platform']='999'
  next(s for s in data['trip_number_segments'] if s['trip_id']=='jr-east.narita-express.4.exact-2026-09-30')['train_number']='wrong'
  self.assertEqual(len(module.audit(data,self.c)['mismatches']),2)
 def test_family_guide_not_promoted_to_actual_dispatch(self):
  a=json.loads((module.BASE/'audits/jr-east-nex-formation-evidence-20260930.json').read_text())
  self.assertEqual(len(a['research_gaps']),54)
  self.assertEqual(a['direct_train_specific']['actual_dispatch'],0)
  self.assertEqual(a['family_evidence'][0]['publication_date'],'2026-09-09')
if __name__=='__main__':unittest.main()
