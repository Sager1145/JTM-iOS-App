import importlib.util
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1] / 'history'
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('station_history', HERE / 'build-jp-history-stations.py')
station_history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(station_history)


def station(name, group='G', history_id=None, end=None):
    properties = {'station_name': name, 'line_name': 'L', 'operator': 'O',
                  'n02_group_code': group}
    if history_id:
        properties.update(history_id=history_id, valid_to=end)
    return {'type': 'Feature', 'properties': properties,
            'geometry': {'type': 'Point', 'coordinates': [139, 35]}}


class StationHistoryTests(unittest.TestCase):
    def test_reviewed_rename_keeps_one_entity_and_two_dated_memberships(self):
        event = {'id': 'jp.rename', 'station_entity_id': 'jp.station.reviewed',
                 'review': {'status': 'verified'}}
        overlay = {'revision': 'test', 'sections': [],
            'stations': [station('Old', history_id='jp.rename.period0.station', end='2020-01-01')],
            'retirements': [{'history_id': 'jp.rename.current.station', 'valid_from': '2020-01-01',
                'match': {'line_name': 'L', 'operator': 'O', 'bbox': [138, 34, 140, 36],
                          'targets': ['stations']}}]}
        result = station_history.build({'events': [], 'temporal_events': [event]}, overlay, [station('New')])
        self.assertEqual(result['summary']['station_entities'], 1)
        names = {m['station_name']: m['observations'][0]['service_validity'] for m in result['memberships']}
        self.assertEqual(names, {'Old': [None, '2020-01-01'], 'New': ['2020-01-01', None]})

    def test_same_name_different_observed_groups_are_not_fuzzily_merged(self):
        overlay = {'revision': 'test', 'sections': [], 'stations': [], 'retirements': []}
        result = station_history.build({'events': []}, overlay,
                                       [station('Shared', 'A'), station('Shared', 'B')])
        self.assertEqual(result['summary']['station_entities'], 2)
        self.assertFalse(result['policy']['fuzzy_name_identity_merge'])


if __name__ == '__main__':
    unittest.main()
