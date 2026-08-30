import importlib.util
import os
import sys
import tempfile
import unittest
import json


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'download-north-america-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
SPEC = importlib.util.spec_from_file_location('na_official_download', SCRIPT)
download = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(download)


def feature(**properties):
    return {
        'type': 'Feature',
        'properties': properties,
        'geometry': {'type': 'LineString',
                     'coordinates': [[-73.0, 40.0], [-73.1, 40.1]]},
    }


class OfficialNetworkNormalizationTests(unittest.TestCase):
    def test_shared_manifest_preserves_another_authoritys_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, 'manifest.json')
            with open(path, 'w', encoding='utf-8') as target:
                json.dump({
                    'schemaVersion': 1,
                    'sources': {'ttc': {'publisher': 'City of Toronto'}},
                    'files': {'ttc-subway-1': {'file': 'ttc-subway-1.geojson'}},
                }, target)
            manifest = download.load_manifest(directory)
            self.assertIn('ttc', manifest['sources'])
            self.assertIn('ttc-subway-1', manifest['files'])

    def test_mta_combines_peak_and_base_service_without_merging_routes(self):
        groups = download.mta_groups([
            feature(service='5'), feature(service='5 Peak'),
            feature(service='4'),
        ])
        self.assertEqual(len(groups['mta-subway-5']), 2)
        self.assertEqual(len(groups['mta-subway-4']), 1)

    def test_mta_refuses_unknown_service_instead_of_guessing_mapping(self):
        with self.assertRaisesRegex(SystemExit, 'unmapped services'):
            download.mta_groups([feature(service='mystery')])

    def test_cta_shared_track_is_present_in_each_named_route(self):
        groups = download.cta_groups([
            feature(lines='Brown, Green, Orange, Pink, Purple (Exp)'),
            feature(lines='Blue Line (O\'Hare)'),
        ])
        for route in ('brown', 'green', 'orange', 'pink', 'purple'):
            self.assertEqual(len(groups[f'cta-{route}']), 1)
        self.assertEqual(len(groups['cta-blue']), 1)
        self.assertEqual(len(groups['cta-red']), 0)


if __name__ == '__main__':
    unittest.main()
