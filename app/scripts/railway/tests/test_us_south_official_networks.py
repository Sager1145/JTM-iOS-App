import importlib.util
import json
import os
import sys
import tempfile
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-us-south-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
SPEC = importlib.util.spec_from_file_location('south_official', SCRIPT)
south = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(south)
import na_provenance

REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def feature(color, status='Operational', kind='RAIL'):
    return {'type': 'Feature',
            'properties': {'LineColor': color, 'Status': status,
                           'TYPE': kind},
            'geometry': {'type': 'LineString', 'coordinates': [
                [-95.4, 29.7], [-95.39, 29.71],
            ]}}


class SouthOfficialNetworkTests(unittest.TestCase):
    def test_houston_routes_are_color_isolated_and_non_operational_is_ignored(self):
        groups = south.route_groups([
            feature('Red'), feature('Green'), feature('Purple'),
            feature('Red', status='Planned'), feature('Red', kind='BUS'),
        ])
        self.assertEqual(set(groups),
                         {'houston-metro-700', 'houston-metro-800',
                          'houston-metro-900'})
        self.assertTrue(all(len(rows) == 1 for rows in groups.values()))

    def test_manifest_merge_preserves_other_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, 'manifest.json'), 'w') as output:
                json.dump({'schemaVersion': 1,
                           'sources': {'mta': {'publisher': 'MTA'}},
                           'files': {'mta-subway-a': {'file': 'a.geojson'}}},
                          output)
            manifest = south.load_manifest(directory)
        self.assertIn('mta', manifest['sources'])
        self.assertIn('mta-subway-a', manifest['files'])

    def test_houston_source_and_feed_are_exact_and_fail_closed(self):
        self.assertEqual(south.SOURCE['url'], (
            'https://services5.arcgis.com/p8QKnlioaN3sruqA/arcgis/rest/'
            'services/METRO_transit_layers/FeatureServer/4/query?'
            'where=1%3D1&outFields=*&returnGeometry=true&'
            'outSR=4326&f=geojson'))
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        feed = next(row for row in feeds if row['slug'] == 'houston-metro')
        self.assertEqual(feed['url'],
                         'https://metro.resourcespace.com/pages/download.php?'
                         'ref=4835&ext=zip')
        self.assertTrue(feed['requireVerifiedOfficialNetwork'])
        self.assertEqual(feed['officialNetworkByRouteId'], {
            '700': 'houston-metro-700',
            '800': 'houston-metro-800',
            '900': 'houston-metro-900',
        })

    def test_houston_provenance_is_exact(self):
        self.assertEqual(
            na_provenance.KEY_SOURCE_EXACT['houston-metro-700'],
            'houston-metro')
        self.assertNotIn('houston-metro-',
                         na_provenance.KEY_SOURCE_PREFIXES)


if __name__ == '__main__':
    unittest.main()
