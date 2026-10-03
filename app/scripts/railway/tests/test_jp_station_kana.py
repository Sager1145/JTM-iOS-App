"""Published kana extraction must preserve operator/station/line identities."""
import gzip
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from jp_station_kana import build_kana_evidence, reading_forms, read_source


class KanaEvidenceTests(unittest.TestCase):
    def test_script_conversion_preserves_published_sounds(self):
        self.assertEqual(reading_forms('じぇいあーるみやまき'), ('じぇいあーるみやまき', 'ジェイアールミヤマキ'))
        self.assertEqual(reading_forms('オクツガルイマベツ'), ('おくつがるいまべつ', 'オクツガルイマベツ'))
        self.assertIsNone(reading_forms('JR-Miyamaki'))
        self.assertIsNone(reading_forms('新潟'))

    def test_hash_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'source.html'
            path.write_text('source')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                read_source(path, '0' * 64)

    def test_station_id_line_operator_and_conflicts(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            root = app / 'data/station-english-sources'
            (root / 'jp').mkdir(parents=True)
            (root / 'jp-private').mkdir()
            manifest = {}
            for sid, filename, value in [('hokkaido', 'hokkaido-master.json', []),
                                         ('central-ja', 'central-ja.json', {'lst': [
                                             {'ryokakuEkiCd': '1', 'ryokakuSenkuCd': 'L1', 'ryokakuSenkuKbn': '1', 'ekiMei': '府中', 'ekiMeiYomigana': 'ふちゅう'},
                                             {'ryokakuEkiCd': '2', 'ryokakuSenkuCd': 'L2', 'ryokakuSenkuKbn': '1', 'ekiMei': '府中', 'ekiMeiYomigana': 'こう'},
                                             {'ryokakuEkiCd': '3', 'ryokakuSenkuCd': 'L3', 'ryokakuSenkuKbn': '1', 'ekiMei': '高松', 'ekiMeiYomigana': 'たかまつ'},
                                             {'ryokakuEkiCd': '3', 'ryokakuSenkuCd': 'L3', 'ryokakuSenkuKbn': '1', 'ekiMei': '高松', 'ekiMeiYomigana': 'こうしょう'},
                                         ]})]:
                content = json.dumps(value, ensure_ascii=False)
                (root / 'jp' / filename).write_text(content)
                manifest[sid] = {'filename': filename, 'url': 'https://operator.example/' + filename,
                                 'sha256': hashlib.sha256(content.encode()).hexdigest()}
            (root / 'jp/manifest.json').write_text(json.dumps(manifest))
            (root / 'jp-private/manifest.json').write_text('[]')
            rows = {}
            for key, station_id, line_id, operator, name in [
                ('correct:1', '1', 'L1', '東海旅客鉄道', '府中'),
                ('different-id:2', '2', 'L2', '東海旅客鉄道', '府中'),
                ('wrong-line:1', '1', 'L2', '東海旅客鉄道', '府中'),
                ('other-operator:1', '1', 'L1', '別会社', '府中'),
                ('conflict:3', '3', 'L3', '東海旅客鉄道', '高松'),
            ]:
                rows[key] = {'country': 'jp', 'lineId': key.split(':')[0], 'stationCode': key.split(':')[1], 'operator': operator, 'name': name,
                             'identityEvidence': [{'name': name, 'officialStationId': station_id, 'officialLineIds': [line_id]}]}
            for cohort in ('jp', 'jp-private', 'jp-west'):
                (app / ('data/station-english-verified-' + cohort + '.json')).write_text(json.dumps({'byLineStation': rows if cohort == 'jp' else {}}, ensure_ascii=False))
            (root / 'jp-east').mkdir()
            east_document = '<div class="estation-nameplate"><h1>羽沢横浜国大<span>はざわよこはまこくだい</span></h1></div><a href="/estation/station/info.aspx?StationCd=1749">駅情報</a>'
            east_bytes = east_document.encode()
            east_path = root / 'jp-east/ja-station-1749.html.gz'
            east_path.write_bytes(gzip.compress(east_bytes, mtime=0))
            east = {'country': 'jp', 'lineId': 'east', 'stationCode': '1749', 'operator': '東日本旅客鉄道', 'name': '羽沢横浜国大',
                    'identityEvidence': [{'ja': '羽沢横浜国大', 'stationId': '1749', 'japaneseRawSource': 'data/station-english-sources/jp-east/ja-station-1749.html.gz',
                                          'japaneseSha256': hashlib.sha256(east_bytes).hexdigest(), 'japaneseSource': 'https://operator.example/list1749.html'}]}
            (app / 'data/station-english-verified-jp-east.json').write_text(json.dumps({'byLineStation': {'east:1749': east}}, ensure_ascii=False))
            result = build_kana_evidence(app)
            self.assertEqual(result, build_kana_evidence(app))
            self.assertEqual(result['inputSha256'][east_path.relative_to(app).as_posix()], hashlib.sha256(east_path.read_bytes()).hexdigest())
            self.assertEqual(result['byLineStation']['east:1749']['kana'], 'はざわよこはまこくだい')
            self.assertEqual(set(result['byLineStation']), {'correct:1', 'different-id:2', 'east:1749'})
            self.assertEqual(result['byLineStation']['correct:1']['kana'], 'ふちゅう')
            self.assertEqual(result['byLineStation']['different-id:2']['kana'], 'こう')
            self.assertEqual(next(r for r in result['unresolved'] if r['key'] == 'conflict:3')['reason'], 'conflicting-published-readings')


if __name__ == '__main__':
    unittest.main()
