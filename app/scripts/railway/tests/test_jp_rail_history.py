"""Phase 5 event kinds and service/infrastructure intervals.

Geometry here is synthetic. Shipped features still come only from an N02
release plus an explicit date on jp-rail-history-events.json.
"""
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.abspath(os.path.join(HERE, '..', 'build-jp-rail-history.py'))
SPEC = importlib.util.spec_from_file_location('build_jp_rail_history', PATH)
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def section(line, operator, coordinates):
    return {
        'type': 'Feature',
        'properties': {'N02_003': line, 'N02_004': operator},
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
    }


def station(line, operator, name, coordinates):
    return {
        'type': 'Feature',
        'properties': {'line_name': line, 'operator': operator, 'station_name': name},
        'geometry': {'type': 'Point', 'coordinates': coordinates},
    }


class RailHistoryEventTests(unittest.TestCase):

    def test_missing_kind_is_closure_and_relocation_stays(self):
        self.assertEqual(mod.event_kind({'id': 'a', 'valid_to': '2016-12-05'}), 'closure')
        self.assertEqual(mod.event_kind({'id': 'b', 'kind': 'relocation'}), 'relocation')
        with self.assertRaises(SystemExit):
            mod.event_kind({'id': 'c', 'kind': 'brt'})

    def test_legacy_pair_is_the_service_interval_and_is_not_rewritten(self):
        props = {'history_id': 'x', 'valid_to': '2016-12-05'}
        event = {'id': 'x', 'line': 'L', 'operator': 'O', 'valid_to': '2016-12-05', 'source': 's'}
        mod.write_stated_domains(props, event)
        self.assertEqual(props, {'history_id': 'x', 'valid_to': '2016-12-05'})
        self.assertEqual(mod.split_domains(event), (None, '2016-12-05', None))

    def test_lone_infrastructure_pair_becomes_the_service_interval(self):
        event = {'id': 'i', 'infrastructure_validity': [None, '2020-04-01']}
        self.assertEqual(mod.split_domains(event), (None, '2020-04-01', None))
        props = {}
        mod.write_stated_domains(props, event)
        self.assertEqual(props['valid_to'], '2020-04-01')
        self.assertNotIn('service_validity', props)
        self.assertNotIn('infrastructure_validity', props)

    def test_both_domains_stay_distinct(self):
        event = {
            'id': 'u', 'kind': 'suspension',
            'service_validity': [None, '2019-11-01'],
            'infrastructure_validity': [None, '2023-12-27'],
        }
        start, end, infra = mod.split_domains(event)
        self.assertEqual((start, end), (None, '2019-11-01'))
        self.assertEqual(infra, (None, '2023-12-27'))
        props = {'valid_to': '2023-12-27'}
        mod.write_stated_domains(props, event)
        self.assertEqual(props['valid_to'], '2019-11-01')
        self.assertEqual(props['service_validity'], [None, '2019-11-01'])
        self.assertEqual(props['infrastructure_validity'], [None, '2023-12-27'])
        self.assertEqual(props['kind'], 'suspension')
        with self.assertRaises(SystemExit):
            mod.split_domains({'id': 'bad', 'service_validity': ['2020-01-01', '2019-01-01']})

    def test_station_closure_uses_release_geometry_not_an_open_platform(self):
        event = {
            'id': 'st', 'kind': 'station_closure', 'line': 'L', 'operator': 'O',
            'year': '16', 'valid_to': '2016-12-05', 'station': '増毛', 'source': 's',
        }
        rows = [(
            {'N02_001': '11', 'N02_002': '2', 'N02_003': 'L', 'N02_004': 'O', 'N02_005': '増毛'},
            [(141.0, 43.0), (141.01, 43.0)],
        )]
        closed = mod.closed_station_rows(event, rows, {})
        self.assertEqual(len(closed), 1)
        feature = mod.overlay_station_feature(event, *closed[0])
        self.assertEqual(feature['properties']['kind'], 'station_closure')
        self.assertEqual(feature['properties']['valid_to'], '2016-12-05')
        self.assertEqual(feature['properties']['station_name'], '増毛')
        self.assertNotIn('service_validity', feature['properties'])
        # N02 station "mid" is pts[len//2], the last vertex of a two-point platform.
        still_open = {'増毛': [('L', (141.01, 43.0))]}
        self.assertEqual(mod.closed_station_rows(event, rows, still_open), [])

    def test_station_opening_targets_stations_only(self):
        event = {
            'id': 'open.s', 'kind': 'station_opening', 'line': 'L', 'operator': 'O',
            'year': '16', 'valid_from': '2011-01-01', 'station': 'S', 'source': 's',
        }

        def release(_year):
            return (
                [({'N02_001': '11', 'N02_002': '2', 'N02_003': 'L', 'N02_004': 'O'},
                  [(0.0, 0.0), (1.0, 0.0)])],
                [({'N02_001': '11', 'N02_002': '2', 'N02_003': 'L', 'N02_004': 'O', 'N02_005': 'S'},
                  [(0.2, 0.2), (0.21, 0.2)])],
            )

        current = [station('L', 'O', 'S', [0.2, 0.2])]
        sections, stations, retirements = [], {}, []
        mod.emit_extended(
            event, release, [], current, {}, sections, stations, retirements,
            mod.SegIndex(), mod.SegIndex(), [])
        self.assertEqual(sections, [])
        self.assertEqual(retirements[0]['match']['targets'], ['stations'])
        self.assertEqual(retirements[0]['valid_from'], '2011-01-01')
        self.assertEqual(retirements[0]['kind'], 'station_opening')

    def test_suspension_and_transfer_need_a_release_row(self):
        suspended = {
            'id': 'sus', 'kind': 'suspension', 'line': 'L', 'operator': 'O',
            'year': '16', 'valid_to': '2019-11-01', 'source': 's',
        }
        current = [section('L', 'O', [[0.0, 0.0], [1.0, 0.0]])]
        sections, stations, retirements = [], {}, []
        mod.emit_extended(
            suspended, lambda _year: ([], []), current, [], {},
            sections, stations, retirements, mod.SegIndex(), mod.SegIndex(), [])
        self.assertEqual(retirements[0]['valid_to'], '2019-11-01')
        self.assertNotIn('targets', retirements[0]['match'])

        transferred = {
            'id': 'op', 'kind': 'operator_transfer', 'line': 'L', 'operator': 'Old',
            'to_operator': 'New', 'year': '16', 'valid_to': '2016-03-26', 'source': 's',
        }

        def release(_year):
            return (
                [({'N02_001': '11', 'N02_002': '2', 'N02_003': 'L', 'N02_004': 'Old'},
                  [(140.0, 36.0), (140.1, 36.0)])],
                [],
            )

        successor = [section('L', 'New', [[140.0, 36.0], [140.1, 36.0]])]
        sections, retirements = [], []
        mod.emit_extended(
            transferred, release, successor, [], {}, sections, {}, retirements,
            mod.SegIndex(), mod.SegIndex(), [])
        self.assertEqual(sections[0]['properties']['N02_004'], 'Old')
        self.assertEqual(sections[0]['properties']['kind'], 'operator_transfer')
        self.assertEqual(sections[0]['properties']['valid_to'], '2016-03-26')
        self.assertEqual(retirements[0]['history_id'], 'op.to')
        self.assertEqual(retirements[0]['valid_from'], '2016-03-26')
        self.assertEqual(retirements[0]['match']['operator'], 'New')
        with self.assertRaises(SystemExit):
            mod.emit_extended(
                {'id': 'op2', 'kind': 'operator_transfer', 'line': 'L', 'operator': 'Old',
                 'year': '16', 'valid_to': '2016-03-26', 'source': 's'},
                release, [], [], {}, [], {}, [], mod.SegIndex(), mod.SegIndex(), [])


if __name__ == '__main__':
    unittest.main()
