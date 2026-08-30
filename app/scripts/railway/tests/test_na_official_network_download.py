import importlib.util
import os
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'download-north-america-official-networks.py'))
SPEC = importlib.util.spec_from_file_location('official_network_download', SCRIPT)
download = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(download)


class NewOrleansOfficialNetworkTests(unittest.TestCase):
    @staticmethod
    def feature(route_id, shape_id):
        return {
            'type': 'Feature',
            'properties': {'route_id': route_id, 'shape_id': shape_id},
            'geometry': {'type': 'LineString',
                         'coordinates': [[-90.1, 29.9], [-90.0, 29.9]]},
        }

    def test_only_reviewed_complete_city_shape_enters_each_route_graph(self):
        features = [
            self.feature('12', 'shp-12-01'),
            self.feature('12', 'shp-12-02'),
            self.feature('47', 'shp-47-01'),
            self.feature('47', 'shp-47-52'),
            self.feature('48', 'shp-48-08'),
        ]

        groups = download.norta_groups(features)

        self.assertEqual([row['properties']['shape_id']
                          for row in groups['norta-12']], ['shp-12-01'])
        self.assertEqual([row['properties']['shape_id']
                          for row in groups['norta-47']], ['shp-47-01'])
        self.assertEqual([row['properties']['shape_id']
                          for row in groups['norta-48']], ['shp-48-08'])

    def test_city_source_is_an_allowlisted_government_endpoint(self):
        source = download.SOURCES['norta']
        self.assertEqual(source['publisher'],
                         'City of New Orleans GIS Department')
        self.assertTrue(source['url'].startswith('https://services.arcgis.com/'))


if __name__ == '__main__':
    unittest.main()
