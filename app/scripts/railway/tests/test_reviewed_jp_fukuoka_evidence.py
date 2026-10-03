import copy, importlib.util, json, tempfile, unittest
from pathlib import Path
APP=Path(__file__).resolve().parents[3]
ROOT=APP/'data/station-english-sources/jp-fukuoka'
spec=importlib.util.spec_from_file_location('verify',APP/'scripts/railway/verify-jp-fukuoka-station-english.py');verify=importlib.util.module_from_spec(spec);spec.loader.exec_module(verify)
class EvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # An existing but incomplete archive must still fail its original checks.
        if not ROOT.exists():
            raise unittest.SkipTest("本地官方原始证据未提供: " + str(ROOT))
    def test_all_memberships_and_shared_numbers(self):
        r=verify.build(APP/'public/rail/jp-2025.json');self.assertEqual(len(r['byLineStation']),38);self.assertEqual(len({x['stationCode'] for x in r['byLineStation'].values()}),36);self.assertEqual(r['unresolved'],[])
        identities={x['identityEvidence'][0]['officialStationId'] for x in r['byLineStation'].values()};self.assertEqual(len(identities),38)
        self.assertEqual(r['byLineStation']['jp-福岡市-3号線(七隈線):009033']['identityEvidence'][0]['stationNumber'],'N18')
        self.assertEqual(r['byLineStation']['jp-福岡市-2号線(箱崎線):009000']['en'],'Maidashi-Kyudaibyoinmae')
    def test_package_romanization_has_no_effect(self):
        package=json.loads((APP/'public/rail/jp-2025.json').read_text());baseline=verify.build(APP/'public/rail/jp-2025.json')
        for line in package['lines']:
            for station in line['stations']:station[4]='NOT A SOURCE'
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            path=Path(directory)/'package.json';path.write_text(json.dumps(package));self.assertEqual(verify.build(path),baseline)
    def test_wrong_native_identity_is_unresolved(self):
        package=json.loads((APP/'public/rail/jp-2025.json').read_text());package['lines']=[l for l in package['lines'] if l['operator']=='福岡市'];package['lines'][0]['stations'][0][1]='別の姪浜'
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            path=Path(directory)/'package.json';path.write_text(json.dumps(package));result=verify.build(path);self.assertEqual(len(result['unresolved']),1);self.assertNotIn('jp-福岡市-1号線(空港線):009046',result['byLineStation'])
    def test_comments_do_not_prove_native_identity(self):
        source=(ROOT/'home-ja.html').read_text();source=source.replace('<li class="k01"><a href="eki/stations/meinohama.php"><b>姪浜</b></a>　―　JR筑肥線</li>','<!--<li class="k01"><a href="eki/stations/meinohama.php"><b>姪浜</b></a></li>-->')
        with self.assertRaisesRegex(ValueError,'Incomplete'):verify.parse_native(source)
    def test_changed_source_hash_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            scratch=Path(directory)
            for filename in json.loads((ROOT/'sources.json').read_text()):
                (scratch/filename).write_bytes((ROOT/filename).read_bytes())
            (scratch/'sources.json').write_bytes((ROOT/'sources.json').read_bytes());(scratch/'map-labels-reviewed.json').write_bytes((ROOT/'map-labels-reviewed.json').read_bytes());(scratch/'home-ja.html').write_text('modified')
            with self.assertRaisesRegex(ValueError,'digest mismatch'):verify.build(APP/'public/rail/jp-2025.json',scratch)
if __name__ == '__main__':
 unittest.main()
