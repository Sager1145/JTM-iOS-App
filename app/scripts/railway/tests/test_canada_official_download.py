import importlib.util
import json
import os
import tempfile
import unittest
from unittest import mock


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-canada-official-networks.py'))
SPEC = importlib.util.spec_from_file_location('canada_official', SCRIPT)
canada = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(canada)


def feature(route_id):
    return {
        'type': 'Feature',
        'properties': {'route_id': route_id},
        'geometry': {'type': 'LineString',
                     'coordinates': [[-79.4, 43.6], [-79.3, 43.7]]},
    }


class CanadaOfficialNetworkTests(unittest.TestCase):
    def test_ttc_subway_outputs_are_route_isolated_and_hashed(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = os.path.join(directory, 'official.zip')
            with open(archive, 'wb') as output:
                output.write(b'authority archive')
            records = [(route, feature(route)) for route in ('1', '2', '3', '4')]
            with mock.patch.object(canada, 'shapefile_features',
                                   return_value=records):
                manifest = canada.normalize_ttc_subway(
                    archive, directory, generated_at='2026-08-31T00:00:00Z')

            self.assertEqual(set(manifest['files']), {
                'ttc-subway-1', 'ttc-subway-2',
                'ttc-subway-3', 'ttc-subway-4'})
            self.assertEqual(
                manifest['sources']['ttc']['rawSha256'],
                canada.sha256(b'authority archive'))
            for key in manifest['files']:
                with open(os.path.join(directory, f'{key}.geojson')) as source:
                    payload = json.load(source)
                self.assertEqual(len(payload['features']), 1)
                self.assertEqual(
                    payload['features'][0]['properties']['route_id'],
                    key.rsplit('-', 1)[-1])


if __name__ == '__main__':
    unittest.main()
