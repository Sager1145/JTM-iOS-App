import importlib.util
import json
import os
import sys
import tempfile
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-us-west-metro-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
SPEC = importlib.util.spec_from_file_location('west_metro_official', SCRIPT)
metro = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metro)
import na_provenance
REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def feature(properties, offset=0.0):
    return {'type': 'Feature', 'properties': properties,
            'geometry': {'type': 'LineString', 'coordinates': [
                [-118.3 + offset, 34.0], [-118.29 + offset, 34.01],
            ]}}


class WesternMetroOfficialTests(unittest.TestCase):
    def feed(self, slug):
        with open(REGISTRY, encoding='utf-8') as source:
            registry = json.load(source)
        return next(row for row in registry['feeds'] if row['slug'] == slug)

    def test_la_shared_corridors_are_copied_only_to_serving_routes(self):
        rows = []
        for label in ('Metro A Line', 'Metro B Line', 'Metro C Line',
                      'Metro E Line', 'Metro D Line', 'Metro K Line',
                      'Metro A & E Line', 'Metro B & D Line'):
            rows.append(feature({'LABEL': label, 'STATUS': 'Existing',
                                 'TYPE': 'Rail'}))
        rows.extend([
            feature({'LABEL': 'Metro D Line', 'STATUS': 'Construction',
                     'TYPE': 'Rail'}),
            feature({'LABEL': 'Metro G Line', 'STATUS': 'Existing',
                     'TYPE': 'Bus'}),
        ])
        groups = metro.la_groups(rows)
        self.assertEqual(len(groups['la-metro-801']), 2)
        self.assertEqual(len(groups['la-metro-804']), 2)
        self.assertEqual(len(groups['la-metro-802']), 2)
        self.assertEqual(len(groups['la-metro-805']), 2)
        self.assertEqual(len(groups['la-metro-803']), 1)
        self.assertEqual(len(groups['la-metro-807']), 1)

    def test_sfmta_directions_are_separate_and_night_patterns_are_ignored(self):
        rows = []
        for public_name in metro.SFMTA_ROUTES:
            for direction in ('I', 'O'):
                rows.append(feature({'route_name': public_name,
                                     'direction': direction,
                                     'pattern_type': 'F'}))
        rows.append(feature({'route_name': 'N', 'direction': 'I',
                             'pattern_type': 'N'}))
        groups = metro.sfmta_groups(rows)
        self.assertTrue(all(len(value) == 1 for value in groups.values()))
        self.assertEqual(len(groups), 20)

    def test_manifest_merge_preserves_other_authorities(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, 'manifest.json'), 'w') as output:
                json.dump({'schemaVersion': 1,
                           'sources': {'mta': {'publisher': 'MTA'}},
                           'files': {'mta-subway-a': {'file': 'a.geojson'}}},
                          output)
            manifest = metro.load_manifest(directory)
        self.assertIn('mta', manifest['sources'])
        self.assertIn('mta-subway-a', manifest['files'])

    def test_official_source_urls_are_exact(self):
        self.assertEqual(metro.SOURCES['la-metro']['url'], (
            'https://services.arcgis.com/RmCCgQtiZLDCtblq/ArcGIS/rest/'
            'services/MTA_Metro_Lines/FeatureServer/0/query?where=1%3D1&'
            'outFields=*&returnGeometry=true&outSR=4326&f=geojson'))
        self.assertEqual(metro.SOURCES['sfmta']['url'], (
            'https://data.sfgov.org/api/v3/views/9exe-acju/'
            'query.geojson?accessType=DOWNLOAD'))

    def test_la_metro_cannot_fall_back_from_official_survey(self):
        feed = self.feed('los-angeles-county-metropoli')
        self.assertTrue(feed['requireVerifiedOfficialNetwork'])
        self.assertEqual(set(feed['officialNetworkByRouteId']),
                         {'801', '802', '803', '804', '805', '807'})

    def test_sfmta_uses_one_audited_direction_and_blocks_uncovered_routes(self):
        feed = self.feed('san-francisco-municipal-tran')
        self.assertTrue(feed['requireVerifiedOfficialNetwork'])
        self.assertEqual(set(feed['excludeRoutes']), {'K', 'L', 'M'})
        self.assertEqual(feed['officialNetworkByRouteId']['CA'], 'sfmta-ca-i')
        self.assertTrue(all(key.endswith('-i')
                            for key in feed['officialNetworkByRouteId'].values()))

    def test_bart_is_fail_closed_while_operator_kmz_is_unavailable(self):
        feed = self.feed('bart')
        self.assertEqual(set(feed['excludeRoutes']),
                         {'1', '2', '3', '4', '5', '6', '7', '8',
                          '11', '12', '19', '20'})

    def test_route_keys_have_exact_provenance_mappings(self):
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['la-metro-801'],
                         'la-metro')
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['sfmta-ca-i'],
                         'sfmta')
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['sfmta-t-o'],
                         'sfmta')
        self.assertNotIn('sfmta-', na_provenance.KEY_SOURCE_PREFIXES)


if __name__ == '__main__':
    unittest.main()
