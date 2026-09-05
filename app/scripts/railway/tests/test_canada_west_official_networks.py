import importlib.util
import json
import os
import sys
import unittest

SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                      'normalize-canada-west-official-networks.py'))
LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib'))
if LIB not in sys.path:
    sys.path.insert(0, LIB)
import na_official
SPEC = importlib.util.spec_from_file_location('ca_west', SCRIPT)
west = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(west)


def feature(**props):
    return {'type': 'Feature', 'properties': props,
            'geometry': {'type': 'LineString',
                         'coordinates': [[-114, 51], [-113.9, 51.1]]}}


class CanadaWestTests(unittest.TestCase):
    def test_calgary_network_is_owned_by_calgary_not_vre(self):
        registry_path = os.path.abspath(os.path.join(
            os.path.dirname(__file__), '..', 'na-feeds.json'))
        with open(registry_path, encoding='utf-8') as source:
            feeds = {row['slug']: row for row in json.load(source)['feeds']}
        calgary = feeds['calgary-transit']
        self.assertTrue(calgary['requireVerifiedOfficialNetwork'])
        self.assertEqual(
            calgary['officialNetworkByRouteId'], {
                '201-20785': 'calgary-red',
                '201-20786': 'calgary-red',
                '202-20785': 'calgary-blue',
                '202-20786': 'calgary-blue',
            })
        self.assertEqual(calgary['officialColorByRouteId'], {
            '201-20785': 'EC3001', '201-20786': 'EC3001',
            '202-20785': '5B9EC9', '202-20786': '5B9EC9',
        })
        self.assertEqual(set(calgary['officialNetworkDefectByRouteId']),
                         {'201-20785', '201-20786',
                          '202-20785', '202-20786'})
        self.assertIn('39 Avenue',
                      calgary['officialNetworkDefectByRouteId']['201-20785'])
        self.assertIn('3.9x', calgary['officialNetworkDefectByRouteId']['202-20785'])
        self.assertIn('branch b1', calgary['officialNetworkDefectByRouteId']['202-20785'])
        self.assertNotIn(
            'calgary-red', feeds['vre'].get('officialNetworkByRouteId', {}).values())
        self.assertNotIn(
            'calgary-blue', feeds['vre'].get('officialNetworkByRouteId', {}).values())

    def test_calgary_shared_downtown_track_enters_both_routes(self):
        shared = feature(full_name='FREE FARE ZONE')
        groups = west.calgary_groups([
            feature(full_name='RED LINE', direction_code='Southbound'),
            feature(full_name='BLUE LINE', direction_code='Westbound'),
            shared, feature(full_name='BLUE LINE - RED LINE')])
        self.assertIn(shared, groups['calgary-red'])
        self.assertIn(shared, groups['calgary-blue'])

    def test_calgary_sunalta_crossover_does_not_enter_passenger_route_graph(self):
        ordinary_crossover = feature(
            full_name='BLUE LINE', direction_code='Unspecified Bidirectional')
        sunalta_crossover = feature(
            full_name='BLUE LINE', direction_code='Unspecified Bidirectional')
        sunalta_crossover['geometry'] = {
            'type': 'MultiLineString',
            'coordinates': [[
                [-114.0979228, 51.0447458],
                [-114.0981677, 51.0447722],
            ]],
        }
        shared = feature(full_name='BLUE LINE - RED LINE',
                         direction_code='Unspecified Bidirectional')

        groups = west.calgary_groups(
            [ordinary_crossover, sunalta_crossover, shared])

        self.assertIn(ordinary_crossover, groups['calgary-blue'])
        self.assertNotIn(sunalta_crossover, groups['calgary-blue'])
        self.assertIn(shared, groups['calgary-red'])
        self.assertIn(shared, groups['calgary-blue'])

    def test_edmonton_uses_exact_official_route_code(self):
        groups = west.edmonton_groups([
            feature(lrt_route_='021R'), feature(lrt_route_='022R'),
            feature(lrt_route_='023R')])
        self.assertEqual(groups['edmonton-valley'][0]['properties']['lrt_route_'],
                         '023R')
        self.assertEqual(
            {row['properties']['lrt_route_'] for row in groups['edmonton-metro']},
            {'021R', '022R'})

    def test_translink_excludes_bus_and_ferry_features(self):
        groups = west.translink_groups([
            feature(line_no='CL'), feature(line_no='EL'), feature(line_no='ML'),
            feature(line_no='WCE'), feature(line_no='099'), feature(line_no='SB')])
        self.assertTrue(all(len(rows) == 1 for rows in groups.values()))

    def test_translink_densification_keeps_endpoints_and_stays_on_source_segment(self):
        line = [[-123.2, 49.1], [-123.1, 49.3]]

        dense = west.densify_line(line, max_segment_m=1_000)

        self.assertEqual(dense[0], line[0])
        self.assertEqual(dense[-1], line[-1])
        self.assertGreater(len(dense), 2)
        dx = line[-1][0] - line[0][0]
        dy = line[-1][1] - line[0][1]
        for point in dense:
            cross = ((point[0] - line[0][0]) * dy
                     - (point[1] - line[0][1]) * dx)
            self.assertAlmostEqual(cross, 0.0, places=12)

    def test_sparse_official_trunk_and_airport_branch_route_after_densification(self):
        sparse = feature(line_no='CL')
        sparse['geometry'] = {
            'type': 'MultiLineString',
            'coordinates': [
                [[-123.20, 49.20], [-123.10, 49.20]],
                [[-123.10, 49.20], [-123.10, 49.25]],
            ],
        }
        dense = west.densify_feature(sparse)
        network = na_official.PassengerNetwork([dense])

        trunk, trunk_report = network.route_stations([
            [-123.20, 49.20], [-123.15, 49.20], [-123.10, 49.20]],
            max_snap_m=150)
        airport, airport_report = network.route_stations([
            [-123.15, 49.20], [-123.10, 49.20], [-123.10, 49.225],
            [-123.10, 49.25]], max_snap_m=150)

        self.assertEqual(len(trunk), 2, trunk_report)
        self.assertEqual(len(airport), 3, airport_report)
        self.assertTrue(all(value is not None
                            for value in trunk_report['snapMeters']))
        self.assertTrue(all(value is not None
                            for value in airport_report['snapMeters']))


if __name__ == '__main__':
    unittest.main()
