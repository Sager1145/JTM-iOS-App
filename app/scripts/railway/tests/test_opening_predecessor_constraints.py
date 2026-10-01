import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'history'))
import temporal_source as source


def inputs():
    sections = [
        {'type': 'Feature', 'properties': {'N02_003': 'L', 'N02_004': 'New'},
         'geometry': {'type': 'LineString', 'coordinates': [[x, 0], [x + 1, 0]]}}
        for x in (0, 1)]
    stations = [
        {'type': 'Feature', 'properties': {'line_name': 'L', 'operator': 'New',
                                          'station_name': name, 'n02_station_code': str(x)},
         'geometry': {'type': 'Point', 'coordinates': [x, 0]}}
        for x, name in enumerate(('A', 'B', 'C'))]
    proof = [{'authority': 'operator', 'reference': 'https://example.test/history',
              'date_precision': 'exact_day'}]
    base = {'date_precision': 'exact_day', 'review': {'status': 'verified'},
            'corridor_id': 'c', 'alignment_id': 'a', 'service_identity_id': 's',
            'evidence': proof, 'geometry': {'source': 'N02', 'licence_status': 'redistributable'}}
    rename = dict(copy.deepcopy(base), id='rename', kind='operator_rename', date='2020-01-01',
                  before={'line': 'L', 'operator': 'Old'}, after={'line': 'L', 'operator': 'New'})
    opening = dict(copy.deepcopy(base), id='extension', kind='opening', line='L', operator='Old',
                   after={'line': 'L', 'operator': 'New'},
                   service_periods=[['2010-01-01', None]], predecessor_event_ids=['rename'])
    opening['geometry']['selector'] = {'bbox': [1, -1, 2, 1], 'stations': ['C']}
    compiled = source.compile_event(rename, sections, stations)
    return rename, opening, sections, stations, compiled


class OpeningPredecessorConstraintsTests(unittest.TestCase):
    def test_partial_opening_constrains_old_operator_without_backdating_shared_station(self):
        rename, opening, sections, stations, compiled = inputs()
        ids = [f['properties']['history_id'] for f in compiled['sections'] + compiled['stations']]
        old_sections, old_stations = source.constrain_opening_predecessors(
            [rename, opening], compiled['sections'], compiled['stations'], sections, stations)
        self.assertEqual(old_sections[0]['properties']['service_validity'], [None, '2020-01-01'])
        self.assertEqual(old_sections[1]['properties']['service_validity'], ['2010-01-01', '2020-01-01'])
        self.assertEqual(old_stations[1]['properties']['service_validity'], [None, '2020-01-01'])
        self.assertEqual(old_stations[2]['properties']['service_validity'], ['2010-01-01', '2020-01-01'])
        self.assertEqual(ids, [f['properties']['history_id'] for f in old_sections + old_stations])
        self.assertNotIn('valid_from', compiled['sections'][1]['properties'])

    def test_opening_after_identity_end_removes_never_operated_predecessor_features(self):
        rename, opening, sections, stations, compiled = inputs()
        opening['service_periods'] = [['2021-01-01', None]]
        old_sections, old_stations = source.constrain_opening_predecessors(
            [rename, opening], compiled['sections'], compiled['stations'], sections, stations)
        self.assertEqual(len(old_sections), 1)
        self.assertEqual([f['properties']['station_name'] for f in old_stations], ['A', 'B'])

    def test_missing_or_inexact_predecessor_is_rejected(self):
        rename, opening, sections, stations, compiled = inputs()
        with self.assertRaisesRegex(ValueError, 'unknown identity predecessor'):
            source.constrain_opening_predecessors(
                [opening], compiled['sections'], compiled['stations'], sections, stations)
        compiled['sections'][1]['geometry']['coordinates'][1][0] += 0.00001
        with self.assertRaisesRegex(ValueError, 'geometry is missing or ambiguous'):
            source.constrain_opening_predecessors(
                [rename, opening], compiled['sections'], compiled['stations'], sections, stations)

    def test_undeclared_opening_does_not_constrain_other_identities(self):
        rename, opening, sections, stations, compiled = inputs()
        opening.pop('predecessor_event_ids')
        actual = source.constrain_opening_predecessors(
            [rename, opening], compiled['sections'], compiled['stations'], sections, stations)
        self.assertEqual(actual, (compiled['sections'], compiled['stations']))


if __name__ == '__main__':
    unittest.main()
