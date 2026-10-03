"""Offline identity/evidence regression tests for the official HK/MO snapshot."""
import copy
import importlib.util
import json
import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('hk_mo_english', APP / 'scripts/railway/fetch-hk-mo-station-english.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class OfficialStationEnglishTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.snapshot = json.loads((APP / 'data/hk-mo-station-english-official.json').read_text())
        cls.packages = {c: json.loads((APP / f'public/rail/{c}-2025.json').read_text()) for c in ['hk', 'mo']}

    def test_every_shipped_group_has_primary_evidence(self):
        for country, expected in [('hk', 282), ('mo', 15)]:
            data = self.snapshot['byCountry'][country]
            self.assertEqual(len(data['byCode']), expected)
            self.assertEqual(data['unresolved'], [])
            self.assertEqual(set(data['byCode']), {s[0] for l in self.packages[country]['lines'] for s in l['stations']})
            for row in data['byCode'].values():
                self.assertTrue(row['identityEvidence']['sourceStationCode'])
                self.assertTrue(row['identityEvidence']['sourceName'])
                self.assertIn(row['source'], module.URLS.values())
                self.assertTrue(row['retrievedAt'])

    def test_rebuild_does_not_use_package_english_or_official_flags(self):
        packages = copy.deepcopy(self.packages)
        for package in packages.values():
            for line in package['lines']:
                for station in line['stations']:
                    station[4:] = ['deliberately wrong English', 0]
        rebuilt = module.build_snapshot(packages, self.snapshot['sourceRecords'], self.snapshot['sources'], self.snapshot['retrievedAt'])
        self.assertEqual(rebuilt['byCountry'], self.snapshot['byCountry'])

    def test_operator_mismatch_and_ambiguous_source_never_promote(self):
        records = self.snapshot['sourceRecords']
        group = 'hk-official-mtr-hok'
        self.assertIsNone(module.match_group('hk', group, '香港', '香港電車', records))
        bad = records + [dict(next(r for r in records if r['operator'] == 'MTR' and r['code'] == 'HOK'), en='Invented')]
        self.assertIsNone(module.match_group('hk', group, '香港', 'MTR', bad))
        self.assertIsNone(module.match_group('hk', group, 'Wrong Chinese', 'MTR', records))

    def test_reused_tram_terminal_code_is_resolved_by_chinese_identity(self):
        rows = self.snapshot['byCountry']['hk']['byCode']
        self.assertEqual(rows['hk-official-tram-ktt']['en'], 'Kennedy Town Terminus')
        self.assertEqual(rows['hk-official-tram-skt']['en'], 'Shau Kei Wan Terminus')
        self.assertEqual(rows['hk-official-tram-ktt']['identityEvidence']['sourceStationCode'], 'T')
        self.assertNotEqual(rows['hk-official-tram-ktt']['identityEvidence']['sourceName'], rows['hk-official-tram-skt']['identityEvidence']['sourceName'])

    def test_duplicate_official_codes_must_agree(self):
        rows = [dict(operator='MTR', code='HOK', name='香港', en='Hong Kong'),
                dict(operator='MTR', code='HOK', name='香港', en='Invented')]
        with self.assertRaisesRegex(ValueError, 'Conflicting official bilingual identity'):
            module.unique(rows, 'code')
        self.assertEqual(len(module.unique([rows[0], rows[0]], 'code')), 1)

    def test_source_variants_and_racecourse_are_visible(self):
        rows = self.snapshot['byCountry']['hk']['byCode']
        self.assertEqual(rows['hk-official-mtr-lak']['name'], '荔景')
        self.assertEqual(rows['hk-official-mtr-lak']['identityEvidence']['sourceName'], '茘景')
        self.assertEqual(rows['hk-official-mtr-rac']['en'], 'Racecourse')
        self.assertEqual(rows['hk-official-mtr-rac']['identityEvidence']['sourceCode'], 'rac.pdf')
        lotus = self.snapshot['byCountry']['mo']['byCode']['mo-official-mlm-lotus']
        self.assertEqual(lotus['en'], 'Lotus')
        self.assertEqual(lotus['identityEvidence']['sourceName'], '蓮花口岸站')
        self.assertEqual(lotus['identityEvidence']['sourceStationCode'], '7.1')

if __name__ == '__main__':
    unittest.main()
