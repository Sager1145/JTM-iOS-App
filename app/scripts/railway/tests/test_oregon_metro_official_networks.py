import importlib.util
import json
import os
import sys
import tempfile
import unittest


HERE = os.path.dirname(__file__)
SCRIPT = os.path.abspath(os.path.join(
    HERE, '..', 'normalize-oregon-metro-official-networks.py'))
REGISTRY = os.path.abspath(os.path.join(HERE, '..', 'na-feeds.json'))
REBUILD = os.path.abspath(os.path.join(
    HERE, '..', 'rebuild-na-official-networks.sh'))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
import na_provenance

SPEC = importlib.util.spec_from_file_location('oregon_metro', SCRIPT)
networks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(networks)


def feature(fid, line, status='Existing', route_type='Street Car'):
    return {
        'type': 'Feature',
        'properties': {
            'FID': fid, 'LINE': line, 'STATUS': status, 'TYPE': route_type,
        },
        'geometry': {
            'type': 'LineString',
            'coordinates': [[-122.68, 45.52], [-122.67, 45.53]],
        },
    }


class OregonMetroOfficialNetworkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            cls.feed = next(
                row for row in json.load(source)['feeds']
                if row['slug'] == 'trimet-portland-streetcar')

    def reviewed_features(self):
        rows = []
        for index, line in enumerate(sorted(networks.A_LOOP_LINES)):
            route_type = ('MAX/Street Car' if line.startswith('Orange MAX')
                          else 'Street Car')
            rows.append(feature(index, line, route_type=route_type))
        return rows

    def test_selector_is_existing_a_loop_only(self):
        rows = self.reviewed_features()
        rows.extend([
            feature(20, 'Portland Street Car B Loop'),
            feature(21, 'Portland Street Car A Loop', status='Planned'),
        ])
        selected = networks.a_loop_group(rows)
        self.assertEqual(len(selected), len(networks.A_LOOP_LINES))
        self.assertEqual(
            {row['properties']['LINE'] for row in selected},
            networks.A_LOOP_LINES)

    def test_selector_fails_closed_when_a_reviewed_component_disappears(self):
        with self.assertRaises(SystemExit):
            networks.a_loop_group(self.reviewed_features()[:-1])

    def test_provenance_registry_and_rebuild_are_exact(self):
        source = na_provenance.SOURCES[networks.SOURCE_ID]
        self.assertEqual(source, networks.SOURCE)
        self.assertEqual(
            na_provenance.KEY_SOURCE_EXACT[networks.ROUTE_KEY],
            networks.SOURCE_ID)
        self.assertEqual(self.feed['officialNetworkByRouteId'], {
            '194': networks.ROUTE_KEY,
        })
        self.assertNotIn('194', self.feed['geometryReviewByRouteId'])
        self.assertEqual(len(self.feed['geometryReviewByRouteId']), 9)
        self.assertTrue(self.feed['requireVerifiedOfficialNetwork'])
        self.assertTrue(self.feed['forbidOfficialNetworkFallback'])
        with open(REBUILD, encoding='utf-8') as source_file:
            rebuild = source_file.read()
        self.assertIn('normalize-oregon-metro-official-networks.py', rebuild)
        self.assertIn('raw oregonmetro-rlis-rail-transit', rebuild)

    def test_normalized_output_passes_provenance_verifier(self):
        payload = {
            'type': 'FeatureCollection',
            'features': self.reviewed_features(),
        }
        with tempfile.TemporaryDirectory() as directory:
            raw_path = os.path.join(directory, 'rlis.geojson')
            output_dir = os.path.join(directory, 'networks')
            with open(raw_path, 'w', encoding='utf-8') as output:
                json.dump(payload, output)
            _, selected = networks.normalize(output_dir, raw_path)
            verified, diagnostics = na_provenance.verify_route_networks(
                output_dir, [networks.ROUTE_KEY])
        self.assertEqual(len(selected), len(networks.A_LOOP_LINES))
        self.assertEqual(set(verified), {networks.ROUTE_KEY})
        self.assertEqual(diagnostics, [])


if __name__ == '__main__':
    unittest.main()
