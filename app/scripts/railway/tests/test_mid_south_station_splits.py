import importlib.util
import json
import os
import unittest


HERE = os.path.dirname(__file__)
REGISTRY = os.path.abspath(os.path.join(HERE, '..', 'na-feeds.json'))


class MidSouthStationSplitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            cls.registry = json.load(source)

    def test_exact_official_station_complex_limits(self):
        records = self.registry['stationSplitExceptions']
        expected = {
            'us-official-fairview-heights-metrolink':
                (80, ['10602'], {
                    '4166ed2551eec48789d9e5387057644e108e976cd30995c0e35f6dea648d167f',
                    '63482e125700bf820d2e5a8151a32b294d2dd6e270d4cb65a221bee3313763bd',
                }),
            'us-official-canal-st-at-carondelet-st':
                (35, ['1041', '1965', '1667'], {
                    '3b32471680f5736301fdcaa2ae98bf62ba6e108ea51589febb1d66114ee567f9',
                    'b59d26a9ede987908180886bb1391f0bdaa7a64ef3092594fbd2258807a4ebaf',
                }),
            'us-official-n-carrollton-ave-at-canal-st':
                (40, ['1634', '1635'], {
                    '3b32471680f5736301fdcaa2ae98bf62ba6e108ea51589febb1d66114ee567f9',
                    'b59d26a9ede987908180886bb1391f0bdaa7a64ef3092594fbd2258807a4ebaf',
                }),
        }
        for station_id, (limit, stop_ids, hashes) in expected.items():
            record = records[station_id]
            self.assertEqual(record['maxMeters'], limit)
            self.assertEqual(record['stopIds'], stop_ids)
            self.assertEqual(set(record['sourceSha256']), hashes)
            self.assertTrue(record['evidenceUrl'].startswith('https://'))



if __name__ == '__main__':
    unittest.main()
