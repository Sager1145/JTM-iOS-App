import importlib.util
import json
from pathlib import Path
import unittest
APP=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('verify_kr',APP/'scripts/railway/verify-kr-station-english.py')
kr=importlib.util.module_from_spec(spec);spec.loader.exec_module(kr)

def official(operator='부산교통공사',line='1호선',name='중앙',en='Jungang',**extra):
 return dict(operator=operator,officialLine=line,name=name,en=en,officialStationCode='112',source='https://www.data.go.kr/data/15041037/fileData.do',identitySource='https://www.data.go.kr/data/15041037/fileData.do',retrievedAt='2026-10-01T00:00:00Z',sha256='a'*64,rawFile='15041037.xlsx',sourceRow=2,**extra)
def package(line='kr-busan-dosicheoldo-1hoseon',operator='부산교통공사',name='중앙',lon=129.035,lat=35.10):
 return {'lines':[{'id':line,'name':'부산 도시철도 1호선','operator':operator,'stations':[['kr-official-jungang',name,lon,lat,'Candidate',3]]}]}
def result(p,rows,positions=[]):return kr.build(p,{'features':[]},rows,[],positions)

class IdentityTests(unittest.TestCase):
 def test_same_native_name_in_another_city_cannot_verify(self):
  r=result(package(),[official(operator='대구교통공사',name='중앙',en='Wrong City')]);self.assertEqual({},r['byLineStation'])
 def test_same_operator_wrong_line_cannot_verify(self):
  r=result(package(),[official(line='2호선')]);self.assertEqual({},r['byLineStation'])
 def test_korail_mainline_contamination_not_verified_by_busans_metro(self):
  r=result(package(line='kr-gyeongbuseon',operator='한국철도공사',name='초량'),[official(name='초량',en='Choryang')]);self.assertEqual({},r['byLineStation'])
 def test_coordinate_disagreement_cannot_verify(self):
  r=result(package(),[official(lon=128.5,lat=35.8)]);self.assertEqual(r['unresolved'][0]['reason'],'official-coordinate-disagrees-with-package')
 def test_exact_official_parenthetical_name_is_retained(self):
  r=result(package(),[official(name='중앙(중앙동)',en='Jungang (Jungang-dong)')]);v=next(iter(r['byLineStation'].values()));self.assertEqual(v['en'],'Jungang (Jungang-dong)');self.assertEqual(v['nameAliases'],['중앙(중앙동)'])
 def test_generated_package_english_is_never_evidence(self):
  r=result(package(),[]);self.assertEqual({},r['byLineStation'])
 def test_current_official_conflict_remains_unresolved(self):
  a=official();a['rawFile']='15064687.xlsx';b=dict(a,en='Different');r=result(package(),[a,b]);self.assertEqual({},r['byLineStation']);self.assertEqual(r['unresolved'][0]['reason'],'conflicting-official-english-rows')

class RetainedEvidenceTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  # An existing but incomplete archive must still fail its original checks.
  if not kr.RAW.exists():
      raise unittest.SkipTest("本地官方原始证据未提供: " + str(kr.RAW))
  cls.records,cls.sources,cls.positions=kr.source_rows()
  cls.package=json.loads((APP/'public/rail/kr-2025.json').read_text());cls.features=json.loads((APP/'data/stations-kr.json').read_text())
  cls.saved=json.loads((APP/'data/station-english-verified-kr.json').read_text())
 def test_raw_digest_and_offline_rebuild(self):
  self.assertEqual(self.saved,kr.build(self.package,self.features,self.records,self.sources,self.positions))
 def test_every_membership_has_exactly_one_outcome(self):
  expected={line['id']+':'+s[0] for line in self.package['lines'] for s in line['stations']}
  verified=set(self.saved['byLineStation']);unresolved={r['lineId']+':'+r['group'] for r in self.saved['unresolved']}
  self.assertFalse(verified & unresolved);self.assertEqual(expected,verified | unresolved)
 def test_group_coverage_requires_every_membership(self):
  verified={k.split(':',1)[1] for k in self.saved['byLineStation']};pending={r['group'] for r in self.saved['unresolved']}
  self.assertEqual(self.saved['coverage']['verifiedGroups'],len(verified-pending))
  self.assertEqual(self.saved['coverage']['groupsWithVerifiedMembership'],len(verified))
 def test_incheon_seongnam_is_not_guessed_seoknam(self):
  row=self.saved['byLineStation']['kr-incheon-dosicheoldo-2hoseon:kr-official-seoknam'];self.assertTrue(row['en'].startswith('Seongnam'))
 def test_all_verified_records_have_official_identity_evidence(self):
  for row in self.saved['byLineStation'].values():
   self.assertTrue(row['identityEvidence']);self.assertNotEqual('Candidate',row['en'])
   for e in row['identityEvidence']:
    self.assertTrue(e['operator']);self.assertTrue(e['officialLine']);self.assertTrue(e['name']);self.assertRegex(e['sha256'],r'^[a-f0-9]{64}$');self.assertIn('official-operator-line-native-name',e['matchMethod'])
if __name__ == '__main__':
 unittest.main()
