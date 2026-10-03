import copy,importlib.util,json,shutil,tempfile,unittest
from pathlib import Path
APP=Path(__file__).resolve().parents[3]
r=APP/'data/station-english-sources/jp-shikoku'
spec=importlib.util.spec_from_file_location('verify_shikoku',APP/'scripts/railway/verify-jp-shikoku-station-english.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
class VerificationTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  # An existing but incomplete archive must still fail its original checks.
  if not r.exists():
   raise unittest.SkipTest("本地官方原始证据未提供: " + str(r))
 def setUp(self):self.package=json.loads(v.PACKAGE.read_bytes())
 def test_complete_snapshot(self):
  b=v.build();self.assertEqual(b['coverage']['verifiedMemberships'],273);self.assertEqual(b['coverage']['groupsWithVerifiedMembership'],261);self.assertEqual(b['unresolved'],[])
 def test_package_english_never_evidence(self):
  expected={k:x['en'] for k,x in v.build()['byLineStation'].items()}
  for line in self.package['lines']:
   if line['operator']==v.OPERATOR:
    for station in line['stations']:station[4]='POISON_TRANSLITERATION'
  self.assertEqual(expected,{k:x['en'] for k,x in v.build(self.package)['byLineStation'].items()})
 def test_wrong_published_route_fails_closed(self):
  line=next(l for l in self.package['lines'] if l['id']=='jp-四国旅客鉄道-予讃線-2');line['stations'][1][1]='金蔵寺'
  b=v.build(self.package);self.assertNotIn(line['id']+':'+line['stations'][1][0],b['byLineStation'])
 def test_ambiguous_native_groups_fail_closed(self):
  line=next(l for l in self.package['lines'] if l['name']=='徳島線');line['stations'].append(['FAKE_GROUP','府中',0,0,'FAKE',1])
  b=v.build(self.package);self.assertNotIn(line['id']+':FAKE_GROUP',b['byLineStation']);self.assertTrue(any(x['name']=='府中' for x in b['unresolved']))
 def test_source_tampering_rejected(self):
  with tempfile.TemporaryDirectory(prefix='test-',dir=r) as d:
   rr=Path(d);shutil.copytree(r/'raw',rr/'raw');shutil.copy(r/'visual-review.json',rr);shutil.copy(r/'transcription.tsv',rr);(rr/'raw/map.pdf').write_bytes(b'changed')
   with self.assertRaisesRegex(ValueError,'Source digest mismatch'):v.build(root=rr)
 def test_transcription_tampering_rejected(self):
  with tempfile.TemporaryDirectory(prefix='test-',dir=r) as d:
   rr=Path(d);shutil.copytree(r/'raw',rr/'raw');shutil.copy(r/'visual-review.json',rr);shutil.copy(r/'transcription.tsv',rr);(rr/'transcription.tsv').write_text((rr/'transcription.tsv').read_text().replace('Kan-onji','GUESS'))
   with self.assertRaisesRegex(ValueError,'Unreviewed visual transcription'):v.build(root=rr)
 def test_branch_identity_and_temporary_names(self):
  b=v.build()['byLineStation'];uchiko=[x for x in b.values() if x['lineId']=='jp-四国旅客鉄道-予讃線-2' and x['name']=='内子'];self.assertEqual(len(uchiko),1);self.assertEqual(uchiko[0]['identityEvidence'][0]['officialStationNumbers'],['U10'])
  for name,en in [('津島ノ宮','Tsushimanomiya'),('田井ノ浜','Tainohama'),('金比羅前','Kompiramae')]:self.assertTrue(any(x['name']==name and x['en']==en for x in b.values()))
if __name__ == '__main__':
 unittest.main()
