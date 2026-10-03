import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('border_merge', Path(__file__).parents[1] / 'merge-na-feed-build.py')
merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge)


class ForeignEndpointMergeTests(unittest.TestCase):
    def test_replacing_existing_border_keeps_foreign_removal_scoped_to_feed(self):
        line = {'stations': [['us-a'], ['ca-b']],
                'borderConnector': {'stationCountries': ['us', 'ca'], 'evidence': 'survey'}}
        prefixes = tuple(merge.selected_station_prefixes([line], 'us', 'amtrak'))
        predicate = merge.station_removal_predicate({('Rail', 'ca-b')}, {'Rail'}, True, prefixes)
        def feature(code):
            return {'properties': {'operator': 'Rail', 'n02_group_code': 'ca-b', 'n02_station_code': code}}
        self.assertTrue(predicate(feature('CA-AMTRAK-RAIL-B')))
        self.assertFalse(predicate(feature('CA-OTHER-RAIL-B')))
        self.assertEqual(merge.selected_station_prefixes([], 'us', 'amtrak'), {'US-AMTRAK-'})

    def test_partial_merge_keeps_exact_foreign_identity_but_not_other_feed(self):
        line = {'id': 'amtrak-border1', 'name': 'Service', 'operator': 'Rail', 'sourceFeed': 'amtrak',
                'stations': [['us-a', 'A', 0, 0], ['ca-b', 'B', 1, 1]],
                'segments': [[1, 0, [[0, 0], [1, 1]]]],
                'borderConnector': {'stationCountries': ['us', 'ca'], 'evidence': 'survey'}}
        def station(code, group, point):
            return {'properties': {'operator': 'Rail', 'line_name': 'Service',
                                  'n02_station_code': code, 'n02_group_code': group, 'display_point': point}}
        foreign = station('CA-AMTRAK-RAIL-B-CA-B', 'ca-b', [1, 1])
        candidate = {'package': {'country': 'US', 'lines': [line]},
                     'stations': {'features': [station('US-AMTRAK-RAIL-A-US-A', 'us-a', [0, 0]), foreign,
                                              station('CA-OTHER-RAIL-B-CA-B', 'ca-b', [1, 1])]},
                     'sections': {'features': [{'properties': {'operator': 'Rail', 'line_name': 'Service'},
                                               'geometry': {'type': 'LineString', 'coordinates': [[0, 0], [1, 1]]}}]}}
        scoped = merge.scope_candidate_to_lines(candidate, 'amtrak', ['amtrak-border1'], 'us', True)
        self.assertEqual(len(scoped['stations']['features']), 2)
        self.assertEqual(scoped['stations']['features'][1], foreign)


if __name__ == '__main__':
    unittest.main()
