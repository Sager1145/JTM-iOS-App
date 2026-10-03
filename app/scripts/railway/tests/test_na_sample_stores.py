import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'make-na-sample-stores.py'))
SPEC = importlib.util.spec_from_file_location('na_sample_stores', SCRIPT)
samples = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(samples)


class CrossBorderSampleTests(unittest.TestCase):
    def test_scoped_repair_preserves_unrelated_samples_and_appends_new_one(self):
        unchanged = {'id': 'historic', 'stops': ['original']}
        repaired = {'id': 'border', 'stops': ['surveyed']}
        added = {'id': 'cascades'}
        result = samples.replace_samples([unchanged, {'id': 'border'}],
                                         [repaired, added], {'border', 'cascades'})
        self.assertEqual(result, [unchanged, repaired, added])
        self.assertIs(result[0], unchanged)

    def test_scoped_repair_rejects_missing_replacement(self):
        with self.assertRaisesRegex(ValueError, 'missing or duplicated'):
            samples.replace_samples([], [], {'border'})

    def fixture(self):
        stations = [
            ['us-official-a', 'Albany', -73.0, 45.0],
            ['us-official-b', 'Rouses Point', -72.99, 45.0],
            ['ca-official-c', 'St-Lambert', -72.98, 45.0],
            ['ca-official-d', 'Montréal', -72.97, 45.0],
        ]
        lines = []
        for index, line_id in enumerate(['train-us', 'train-border1', 'train-ca']):
            start, end = stations[index:index + 2]
            geometry = [start[2:], [(start[2] + end[2]) / 2, 45.001], end[2:]]
            lines.append({
                'id': line_id, 'name': 'International', 'operator': 'Railway',
                'color': '#123456', 'stations': [start, end],
                'segments': [[1.0, 0, geometry]],
            })
        lines[1]['borderConnector'] = {'stationCountries': ['us', 'ca'],
                                      'sourceLineId': 'train', 'sourceInterval': 1,
                                      'evidence': 'Fixture surveyed interval'}
        codes = {'International': {row[0]: row[0].split('-')[0].upper() + '-FEED-' + row[0]
                                   for row in stations}}
        spec = {
            'id': 'cross-border', 'date': '2026-01-01', 'number': '1',
            'trainType': 'intercity',
            'lines': [
                {'id': 'train-us', 'from': 'Albany', 'to': 'Rouses Point'},
                {'id': 'train-border1', 'from': 'Rouses Point', 'to': 'St-Lambert'},
                {'id': 'train-ca', 'from': 'St-Lambert', 'to': 'Montréal'},
            ],
        }
        return {'lines': lines}, codes, spec

    def test_explicit_surveyed_border_interval_is_written_once(self):
        package, codes, spec = self.fixture()
        result = samples.journey(package, codes, spec, 'us')
        self.assertIsNotNone(result)
        self.assertEqual([stop['name'] for stop in result['stops']],
                         ['Albany', 'Rouses Point', 'St-Lambert', 'Montréal'])
        self.assertEqual(len(result['route_sections']), 3)
        border = result['route_sections'][1]
        self.assertTrue(border['from_n02_station_code'].startswith('US-'))
        self.assertTrue(border['to_n02_station_code'].startswith('CA-'))
        self.assertTrue(all(
            section['from_n02_station_code'] != section['to_n02_station_code']
            for section in result['route_sections']))
        self.assertFalse(result['route_policy']['allow_browser_straight_line_fallback'])

    def test_reverse_connector_keeps_ordered_canonical_country_codes(self):
        package, codes, spec = self.fixture()
        spec['lines'] = [dict(part, **{'from': part['to'], 'to': part['from']})
                         for part in reversed(spec['lines'])]
        result = samples.journey(package, codes, spec, 'ca')
        self.assertEqual([stop['name'] for stop in result['stops']],
                         ['Montréal', 'St-Lambert', 'Rouses Point', 'Albany'])
        border = result['route_sections'][1]
        self.assertTrue(border['from_n02_station_code'].startswith('CA-'))
        self.assertTrue(border['to_n02_station_code'].startswith('US-'))

    def test_missing_border_part_is_rejected_instead_of_inventing_an_interval(self):
        package, codes, spec = self.fixture()
        del spec['lines'][1]
        self.assertIsNone(samples.journey(package, codes, spec, 'us'))

    def test_missing_border_geometry_is_rejected(self):
        package, codes, spec = self.fixture()
        package['lines'][1]['segments'] = []
        self.assertIsNone(samples.journey(package, codes, spec, 'us'))

    def test_missing_border_line_is_rejected(self):
        package, codes, spec = self.fixture()
        del package['lines'][1]
        self.assertIsNone(samples.journey(package, codes, spec, 'us'))

    def test_foreign_station_is_never_deduplicated_by_proximity(self):
        package, codes, spec = self.fixture()
        # Two real stations with distinct country identities, less than 20 m
        # apart. Only their accepted geometry can connect them.
        package['lines'][1]['stations'][1][2] = -72.98999
        package['lines'][1]['segments'][0][2][-1] = [-72.98999, 45.0]
        package['lines'][2]['segments'][0][2][0] = [-72.98999, 45.0]
        result = samples.journey(package, codes, spec, 'us')
        self.assertEqual(len(result['stops']), 4)
        self.assertEqual(len(result['route_sections']), 3)

    def test_matching_code_with_broken_geometry_anchor_is_rejected(self):
        package, codes, spec = self.fixture()
        package['lines'][1]['segments'][0][2][0] = [-72.989, 45.0]
        self.assertIsNone(samples.journey(package, codes, spec, 'us'))

    def test_compact_continuation_reconstructs_its_surveyed_first_vertex(self):
        line = {'segments': [
            [1, 0, [[1, 2], [2, 3]]], [1, 1, [[3, 4], [4, 5]]],
        ]}
        self.assertEqual(samples.decoded_intervals(line),
                         [[[1, 2], [2, 3]], [[2, 3], [3, 4], [4, 5]]])
        self.assertIsNone(samples.decoded_intervals({'segments': [[1, 1, [[1, 2]]]]}))

    @unittest.skipUnless(shutil.which('node'), 'Actual Web solver requires Node')
    def test_actual_web_graph_solver_uses_the_surveyed_border(self):
        package, codes, spec = self.fixture()
        train = samples.journey(package, codes, spec, 'us')
        features = []
        stations = []
        for line in package['lines']:
            piece = line['segments'][0][2]
            features.append({'type': 'Feature', 'geometry': {
                'type': 'LineString', 'coordinates': piece},
                'properties': {'line_name': line['name'], 'operator': line['operator'],
                               'institution_type_code': '1', 'railway_class_code': '11'}})
            for row in line['stations']:
                stations.append({'type': 'Feature', 'geometry': {
                    'type': 'LineString', 'coordinates': [row[2:], row[2:]]},
                    'properties': {'station_name': row[1],
                                   'n02_station_code': codes[line['name']][row[0]],
                                   'n02_group_code': row[0], 'display_point': row[2:],
                                   'line_name': line['name'], 'operator': line['operator'],
                                   'institution_type_code': '1'}})
        answers = solve_with_actual_web_client(train, features, stations)
        self.assertEqual(len(answers), 3)
        self.assertTrue(all(answer is not None for answer in answers))
        self.assertEqual(answers[1]['geometry']['coordinates'],
                         package['lines'][1]['segments'][0][2])

    @unittest.skipUnless(os.environ.get('NA_BORDER_SAMPLE_TEST_DIR') and shutil.which('node'),
                         'Set NA_BORDER_SAMPLE_TEST_DIR to scoped repaired package/data outputs')
    def test_all_three_actual_services_keep_boundary_sections_and_solve(self):
        root = Path(os.environ['NA_BORDER_SAMPLE_TEST_DIR'])
        package_dir = root / 'public'
        if (package_dir / 'rail').is_dir():
            package_dir /= 'rail'
        package, codes = samples.load(
            [package_dir / f'{country}-2025.json' for country in ['us', 'ca']],
            [root / 'data' / f'stations-{country}.json' for country in ['us', 'ca']])
        sections, stations = [], []
        for country in ['us', 'ca']:
            sections += json.loads((root / 'data' / f'rail-sections-{country}.json').read_text())['features']
            stations += json.loads((root / 'data' / f'stations-{country}.json').read_text())['features']
        routes = [
            ('Adirondack', 'us', [('amtrak-adirondack-us', True),
                                  ('amtrak-adirondack-border1', True),
                                  ('amtrak-adirondack-ca', True)]),
            ('Maple Leaf', 'ca', [('amtrak-maple-leaf-ca', True),
                                  ('amtrak-maple-leaf-border1', True),
                                  ('amtrak-maple-leaf-us', True)]),
            ('Cascades', 'us', [('amtrak-amtrak-cascades-us', False),
                                ('amtrak-amtrak-cascades-border1', False)]),
        ]
        for name, region, parts in routes:
            with self.subTest(service=name):
                spec = {'id': 'SAMPLE-' + name.replace(' ', '-'), 'date': '2026-09-30',
                        'number': name, 'trainType': 'Amtrak', 'lines': []}
                border = None
                for line_id, reverse in parts:
                    line = samples.line_by_id(package, line_id)
                    self.assertIsNotNone(line)
                    spec['lines'].append({'id': line_id,
                                          'from': line['stations'][-1 if reverse else 0][0],
                                          'to': line['stations'][0 if reverse else -1][0]})
                    if line.get('borderConnector'):
                        border = (line, reverse)
                train = samples.journey(package, codes, spec, region)
                self.assertIsNotNone(train)
                # RegionScopeRule reads these canonical prefixes, in journey
                # order, from both stops and sections for its touched regions.
                touched = list(dict.fromkeys(stop['n02_station_code'].split('-')[0].lower()
                                             for stop in train['stops']))
                self.assertEqual(touched, [region, 'ca' if region == 'us' else 'us'])
                self.assertEqual(len(train['route_sections']), len(train['stops']) - 1)
                line, reverse = border
                rows = list(reversed(line['stations'])) if reverse else line['stations']
                pair = [codes[line['name']][row[0]] for row in rows]
                matching = [(index, section) for index, section in enumerate(train['route_sections'])
                            if [section['from_n02_station_code'], section['to_n02_station_code']] == pair]
                self.assertEqual(len(matching), 1)
                solved = solve_with_actual_web_client(train, sections, stations)
                self.assertTrue(all(feature is not None for feature in solved))
                boundary = solved[matching[0][0]]['geometry']['coordinates']
                surveyed = samples.decoded_intervals(line)[0]
                if reverse:
                    surveyed = list(reversed(surveyed))
                self.assertGreater(len(boundary), 2)
                self.assertGreaterEqual(len(boundary), .9 * len(surveyed))
                for actual, expected in [(boundary[0], surveyed[0]),
                                         (boundary[-1], surveyed[-1])]:
                    self.assertLess(samples.distance_metres(actual, expected), 2)


def solve_with_actual_web_client(train, sections, stations):
    """The production graph, station resolver and Dijkstra from their real files."""
    script = r'''
const fs = require('node:fs'), path = require('node:path');
const app = process.argv[1], input = JSON.parse(fs.readFileSync(0, 'utf8'));
const files = ['app-operator-branding.js', 'railmap-basemap.js', 'railmap-style.js',
  'app-coords.js', 'app-config.js', 'app-route-simplify.js', 'app-scheduling.js', 'app-datasets.js',
  'app-state.js', 'app-stations.js', 'app-store-ops.js', 'app-route-features.js',
  'app-rail-history.js', 'app-route-graph.js', 'app-route-solver.js'];
const source = files.map(file => fs.readFileSync(path.join(app, 'public', file), 'utf8')).join('\n');
const js = new Function('window', source + `
configureStationRouteResolver({ allowedInstitutionCodes: getAllowedInstitutionTypeCodes,
  filterPreferredStations: filterStationsByPreferredInstitution, distanceMeters });
configureRouteSolverApi({ addStationTransferConnectorEdges, coordKey, coordinatesClose,
  distanceMeters, graphGridKey, normalizeGraphCoord, pathLengthForCoordinates,
  resolveEndpointCandidates: resolveRouteEndpointStationCandidates,
  solveSection: solveRouteSectionOnN02Graph });
configureRouteGraphApi({ allowedInstitutionCodes: getAllowedInstitutionTypeCodes,
  intersects, keyDigest: routeKeyDigest, nearbyNodes: nearbyGraphNodes,
  preferredOperatorNames: derivedPreferredOperatorNames,
  resolveSectionEndpoints, templateKey: getTrainRouteTemplateKey });
return { install: async (sections, stations) => { activeCountry = 'us';
  AppDatasets.installRailSections(sections); AppDatasets.installStations(stations);
  await buildStationIndexesSliced(stations); }, stationNameForCode, buildRouteGraphFromFeatures,
  addStationTransferConnectorEdges, solveRouteSectionOnN02Graph,
  getAllowedInstitutionTypeCodes };`)({
  AppCore: require(path.join(app, 'shared', 'app-core.js')),
  RailNetwork: require(path.join(app, 'public', 'rail-network.js')) });
async function run() {
await js.install({type:'FeatureCollection', features:input.sections},
           {type:'FeatureCollection', features:input.stations});
const graph=js.buildRouteGraphFromFeatures(input.sections);
js.addStationTransferConnectorEdges(graph, input.stations);
const allowed=js.getAllowedInstitutionTypeCodes(input.train);
let continuity=null;
const solved=input.train.route_sections.map((raw,index)=>{
  const section={...raw, from:js.stationNameForCode(raw.from_n02_station_code),
                        to:js.stationNameForCode(raw.to_n02_station_code)};
  const result=js.solveRouteSectionOnN02Graph(section,index,input.train,graph,allowed,continuity);
  if(result?.geometry?.coordinates?.length)continuity=result.geometry.coordinates.at(-1);
  return result;
});
process.stdout.write(JSON.stringify(solved));
}
run().catch(error => { console.error(error); process.exitCode = 1; });
'''
    app = Path(SCRIPT).resolve().parents[2]
    result = subprocess.run(['node', '-e', script, str(app)],
                            input=json.dumps({'train': train, 'sections': sections,
                                              'stations': stations}),
                            capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(result.stderr)
    return json.loads(result.stdout)


if __name__ == '__main__':
    unittest.main()
