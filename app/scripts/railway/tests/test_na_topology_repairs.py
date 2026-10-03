import copy
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
from na_build import profile_for_line
from na_service_patterns import _decode, _encode

SPEC = importlib.util.spec_from_file_location('na_topology_repair_test',
                                             HERE / 'repair-na-topology.py')
repair = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(repair)


def line(line_id, points, station_ids=None, source='survey-i'):
    ids = station_ids or [f'{line_id}-s{i}' for i in range(len(points))]
    pieces = [[a, b] for a, b in zip(points, points[1:])]
    segments = _encode(pieces)
    return {'id': line_id, 'name': line_id.split('-branch')[0], 'operator': 'OP',
            'geometrySource': source, 'smoothingProfile': 'street',
            'kind': 'funicular', 'lengthKm': round(sum(p[0] for p in segments), 3),
            'rank': 4, 'color': '#abcdef',
            'stations': [[sid, sid, *pt, sid, 3, 0] for sid, pt in zip(ids, points)],
            'segments': segments}


def data(lines):
    package = {'country': 'us', 'lines': lines}
    stations = {'type': 'FeatureCollection', 'features': []}
    sections = {'type': 'FeatureCollection', 'features': []}
    readings = {'byCode': {}, 'byName': {}, 'stats': {}, 'note': 'retain metadata'}
    for item in lines:
        pieces = _decode(item)
        for piece in pieces:
            sections['features'].append({'type': 'Feature', 'properties': {
                'operator': item['operator'], 'line_name': item['name'],
                'railway_class_code': '31', 'institution_type_code': '3'},
                'geometry': {'type': 'LineString', 'coordinates': piece}})
        for i, row in enumerate(item['stations']):
            neighbour = pieces[i][1] if i < len(pieces) else pieces[i - 1][-2]
            code = 'US-' + row[0]
            stations['features'].append({'type': 'Feature', 'properties': {
                'operator': item['operator'], 'line_name': item['name'],
                'station_name': row[1], 'n02_group_code': row[0],
                'n02_station_code': code, 'display_point': row[2:4]},
                'geometry': {'type': 'LineString', 'coordinates': [row[2:4], neighbour]}})
            reading = {'name': row[1], 'en': row[1], 'ja': 'retain translation'}
            readings['byCode'][code] = readings['byCode'][row[0]] = reading
            readings['byName'][row[1]] = reading
    readings['stats'] = {key: len(readings[key]) for key in ('byCode', 'byName')}
    return dict(package=package, stations=stations, sections=sections, readings=readings)


SOURCE = {'publisher': 'Official survey', 'url': 'https://example.gov/rail',
          'rawSha256': 'a' * 64, 'normalizedSha256': 'b' * 64}


def catalog(entry):
    return {'country': 'us', 'reviewedAt': '2026-09-30',
            'repairs': [{**entry, 'source': SOURCE, 'evidence': ['Reviewed physical geometry']}]}


def direction_case():
    points = [[0, 0], [.01, 0], [.02, 0]]
    trunk = line('trunk', points)
    geometry = [[0, .00001], [0, .002], [.01, .002], [.01, .0001]]
    trunk['extraSegments'] = [{'from': 0, 'to': 2, 'geometry': geometry,
                              'km': round(geo.line_length(geometry) / 1000, 3),
                              'evidence': 'survey-o direction 1; original target stop s1'}]
    entry = {'id': 'direction-edge', 'op': 'materializeDirectionalEdge',
             'lineId': trunk['id'], 'expectedLineSha256': repair.digest(trunk),
             'extraIndex': 0, 'newLineId': 'trunk-direction1', 'geometrySource': 'survey-o',
             'fromStationId': trunk['stations'][0][0],
             'toStationId': trunk['stations'][1][0], 'maxDeviationMeters': 223}
    return data([trunk]), catalog(entry)


def covered_case(alias=False):
    points = [[0, 0], [.01, 0], [.02, 0], [.03, 0]]
    trunk = line('trunk', points)
    branch = copy.deepcopy(trunk)
    branch.update({'id': 'trunk-branch', 'branchOf': trunk['id']})
    branch['stations'] = copy.deepcopy(trunk['stations'][1:])
    branch['segments'] = _encode(_decode(trunk)[1:])
    branch['lengthKm'] = round(sum(p[0] for p in branch['segments']), 3)
    aliases = {}
    if alias:
        old_id = branch['stations'][1][0]
        branch['stations'][1][0] = 'stadium-direction-stop'
        aliases = {'stadium-direction-stop': old_id}
    entry = {'id': 'covered-branch', 'op': 'removeCoveredBranch',
             'lineId': branch['id'], 'trunkId': trunk['id'],
             'expectedLineSha256': repair.digest(branch),
             'expectedTrunkSha256': repair.digest(trunk),
             'stationAliases': aliases, 'maxCoverageDistanceMeters': 5}
    return data([trunk, branch]), catalog(entry)


class TopologyRepairTests(unittest.TestCase):
    def test_direction_edge_retains_survey_and_exact_own_anchors(self):
        inputs, review = direction_case()
        original = copy.deepcopy(inputs)
        result = repair.apply_repairs(**inputs, catalog=review)
        trunk, edge = result['package']['lines']
        self.assertNotIn('extraSegments', trunk)
        self.assertEqual(trunk['stations'], original['package']['lines'][0]['stations'])
        self.assertEqual(trunk['segments'], original['package']['lines'][0]['segments'])
        geometry = original['package']['lines'][0]['extraSegments'][0]['geometry']
        self.assertEqual(edge['segments'][0][2], geometry)
        self.assertEqual(edge['stations'][0][2:4], geometry[0])
        self.assertEqual(edge['stations'][-1][2:4], geometry[-1])
        self.assertEqual(edge['stations'][1][0], trunk['stations'][1][0])
        self.assertNotEqual(edge['stations'][1][2:4], trunk['stations'][1][2:4])
        self.assertEqual(edge['branchOf'], trunk['id'])
        self.assertEqual(edge['geometrySource'], 'survey-o')
        self.assertEqual(edge['smoothingProfile'], profile_for_line([geometry])[0].name)
        self.assertNotEqual(edge['smoothingProfile'], trunk['smoothingProfile'])
        self.assertGreater(edge['directionSpecificGeometry']['measuredDeviationMeters'], 30)
        self.assertEqual(result['sections']['features'][-1]['geometry']['coordinates'], geometry)
        self.assertEqual(inputs, original)
        self.assertIn('survey-o', result['package']['geometrySource']['verifiedOfficialNetworks'])
        self.assertEqual(result['readings']['byCode']['US-trunk-s0-DIRECTION1']['ja'],
                         'retain translation')

    def test_coincident_geometry_cannot_claim_direction_specific_edge(self):
        inputs, review = direction_case()
        trunk = inputs['package']['lines'][0]
        trunk['extraSegments'][0]['geometry'] = [[0, 0], [.01, 0]]
        trunk['extraSegments'][0]['km'] = round(geo.line_length([[0, 0], [.01, 0]]) / 1000, 3)
        review['repairs'][0]['expectedLineSha256'] = repair.digest(trunk)
        with self.assertRaisesRegex(ValueError, 'no reviewed physical divergence'):
            repair.apply_repairs(**inputs, catalog=review)

    def test_covered_branch_removes_only_its_sections_and_station_occurrences(self):
        inputs, review = covered_case()
        trunk = copy.deepcopy(inputs['package']['lines'][0])
        result = repair.apply_repairs(**inputs, catalog=review)
        self.assertEqual(result['package']['lines'], [trunk])
        self.assertEqual(len(result['stations']['features']), len(trunk['stations']))
        self.assertEqual([f['geometry']['coordinates'] for f in result['sections']['features']],
                         _decode(trunk))
        self.assertEqual(result['readings']['note'], 'retain metadata')

    def test_stadium_alias_folds_identity_without_moving_trunk(self):
        inputs, review = covered_case(alias=True)
        trunk = copy.deepcopy(inputs['package']['lines'][0])
        result = repair.apply_repairs(**inputs, catalog=review)
        self.assertEqual(result['package']['lines'], [trunk])
        self.assertNotIn('stadium-direction-stop', result['readings']['byCode'])
        self.assertIn(trunk['stations'][2][0], result['readings']['byCode'])
        self.assertEqual(result['changes'][0]['stationAliases'],
                         {'stadium-direction-stop': trunk['stations'][2][0]})

    def test_station_subset_with_distinct_physical_edge_is_refused(self):
        inputs, review = covered_case()
        branch = inputs['package']['lines'][1]
        branch['segments'][0][2].insert(1, [.015, .002])
        review['repairs'][0]['expectedLineSha256'] = repair.digest(branch)
        with self.assertRaisesRegex(ValueError, 'distinct physical edge'):
            repair.apply_repairs(**inputs, catalog=review)

    def test_changed_release_is_refused_and_inputs_remain_untouched(self):
        inputs, review = covered_case()
        inputs['package']['lines'][0]['color'] = '#123456'
        previous = copy.deepcopy(inputs)
        with self.assertRaisesRegex(ValueError, 'fingerprint changed'):
            repair.apply_repairs(**inputs, catalog=review)
        self.assertEqual(inputs, previous)

    def test_missing_station_feature_fails_without_partial_input_mutation(self):
        inputs, review = covered_case(alias=True)
        inputs['stations']['features'] = [f for f in inputs['stations']['features']
                                        if f['properties']['n02_group_code'] !=
                                        'stadium-direction-stop']
        previous = copy.deepcopy(inputs)
        with self.assertRaisesRegex(ValueError, 'station feature missing'):
            repair.apply_repairs(**inputs, catalog=review)
        self.assertEqual(inputs, previous)

    def test_recorded_repairs_are_idempotent(self):
        inputs, review = direction_case()
        result = repair.apply_repairs(**inputs, catalog=review)
        result['package']['topologyRepair'] = {'changes': result.pop('changes')}
        again = repair.apply_repairs(**result, catalog=review)
        self.assertEqual(again['changes'], [])
        for key in result:
            self.assertEqual(again[key], result[key])

    def test_cli_writes_only_four_us_files_and_second_run_changes_nothing(self):
        inputs, review = direction_case()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = {'package': root / 'public/rail/us-2025.json',
                     'stations': root / 'data/stations-us.json',
                     'sections': root / 'data/rail-sections-us.json',
                     'readings': root / 'data/station-readings-us.json'}
            for key, path in paths.items():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(inputs[key]))
            other = root / 'public/rail/ca-2025.json'
            other.write_text('Canadian package untouched\n')
            review_path = root / 'review.json'
            review_path.write_text(json.dumps(review))
            command = [sys.executable, str(HERE / 'repair-na-topology.py'),
                       '--app-root', str(root), '--catalog', str(review_path)]
            baseline = {path: path.read_bytes() for path in paths.values()}
            dry = subprocess.run(command + ['--dry-run'], check=True,
                                 capture_output=True, text=True)
            self.assertEqual(json.loads(dry.stdout)['repairs'], 1)
            self.assertEqual(baseline, {path: path.read_bytes() for path in paths.values()})
            subprocess.run(command, check=True, capture_output=True, text=True)
            first = {path: path.read_bytes() for path in paths.values()}
            rerun = subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertEqual(json.loads(rerun.stdout)['repairs'], 0)
            self.assertEqual(first, {path: path.read_bytes() for path in paths.values()})
            self.assertEqual(other.read_text(), 'Canadian package untouched\n')
            self.assertFalse((root / 'public/rail/na-2025-build-report.json').exists())


if __name__ == '__main__':
    unittest.main()
