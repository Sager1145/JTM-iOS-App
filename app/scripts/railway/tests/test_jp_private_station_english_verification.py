"""Exercise private operator identity matching and retained official snapshots."""
import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-jp-private-station-english.py'
SPEC = importlib.util.spec_from_file_location('verify_jp_private_station_english', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PrivateRailwayEnglishTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # An existing but incomplete archive must still fail its original checks.
        if not MODULE.SOURCES.exists():
            raise unittest.SkipTest("本地官方原始证据未提供: " + str(MODULE.SOURCES))
        cls.documents, cls.metadata, cls.manifest = MODULE.load_sources(MODULE.SOURCES)
        cls.records = MODULE.official_records(cls.documents, cls.metadata)
        cls.package = json.loads(MODULE.PACKAGE.read_text())
        cls.result = MODULE.build(cls.package, cls.records, cls.manifest)

    def test_full_major_operator_coverage_and_reproducible_snapshot(self):
        for operator, count in [('近畿日本鉄道', 287), ('名古屋鉄道', 276), ('東急電鉄', 98), ('西武鉄道', 92)]:
            stat = self.result['coverage']['byOperator'][operator]
            self.assertEqual(count, stat['verifiedStationGroups'])
            self.assertEqual(0, stat['unresolvedStationGroups'])
        self.assertEqual(self.result, json.loads(MODULE.OUTPUT.read_text()))

    def test_kintetsu_connecting_operator_records_are_not_admitted(self):
        master = json.loads(self.documents['kintetsu-master'])
        record_ids = {r['officialStationId'] for r in self.records if r['operator'] == '近畿日本鉄道'}
        for row in master:
            if row.get('駅コード') is not None and (not row.get('路線1') or not row.get('駅名英語')):
                self.assertNotIn(str(row['駅コード']).zfill(5), record_ids)
        self.assertEqual('Osaka-Namba', next(r['en'] for r in self.records
                         if r['operator'] == '近畿日本鉄道' and r['officialStationId'] == '01005'))

    def test_keisei_bilingual_dropdown_joins_numeric_ids(self):
        records = [r for r in self.records if r['operator'] == '京成電鉄']
        self.assertEqual(87, len(records))
        row = next(r for r in records if r['officialStationId'] == '110')
        self.assertEqual(('青砥', 'Aoto'), (row['ja'], row['en']))
        self.assertIn('same numeric station map ID', row['matchMethod'])

    def test_exact_official_english_label_is_preserved(self):
        row = next(r for r in self.records if r['operator'] == '名古屋鉄道' and r['ja'] == '名鉄名古屋')
        self.assertEqual('MEITETSU NAGOYA', row['en'])
        row = next(r for r in self.records if r['operator'] == '東急電鉄' and r['ja'] == '大岡山')
        self.assertEqual('Ōokayama', row['en'])

    def test_package_english_cannot_supply_or_override_evidence(self):
        package = copy.deepcopy(self.package)
        for line in package['lines']:
            for station in line['stations']:
                station[4] = 'UNTRUSTED ROMAJI FALLBACK'
        result = MODULE.build(package, self.records, self.manifest)
        self.assertEqual(self.result, result)
        self.assertFalse(any(r['en'] == 'UNTRUSTED ROMAJI FALLBACK'
                             for r in result['byLineStation'].values()))

    def test_foreign_operator_same_name_cannot_promote(self):
        line = next(l for l in self.package['lines'] if l['operator'] == '名古屋鉄道')
        station = line['stations'][0]
        foreign = {'operator': '京成電鉄', 'ja': station[1], 'en': 'Foreign station label', 'officialStationId': 'foreign'}
        result = MODULE.build({'lines': [line]}, [foreign], self.manifest)
        self.assertFalse(result['byLineStation'])

    def test_conflicting_official_ids_stay_unresolved(self):
        line = next(l for l in self.package['lines'] if l['operator'] == '名古屋鉄道')
        station = line['stations'][0]
        a = next(r for r in self.records if r['operator'] == line['operator'] and MODULE.normalize(r['ja']) == MODULE.normalize(station[1]))
        b = dict(a, officialStationId='another official identity')
        result = MODULE.build({'lines': [dict(line, stations=[station])]}, [a, b], self.manifest)
        self.assertFalse(result['byLineStation'])
        self.assertIn('ambiguous', result['unresolved'][0]['reason'])

    def test_gzip_snapshot_keeps_original_response_hash(self):
        item = next(m for m in self.manifest if m.get('compression') == 'gzip')
        raw = (MODULE.SOURCES / item['rawFile']).read_bytes()
        self.assertEqual(item['sha256'], hashlib.sha256(gzip.decompress(raw)).hexdigest())
        self.assertEqual('decompressed-original-response', item['sha256Of'])

    def test_altered_snapshot_is_rejected(self):
        item = next(m for m in self.manifest if m.get('compression') == 'gzip')
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / 'manifest.json').write_text(json.dumps([item]))
            (directory / item['rawFile']).write_bytes(gzip.compress(b'<h1>altered official name</h1>'))
            with self.assertRaisesRegex(ValueError, 'source hash mismatch'):
                MODULE.load_sources(directory)

    def test_native_glyph_variation_does_not_romanize_name(self):
        self.assertEqual(MODULE.normalize('祇園四条'), MODULE.normalize('祇\U000e0100園四条'))
        self.assertNotEqual(MODULE.normalize('新宿'), MODULE.normalize('西武新宿'))


if __name__ == '__main__':
    unittest.main()
