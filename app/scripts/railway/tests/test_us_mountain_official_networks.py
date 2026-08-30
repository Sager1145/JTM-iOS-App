import csv
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
import zipfile


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-us-mountain-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
SPEC = importlib.util.spec_from_file_location('mountain_official', SCRIPT)
mountain = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mountain)
import na_provenance

REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def feature(division, coordinates, object_id=1):
    return {
        'type': 'Feature',
        'properties': {
            'OBJECTID': object_id,
            'OPERATOR': 'UT Transit Auth',
            'DIVISION': division,
        },
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
    }


def write_gtfs(path):
    with zipfile.ZipFile(path, 'w') as archive:
        trips = io.StringIO()
        writer = csv.writer(trips, lineterminator='\n')
        writer.writerow(['route_id', 'service_id', 'trip_id', 'shape_id'])
        shapes = io.StringIO()
        shape_writer = csv.writer(shapes, lineterminator='\n')
        shape_writer.writerow(['shape_id', 'shape_pt_lat', 'shape_pt_lon',
                               'shape_pt_sequence'])
        for index, route_id in enumerate(mountain.ROUTES):
            shape_id = f's{route_id}'
            writer.writerow([route_id, 'weekday', f't{route_id}', shape_id])
            latitude = 40.0 + index * 0.1
            shape_writer.writerow([shape_id, latitude, -111.0, 1])
            shape_writer.writerow([shape_id, latitude, -110.99, 2])
        archive.writestr('trips.txt', trips.getvalue())
        archive.writestr('shapes.txt', shapes.getvalue())


class MountainOfficialNetworkTests(unittest.TestCase):
    def test_parallel_surveyed_rails_are_not_joined_into_a_false_loop(self):
        lower = feature('TRAX - Blue Line (701)',
                        [[-111.0, 40.0], [-110.99, 40.0]], 1)
        upper = feature('TRAX - Blue Line (701)',
                        [[-111.0, 40.0001], [-110.99, 40.0001]], 2)
        selected = mountain.primary_surveyed_rail(
            [lower, upper], [[[-111.0, 40.0], [-110.99, 40.0]]])
        self.assertEqual([row['properties']['OBJECTID'] for row in selected],
                         [1])

    def test_normalize_preserves_manifest_and_isolates_all_routes(self):
        with tempfile.TemporaryDirectory() as directory:
            raw_path = os.path.join(directory, 'railroads.geojson')
            gtfs_path = os.path.join(directory, 'uta.zip')
            output = os.path.join(directory, 'official')
            os.mkdir(output)
            rows = []
            divisions = {
                '5907': 'TRAX - Blue Line (701)',
                '8246': 'TRAX - Red Line (703)',
                '39020': 'TRAX - Green Line (704)',
                '45389': 'TRAX - Sugarhouse Street Car (720)',
                '41065': 'FRONT RUNNER',
            }
            for index, (route_id, division) in enumerate(divisions.items()):
                latitude = 40.0 + index * 0.1
                rows.append(feature(
                    division, [[-111.0, latitude], [-110.99, latitude]],
                    index + 1))
            with open(raw_path, 'w', encoding='utf-8') as destination:
                json.dump({'type': 'FeatureCollection', 'features': rows},
                          destination)
            write_gtfs(gtfs_path)
            with open(os.path.join(output, 'manifest.json'), 'w') as target:
                json.dump({'schemaVersion': 1,
                           'sources': {'mta': {'publisher': 'MTA'}},
                           'files': {'mta-subway-a': {'file': 'a.geojson'}}},
                          target)

            manifest = mountain.normalize(output, raw_path, gtfs_path)

            self.assertIn('mta-subway-a', manifest['files'])
            self.assertEqual(
                {key for key in manifest['files'] if key.startswith('uta-')},
                {'uta-701', 'uta-703', 'uta-704', 'uta-720', 'uta-750'})
            self.assertTrue(all(manifest['files'][key]['features'] == 1
                                for key in manifest['files']
                                if key.startswith('uta-')))

    def test_source_url_and_registry_are_fail_closed(self):
        self.assertEqual(mountain.SOURCE['url'], (
            'https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/'
            'services/UtahRailroads/FeatureServer/0/query?where='
            'OPERATOR%3D%27UT%20Transit%20Auth%27&outFields=*&'
            'returnGeometry=true&outSR=4326&f=geojson'))
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        uta = next(row for row in feeds
                   if row['slug'] == 'utah-transit-authority-uta')
        self.assertTrue(uta['requireVerifiedOfficialNetwork'])
        self.assertEqual(set(uta['officialNetworkByRouteId'].values()),
                         {'uta-701', 'uta-703', 'uta-704',
                          'uta-720', 'uta-750'})

    def test_provenance_is_exact_not_prefix_based(self):
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['uta-701'],
                         'utah-railroads')
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['uta-750'],
                         'utah-railroads')
        self.assertNotIn('uta-', na_provenance.KEY_SOURCE_PREFIXES)


if __name__ == '__main__':
    unittest.main()
