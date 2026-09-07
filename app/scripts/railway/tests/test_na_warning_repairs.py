"""Regressions for local station identities and reported source evidence."""
import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
import copy

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'lib'))
import na_geo
import na_official
from na_station_ids import apply_repairs
spec = importlib.util.spec_from_file_location('warning_builder', HERE / 'build-north-america-rail-package.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
spec = importlib.util.spec_from_file_location('warning_merger', HERE / 'merge-na-feed-build.py')
merger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merger)


class WarningRepairTests(unittest.TestCase):
    def test_partial_merge_keeps_same_named_sibling_anchors_and_duplicate_counts(self):
        line = {'operator': 'MBTA', 'name': 'Green Line',
                'stations': [['union', 'Union Square', 0, 0], ['lech', 'Lechmere', 1, 0]],
                'segments': [[1, 0, [[0, 0], [1, 0]]]]}
        features = [{'properties': {'operator': 'MBTA', 'line_name': 'Green Line',
                     'n02_group_code': s[0], 'display_point': s[2:4]}}
                    for s in line['stations']]
        sibling = copy.deepcopy(features[-1])
        sibling['properties']['display_point'] = [2, 0]
        duplicate = copy.deepcopy(features[-1])
        selected = merger.partial_line_features(features + [sibling, duplicate], [line], True)
        self.assertEqual([id(x) for x in selected], [id(x) for x in features])
        sections = [{'properties': {'operator': 'MBTA', 'line_name': 'Green Line'},
                     'geometry': {'type': 'LineString', 'coordinates': pts}}
                    for pts in [[[0, 0], [1, 0]], [[0, 0], [2, 0]]]]
        self.assertEqual(merger.partial_line_features(sections, [line], False), sections[:1])
        with self.assertRaisesRegex(ValueError, 'cannot match'):
            merger.partial_line_features([features[0], sibling], [line], True)

    def test_reviewed_local_ids_split_without_moving_geometry(self):
        catalog = json.loads((HERE / 'na-local-station-id-repairs.json').read_text())
        lines, features = [], []
        for repair in catalog['repairs']:
            for place in repair['places']:
                for member in place['members']:
                    line = {'id': member['lineId'], 'operator': member['feed'],
                            'name': member['lineId'], 'segments': [],
                            'stations': [[repair['oldId'], member['name'], *member['point']]]}
                    lines.append(line)
                    features.append({'properties': {'operator': line['operator'],
                        'line_name': line['name'], 'n02_group_code': repair['oldId'],
                        'n02_station_code': 'US-' + repair['oldId'].upper(),
                        'display_point': member['point']}})
        package = {'country': 'US', 'lines': lines}
        stations = {'features': features}
        repaired, repaired_stations, changes = apply_repairs(package, stations, catalog)
        self.assertEqual(len(changes), 2)
        for before, after in zip(lines, repaired['lines']):
            self.assertEqual(before['stations'][0][1:], after['stations'][0][1:])
            self.assertEqual(before['segments'], after['segments'])
        for repair in catalog['repairs']:
            members = [l for l in repaired['lines'] if l['stations'][0][0].startswith(repair['oldId'])]
            self.assertEqual(len({l['stations'][0][0] for l in members}), 2)
        self.assertEqual(apply_repairs(repaired, repaired_stations, catalog),
                         (repaired, repaired_stations, []))

    def test_lechmere_report_measures_used_anchors_and_limit_restores_approach(self):
        source = json.loads((HERE / 'tests/fixtures/mbta-green-e-anchor-source.geojson').read_text())
        network = na_official.PassengerNetwork(source['features'], endpoint_join_m=25)
        stations = [[-71.094761, 42.377359], [-71.076584, 42.371572]]
        old, report = network.route_stations(stations, max_snap_m=600)
        self.assertGreater(report['snapMeters'][1], 450)
        self.assertLess(max(report['nearestSnapMeters']), 9)
        for i, point in enumerate([old[0][0], old[0][-1]]):
            self.assertAlmostEqual(report['snapMeters'][i], na_geo.haversine(stations[i], point))
        registry = json.loads((HERE / 'na-feeds.json').read_text())
        entry = next(f for f in registry['feeds'] if f['slug'] == 'mbta')
        limit = builder.official_snap_limit(entry, 'Green-E', 600)
        fixed, report = network.route_stations(stations, max_snap_m=limit)
        self.assertLess(max(report['snapMeters']), 9)
        self.assertGreater(na_geo.line_length(fixed[0]), 1600)
        self.assertLess(na_geo.line_length(fixed[0]), 1750)
        self.assertGreater(na_geo.line_length(fixed[0]) - na_geo.line_length(old[0]), 750)
        self.assertEqual(builder.official_snap_limit(entry, 'Red', 600), 600)
        self.assertEqual(builder.official_snap_limit(entry, 'Green-E', 20), 20)
        trunk = json.loads((HERE / 'tests/fixtures/mbta-green-e-stops.json').read_text())
        trunk_points = [station['point'] for station in trunk['stations']]
        self.assertEqual(len(trunk_points), 25)
        routed, report = network.route_stations(trunk_points, max_snap_m=limit)
        self.assertIsNotNone(routed, report)
        self.assertEqual(len(routed), 24)
        self.assertLessEqual(max(report['snapMeters']), limit)
        d_source = json.loads((HERE / 'tests/fixtures/mbta-green-d-anchor-source.geojson').read_text())
        d_points = json.loads((HERE / 'tests/fixtures/mbta-green-d-stops.json').read_text())
        d_network = na_official.PassengerNetwork(d_source['features'], endpoint_join_m=25)
        d_intervals, report = d_network.route_stations(
            d_points, max_snap_m=builder.official_snap_limit(entry, 'Green-D', 600))
        self.assertEqual(len(d_intervals), 24)
        self.assertLess(max(report['snapMeters']), 53)
        self.assertLess(na_geo.haversine(d_intervals[-1][-1], stations[0]), 4)

    def test_named_osm_extract_cannot_verify_itself(self):
        osm = SimpleNamespace(way_count=1, nearest=lambda p, n: (0.0, 'rail'))
        source = {'named-composite': {'publisher': 'OpenStreetMap contributors'}}
        checker = builder.CrossCheck(None, osm, source_provenance=source)
        piece = [[-122.1, 37.5], [-122.099, 37.5]]
        result = checker.measure([piece], 'named-composite')
        self.assertEqual(result['unmatched'], 2)
        self.assertEqual(result['agreedWith'], {})
        self.assertFalse(checker.straight_is_surveyed(piece, 'named-composite', 25)['agrees'])
        self.assertEqual(checker.measure([piece], 'operator-gtfs')['agreedWith'], {'osm': 2})
        survey = SimpleNamespace(nearest=lambda p, n: (2.0, 'city-survey'))
        independent = builder.CrossCheck(None, osm, survey, source)
        self.assertEqual(independent.measure([piece], 'named-composite')['agreedWith'], {'city-survey': 2})


if __name__ == '__main__':
    unittest.main()
