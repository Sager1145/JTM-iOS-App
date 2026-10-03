"""Verify official identity admission and every retained Taiwan snapshot."""
import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-tw-station-english.py'
SPEC = importlib.util.spec_from_file_location('verify_tw_station_english', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class TaiwanEnglishVerificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # An existing but incomplete archive must still fail its original checks.
        if not MODULE.SOURCES.exists():
            raise unittest.SkipTest("本地官方原始证据未提供: " + str(MODULE.SOURCES))
        cls.sources, cls.manifest = MODULE.load_sources(MODULE.SOURCES)
        cls.package = json.loads(MODULE.PACKAGE.read_text())
        cls.result = MODULE.build(cls.package, cls.sources, cls.manifest)

    def test_all_non_afr_package_line_stations_have_official_identity(self):
        expected = {line['id'] + ':' + row[0] for line in self.package['lines']
                    if not line['id'].startswith('tw-alsr') for row in line['stations']}
        self.assertEqual(expected, set(self.result['byLineStation']))
        self.assertFalse(self.result['unresolved'])
        self.assertEqual(562, len(expected))
        self.assertEqual(self.result, json.loads(MODULE.OUTPUT.read_text()))

    def test_merged_kaohsiung_group_keeps_each_official_line_label(self):
        rows = self.result['byLineStation']
        group = 'tw-official-klrt-network-c3'
        light = rows['tw-klrt-c:' + group]
        metro = rows['tw-krtc-r:' + group]
        self.assertEqual('Cianjhen Star', light['en'])
        self.assertEqual('Kaisyuan', metro['en'])
        self.assertEqual('KLRT-NETWORK-C3', light['identityEvidence'][0]['officialStationId'])
        self.assertEqual('KRTC-R6', metro['identityEvidence'][0]['officialStationId'])

    def test_taipei_interchanges_keep_operator_english_variants(self):
        rows = self.result['byLineStation']
        group = 'tw-official-thsr-1000'
        self.assertEqual('Taipei', rows['tw-thsr-main:' + group]['en'])
        self.assertEqual('Taipei Main Station', rows['tw-tym-a:' + group]['en'])
        self.assertEqual('TYMC-A1', rows['tw-tym-a:' + group]['identityEvidence'][0]['officialStationId'])

    def test_wrong_operator_is_rejected(self):
        line = copy.deepcopy(next(l for l in self.package['lines'] if l['id'] == 'tw-thsr-main'))
        line['operator'] = '國營臺灣鐵路股份有限公司'
        with self.assertRaisesRegex(ValueError, 'operator mismatch'):
            MODULE.mapping(line)

    def test_existing_english_and_flags_cannot_create_evidence(self):
        official = copy.deepcopy(self.sources[('THSR', 'station')][0][0])
        row = next(l for l in self.package['lines'] if l['id'] == 'tw-thsr-main')['stations'][0]
        official['StationName']['En'] = ''
        matched, reason = MODULE.match_station(row, [official], {official['StationID']: official['StationName']})
        self.assertIsNone(matched)
        self.assertIn('no English', reason)

    def test_same_name_far_away_and_wrong_line_are_rejected(self):
        official = copy.deepcopy(self.sources[('THSR', 'station')][0][0])
        row = next(l for l in self.package['lines'] if l['id'] == 'tw-thsr-main')['stations'][0]
        members = {official['StationID']: official['StationName']}
        self.assertIsNone(MODULE.match_station(row, [official], {})[0])
        official['StationPosition']['PositionLon'] += 1
        self.assertIsNone(MODULE.match_station(row, [official], members)[0])

    def test_disagreeing_official_bilingual_line_is_not_admitted(self):
        official = copy.deepcopy(self.sources[('THSR', 'station')][0][0])
        row = next(l for l in self.package['lines'] if l['id'] == 'tw-thsr-main')['stations'][0]
        members = {official['StationID']: dict(official['StationName'], En='Unverified spelling')}
        self.assertIn('disagree', MODULE.match_station(row, [official], members)[1])

    def test_snapshot_tampering_fails_hash_check(self):
        item = self.manifest[0]
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / 'manifest.json').write_text(json.dumps([item]))
            (directory / item['rawFile']).write_text('[]')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                MODULE.load_sources(directory)


if __name__ == '__main__':
    unittest.main()
