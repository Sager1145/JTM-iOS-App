import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-jp-east-station-english.py'
SPEC = importlib.util.spec_from_file_location('jp_east_english_verification', SCRIPT)
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class JrEastEnglishVerificationTests(unittest.TestCase):
    def record(self, station_id, name, routes=('東北本線',)):
        return {'stationId': station_id, 'name': name, 'routes': list(routes)}

    def test_table_parser_retains_publisher_id_and_routes(self):
        document = '''<table><tr><th class="eki"><a href="/timetable/list1039.html">東京(とうきょう)</a></th>
          <td class="token">東京都</td><td class="rosen"><span>山手線</span><span>東北本線</span></td></tr></table>'''
        row = VERIFY.table_rows(document, 'ja')[0]
        self.assertEqual(row['stationId'], '1039')
        self.assertEqual(row['name'], '東京')
        self.assertEqual(row['publishedLabel'], '東京(とうきょう)')
        self.assertEqual(row['routes'], ['山手線', '東北本線'])

    def test_exact_station_id_pairs_languages_and_preserves_official_spelling(self):
        japanese = {'1': self.record('1', '東京')}
        english = {'1': self.record('1', 'Tokyo'), '2': self.record('2', 'Wrong English')}
        jp, en, reason = VERIFY.match_station('東京', '東北線', japanese, english)
        self.assertEqual(jp['stationId'], en['stationId'])
        self.assertEqual(en['name'], 'Tokyo')
        self.assertIsNone(reason)

    def test_no_english_name_fallback_when_native_identity_does_not_match(self):
        japanese = {'1': self.record('1', '別駅')}
        english = {'1': self.record('1', 'Tokyo')}
        self.assertIsNone(VERIFY.match_station('東京', '東北線', japanese, english)[0])

    def test_homonyms_require_route_identity_and_ambiguous_route_is_refused(self):
        japanese = {'1': self.record('1', '同名駅', ('常磐線',)),
                    '2': self.record('2', '同名駅', ('成田線',))}
        english = {'1': self.record('1', 'First'), '2': self.record('2', 'Second')}
        self.assertEqual(VERIFY.match_station('同名駅', '成田線', japanese, english)[1]['name'], 'Second')
        self.assertIsNone(VERIFY.match_station('同名駅', '東北線', japanese, english)[0])
        japanese['2']['routes'] = ['常磐線']
        self.assertIsNone(VERIFY.match_station('同名駅', '常磐線', japanese, english)[0])

    def test_native_typography_is_accepted_without_phonetic_normalization(self):
        self.assertEqual(VERIFY.native_identity('阿佐ヶ谷'), VERIFY.native_identity('阿佐ケ谷'))
        self.assertEqual(VERIFY.native_identity('Jヴィレッジ'), VERIFY.native_identity('Ｊヴィレッジ'))
        self.assertEqual(VERIFY.native_identity('空港第2ビル'), VERIFY.native_identity('空港第２ビル'))
        self.assertEqual(VERIFY.native_identity('文挟'), VERIFY.native_identity('文挾'))
        self.assertNotEqual(VERIFY.native_identity('東京'), VERIFY.native_identity('とうきょう'))

    def test_station_detail_counterpart_requires_matching_published_numeric_id(self):
        document = '''<div class="estation-nameplate"><h1>羽沢横浜国大<span>はざわよこはまこくだい</span></h1></div>
        <a href="https://www.jreast.co.jp/estation/station/info.aspx?StationCd=1749">駅情報</a>
        <tr><th>相鉄線直通</th><td>埼京線方面</td></tr>'''
        row = VERIFY.station_detail_row(document, '1749')
        self.assertEqual(row['name'], '羽沢横浜国大')
        self.assertEqual(row['routes'], ['相鉄線直通'])
        with self.assertRaises(ValueError):
            VERIFY.station_detail_row(document, '1748')

    def test_complete_snapshot_preserves_compact_codes_and_operator_memberships(self):
        snapshot = VERIFY.read(VERIFY.OUTPUT)
        package = VERIFY.read(VERIFY.APP / 'public/rail/jp-2025.json')
        expected = {line['id'] + ':' + station[0] for line in package['lines']
                    if line['operator'] == VERIFY.OPERATOR for station in line['stations']}
        self.assertEqual(set(snapshot['byLineStation']), expected)
        self.assertFalse(snapshot['unresolved'])
        self.assertEqual(snapshot['coverage']['verifiedJrEastGroups'], 1628)
        for row in snapshot['byLineStation'].values():
            self.assertEqual(row['operator'], VERIFY.OPERATOR)
            self.assertEqual(row['country'], 'jp')
            evidence = row['identityEvidence'][0]
            self.assertEqual(row['en'], evidence['en'])
            self.assertEqual(len(evidence['sha256']), 64)
            self.assertEqual(len(evidence['japaneseSha256']), 64)
            self.assertTrue(evidence['stationId'])
            self.assertTrue(evidence['retrievedAt'])


if __name__ == '__main__':
    unittest.main()
