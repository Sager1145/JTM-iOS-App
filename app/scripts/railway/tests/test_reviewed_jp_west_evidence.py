import hashlib,importlib.util,json,pathlib,shutil,sys,tempfile,unittest
SCRATCH=pathlib.Path(__file__).resolve().parents[1];APP=SCRATCH.parents[1];ROOT=APP/'data/station-english-sources/jp-west';spec=importlib.util.spec_from_file_location('west',SCRATCH/'verify-jp-west-station-english.py');w=importlib.util.module_from_spec(spec);spec.loader.exec_module(w)
class RegressionTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  # An existing but incomplete archive must still fail its original checks.
  if not ROOT.exists():
      raise unittest.SkipTest("本地官方原始证据未提供: " + str(ROOT))
  cls.manifest,cls.searches,cls.stations=w.source_rows(ROOT);cls.snapshot=w.build(APP,ROOT)
 def test_homonyms_require_published_line_station_ids(self):
  cases=[('上道','境線','0641709','Agarimichi'),('上道','山陽線','0650628','Joto'),('下松','山陽線','0800636','Kudamatsu'),('下松','阪和線','0621933','Shimomatsu'),('柏原','福知山線','0630311','Kaibara'),('柏原','関西線','0620822','Kashiwara')]
  for name,line,sid,en in cases:
   with self.subTest(name=name,line=line):
    row,reason=w.select_station(name,line,self.searches,self.stations,duplicated=True)
    self.assertIsNone(reason);self.assertEqual(row['officialStationId'],sid);self.assertEqual(row['en'],en);self.assertIn('identity',row);self.assertIn(row['identity']['officialStationId'],self.stations)
  row,reason=w.select_station('上道','阪和線',self.searches,self.stations,duplicated=True)
  self.assertIsNone(row);self.assertEqual(reason,'Native station identity requires an unambiguous published line match')
 def test_prefecture_suffix_keeps_full_published_label(self):
  for label,name in [('泊（鳥取県）','泊'),('長谷（兵庫県）','長谷'),('下松（大阪府）','下松')]:
   with self.subTest(label=label):
    row=w.station_sign(self.sign_html(label))
    self.assertEqual(row['name'],name);self.assertEqual(row['officialQualifiedName'],label)
 def test_non_prefecture_parentheses_are_not_stripped(self):
  for label in ['駅（仮称）','駅（中央）','駅（あがりみち）','駅（大阪）']:
   with self.subTest(label=label):
    row=w.station_sign(self.sign_html(label));self.assertEqual(row['name'],label);self.assertEqual(row['officialQualifiedName'],label)
 def test_manifest_digest_mismatch_is_rejected(self):
  meta=next(m for m in self.manifest if m['file'].endswith('.html'))
  with tempfile.TemporaryDirectory(prefix='digest-test-',dir=SCRATCH) as directory:
   root=pathlib.Path(directory);(root/'manifest.json').write_text(json.dumps([meta]));(root/meta['file']).write_bytes((ROOT/meta['file']).read_bytes()+b' altered')
   with self.assertRaisesRegex(ValueError,'Source digest mismatch'):
    w.source_rows(root)
 def test_exact_package_membership_coverage(self):
  package=json.loads((APP/'public/rail/jp-2025.json').read_text());expected={l['id']+':'+s[0] for l in package['lines'] if l['operator']==w.OPERATOR for s in l['stations']}
  self.assertEqual(len(expected),1255);self.assertEqual(set(self.snapshot['byLineStation']),expected);self.assertEqual(self.snapshot['unresolved'],[]);self.assertEqual(self.snapshot['coverage']['groupsWithVerifiedMembership'],1154)
 def test_every_promoted_label_is_verbatim_official_sign_text(self):
  for key,row in self.snapshot['byLineStation'].items():
   e=row['identityEvidence'][0];sign=w.station_sign((ROOT/e['rawFile']).read_text());self.assertEqual(row['en'],sign['en'],key);self.assertEqual(e['officialStationId'],sign['officialStationId'],key)
 @staticmethod
 def sign_html(label):
  return '<h2 class="ekiSignBox__name">'+label+'</h2><span class="ekiSignBox__romanization">Published label</span><div class="ekiSignBox__link"><a href="/top?id=0123456">Station</a></div>'
if __name__ == '__main__':
 unittest.main(verbosity=2)
