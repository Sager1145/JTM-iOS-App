import csv
import importlib.util
import io
import json
import os
import tempfile
import unittest
import zipfile


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-ottawa-official-networks.py'))
SPEC = importlib.util.spec_from_file_location('ottawa_official', SCRIPT)
ottawa = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ottawa)

REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def csv_bytes(fields, rows):
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue()


class OttawaCanadaStrictOfficialTests(unittest.TestCase):
    def synthetic_gtfs(self, path):
        stops = {
            'A': [-75.72, 45.40],
            'B': [-75.70, 45.38],
            'C': [-75.68, 45.36],
            'D': [-75.66, 45.37],
        }
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('routes.txt', csv_bytes(
                ['route_id', 'route_short_name'], [
                    {'route_id': 'route-2', 'route_short_name': '2'},
                    {'route_id': 'route-4', 'route_short_name': '4'},
                ]))
            archive.writestr('trips.txt', csv_bytes(
                ['route_id', 'trip_id'], [
                    {'route_id': 'route-2', 'trip_id': 'trip-2'},
                    {'route_id': 'route-4', 'trip_id': 'trip-4'},
                ]))
            archive.writestr('stops.txt', csv_bytes(
                ['stop_id', 'stop_lon', 'stop_lat'], [
                    {'stop_id': stop, 'stop_lon': point[0],
                     'stop_lat': point[1]}
                    for stop, point in stops.items()
                ]))
            archive.writestr('stop_times.txt', csv_bytes(
                ['trip_id', 'stop_id', 'stop_sequence'], [
                    {'trip_id': 'trip-2', 'stop_id': stop,
                     'stop_sequence': index}
                    for index, stop in enumerate(('A', 'B', 'C'), 1)
                ] + [
                    {'trip_id': 'trip-4', 'stop_id': stop,
                     'stop_sequence': index}
                    for index, stop in enumerate(('B', 'D'), 1)
                ]))

    def test_trillium_main_line_and_airport_branch_are_route_isolated(self):
        alignment = {
            'type': 'FeatureCollection',
            'features': [
                {'type': 'Feature',
                 'properties': {'REFNAME': 'Trillium',
                                'LAYER': 'T-ALIGN-NB ALIGN'},
                 'geometry': {'type': 'LineString',
                              'coordinates': [[-75.72, 45.40],
                                              [-75.70, 45.38],
                                              [-75.68, 45.36]]}},
                {'type': 'Feature',
                 'properties': {'REFNAME': 'Trillium',
                                'LAYER': 'T-ALIGN-MISC ALIGN'},
                 'geometry': {'type': 'LineString',
                              'coordinates': [[-75.70, 45.38],
                                              [-75.66, 45.37]]}},
                {'type': 'Feature',
                 'properties': {'REFNAME': 'Confederation Extension',
                                'LAYER': 'T-ALIGN-NB ALIGN'},
                 'geometry': {'type': 'LineString',
                              'coordinates': [[-75.7, 45.4],
                                              [-75.6, 45.4]]}},
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            alignment_path = os.path.join(directory, 'alignment.geojson')
            gtfs_path = os.path.join(directory, 'gtfs.zip')
            with open(alignment_path, 'w', encoding='utf-8') as output:
                json.dump(alignment, output)
            self.synthetic_gtfs(gtfs_path)
            manifest = ottawa.normalize(
                directory, alignment_path, gtfs_path,
                generated_at='2026-08-31T00:00:00Z')

            self.assertEqual(
                {key for key in manifest['files']
                 if key.startswith('ottawa-trillium-')},
                {'ottawa-trillium-2', 'ottawa-trillium-4'})
            with open(os.path.join(directory, 'ottawa-trillium-2.geojson'),
                      encoding='utf-8') as source:
                line2 = json.load(source)
            with open(os.path.join(directory, 'ottawa-trillium-4.geojson'),
                      encoding='utf-8') as source:
                line4 = json.load(source)
            line2_points = {
                tuple(point) for feature in line2['features']
                for point in feature['geometry']['coordinates']}
            line4_points = {
                tuple(point) for feature in line4['features']
                for point in feature['geometry']['coordinates']}
            self.assertNotIn((-75.66, 45.37), line2_points)
            self.assertNotIn((-75.72, 45.40), line4_points)
            self.assertIn((-75.66, 45.37), line4_points)

    def test_registry_fail_closes_mapped_ottawa_ttc_and_go_routes(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = {row['slug']: row for row in json.load(source)['feeds']}
        ottawa_feed = feeds['ottawa-carleton-regional-tra']
        self.assertTrue(ottawa_feed['forbidOfficialNetworkFallback'])
        self.assertEqual(ottawa_feed['officialNetworkByRouteId'], {
            '2-354': 'ottawa-trillium-2',
            '2-354-1': 'ottawa-trillium-2',
            '4-354': 'ottawa-trillium-4',
            '4-354-1': 'ottawa-trillium-4',
        })
        self.assertTrue(feeds['ttc']['forbidOfficialNetworkFallback'])
        self.assertTrue(feeds['go-transit']['forbidOfficialNetworkFallback'])

    def test_unverified_via_routes_are_explicitly_blocked(self):
        with open(REGISTRY, encoding='utf-8') as source:
            via = next(row for row in json.load(source)['feeds']
                       if row['slug'] == 'via')
        expected = {
            '21-458', '226-620', '226-119', '617-628', '628-576',
            '621-116', '8-119', '388-435', '149-435',
        }
        self.assertTrue(expected.issubset(via['officialNetworkDefectByRouteId']))
        for route_id in expected:
            self.assertNotIn(route_id, via['officialNetworkByRouteId'])


if __name__ == '__main__':
    unittest.main()
