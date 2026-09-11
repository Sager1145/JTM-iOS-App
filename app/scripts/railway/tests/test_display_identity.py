import os
import sys
import unittest

SCRIPT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LIB_DIR = os.path.join(SCRIPT_DIR, 'lib')
sys.path.insert(0, LIB_DIR)
import display_identity  # noqa: E402


def make_line(line_id, name, operator, rank, stations, operator_short=None):
    line = {
        'id': line_id,
        'name': name,
        'operator': operator,
        'rank': rank,
        'stations': stations,
    }
    if operator_short:
        line['operatorShort'] = operator_short
    return line


class NameKeyTests(unittest.TestCase):
    def test_full_width_space_stripped(self):
        self.assertEqual(display_identity.name_key('東　京', 'jp'), '東京')

    def test_yagana_normalised(self):
        # Spec 5.0: ヶ -> ケ, ヵ -> カ (two distinct target characters).
        self.assertEqual(display_identity.name_key('五ヶ瀬', 'jp'), '五ケ瀬')
        self.assertEqual(display_identity.name_key('五ヵ瀬', 'jp'), '五カ瀬')

    def test_nfkc_normalises_compat_forms(self):
        # Halfwidth katakana ｶ NFKC-normalises to full-width カ, matching
        # the post-NFKC form of ヵ (which also maps to カ, not ケ).
        self.assertEqual(
            display_identity.name_key('五ｶ瀬', 'jp'),
            display_identity.name_key('五ヵ瀬', 'jp'),
        )

    def test_latin_station_suffix_stripped_and_casefolded(self):
        self.assertEqual(display_identity.name_key('Union Station', 'us'), 'union')
        self.assertEqual(display_identity.name_key('Union station', 'us'), 'union')
        self.assertEqual(display_identity.name_key('UNION', 'us'), 'union')

    def test_trailing_eki_stripped_only_when_longer(self):
        self.assertEqual(display_identity.name_key('新宿駅', 'jp'), '新宿')
        # A name that IS just the suffix is left alone (not longer than it).
        self.assertEqual(display_identity.name_key('駅', 'jp'), '駅')

    def test_kr_yeok_and_tw_zhan_suffixes(self):
        self.assertEqual(display_identity.name_key('서울역', 'kr'), '서울')
        self.assertEqual(display_identity.name_key('台北站', 'tw'), '台北')


class HomonymLabelTests(unittest.TestCase):
    def test_same_name_different_operator_gets_operator_suffix(self):
        # 池田: two distinct stations, different ids, different operators.
        lines = [
            make_line(
                'op-a-line', '甲線', 'A鉄道', 1,
                [['ikeda-a', '池田', 135.0, 35.0, 'Ikeda']],
                operator_short='A',
            ),
            make_line(
                'op-b-line', '乙線', 'B鉄道', 2,
                [['ikeda-b', '池田', 135.5, 35.5, 'Ikeda']],
                operator_short='B',
            ),
        ]
        doc = display_identity.build_station_identity('jp', lines, {})
        by_id = {s['id']: s for s in doc['stations']}
        self.assertEqual(by_id['ikeda-a']['displayLabel'], '池田（A）')
        self.assertEqual(by_id['ikeda-b']['displayLabel'], '池田（B）')
        self.assertEqual(by_id['ikeda-a']['homonymGroup'], '池田')
        self.assertIn('池田', doc['homonymGroups'])
        self.assertEqual(sorted(doc['homonymGroups']['池田']['keys']), ['jp:ikeda-a', 'jp:ikeda-b'])

    def test_same_name_same_operator_different_line_gets_line_suffix(self):
        lines = [
            make_line(
                'op-a-line1', '甲線', 'A鉄道', 1,
                [['tanaka-1', '田中', 135.0, 35.0, 'Tanaka']],
                operator_short='A',
            ),
            make_line(
                'op-a-line2', '乙線', 'A鉄道', 2,
                [['tanaka-2', '田中', 135.5, 35.5, 'Tanaka']],
                operator_short='A',
            ),
        ]
        doc = display_identity.build_station_identity('jp', lines, {})
        by_id = {s['id']: s for s in doc['stations']}
        self.assertEqual(by_id['tanaka-1']['displayLabel'], '田中（甲線）')
        self.assertEqual(by_id['tanaka-2']['displayLabel'], '田中（乙線）')

    def test_coordinate_fallback_when_operator_and_line_both_match(self):
        lines = [
            make_line(
                'shared-line', '共通線', 'A鉄道', 1,
                [
                    ['dup-1', '重複', 135.0, 35.0, 'Juufuku'],
                    ['dup-2', '重複', 135.5, 35.5, 'Juufuku'],
                ],
                operator_short='A',
            ),
        ]
        doc = display_identity.build_station_identity('jp', lines, {})
        by_id = {s['id']: s for s in doc['stations']}
        self.assertEqual(by_id['dup-1']['displayLabel'], '重複（35.00,135.00）')
        self.assertEqual(by_id['dup-2']['displayLabel'], '重複（35.50,135.50）')

    def test_station_id_fallback_when_coordinates_round_together(self):
        # Two directional tram stops of one operator on one line, 30 m apart:
        # rule 4 rounds both to the same 0.01°, so rule 5 uses the id.
        lines = [
            make_line(
                'hk-tram', '港島綫', '香港電車', 1,
                [
                    ['tram-34w', '炮台山', 114.1901, 22.2901, 'Fortress Hill'],
                    ['tram-65e', '炮台山', 114.1903, 22.2902, 'Fortress Hill'],
                ],
            ),
        ]
        doc = display_identity.build_station_identity('hk', lines, {})
        by_id = {s['id']: s for s in doc['stations']}
        self.assertEqual(by_id['tram-34w']['displayLabel'], '炮台山（tram-34w）')
        self.assertEqual(by_id['tram-65e']['displayLabel'], '炮台山（tram-65e）')
        labels = [s['displayLabel'] for s in doc['stations']]
        self.assertEqual(len(labels), len(set(labels)))


class IdCollisionTests(unittest.TestCase):
    def test_spread_over_300m_flagged(self):
        # ~0.01 degrees longitude at the equator is ~1.1km, well over 300m.
        lines = [
            make_line(
                'line-x', 'X線', 'X鉄道', 1,
                [
                    ['same-id', '駅A', 0.0, 0.0, 'EkiA'],
                ],
                operator_short='X',
            ),
            make_line(
                'line-y', 'Y線', 'Y鉄道', 2,
                [
                    ['same-id', '駅A', 0.01, 0.0, 'EkiA'],
                ],
                operator_short='Y',
            ),
        ]
        doc = display_identity.build_station_identity('jp', lines, {})
        by_id = {s['id']: s for s in doc['stations']}
        self.assertTrue(by_id['same-id']['idCollision'])
        self.assertGreater(by_id['same-id']['spreadMetres'], 300)
        collision_keys = [c['key'] for c in doc['idCollisions']]
        self.assertIn('jp:same-id', collision_keys)

    def test_spread_under_300m_not_flagged(self):
        lines = [
            make_line(
                'line-x', 'X線', 'X鉄道', 1,
                [['near-id', '駅B', 0.0, 0.0, 'EkiB']],
                operator_short='X',
            ),
            make_line(
                'line-y', 'Y線', 'Y鉄道', 2,
                [['near-id', '駅B', 0.0005, 0.0, 'EkiB']],
                operator_short='Y',
            ),
        ]
        doc = display_identity.build_station_identity('jp', lines, {})
        by_id = {s['id']: s for s in doc['stations']}
        self.assertFalse(by_id['near-id']['idCollision'])
        self.assertEqual(doc['idCollisions'], [])


class SimilarNameGroupTests(unittest.TestCase):
    def test_similar_names_never_merge_identity_but_are_grouped_for_review(self):
        lines = [
            make_line(
                'saitama-line', '埼玉線', '埼玉鉄道', 1,
                [
                    ['urawa', '浦和', 139.65, 35.86, 'Urawa'],
                    ['higashi-urawa', '東浦和', 139.7, 35.87, 'Higashi-Urawa'],
                    ['minami-urawa', '南浦和', 139.66, 35.85, 'Minami-Urawa'],
                ],
                operator_short='埼玉',
            ),
        ]
        doc = display_identity.build_station_identity('jp', lines, {})
        by_id = {s['id']: s for s in doc['stations']}
        # Each keeps its own distinct nameKey / displayLabel — never merged.
        self.assertEqual(by_id['urawa']['nameKey'], '浦和')
        self.assertEqual(by_id['higashi-urawa']['nameKey'], '東浦和')
        self.assertEqual(by_id['minami-urawa']['nameKey'], '南浦和')
        self.assertEqual(by_id['urawa']['displayLabel'], '浦和')
        self.assertEqual(by_id['higashi-urawa']['displayLabel'], '東浦和')
        self.assertIsNone(by_id['urawa']['homonymGroup'])

        cores = {g['core']: g for g in doc['similarNameGroups']}
        self.assertIn('浦和', cores)
        self.assertEqual(sorted(cores['浦和']['names']), ['南浦和', '東浦和', '浦和'])


class LineDisplayLabelTests(unittest.TestCase):
    def test_duplicate_line_name_same_operator_falls_to_terminal_stations(self):
        lines = [
            make_line(
                'op-honsen-1', '本線', 'X鉄道', 1,
                [
                    ['a1', '甲', 135.0, 35.0, 'Kou'],
                    ['a2', '乙', 135.1, 35.1, 'Otsu'],
                ],
                operator_short='X',
            ),
            make_line(
                'op-honsen-2', '本線', 'X鉄道', 2,
                [
                    ['b1', '丙', 135.2, 35.2, 'Hei'],
                    ['b2', '丁', 135.3, 35.3, 'Tei'],
                ],
                operator_short='X',
            ),
        ]
        labels = display_identity.line_display_labels('jp', lines)
        self.assertEqual(labels['op-honsen-1']['displayLabel'], 'X本線（甲–乙）')
        self.assertEqual(labels['op-honsen-2']['displayLabel'], 'X本線（丙–丁）')
        self.assertEqual(len({v['displayLabel'] for v in labels.values()}), 2)

    def test_duplicate_line_name_different_operator_gets_operator_prefix(self):
        lines = [
            make_line(
                'toei-tozai', '東西線', '都営', 1,
                [['s1', '甲', 135.0, 35.0, 'Kou']],
                operator_short='都営',
            ),
            make_line(
                'tokyometro-tozai', '東西線', '東京メトロ', 2,
                [['s2', '乙', 135.1, 35.1, 'Otsu']],
                operator_short='メトロ',
            ),
        ]
        labels = display_identity.line_display_labels('jp', lines)
        self.assertEqual(labels['toei-tozai']['displayLabel'], '都営東西線')
        self.assertEqual(labels['tokyometro-tozai']['displayLabel'], 'メトロ東西線')

    def test_unique_line_name_kept_as_is(self):
        lines = [
            make_line('yamanote', '山手線', 'JR東日本', 1, [], operator_short='JR東'),
        ]
        labels = display_identity.line_display_labels('jp', lines)
        self.assertEqual(labels['yamanote']['displayLabel'], '山手線')


class IdentitySummaryTests(unittest.TestCase):
    def test_counters_reflect_document(self):
        lines = [
            make_line(
                'op-honsen-1', '本線', 'X鉄道', 1,
                [['a1', '池田', 135.0, 35.0, 'Ikeda']],
                operator_short='X',
            ),
            make_line(
                'op-honsen-2', '本線', 'Y鉄道', 2,
                [['b1', '池田', 135.5, 35.5, 'Ikeda']],
                operator_short='Y',
            ),
        ]
        station_doc = display_identity.build_station_identity('jp', lines, {})
        line_labels = display_identity.line_display_labels('jp', lines)
        summary = display_identity.identity_summary(station_doc, line_labels, lines)
        self.assertEqual(summary['homonymGroups'], 1)
        # sameNameLines counts distinct nameKeys shared by >=2 lines, not
        # the number of lines involved — one nameKey ('本線') here.
        self.assertEqual(summary['sameNameLines'], 1)
        self.assertEqual(summary['idCollisions'], 0)


class HubIndexTests(unittest.TestCase):
    def test_returns_empty_for_current_geographic_schema(self):
        doc = {
            'format': 'jtm-display-hubs-v1',
            'hubs': [
                {'id': 'chicago-union', 'region': 'us', 'centre': [-87.64, 41.87]},
            ],
        }
        self.assertEqual(display_identity.hub_index(doc, 'us'), {})

    def test_maps_station_ids_when_present(self):
        doc = {
            'hubs': [
                {'id': 'some-hub', 'region': 'jp', 'stationIds': ['s1', 's2']},
            ],
        }
        self.assertEqual(
            display_identity.hub_index(doc, 'jp'),
            {'s1': 'some-hub', 's2': 'some-hub'},
        )


if __name__ == '__main__':
    unittest.main()
