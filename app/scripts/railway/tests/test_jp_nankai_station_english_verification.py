"""Official bilingual identity and coverage regressions for Nankai."""
import copy
import gzip
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-jp-nankai-station-english.py'
SPEC = importlib.util.spec_from_file_location('nankai_evidence', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class NankaiEnglishTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # An existing but incomplete archive must still fail its original checks.
        if not MODULE.SOURCES.exists():
            raise unittest.SkipTest("本地官方原始证据未提供: " + str(MODULE.SOURCES))
        cls.documents, cls.metadata, cls.manifest = MODULE.load_sources()
        cls.records = MODULE.bilingual_rows(cls.documents, cls.metadata)
        cls.package = json.loads(MODULE.PACKAGE.read_text())
        cls.result = MODULE.build(cls.package, cls.records, cls.manifest, MODULE.load_review())

    def test_retained_snapshot_and_coverage_are_reproducible(self):
        published = json.loads(MODULE.OUTPUT.read_text())
        for field in ('byLineStation', 'coverage', 'unresolved'):
            self.assertEqual(self.result[field], published[field])
        self.assertEqual(105, self.result['coverage']['verifiedStationGroups'])
        self.assertEqual([], self.result['unresolved'])

    def test_exact_uppercase_and_macron_labels_are_preserved(self):
        row = next(r for r in self.result['byLineStation'].values() if r['name'] == '七道')
        self.assertEqual('SHICHIDŌ', row['en'])
        self.assertEqual('NK10', row['identityEvidence'][0]['stationNumber'])

    def test_english_package_fields_do_not_supply_evidence(self):
        package = copy.deepcopy(self.package)
        for line in package['lines']:
            for station in line['stations']:
                station[4] = 'UNTRUSTED FALLBACK'
        self.assertEqual(self.result, MODULE.build(package, self.records, self.manifest, MODULE.load_review()))

    def test_operator_identity_is_required(self):
        original = next(l for l in self.package['lines'] if l['operator'] == MODULE.OPERATOR)
        package = {'lines': [dict(original, operator='Other Railway')]}
        self.assertFalse(MODULE.build(package, self.records, self.manifest)['byLineStation'])

    def test_bilingual_station_number_disagreement_is_rejected(self):
        documents = dict(self.documents)
        documents['en-nankai_line'] = documents['en-nankai_line'].replace(
            'NK<span class="el-station-block__item__detail__numbering__item__number">01</span>',
            'NK<span class="el-station-block__item__detail__numbering__item__number">99</span>', 1)
        with self.assertRaisesRegex(ValueError, 'station number disagreement'):
            MODULE.bilingual_rows(documents, self.metadata)

    def test_snapshot_hash_tampering_is_rejected(self):
        source = next(r for r in self.manifest if r['id'] == 'operator-home')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / 'manifest.json').write_text(json.dumps([source]))
            (path / source['rawFile']).write_bytes(gzip.compress(b'changed official snapshot'))
            with self.assertRaisesRegex(ValueError, 'source hash mismatch'):
                MODULE.load_sources(path)

    def test_owned_english_site_link_is_required(self):
        documents = dict(self.documents)
        documents['operator-home'] = documents['operator-home'].replace(
            '<option value="/en_railway">English</option>', '')
        # The ownership link is checked when raw snapshots are loaded. Keep a
        # valid hash for this altered fixture so ownership, not hashing, fails.
        source = next(r for r in self.manifest if r['id'] == 'operator-home')
        raw = documents['operator-home'].encode()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / 'manifest.json').write_text(json.dumps([dict(source, sha256=MODULE.sha(raw))]))
            (path / source['rawFile']).write_bytes(gzip.compress(raw))
            with self.assertRaisesRegex(ValueError, 'ownership link absent'):
                MODULE.load_sources(path)


if __name__ == '__main__':
    unittest.main()
