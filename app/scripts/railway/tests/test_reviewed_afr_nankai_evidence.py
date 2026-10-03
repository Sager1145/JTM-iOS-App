import copy, gzip, importlib.util, json, pathlib, tempfile, unittest
BASE=pathlib.Path(__file__).resolve().parents[1]; REPO=BASE.parents[2]
def module(name):
 p=BASE/('verify-'+name+'-station-english.py');s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
AFR=module('tw-afr');N=module('jp-nankai')
class AFRTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  # An existing but incomplete archive must still fail its original checks.
  if not AFR.SOURCES.exists():
      raise unittest.SkipTest("本地官方原始证据未提供: " + str(AFR.SOURCES))
  cls.result=AFR.build();cls.original=AFR.read(AFR.BASELINE);cls.manifest,cls.docs=AFR.load_raw();cls.features,cls.members=AFR.package_identities()
 def verify(self,row,documents=None,memberships=None):
  return AFR.verify_row(row,self.manifest,documents or self.docs,self.features[row['stationCode']],memberships or self.members[row['stationGroupCode']])
 def test_all_19_labels_preserved_with_38_hashed_sources(self):
  self.assertEqual(19,len(self.result['byCode']));self.assertEqual(38,len(self.docs));self.assertEqual(0,self.result['rawVerification']['labelsChanged'])
  for code,original in self.original['byCode'].items():
   for field,value in original.items():self.assertEqual(value,self.result['byCode'][code][field])
 def test_reviewed_wood_alias_preserves_dataset_and_package_spellings(self):
  row=self.result['byCode']['AFR-Q0000004496'];self.assertEqual('木屐寮',row['name']);self.assertEqual('木履寮',row['zh_Hant']);self.assertEqual('木履寮',row['rawSourceVerification']['packageMemberships'][0]['name']);self.assertEqual('木履寮又叫木屐寮',row['rawSourceVerification']['nativeAlias']['publishedStatement'])
 def test_wood_unreviewed_alias_rejected(self):
  row=copy.deepcopy(self.original['byCode']['AFR-Q0000004496']);row['identityAliases']=[]
  with self.assertRaisesRegex(ValueError,'unreviewed'):self.verify(row)
 def test_package_wrong_native_rejected(self):
  row=self.original['byCode']['AFR-Q0000004496'];members=copy.deepcopy(self.members[row['stationGroupCode']]);members[0]['name']='木履寮別站'
  with self.assertRaisesRegex(ValueError,'membership mismatch'):self.verify(row,memberships=members)
 def test_homepage_relative_native_anchor_and_javascript_links(self):
  document='<a href="javascript:void(0)">menu</a><a href="0000087">獨立山</a>'
  self.assertEqual('0000087',AFR.homepage_identity(document,'0000087','獨立山')['pageId'])
 def test_homepage_external_and_wrong_id_rejected(self):
  for document in ['<a href="https://example.org/0000087">獨立山</a>','<a href="0000088">獨立山</a>']:
   with self.subTest(document=document),self.assertRaisesRegex(ValueError,'does not link'):AFR.homepage_identity(document,'0000087','獨立山')
 def test_original_english_variant_cannot_be_replaced(self):
  row=copy.deepcopy(self.original['byCode']['AFR-Q0000004496']);row['en']='Muliliao';row['englishEvidence']='Muliliao Station'
  with self.assertRaisesRegex(ValueError,'heading changed'):self.verify(row)
 def test_native_cms_disagreement_rejected(self):
  row=self.original['byCode']['AFR-I0000000551'];documents=dict(self.docs);documents[row['identitySource']]=documents[row['identitySource']].replace('SP_130000082','SP_130000099')
  with self.assertRaisesRegex(ValueError,'CMS identities disagree'):self.verify(row,documents=documents)
class NankaiProposedTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  # An existing but incomplete archive must still fail its original checks.
  if not N.SOURCES.exists():
      raise unittest.SkipTest("本地官方原始证据未提供: " + str(N.SOURCES))
  cls.docs,cls.metadata,cls.manifest=N.load_sources();cls.records=N.bilingual_rows(cls.docs,cls.metadata);cls.package=json.loads(N.PACKAGE.read_text());cls.review=N.load_review();cls.baseline=N.build(cls.package,cls.records,cls.manifest);cls.result=N.build(cls.package,cls.records,cls.manifest,cls.review)
 def build(self,package=None,records=None,review=None):return N.build(package or self.package,records or self.records,self.manifest,review or self.review)
 def test_retained_101_groups_four_pending(self):
  self.assertEqual(101,self.baseline['coverage']['verifiedStationGroups']);self.assertEqual(110,self.baseline['coverage']['verifiedLineStations']);self.assertEqual({'難波','和歌山大学前','今宮戎','萩ノ茶屋'},{row['name'] for row in self.baseline['unresolved']})
 def test_all_105_groups_114_memberships(self):
  self.assertEqual({'verifiedLineStations':114,'verifiedStationGroups':105,'unresolvedLineStations':0,'unresolvedStationGroups':0},self.result['coverage'])
 def test_existing_110_memberships_unchanged(self):
  for key,value in self.baseline['byLineStation'].items():self.assertEqual(value,self.result['byLineStation'][key])
 def test_exact_published_english_and_native_identity(self):
  expected={'007356':('NAMBA','namba','NK01','なんば'),'008294':('WAKAYAMADAIGAKUMAE','wadaimae','NK43','和歌山大学前(ふじと台)'),'007402':('IMAMIYAEBISU','imamiyaebisu','NK02','今宮戎'),'007452':('HAGINOCHAYA','haginochaya','NK04','萩ノ茶屋')}
  for code,values in expected.items():
   row=self.result['byLineStation']['jp-南海電気鉄道-南海本線:'+code];e=row['identityEvidence'][0];self.assertEqual(values,(row['en'],e['officialStationId'],e['stationNumber'],e['ja']))
 def test_english_package_poisoning_has_no_effect(self):
  package=copy.deepcopy(self.package)
  for line in package['lines']:
   for station in line['stations']:station[4]='UNTRUSTED ENGLISH'
  self.assertEqual(self.result,self.build(package=package))
 def test_explicit_physical_not_service_line_evidence(self):
  for code,name in [('007402','今宮戎'),('007452','萩ノ茶屋')]:
   self.assertFalse(self.records.get(('nankai_line',N.native(name))));self.assertEqual(1,len(self.records[('koya_line',N.native(name))]));row=self.result['byLineStation']['jp-南海電気鉄道-南海本線:'+code];e=row['identityEvidence'][0];self.assertEqual('koya_line',e['officialRouteId']);self.assertEqual('nankai_line',e['reviewedPackageIdentity']['packageRoute']);self.assertEqual({'handbook-2023','securities-109th'},{proof['sourceId'] for proof in e['reviewedNativeIdentityEvidence']})
 def test_unreviewed_native_alias_mutants_rejected(self):
  for field,value in [('packageNative','難波別站'),('officialNative','難波'),('officialStationId','different'),('stationNumber','NK99'),('packageRoute','airport_line')]:
   review=copy.deepcopy(self.review);review['rules'][0][field]=value
   with self.subTest(field=field),self.assertRaisesRegex(ValueError,'unreviewed'):self.build(review=review)
 def test_package_code_native_mutant_rejected(self):
  for code in ['007356','007402','007452','008294']:
   package=copy.deepcopy(self.package);line=next(l for l in package['lines'] if l['id']=='jp-南海電気鉄道-南海本線');next(s for s in line['stations'] if s[0]==code)[1]='wrong station'
   with self.subTest(code=code),self.assertRaisesRegex(ValueError,'code/native identity'):self.build(package=package)
 def test_physical_service_route_mutants_rejected(self):
  for i in [2,3]:
   review=copy.deepcopy(self.review);review['rules'][i]['evidenceRoute']='airport_line'
   with self.subTest(rule=i),self.assertRaisesRegex(ValueError,'unreviewed'):self.build(review=review)
 def test_missing_physical_membership_proof_rejected(self):
  review=copy.deepcopy(self.review);review['rules'][2]['proof']=[]
  with self.assertRaisesRegex(ValueError,'proof coverage'):self.build(review=review)
 def test_number_and_station_slug_mismatch_rejected(self):
  for field,value in [('stationNumber','NK99'),('officialStationId','different')]:
   records=copy.deepcopy(self.records);records[('koya_line',N.native('今宮戎'))][0][field]=value
   with self.subTest(field=field),self.assertRaisesRegex(ValueError,'official native station identity'):self.build(records=records)
 def test_bilingual_number_disagreement_rejected(self):
  docs=dict(self.docs);docs['en-koya_line']=docs['en-koya_line'].replace('NK<span class="el-station-block__item__detail__numbering__item__number">02</span>','NK<span class="el-station-block__item__detail__numbering__item__number">99</span>',1)
  with self.assertRaisesRegex(ValueError,'number disagreement'):N.bilingual_rows(docs,self.metadata)
 def test_supplemental_raw_hash_tampering_rejected(self):
  with tempfile.TemporaryDirectory(dir=BASE) as temp:
   path=pathlib.Path(temp);review=copy.deepcopy(self.review);review['rawDirectory']=str(path)
   for record in review['sourceRecords']:(path/record['rawFile']).write_bytes((N.REVIEW.parent/record['rawFile']).read_bytes())
   victim=review['sourceRecords'][0];(path/victim['rawFile']).write_bytes(gzip.compress(b'changed official source'));(path/'review.json').write_text(json.dumps(review))
   with self.assertRaisesRegex(ValueError,'source hash mismatch'):N.load_review(path/'review.json')
if __name__ == '__main__':
 unittest.main()
