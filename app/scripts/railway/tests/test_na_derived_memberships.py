import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('refresh_na_memberships', Path(__file__).parents[1] / 'refresh-na-derived-memberships.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MembershipTests(unittest.TestCase):
    def fixtures(self):
        line = {'id': 'rail', 'operator': 'Rail', 'name': 'Route',
                'stations': [['us-a', 'A', 0, 0], ['ca-b', 'B', 1, 1], ['ca-c', 'C', 2, 2]],
                'segments': [[1, 0, [[0, 0], [.5, .7], [1, 1]]], [1, 1, [[1.5, 1.7], [2, 2]]]]}
        features = [{'type': 'Feature', 'properties': {'operator': 'Rail', 'line_name': 'Route',
                    'n02_group_code': row[0], 'n02_station_code': row[0] + '-platform',
                    'display_point': row[2:4]}, 'geometry': {'type': 'LineString', 'coordinates': [row[2:4], row[2:4]]}}
                    for row in line['stations']]
        sections = {'features': [{'properties': {'operator': 'Rail', 'line_name': 'Route'}, 'geometry': {}}]}
        return {'lines': [line]}, {'features': features}, sections

    def test_removes_orphan_membership_and_preserves_canonical_foreign_id(self):
        package, stations, sections = self.fixtures()
        stations['features'].append(stations['features'][0])
        actual, edges = module.reconcile(package, stations, sections)
        self.assertEqual(len(actual['features']), 3)
        self.assertEqual(actual['features'][1]['properties']['n02_station_code'], 'ca-b-platform')
        self.assertEqual(edges['features'][1]['geometry']['coordinates'][0], [1, 1])
        self.assertEqual(actual['features'][2]['geometry']['coordinates'][0], [2, 2])
        self.assertNotEqual(actual['features'][2]['geometry']['coordinates'][1], [1.5, 1.7])
        self.assertLess(abs(actual['features'][2]['geometry']['coordinates'][1][0] - 2), .00002)

    def test_missing_identity_fails_without_name_inference(self):
        package, stations, sections = self.fixtures()
        stations['features'].pop()
        with self.assertRaisesRegex(ValueError, 'missing membership'):
            module.reconcile(package, stations, sections)


if __name__ == '__main__':
    unittest.main()
