import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'lib'))
import na_geo as geo
from na_service_patterns import apply_repairs, _decode, _encode


def _load_cli_module():
    spec = importlib.util.spec_from_file_location(
        'na_service_pattern_repair_cli_under_test', HERE / 'repair-na-service-patterns.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_line(line_id, operator, name, points, class_code='11', inst_code='3'):
    """A synthetic straight-ish chain of `len(points)` stations."""
    segments = []
    for i in range(len(points) - 1):
        piece = [points[i], points[i + 1]]
        continuing = 0 if i == 0 else 1
        segments.append([round(geo.line_length(piece) / 1000, 3), continuing,
                         piece if continuing == 0 else piece[1:]])
    stations = [[f's{i}', f'Station {i}', points[i][0], points[i][1], f'Station {i}', 3, 0]
                for i in range(len(points))]
    line = {'id': line_id, 'name': name, 'nameNorm': name, 'operator': operator,
            'kind': 'metro', 'geometrySource': 'test', 'smoothingProfile': 'street',
            'lengthKm': round(sum(s[0] for s in segments), 3), 'rank': 1, 'color': '#000000',
            'nameRoma': name, 'stations': stations, 'segments': segments}
    return line, class_code, inst_code


def make_package_stations_sections(line, class_code, inst_code):
    package = {'lines': [line]}
    decoded = _decode(line)
    sections = {'type': 'FeatureCollection', 'features': [
        {'type': 'Feature',
         'properties': {'railway_class_code': class_code, 'institution_type_code': inst_code,
                        'line_name': line['name'], 'operator': line['operator']},
         'geometry': {'type': 'LineString', 'coordinates': piece}}
        for piece in decoded]}
    stations = {'type': 'FeatureCollection', 'features': []}
    for i, row in enumerate(line['stations']):
        neighbour = decoded[i][1] if i < len(decoded) else decoded[i - 1][-2]
        stations['features'].append({
            'type': 'Feature',
            'properties': {'railway_class_code': class_code, 'institution_type_code': inst_code,
                           'line_name': line['name'], 'operator': line['operator'],
                           'station_name': row[1], 'n02_station_code': f'US-TEST-{row[0].upper()}',
                           'n02_group_code': row[0], 'display_point': row[2:4],
                           'time_zone': 'America/New_York'},
            'geometry': {'type': 'LineString', 'coordinates': [row[2:4], neighbour]},
        })
    return package, stations, sections


def catalog_of(repair):
    return {'repairs': [repair]}


CHAIN_5 = [[-71.0, 42.0], [-71.01, 42.01], [-71.02, 42.02], [-71.03, 42.03], [-71.04, 42.04]]


class ServicePatternOpTests(unittest.TestCase):
    def test_truncate_after_drops_the_tail(self):
        line, cc, ic = make_line('t1', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r1', 'lineId': 't1', 'op': 'truncateAfter',
                              'station': 'Station 2', 'rule': 'test', 'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Station 0', 'Station 1', 'Station 2'])
        self.assertEqual(len(new_line['segments']), 2)
        self.assertEqual(new_line['segments'][0][1], 0)
        self.assertEqual(new_line['segments'][1][1], 1)
        self.assertEqual(new_line['lengthKm'], round(sum(s[0] for s in new_line['segments']), 3))
        remaining = [f for f in summary['sections']['features']
                    if f['properties']['operator'] == 'OP']
        self.assertEqual(len(remaining), 2)
        remaining_names = {f['properties']['station_name'] for f in summary['stations']['features']}
        self.assertEqual(remaining_names, {'Station 0', 'Station 1', 'Station 2'})

    def test_truncate_after_refuses_unknown_station(self):
        line, cc, ic = make_line('t1', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r1', 'lineId': 't1', 'op': 'truncateAfter',
                              'station': 'Nowhere', 'rule': 'test', 'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_truncate_after_refuses_terminus(self):
        line, cc, ic = make_line('t1', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r1', 'lineId': 't1', 'op': 'truncateAfter',
                              'station': 'Station 4', 'rule': 'test', 'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_drop_stations_merges_a_run_and_preserves_endpoints(self):
        points = [[-71.0, 42.0], [-71.01, 42.0], [-71.02, 42.0], [-71.03, 42.0],
                  [-71.04, 42.0], [-71.05, 42.0]]
        line, cc, ic = make_line('t2', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r2', 'lineId': 't2', 'op': 'dropStations',
                              'stations': ['Station 1', 'Station 2'], 'rule': 'test',
                              'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Station 0', 'Station 3', 'Station 4', 'Station 5'])
        self.assertEqual(len(new_line['segments']), 3)
        # The merged interval (Station 0 -> Station 3) must be Station 0's
        # full chord through Station 3, decoded whole.
        decoded = _decode(new_line)
        self.assertEqual(decoded[0][0], points[0])
        self.assertEqual(decoded[0][-1], points[3])
        self.assertEqual(decoded[0], points[0:4])
        remaining_sections = [f['geometry']['coordinates']
                              for f in summary['sections']['features']
                              if f['properties']['operator'] == 'OP']
        self.assertEqual(remaining_sections, decoded)
        remaining_names = {f['properties']['station_name'] for f in summary['stations']['features']}
        self.assertEqual(remaining_names, {'Station 0', 'Station 3', 'Station 4', 'Station 5'})

    def test_drop_stations_isolated_names(self):
        points = [[-71.0, 42.0], [-71.01, 42.0], [-71.02, 42.0], [-71.03, 42.0],
                  [-71.04, 42.0]]
        line, cc, ic = make_line('t3', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r3', 'lineId': 't3', 'op': 'dropStations',
                              'stations': ['Station 2'], 'rule': 'test', 'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Station 0', 'Station 1', 'Station 3', 'Station 4'])
        self.assertEqual(len(new_line['segments']), 3)

    def test_drop_stations_refuses_terminus(self):
        line, cc, ic = make_line('t4', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r4', 'lineId': 't4', 'op': 'dropStations',
                              'stations': ['Station 0'], 'rule': 'test', 'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_drop_stations_refuses_ambiguous_name(self):
        line, cc, ic = make_line('t5', 'OP', 'Line', CHAIN_5)
        line['stations'][2][1] = 'Station 1'  # duplicate name
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r5', 'lineId': 't5', 'op': 'dropStations',
                              'stations': ['Station 1'], 'rule': 'test', 'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_drop_line_removes_the_line_and_its_own_rows_only(self):
        shared_points_a = CHAIN_5
        shared_points_b = [[p[0] + 1, p[1] + 1] for p in CHAIN_5]
        line_a, cc, ic = make_line('a', 'OP', 'Shared Name', shared_points_a)
        line_b, _, _ = make_line('b', 'OP', 'Shared Name', shared_points_b)
        package = {'lines': [line_a, line_b]}
        _, stations_a, sections_a = make_package_stations_sections(line_a, cc, ic)
        _, stations_b, sections_b = make_package_stations_sections(line_b, cc, ic)
        stations = {'type': 'FeatureCollection',
                    'features': stations_a['features'] + stations_b['features']}
        sections = {'type': 'FeatureCollection',
                    'features': sections_a['features'] + sections_b['features']}
        catalog = catalog_of({'id': 'r6', 'lineId': 'a', 'op': 'dropLine',
                              'rule': 'test', 'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        self.assertEqual([l['id'] for l in summary['package']['lines']], ['b'])
        remaining_sections = [f for f in summary['sections']['features']
                              if f['properties']['operator'] == 'OP']
        self.assertEqual(len(remaining_sections), 4)
        for f in remaining_sections:
            self.assertIn(f['geometry']['coordinates'], _decode(line_b))
        # Every station 0..4 name is shared textually between the two lines,
        # so no feature should have been removed even though line `a` (with
        # the same operator+line_name) is gone: line `b` still lists them.
        remaining_names = {f['properties']['station_name'] for f in summary['stations']['features']}
        self.assertEqual(remaining_names, {f'Station {i}' for i in range(5)})

    def test_close_loop_swaps_identity_and_deletes_the_duplicate_seam(self):
        points = [[-71.0, 42.0], [-71.01, 42.0], [-71.02, 42.0], [-71.0, 42.0]]
        line, cc, ic = make_line('loop1', 'OP', 'Loop', points)
        line['stations'][0][0] = 'seam'
        line['stations'][0][1] = 'Seam Stop'
        line['stations'][-1][0] = 'keeper'
        line['stations'][-1][1] = 'Keeper Stop'
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r7', 'lineId': 'loop1', 'op': 'closeLoop',
                              'seamStation': 'Seam Stop', 'keepIdentityFrom': 'Keeper Stop',
                              'rule': 'test', 'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Keeper Stop', 'Station 1', 'Station 2'])
        self.assertEqual(new_line['stations'][0][2:4], points[0])
        self.assertEqual(len(new_line['segments']), 3)
        self.assertEqual(new_line.get('isLoop'), 1)
        names = [f['properties']['station_name'] for f in summary['stations']['features']
                if f['properties']['operator'] == 'OP']
        self.assertEqual(sorted(names), ['Keeper Stop', 'Station 1', 'Station 2'])
        kept = next(f for f in summary['stations']['features']
                   if f['properties']['station_name'] == 'Keeper Stop')
        self.assertEqual(kept['properties']['display_point'], points[0])

    def test_close_loop_refuses_mismatched_coordinates(self):
        points = [[-71.0, 42.0], [-71.01, 42.0], [-71.02, 42.0], [-71.05, 42.0]]
        line, cc, ic = make_line('loop2', 'OP', 'Loop', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r8', 'lineId': 'loop2', 'op': 'closeLoop',
                              'seamStation': 'Station 0', 'keepIdentityFrom': 'Station 3',
                              'rule': 'test', 'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_close_loop_dropping_lead_in(self):
        points = [[-71.0, 42.0], [-71.005, 42.0], [-71.01, 42.0], [-71.02, 42.0],
                  [-71.03, 42.0]]
        line, cc, ic = make_line('loop3', 'OP', 'Loop', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        closing = [points[-1], [-71.005, 42.005], points[1]]
        catalog = catalog_of({'id': 'r9', 'lineId': 'loop3', 'op': 'closeLoopDroppingLeadIn',
                              'dropFirstStations': 1, 'closingGeometry': closing,
                              'rule': 'test', 'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Station 1', 'Station 2', 'Station 3', 'Station 4'])
        self.assertEqual(len(new_line['segments']), 4)
        self.assertEqual(new_line['segments'][0][1], 0)
        self.assertEqual(new_line.get('isLoop'), 1)
        decoded = _decode(new_line)
        self.assertEqual(decoded[-1], closing)
        remaining_sections = [f['geometry']['coordinates']
                              for f in summary['sections']['features']
                              if f['properties']['operator'] == 'OP']
        self.assertEqual(remaining_sections, decoded)
        names = {f['properties']['station_name'] for f in summary['stations']['features']}
        self.assertEqual(names, {'Station 1', 'Station 2', 'Station 3', 'Station 4'})
        last_feature = next(f for f in summary['stations']['features']
                            if f['properties']['station_name'] == 'Station 4')
        self.assertEqual(last_feature['geometry']['coordinates'][1], closing[1])

    def test_close_loop_dropping_lead_in_refuses_bad_closing_geometry(self):
        points = [[-71.0, 42.0], [-71.005, 42.0], [-71.01, 42.0], [-71.02, 42.0],
                  [-71.03, 42.0]]
        line, cc, ic = make_line('loop4', 'OP', 'Loop', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        bad_closing = [[0, 0], [-71.005, 42.005], points[1]]
        catalog = catalog_of({'id': 'r10', 'lineId': 'loop4', 'op': 'closeLoopDroppingLeadIn',
                              'dropFirstStations': 1, 'closingGeometry': bad_closing,
                              'rule': 'test', 'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_unknown_line_id_refused(self):
        line, cc, ic = make_line('t6', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r11', 'lineId': 'does-not-exist', 'op': 'dropLine',
                              'rule': 'test', 'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_encode_refuses_a_discontinuous_piece(self):
        with self.assertRaises(ValueError):
            _encode([[[-71.0, 42.0], [-71.01, 42.01]], [[-71.5, 42.5], [-71.02, 42.02]]])

    def test_truncate_after_refuses_the_first_station(self):
        line, cc, ic = make_line('t7', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'r12', 'lineId': 't7', 'op': 'truncateAfter',
                              'station': 'Station 0', 'rule': 'test', 'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_remove_section_rows_refuses_an_ambiguous_geometry(self):
        # Two line records sharing (operator, line_name) with identical
        # geometry for one of their rows: the shared piece must not silently
        # pop the first hit.
        line_a, cc, ic = make_line('shareA', 'OP', 'Shared', CHAIN_5)
        line_b, _, _ = make_line('shareB', 'OP', 'Shared', CHAIN_5)
        package = {'lines': [line_a, line_b]}
        _, stations_a, sections_a = make_package_stations_sections(line_a, cc, ic)
        _, stations_b, sections_b = make_package_stations_sections(line_b, cc, ic)
        stations = {'type': 'FeatureCollection',
                    'features': stations_a['features'] + stations_b['features']}
        sections = {'type': 'FeatureCollection',
                    'features': sections_a['features'] + sections_b['features']}
        catalog = catalog_of({'id': 'r13', 'lineId': 'shareA', 'op': 'truncateAfter',
                              'station': 'Station 2', 'rule': 'test', 'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_apply_repairs_refuses_catalog_missing_required_fields(self):
        line, cc, ic = make_line('t8', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        for bad_repair in (
            {'id': 'x1', 'lineId': '', 'op': 'dropLine', 'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'x2', 'lineId': 't8', 'op': '', 'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'x3', 'lineId': 't8', 'op': 'dropLine', 'rule': '', 'evidence': ['a', 'b']},
            {'id': 'x4', 'lineId': 't8', 'op': 'dropLine', 'rule': 'test', 'evidence': ['a']},
            {'id': 'x5', 'lineId': 't8', 'op': 'dropLine', 'rule': 'test', 'evidence': ['a', '']},
            {'id': 'x6', 'lineId': 't8', 'op': 'dropLine', 'rule': 'test', 'evidence': 'a, b'},
        ):
            with self.assertRaises(ValueError):
                apply_repairs(package, stations, sections, catalog_of(bad_repair))

    def test_apply_repairs_refuses_duplicate_repair_ids(self):
        line, cc, ic = make_line('t9', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = {'repairs': [
            {'id': 'dup', 'lineId': 't9', 'op': 'truncateAfter', 'station': 'Station 2',
             'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'dup', 'lineId': 't9', 'op': 'truncateAfter', 'station': 'Station 1',
             'rule': 'test', 'evidence': ['a', 'b']},
        ]}
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_apply_repairs_refuses_bad_close_loop_dropping_lead_in_fields(self):
        points = [[-71.0, 42.0], [-71.005, 42.0], [-71.01, 42.0], [-71.02, 42.0],
                  [-71.03, 42.0]]
        line, cc, ic = make_line('t10', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        closing = [points[-1], [-71.005, 42.005], points[1]]
        for bad_field in (
            {'dropFirstStations': 0, 'closingGeometry': closing},
            {'dropFirstStations': -1, 'closingGeometry': closing},
            {'dropFirstStations': 1.0, 'closingGeometry': closing},
            {'dropFirstStations': 1, 'closingGeometry': [closing[0]]},
            {'dropFirstStations': 1, 'closingGeometry': 'not-a-list'},
        ):
            repair = {'id': 'r14', 'lineId': 't10', 'op': 'closeLoopDroppingLeadIn',
                      'rule': 'test', 'evidence': ['a', 'b'], **bad_field}
            with self.assertRaises(ValueError):
                apply_repairs(package, stations, sections, catalog_of(repair))


class RenameStationOpTests(unittest.TestCase):
    def test_rename_station_updates_name_label_and_feature(self):
        line, cc, ic = make_line('rn1', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'rr1', 'lineId': 'rn1', 'op': 'renameStation',
                              'stationId': 's2', 'newName': 'New Name', 'rule': 'test',
                              'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual(new_line['stations'][2][1], 'New Name')
        self.assertEqual(new_line['stations'][2][4], 'New Name')
        # Every other row is untouched.
        self.assertEqual([s[1] for i, s in enumerate(new_line['stations']) if i != 2],
                         ['Station 0', 'Station 1', 'Station 3', 'Station 4'])
        feature = next(f for f in summary['stations']['features']
                       if f['properties']['n02_group_code'] == 's2')
        self.assertEqual(feature['properties']['station_name'], 'New Name')

    def test_rename_station_refuses_unknown_id(self):
        line, cc, ic = make_line('rn2', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'rr2', 'lineId': 'rn2', 'op': 'renameStation',
                              'stationId': 'nope', 'newName': 'New Name', 'rule': 'test',
                              'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_rename_station_refuses_duplicate_id(self):
        line, cc, ic = make_line('rn3', 'OP', 'Line', CHAIN_5)
        line['stations'][3][0] = 's2'  # duplicate id
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'rr3', 'lineId': 'rn3', 'op': 'renameStation',
                              'stationId': 's2', 'newName': 'New Name', 'rule': 'test',
                              'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_rename_station_refuses_name_already_used_on_line(self):
        line, cc, ic = make_line('rn4', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'rr4', 'lineId': 'rn4', 'op': 'renameStation',
                              'stationId': 's2', 'newName': 'Station 3', 'rule': 'test',
                              'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def _shared_name_lines(self, id_a, id_b):
        # Two line records sharing (operator, line_name), each carrying its
        # own indistinguishable feature for station id 's2' — the exact
        # shape of the shipped MTA N/R/W 'Broadway Local' collision.
        line_a, cc, ic = make_line(id_a, 'OP', 'Shared', CHAIN_5)
        line_b, _, _ = make_line(id_b, 'OP', 'Shared', CHAIN_5)
        package = {'lines': [line_a, line_b]}
        _, stations_a, sections_a = make_package_stations_sections(line_a, cc, ic)
        _, stations_b, sections_b = make_package_stations_sections(line_b, cc, ic)
        stations = {'type': 'FeatureCollection',
                    'features': stations_a['features'] + stations_b['features']}
        sections = {'type': 'FeatureCollection',
                    'features': sections_a['features'] + sections_b['features']}
        return package, stations, sections

    def test_rename_station_renames_all_lines_sharing_the_name_when_all_are_renamed(self):
        package, stations, sections = self._shared_name_lines('rn5', 'rn6')
        catalog = {'repairs': [
            {'id': 'rr5a', 'lineId': 'rn5', 'op': 'renameStation', 'stationId': 's2',
             'newName': 'New Name', 'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'rr5b', 'lineId': 'rn6', 'op': 'renameStation', 'stationId': 's2',
             'newName': 'New Name', 'rule': 'test', 'evidence': ['a', 'b']},
        ]}
        summary = apply_repairs(package, stations, sections, catalog)
        lines_by_id = {l['id']: l for l in summary['package']['lines']}
        self.assertEqual(lines_by_id['rn5']['stations'][2][1], 'New Name')
        self.assertEqual(lines_by_id['rn6']['stations'][2][1], 'New Name')
        matching_features = [f for f in summary['stations']['features']
                             if f['properties']['operator'] == 'OP'
                             and f['properties']['line_name'] == 'Shared'
                             and f['properties']['n02_group_code'] == 's2']
        self.assertEqual(len(matching_features), 2)
        for feature in matching_features:
            self.assertEqual(feature['properties']['station_name'], 'New Name')

    def test_rename_station_refuses_when_only_one_sibling_line_is_renamed(self):
        package, stations, sections = self._shared_name_lines('rn7', 'rn8')
        catalog = catalog_of({'id': 'rr6', 'lineId': 'rn7', 'op': 'renameStation',
                              'stationId': 's2', 'newName': 'New Name', 'rule': 'test',
                              'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)


class MergeStationsOpTests(unittest.TestCase):
    def test_merge_stations_interior_merges_like_drop_stations(self):
        points = [[-71.0, 42.0], [-71.0001, 42.0], [-71.0002, 42.0], [-71.03, 42.0],
                  [-71.04, 42.0]]
        line, cc, ic = make_line('ms1', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'mm1', 'lineId': 'ms1', 'op': 'mergeStations',
                              'keep': 'Station 1', 'drop': 'Station 2', 'rule': 'test',
                              'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Station 0', 'Station 1', 'Station 3', 'Station 4'])
        remaining_names = {f['properties']['station_name'] for f in summary['stations']['features']}
        self.assertEqual(remaining_names, {'Station 0', 'Station 1', 'Station 3', 'Station 4'})

    def test_merge_stations_order_of_keep_and_drop_does_not_matter(self):
        points = [[-71.0, 42.0], [-71.0001, 42.0], [-71.0002, 42.0], [-71.03, 42.0],
                  [-71.04, 42.0]]
        line, cc, ic = make_line('ms2', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'mm2', 'lineId': 'ms2', 'op': 'mergeStations',
                              'keep': 'Station 2', 'drop': 'Station 1', 'rule': 'test',
                              'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Station 0', 'Station 2', 'Station 3', 'Station 4'])

    def test_merge_stations_refuses_non_consecutive_pair(self):
        points = [[-71.0, 42.0], [-71.0001, 42.0], [-71.0002, 42.0], [-71.0003, 42.0],
                  [-71.04, 42.0]]
        line, cc, ic = make_line('ms3', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'mm3', 'lineId': 'ms3', 'op': 'mergeStations',
                              'keep': 'Station 1', 'drop': 'Station 3', 'rule': 'test',
                              'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_merge_stations_refuses_pair_over_30m_apart(self):
        line, cc, ic = make_line('ms4', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'mm4', 'lineId': 'ms4', 'op': 'mergeStations',
                              'keep': 'Station 1', 'drop': 'Station 2', 'rule': 'test',
                              'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_merge_stations_refuses_end_station_with_different_coordinates(self):
        points = [[-71.0, 42.0], [-71.01, 42.0], [-71.02, 42.0], [-71.020009, 42.0]]
        line, cc, ic = make_line('ms5', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'mm5', 'lineId': 'ms5', 'op': 'mergeStations',
                              'keep': 'Station 2', 'drop': 'Station 3', 'rule': 'test',
                              'evidence': ['a', 'b']})
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_merge_stations_allows_end_station_with_identical_coordinates(self):
        points = [[-71.0, 42.0], [-71.01, 42.0], [-71.02, 42.0], [-71.02, 42.0]]
        line, cc, ic = make_line('ms6', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'mm6', 'lineId': 'ms6', 'op': 'mergeStations',
                              'keep': 'Station 2', 'drop': 'Station 3', 'rule': 'test',
                              'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Station 0', 'Station 1', 'Station 2'])
        self.assertEqual(new_line['stations'][-1][2:4], points[2])
        self.assertEqual(len(new_line['segments']), 2)

    def test_merge_stations_allows_first_station_with_identical_coordinates(self):
        points = [[-71.0, 42.0], [-71.0, 42.0], [-71.02, 42.0], [-71.03, 42.0]]
        line, cc, ic = make_line('ms7', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'mm7', 'lineId': 'ms7', 'op': 'mergeStations',
                              'keep': 'Station 1', 'drop': 'Station 0', 'rule': 'test',
                              'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Station 1', 'Station 2', 'Station 3'])
        self.assertEqual(new_line['segments'][0][1], 0)


class InsertStationOpTests(unittest.TestCase):
    def test_insert_station_splits_the_interval_and_adds_a_feature(self):
        line, cc, ic = make_line('is1', 'OP', 'Line', CHAIN_5)
        # Give the Station 1 -> Station 2 interval an extra interior
        # vertex, at (-71.015, 42.015): the vertex the new station anchors
        # to. `_encode`'s convention drops the vertex shared with the
        # previous interval's last point from a `continuing == 1` row.
        extra = [-71.015, 42.015]
        p1, p2 = CHAIN_5[1], CHAIN_5[2]
        line['segments'][1] = [round(geo.line_length([p1, extra, p2]) / 1000, 3), 1,
                               [extra, p2]]
        line['lengthKm'] = round(sum(s[0] for s in line['segments']), 3)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        before_km = line['lengthKm']
        catalog = catalog_of({
            'id': 'ir1', 'lineId': 'is1', 'op': 'insertStation',
            'after': 'Station 1', 'before': 'Station 2',
            'station': ['new-s', 'New Stop', -71.015, 42.015, 'New Stop', 3, 0],
            'rule': 'test', 'evidence': ['a', 'b'],
        })
        summary = apply_repairs(package, stations, sections, catalog)
        new_line = summary['package']['lines'][0]
        self.assertEqual([s[1] for s in new_line['stations']],
                         ['Station 0', 'Station 1', 'New Stop', 'Station 2',
                          'Station 3', 'Station 4'])
        self.assertEqual(len(new_line['segments']), 5)
        decoded = _decode(new_line)
        # The two new intervals both contain the split vertex.
        self.assertEqual(decoded[1][-1], [-71.015, 42.015])
        self.assertEqual(decoded[2][0], [-71.015, 42.015])
        self.assertAlmostEqual(
            new_line['lengthKm'],
            round(sum(s[0] for s in new_line['segments']), 3))
        self.assertNotEqual(new_line['lengthKm'], before_km)
        remaining_sections = [f['geometry']['coordinates']
                              for f in summary['sections']['features']
                              if f['properties']['operator'] == 'OP']
        self.assertEqual(remaining_sections, decoded)
        feature = next(f for f in summary['stations']['features']
                       if f['properties']['n02_group_code'] == 'new-s')
        self.assertEqual(feature['properties']['station_name'], 'New Stop')
        self.assertEqual(feature['properties']['n02_station_code'], 'new-s')
        self.assertEqual(feature['properties']['display_point'], [-71.015, 42.015])
        self.assertEqual(feature['geometry']['coordinates'][0], [-71.015, 42.015])
        self.assertEqual(feature['geometry']['type'], 'LineString')

    def test_insert_station_refuses_non_consecutive_after_before(self):
        line, cc, ic = make_line('is2', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({
            'id': 'ir2', 'lineId': 'is2', 'op': 'insertStation',
            'after': 'Station 0', 'before': 'Station 2',
            'station': ['new-s', 'New Stop', -71.005, 42.005, 'New Stop', 3, 0],
            'rule': 'test', 'evidence': ['a', 'b'],
        })
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_insert_station_refuses_when_vertex_is_not_found(self):
        line, cc, ic = make_line('is3', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({
            'id': 'ir3', 'lineId': 'is3', 'op': 'insertStation',
            'after': 'Station 0', 'before': 'Station 1',
            'station': ['new-s', 'New Stop', -71.0055, 42.0055, 'New Stop', 3, 0],
            'rule': 'test', 'evidence': ['a', 'b'],
        })
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, catalog)

    def test_insert_station_refuses_duplicate_id_or_name(self):
        line, cc, ic = make_line('is4', 'OP', 'Line', CHAIN_5)
        extra = [-71.015, 42.015]
        p1, p2 = CHAIN_5[1], CHAIN_5[2]
        line['segments'][1] = [round(geo.line_length([p1, extra, p2]) / 1000, 3), 1,
                               [extra, p2]]
        line['lengthKm'] = round(sum(s[0] for s in line['segments']), 3)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        dup_id = catalog_of({
            'id': 'ir4', 'lineId': 'is4', 'op': 'insertStation',
            'after': 'Station 0', 'before': 'Station 1',
            'station': ['s1', 'New Stop', -71.015, 42.015, 'New Stop', 3, 0],
            'rule': 'test', 'evidence': ['a', 'b'],
        })
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, dup_id)
        dup_name = catalog_of({
            'id': 'ir5', 'lineId': 'is4', 'op': 'insertStation',
            'after': 'Station 0', 'before': 'Station 1',
            'station': ['new-s', 'Station 1', -71.015, 42.015, 'Station 1', 3, 0],
            'rule': 'test', 'evidence': ['a', 'b'],
        })
        with self.assertRaises(ValueError):
            apply_repairs(package, stations, sections, dup_name)


class CatalogValidationForNewOpsTests(unittest.TestCase):
    def test_validate_catalog_refuses_rename_station_missing_fields(self):
        line, cc, ic = make_line('cv1', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        for bad_repair in (
            {'id': 'v1', 'lineId': 'cv1', 'op': 'renameStation', 'newName': 'X',
             'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'v2', 'lineId': 'cv1', 'op': 'renameStation', 'stationId': 's0',
             'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'v3', 'lineId': 'cv1', 'op': 'renameStation', 'stationId': '',
             'newName': 'X', 'rule': 'test', 'evidence': ['a', 'b']},
        ):
            with self.assertRaises(ValueError):
                apply_repairs(package, stations, sections, catalog_of(bad_repair))

    def test_validate_catalog_refuses_insert_station_missing_fields(self):
        line, cc, ic = make_line('cv3', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        good_station = ['new-s', 'New Stop', -71.005, 42.005, 'New Stop', 3, 0]
        for bad_repair in (
            {'id': 'v6', 'lineId': 'cv3', 'op': 'insertStation', 'before': 'Station 1',
             'station': good_station, 'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'v7', 'lineId': 'cv3', 'op': 'insertStation', 'after': 'Station 0',
             'station': good_station, 'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'v8', 'lineId': 'cv3', 'op': 'insertStation', 'after': 'Station 0',
             'before': 'Station 1', 'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'v9', 'lineId': 'cv3', 'op': 'insertStation', 'after': 'Station 0',
             'before': 'Station 1', 'station': ['new-s', 'New Stop', -71.005, 42.005],
             'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'v10', 'lineId': 'cv3', 'op': 'insertStation', 'after': 'Station 0',
             'before': 'Station 1', 'station': ['', 'New Stop', -71.005, 42.005,
                                                'New Stop', 3, 0],
             'rule': 'test', 'evidence': ['a', 'b']},
        ):
            with self.assertRaises(ValueError):
                apply_repairs(package, stations, sections, catalog_of(bad_repair))

    def test_validate_catalog_refuses_merge_stations_missing_fields(self):
        line, cc, ic = make_line('cv2', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        for bad_repair in (
            {'id': 'v4', 'lineId': 'cv2', 'op': 'mergeStations', 'drop': 'Station 1',
             'rule': 'test', 'evidence': ['a', 'b']},
            {'id': 'v5', 'lineId': 'cv2', 'op': 'mergeStations', 'keep': 'Station 0',
             'rule': 'test', 'evidence': ['a', 'b']},
        ):
            with self.assertRaises(ValueError):
                apply_repairs(package, stations, sections, catalog_of(bad_repair))


class ChangeLedgerRecordsIdTests(unittest.TestCase):
    def test_changes_ledger_records_the_repair_id(self):
        line, cc, ic = make_line('cid1', 'OP', 'Line', CHAIN_5)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        catalog = catalog_of({'id': 'my-repair-id', 'lineId': 'cid1', 'op': 'truncateAfter',
                              'station': 'Station 2', 'rule': 'test', 'evidence': ['a', 'b']})
        summary = apply_repairs(package, stations, sections, catalog)
        self.assertEqual(summary['changes'][0]['id'], 'my-repair-id')


class CumulativeApplyHelperTests(unittest.TestCase):
    """Tests the CLI's chain-walking id collector, which `apply_repairs` itself
    does not know about — cumulative skipping is the caller's responsibility."""

    @classmethod
    def setUpClass(cls):
        cls.cli = _load_cli_module()

    def test_applied_keys_walks_the_previous_repair_chain_by_id(self):
        package = {'servicePatternRepair': {
            'changes': [{'id': 'new-id', 'lineId': 'x', 'op': 'dropLine'}],
            'previousRepair': {
                'changes': [{'id': 'old-id', 'lineId': 'y', 'op': 'dropStations'}],
            },
        }}
        ids, legacy = self.cli._applied_keys(package)
        self.assertEqual(ids, {'new-id', 'old-id'})
        self.assertEqual(legacy, set())

    def test_applied_keys_falls_back_to_line_op_pairs_for_legacy_entries(self):
        # The shipped package's first repair round predates the `id` field on
        # ledger entries; those are recognised by (lineId, op) instead.
        package = {'servicePatternRepair': {
            'changes': [{'lineId': 'mbta-b', 'op': 'truncateAfter'}],
        }}
        ids, legacy = self.cli._applied_keys(package)
        self.assertEqual(ids, set())
        self.assertEqual(legacy, {('mbta-b', 'truncateAfter')})

    def test_applied_keys_on_a_never_repaired_package_is_empty(self):
        ids, legacy = self.cli._applied_keys({})
        self.assertEqual(ids, set())
        self.assertEqual(legacy, set())


class CumulativeCliIntegrationTest(unittest.TestCase):
    """End-to-end: a first CLI run applies one catalog entry; a second run of
    the same catalog is a no-op that skips it and writes nothing; adding a
    new entry to the catalog applies only the new one."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.app_root = Path(self.tmp.name) / 'app'
        (self.app_root / 'public/rail').mkdir(parents=True)
        (self.app_root / 'data').mkdir(parents=True)

        points = [[-71.0, 42.0], [-71.01, 42.01], [-71.02, 42.02], [-71.03, 42.03],
                  [-71.04, 42.04]]
        line, cc, ic = make_line('cli1', 'OP', 'Line', points)
        package, stations, sections = make_package_stations_sections(line, cc, ic)
        package['generatedAt'] = '2026-01-01T00:00:00+00:00'
        (self.app_root / 'public/rail/us-2025.json').write_text(json.dumps(package))
        (self.app_root / 'data/stations-us.json').write_text(json.dumps(stations))
        (self.app_root / 'data/rail-sections-us.json').write_text(json.dumps(sections))
        (self.app_root / 'data/station-readings-us.json').write_text(json.dumps({}))

        self.catalog_path = Path(self.tmp.name) / 'catalog.json'
        self.first_repair = {'id': 'first', 'lineId': 'cli1', 'op': 'truncateAfter',
                             'station': 'Station 2', 'rule': 'test', 'evidence': ['a', 'b']}
        self.catalog_path.write_text(json.dumps({'repairs': [self.first_repair]}))

    def _run(self, *extra_args):
        cmd = [sys.executable, str(HERE / 'repair-na-service-patterns.py'),
              '--app-root', str(self.app_root), '--catalog', str(self.catalog_path), *extra_args]
        return subprocess.run(cmd, capture_output=True, text=True, check=True)

    def test_second_run_of_the_same_catalog_is_a_no_op(self):
        first = self._run()
        first_summary = json.loads(first.stdout)
        self.assertEqual(first_summary['repairs'], 1)
        self.assertEqual(first_summary['alreadyApplied'], [])
        applied_package = json.loads((self.app_root / 'public/rail/us-2025.json').read_text())
        self.assertEqual(applied_package['servicePatternRepair']['changes'][0]['id'], 'first')
        mtime_before = (self.app_root / 'public/rail/us-2025.json').stat().st_mtime_ns

        second = self._run()
        second_summary = json.loads(second.stdout)
        self.assertEqual(second_summary['repairs'], 0)
        self.assertEqual(second_summary['alreadyApplied'], ['first'])
        mtime_after = (self.app_root / 'public/rail/us-2025.json').stat().st_mtime_ns
        self.assertEqual(mtime_before, mtime_after)

    def test_adding_a_new_catalog_entry_applies_only_the_new_one(self):
        self._run()
        second_repair = {'id': 'second', 'lineId': 'cli1', 'op': 'dropStations',
                         'stations': ['Station 1'], 'rule': 'test', 'evidence': ['a', 'b']}
        self.catalog_path.write_text(
            json.dumps({'repairs': [self.first_repair, second_repair]}))

        result = self._run()
        summary = json.loads(result.stdout)
        self.assertEqual(summary['repairs'], 1)
        self.assertEqual(summary['alreadyApplied'], ['first'])
        self.assertEqual(summary['lines'], ['cli1'])

        applied_package = json.loads((self.app_root / 'public/rail/us-2025.json').read_text())
        line = applied_package['lines'][0]
        self.assertEqual([s[1] for s in line['stations']], ['Station 0', 'Station 2'])
        repair_meta = applied_package['servicePatternRepair']
        self.assertEqual(repair_meta['changes'][0]['id'], 'second')
        self.assertEqual(repair_meta['previousRepair']['changes'][0]['id'], 'first')


class RealCatalogIntegrationTest(unittest.TestCase):
    """Apply the real, reviewed (US) catalog entries to the real shipped US
    package and assert the exact resulting station counts, entirely in
    memory (no file is written) — but only the entries the shipped package
    does not already carry.

    The catalog is cumulative: a rebuild applies it once, ships the result,
    and stamps ``servicePatternRepair`` (chained via ``previousRepair``)
    with the ids it applied. This test does not assume all-or-nothing: it
    walks that chain the same way the CLI does (``cli._applied_keys``) to
    work out which catalog entries are still new, applies only those to a
    deep copy, and asserts on the result — so it is correct whether the
    checkout has run the repair CLI zero, one, or many times.
    """

    EXPECTED_STATION_COUNTS = {
        'mbta-b': 23,
        'mbta-c': 20,
        'mbta-providence-stoughton-line': 14,
        'metropolitan-transit-authori-2': 49,
        'metropolitan-transit-authori-3': 34,
        'metropolitan-transit-authori-4': 28,
        'metropolitan-transit-authori-7x': 13,
        'metropolitan-transit-authori-a': 37,
        'metropolitan-transit-authori-d': 36,
        'metropolitan-transit-authori-q': 29,
        'miami-dade-transit-mmi': 8,
        'trimet-portland-streetcar-a': 28,
    }

    # Lines/counts touched only by the newer (rename/merge) catalog entries;
    # unaffected by whether the original 13-entry round has run yet.
    EXPECTED_NEW_STATION_COUNTS = {
        'mckinney-avenue-trolley-m-line-ob': 23,
        'san-francisco-municipal-tran-ph': 28,
        'san-francisco-municipal-tran-pm-b1': 2,
        'septa-g1': 59,
    }
    EXPECTED_RENAMES = {
        'amtrak-acela': {'us-official-south': 'South Station',
                         'us-official-back-bay': 'Back Bay'},
        'amtrak-northeast-regional': {'us-official-south': 'South Station',
                                      'us-official-back-bay': 'Back Bay'},
        'amtrak-lake-shore-limited': {'us-official-south': 'South Station',
                                      'us-official-back-bay': 'Back Bay'},
        'amtrak-amtrak-hartford-line': {'us-official-new-haven': 'New Haven State Street'},
        'metropolitan-transit-authori-l': {'us-official-14-st': '6 Av',
                                           'us-official-14-st-2': '8 Av'},
        'metropolitan-transit-authori-f': {'us-official-avenue': 'Avenue N'},
        'metropolitan-transit-authori-fx': {'us-official-avenue': 'Avenue N'},
    }

    @classmethod
    def setUpClass(cls):
        cls.package = json.loads((HERE.parents[1] / 'public/rail/us-2025.json').read_text())
        cls.stations = json.loads((HERE.parents[1] / 'data/stations-us.json').read_text())
        cls.sections = json.loads((HERE.parents[1] / 'data/rail-sections-us.json').read_text())
        catalog_path = HERE / 'na-service-pattern-repairs.json'
        cls.catalog = json.loads(catalog_path.read_text())
        cls.cli = _load_cli_module()
        applied_ids, legacy_pairs = cls.cli._applied_keys(cls.package)
        region_repairs = [r for r in cls.catalog['repairs'] if r.get('country', 'us') == 'us']
        cls.to_apply = [r for r in region_repairs
                        if r['id'] not in applied_ids
                        and (r['lineId'], r['op']) not in legacy_pairs]
        cls.already_applied_ids = [r['id'] for r in region_repairs
                                   if r not in cls.to_apply]

    def _repaired(self):
        """(lines_by_id, sections) after applying whatever is still new."""
        if not self.to_apply:
            return {l['id']: l for l in self.package['lines']}, self.sections
        summary = apply_repairs(copy.deepcopy(self.package), copy.deepcopy(self.stations),
                                copy.deepcopy(self.sections), {'repairs': self.to_apply})
        return {l['id']: l for l in summary['package']['lines']}, summary['sections']

    def test_expected_station_counts_after_repair(self):
        lines_by_id, _ = self._repaired()
        for line_id, expected in self.EXPECTED_STATION_COUNTS.items():
            self.assertIn(line_id, lines_by_id, line_id)
            self.assertEqual(len(lines_by_id[line_id]['stations']), expected, line_id)
            self.assertEqual(len(lines_by_id[line_id]['segments']),
                             expected if lines_by_id[line_id].get('isLoop') else expected - 1,
                             line_id)
        self.assertNotIn('mbta-providence-stoughton-line-b5', lines_by_id)
        self.assertEqual(lines_by_id['miami-dade-transit-mmi'].get('isLoop'), 1)
        self.assertEqual(lines_by_id['trimet-portland-streetcar-a'].get('isLoop'), 1)

    def test_expected_station_counts_for_the_new_merge_entries(self):
        lines_by_id, _ = self._repaired()
        for line_id, expected in self.EXPECTED_NEW_STATION_COUNTS.items():
            self.assertIn(line_id, lines_by_id, line_id)
            self.assertEqual(len(lines_by_id[line_id]['stations']), expected, line_id)

    def test_expected_names_for_the_new_rename_entries(self):
        lines_by_id, _ = self._repaired()
        for line_id, expected_names in self.EXPECTED_RENAMES.items():
            self.assertIn(line_id, lines_by_id, line_id)
            rows_by_id = {s[0]: s for s in lines_by_id[line_id]['stations']}
            for station_id, expected_name in expected_names.items():
                self.assertIn(station_id, rows_by_id, f'{line_id}/{station_id}')
                self.assertEqual(rows_by_id[station_id][1], expected_name,
                                 f'{line_id}/{station_id}')
                self.assertEqual(rows_by_id[station_id][4], expected_name,
                                 f'{line_id}/{station_id}')

    def test_every_line_segment_reconstructs_into_valid_sections_rows(self):
        lines_by_id, sections = self._repaired()
        for line_id in list(self.EXPECTED_STATION_COUNTS) + list(self.EXPECTED_NEW_STATION_COUNTS):
            line = lines_by_id[line_id]
            decoded = _decode(line)
            rows = [f['geometry']['coordinates'] for f in sections['features']
                    if f['properties']['operator'] == line['operator']
                    and f['properties']['line_name'] == line['name']]
            for piece in decoded:
                self.assertIn(piece, rows, line_id)

    def test_post_repair_state_matches_the_shipped_changes_ledger(self):
        # Walk the (possibly multi-round) servicePatternRepair chain and, for
        # each line, take the most recent recorded `after` — a line can be
        # touched by more than one entry within a round (mckinney's two
        # merges) or across rounds, so only the latest state is checked.
        lines_by_id = {l['id']: l for l in self.package['lines']}
        node = self.package.get('servicePatternRepair')
        rounds = []
        while node:
            rounds.append(node.get('changes', []))
            node = node.get('previousRepair')
        last_after_by_line = {}
        for round_changes in rounds:            # newest round first
            for change in reversed(round_changes):
                last_after_by_line.setdefault(change['lineId'], change['after'])

        for line_id, after in last_after_by_line.items():
            if after is None:
                self.assertNotIn(line_id, lines_by_id, line_id)      # dropLine
                continue
            self.assertIn(line_id, lines_by_id, line_id)
            line = lines_by_id[line_id]
            self.assertEqual(len(line['stations']), after['stations'], line_id)
            self.assertEqual(len(line['segments']), after['segments'], line_id)

    def test_reapplying_already_shipped_entries_is_refused(self):
        if not self.already_applied_ids:
            self.skipTest('nothing from this catalog has been applied to the shipped '
                          'package yet')
        already_applied_repairs = [r for r in self.catalog['repairs']
                                   if r['id'] in self.already_applied_ids]
        with self.assertRaises(ValueError):
            apply_repairs(copy.deepcopy(self.package), copy.deepcopy(self.stations),
                          copy.deepcopy(self.sections), {'repairs': already_applied_repairs})

    def test_reconstruction_reproduces_an_untouched_lines_shipped_rows_exactly(self):
        # Proves the decode/encode convention this module relies on against
        # a line the catalog never touches.
        line = next(l for l in self.package['lines'] if l['id'] == 'mbta-blue-line')
        decoded = _decode(line)
        rows = [f['geometry']['coordinates'] for f in self.sections['features']
                if f['properties']['operator'] == line['operator']
                and f['properties']['line_name'] == line['name']]
        self.assertEqual(decoded, rows)
        self.assertEqual(_encode(decoded), line['segments'])


if __name__ == '__main__':
    unittest.main()
