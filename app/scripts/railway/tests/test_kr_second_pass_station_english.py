from pathlib import Path
import copy,importlib.util,json,shutil,tempfile,unittest
from unittest.mock import patch
P=Path(__file__).resolve().parents[1];spec=importlib.util.spec_from_file_location('krsecond',P/'verify-kr-second-pass-station-english.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
class SecondPassTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  if not g.PACKET.is_dir():raise unittest.SkipTest('local second-pass source archive unavailable')
  cls.temp=tempfile.TemporaryDirectory();cls.original={k:getattr(g,k)for k in ('APP','ROOT','PACKET','OUTPUT','BASELINE','REVIEW')};app=(Path(cls.temp.name)/'repo/app').resolve()
  for rel in ('data/station-english-sources/kr','data/station-english-sources/next-official/kr-operators','data/station-english-sources/next-official/kr-operators-second-pass'):shutil.copytree(g.APP/rel,app/rel)
  for rel in ('scripts/railway/verify-kr-station-english.py','public/rail/kr-2025.json','data/stations-kr.json'):
   p=app/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(g.APP/rel,p)
  g.APP=app;g.ROOT=app/'data/station-english-sources/next-official';g.PACKET=g.ROOT/'kr-operators-second-pass';g.OUTPUT=app/'data/station-english-verified-kr-second-pass.json';g.BASELINE=app/'data/station-english-kr-second-pass-first-baseline.json'
  g.REVIEW=app/'data/station-english-kr-second-pass-review.json'
  cls.result,cls.baseline=g.regenerate(run_regressions=True);cls.package=g.load(app/'public/rail/kr-2025.json');cls.features=g.load(app/'data/stations-kr.json')
 @classmethod
 def tearDownClass(cls):
  for k,v in cls.original.items():setattr(g,k,v)
  cls.temp.cleanup()
 def test_original_six_regressions_and_partition(self):self.assertEqual(self.result['coverage'],{'totalMemberships':107,'verifiedMemberships':11,'unresolvedMemberships':96,'groupsWithVerifiedMembership':11})
 def reject(self,mutation):
  r=copy.deepcopy(self.result);mutation(next(iter(r['byLineStation'].values())))
  with self.assertRaises(ValueError):g.validate(r,self.package,self.features)
 def test_current_operator_mismatch(self):self.reject(lambda r:r.update(operator='OTHER'))
 def test_current_native_mismatch(self):self.reject(lambda r:r.update(name='OTHER'))
 def test_current_code_mismatch(self):self.reject(lambda r:r.update(stationCode='unknown'))
 def test_persisted_station_code_mismatch(self):self.reject(lambda r:r.update(persistedStationCode='unknown'))
 def test_unknown_country(self):self.reject(lambda r:r.update(country='us'))
 def test_source_freshness(self):
  p=g.PACKET/'blueline-stations-en.html';old=p.read_bytes()
  try:
   p.write_bytes(old+b'MUTATION')
   with self.assertRaisesRegex(ValueError,'hash mismatch'):g.regenerate()
  finally:p.write_bytes(old)
 def test_stale_output_check(self):
  g.OUTPUT.write_text('{}');g.BASELINE.write_bytes(self.baseline)
  with patch.object(g,'regenerate',return_value=(self.result,self.baseline)),patch('sys.argv',['gate','--check']):
   with self.assertRaisesRegex(SystemExit,'stale'):g.main()
if __name__=='__main__':unittest.main(verbosity=2)
