import copy
import json
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'lib'))
import na_geo as geo
from na_station_approaches import apply_repairs, intervals, digest

CATALOG = json.loads((HERE / 'na-station-approach-repairs.json').read_text())


def fixture(repair):
    incoming, outgoing = [w['oldCoordinates'] for w in repair['windows']]
    line = {'id': repair['lineId'], 'operator': 'Amtrak', 'name': 'Test',
            'geometrySource': 'narn', 'lengthKm': 0,
            'stations': [['a', 'A', *incoming[0]],
                         [repair['stationId'], 'Station', *repair['oldAnchor']],
                         ['b', 'B', *outgoing[-1]]],
            'segments': [[round(geo.line_length(incoming) / 1000, 3), 0, incoming],
                         [round(geo.line_length(outgoing) / 1000, 3), 1, outgoing[1:]]]}
    properties = {'operator': 'Amtrak', 'line_name': 'Test'}
    stations = {'features': [{'properties': {**properties,
                              'n02_group_code': repair['stationId'],
                              'display_point': repair['oldAnchor']},
                              'geometry': {'coordinates': outgoing[:2]}}]}
    sections = {'features': [{'properties': properties,
                             'geometry': {'coordinates': p}} for p in [incoming, outgoing]]}
    catalog = {**CATALOG, 'repairs': [repair]}
    return copy.deepcopy(({'lines': [line]}, stations, sections, catalog))


class StationApproachTests(unittest.TestCase):
    def test_all_reviewed_windows_preserve_exact_donor_vertices_and_seams(self):
        package = json.loads((HERE.parents[1] / 'public/rail/us-2025.json').read_text())
        lines = {l['id']: l for l in package['lines']}
        for repair in CATALOG['repairs']:
            donor = lines[repair['evidence']['donorLineId']]
            self.assertEqual(digest(donor), repair['evidence']['donorLineSha256'])
            decoded = intervals(donor)
            for window in repair['windows']:
                ranges = window.get('donorRanges') or [{
                    'interval': window['donorInterval'],
                    'vertexRange': window['donorVertexRange'],
                    'reversed': window['reversed'],
                }]
                source = []
                for donor_range in ranges:
                    start, end = donor_range['vertexRange']
                    piece = decoded[donor_range['interval']][start:end + 1]
                    if donor_range['reversed']:
                        piece = piece[::-1]
                    if source:
                        self.assertEqual(source[-1], piece[0])
                        source.extend(piece[1:])
                    else:
                        source = piece
                self.assertEqual(source, window['coordinates'])
                self.assertIn(window['seam'], window['oldCoordinates'])
                self.assertEqual(digest(window['oldCoordinates']),
                                 window['oldCoordinatesSha256'])

    def test_both_sides_anchor_lengths_sections_and_idempotence(self):
        for repair in CATALOG['repairs']:
            with self.subTest(repair=repair['id']):
                package, stations, sections, catalog = fixture(repair)
                result, new_stations, new_sections, changes = apply_repairs(
                    package, stations, sections, catalog)
                self.assertEqual(len(changes), 1)
                line = result['lines'][0]
                decoded = intervals(line)
                self.assertEqual(decoded[0][-1], repair['anchor'])
                self.assertEqual(decoded[1][0], repair['anchor'])
                self.assertEqual(line['stations'][1][2:4], repair['anchor'])
                for index, piece in enumerate(decoded):
                    self.assertEqual(line['segments'][index][0],
                                     round(geo.line_length(piece) / 1000, 3))
                    self.assertEqual(new_sections['features'][index]['geometry']['coordinates'], piece)
                self.assertEqual(line['lengthKm'], round(sum(geo.line_length(p) for p in decoded) / 1000, 3))
                self.assertEqual(new_stations['features'][0]['properties']['display_point'], repair['anchor'])
                again = apply_repairs(result, new_stations, new_sections, catalog)
                self.assertEqual(again[:3], (result, new_stations, new_sections))
                self.assertEqual(again[3], [])
                self.assertEqual(again[0]['stationApproachRepair']['catalogSha256'], digest(catalog))
                self.assertEqual(package['lines'][0]['stations'][1][2:4], repair['oldAnchor'])

    def test_catalog_extension_refreshes_metadata_without_reapplying_geometry(self):
        package, stations, sections, catalog = fixture(CATALOG['repairs'][0])
        package, stations, sections, _ = apply_repairs(package, stations, sections, catalog)
        before_geometry = copy.deepcopy(package['lines'][0]['segments'])
        catalog['version'] += 1
        result, new_stations, new_sections, changes = apply_repairs(package, stations, sections, catalog)
        self.assertEqual(changes, [])
        self.assertEqual(result['lines'][0]['segments'], before_geometry)
        self.assertEqual((new_stations, new_sections), (stations, sections))
        self.assertEqual(result['lines'][0]['stationApproachRepairs'][0]['catalogSha256'], digest(catalog))
        self.assertEqual(result['stationApproachRepair']['changes'][0]['catalogSha256'], digest(catalog))
        self.assertEqual(apply_repairs(result, new_stations, new_sections, catalog)[:3],
                         (result, new_stations, new_sections))

    def test_changed_source_fails_closed_without_mutating_callers(self):
        package, stations, sections, catalog = fixture(CATALOG['repairs'][0])
        package['lines'][0]['segments'][0][2][1][0] += 0.000001
        snapshot = copy.deepcopy((package, stations, sections))
        with self.assertRaisesRegex(ValueError, 'source window changed'):
            apply_repairs(package, stations, sections, catalog)
        self.assertEqual((package, stations, sections), snapshot)

    def test_unrelated_interval_and_source_metadata_are_unchanged(self):
        package, stations, sections, catalog = fixture(CATALOG['repairs'][0])
        unrelated = {'id': 'untouched', 'stations': [], 'segments': []}
        package['lines'].append(unrelated)
        result, _, _, _ = apply_repairs(package, stations, sections, catalog)
        self.assertEqual(result['lines'][1], unrelated)
        self.assertEqual(result['lines'][0]['geometrySource'], 'narn')

    def test_points_outside_exact_seams_survive_without_reencoding(self):
        package, stations, sections, catalog = fixture(CATALOG['repairs'][0])
        line = package['lines'][0]
        prefix = [-74.99, 40.03]
        suffix = [-75.22, 39.93]
        line['segments'][0][2].insert(0, prefix)
        line['segments'][1][2].append(suffix)
        sections['features'][1]['geometry']['coordinates'].append(suffix)
        result, _, new_sections, _ = apply_repairs(package, stations, sections, catalog)
        self.assertEqual(intervals(result['lines'][0])[0][0], prefix)
        self.assertEqual(intervals(result['lines'][0])[1][-1], suffix)
        self.assertEqual(new_sections['features'][0]['geometry']['coordinates'][0], prefix)

    def test_palmetto_windows_remain_close_to_the_reviewed_official_tunnel(self):
        package = json.loads((HERE.parents[1] / 'public/rail/us-2025.json').read_text())
        donor = next(l for l in package['lines'] if l['id'] == 'amtrak-northeast-regional')
        decoded = intervals(donor)
        corridor = decoded[8] + decoded[9][1:]
        for repair in CATALOG['repairs']:
            if repair['evidence']['donorLineId'] != 'amtrak-palmetto':
                continue
            for window in repair['windows']:
                worst = max(min(geo.point_segment_distance(p, a, b)[0]
                                for a, b in zip(corridor, corridor[1:]))
                            for p in window['coordinates'])
                self.assertLess(worst, 10)
                self.assertEqual(round(worst, 3), window['officialCorridorCrosscheckMaxMeters'])

    def test_washington_through_window_cannot_retrace_the_terminal_spur(self):
        for repair in CATALOG['repairs']:
            if repair['stationId'] != 'us-official-washington-union':
                continue
            incoming, outgoing = [w['coordinates'] for w in repair['windows']]
            self.assertTrue(all(p[1] <= repair['anchor'][1] for p in incoming))
            self.assertTrue(all(p[1] >= repair['anchor'][1] for p in outgoing))
            self.assertEqual(set(map(tuple, incoming)) & set(map(tuple, outgoing)),
                             {tuple(repair['anchor'])})

    def test_philadelphia_platform_is_through_not_western_bypass_chord(self):
        for repair in CATALOG['repairs']:
            if repair['stationId'] != 'us-official-philadelphia':
                continue
            for window in repair['windows']:
                points = window['coordinates']
                neighbor = points[-2] if window['side'] == 'incoming' else points[1]
                self.assertLess(abs(neighbor[0] - repair['anchor'][0]), 0.001)

    def test_pennsylvanian_keeps_its_real_philadelphia_reversal(self):
        repair = next(r for r in CATALOG['repairs']
                      if r['lineId'] == 'amtrak-pennsylvanian')
        incoming, outgoing = [w['coordinates'] for w in repair['windows']]
        # Both legs enter the lower-level platforms from the north; the
        # service's real reversal must survive removing the diagonal chords.
        self.assertEqual(incoming[-2], outgoing[1])
        self.assertGreater(incoming[-2][1], repair['anchor'][1])
        self.assertNotEqual(incoming[0], outgoing[-1])


if __name__ == '__main__':
    unittest.main()
