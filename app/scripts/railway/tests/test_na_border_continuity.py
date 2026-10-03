"""Country ownership must never delete the surveyed interval at a border."""
import copy
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
from types import SimpleNamespace
import unittest


HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    'na_border_continuity_builder', HERE / 'build-north-america-rail-package.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def surveyed_line(count=4, name='International Railway', line_id='fixture-route'):
    anchors = [[-73.0 + i * .01, 45.0] for i in range(count)]
    intervals = [[list(a), [round((a[0] + b[0]) / 2, 6), 45.001], list(b)]
                 for a, b in zip(anchors, anchors[1:])]
    return {
        'lineId': line_id, 'name': name, 'operator': 'Fixture Operator',
        'feed': 'fixture', 'region': 'us', 'agencyTimezone': 'America/New_York',
        'stationIds': [chr(65 + i) for i in range(count)],
        'stationNames': ['Station ' + chr(65 + i) for i in range(count)],
        'stationZones': ['America/New_York'] * count,
        'stationPoints': copy.deepcopy(anchors), 'anchors': anchors,
        'intervals': intervals, 'isLoop': False, 'kind': 'rail',
        'geometrySource': 'fixture-survey', 'profile': 'commuter',
        'lengthKm': round(sum(builder.geo.line_length(p)
                              for p in intervals) / 1000, 3),
        'rank': 2, 'class': '11', 'institution': '1',
        'color': '#123456', 'colorDark': '#123456',
        'colorReference': '#123456', 'colorSource': 'fixture official palette',
    }


class StationCountries:
    def __init__(self, codes):
        self.codes = codes

    def code_for(self, lon, lat, fallback=None):
        return self.codes[round((lon + 73) / .01)]


def options():
    return SimpleNamespace(geometry_blockers=[], station_complexes={},
                           verified_official_sources={'fixture-survey': {}})


def reconstruct(line):
    previous = None
    intervals = []
    for _, continues, points in line['segments']:
        piece = ([previous] if continues else []) + points
        intervals.append(piece)
        previous = piece[-1]
    return intervals


class BorderContinuityTests(unittest.TestCase):
    def build(self, source, countries):
        opts = options()
        regions = builder.assemble([source], StationCountries(countries), opts)
        result = builder.build_regions(regions, opts, None)
        self.assertEqual(opts.geometry_blockers, [])
        return regions, result

    def assert_complete(self, source, results):
        decoded = [piece for result in results.values()
                   for line in result['lines'] for piece in reconstruct(line)]
        self.assertEqual(len(decoded), len(source['stationIds']) - 1)
        self.assertCountEqual(decoded, source['intervals'])
        for result in results.values():
            self.assertEqual(len(result['stationFeatures']),
                             sum(len(line['stations']) for line in result['lines']))
            self.assertCountEqual(
                [feature['geometry']['coordinates'] for feature in result['sections']],
                [piece for line in result['lines'] for piece in reconstruct(line)])

    def test_crossing_interval_survives_once_with_every_surveyed_vertex(self):
        source = surveyed_line()
        baseline = copy.deepcopy(source)
        regions, results = self.build(source, ['us', 'us', 'ca', 'ca'])
        self.assert_complete(source, results)
        connector = next(line for line in results['us']['lines']
                         if line.get('borderConnector'))
        self.assertEqual(reconstruct(connector), [source['intervals'][1]])
        self.assertEqual(connector['borderConnector']['stationCountries'], ['us', 'ca'])
        self.assertEqual(connector['operator'], source['operator'])
        self.assertEqual(connector['name'], source['name'])
        self.assertEqual(connector['geometrySource'], source['geometrySource'])
        domestic = {line['id']: line for result in results.values()
                    for line in result['lines'] if not line.get('borderConnector')}
        self.assertEqual(connector['stations'][0][0], domestic['fixture-route-us']['stations'][-1][0])
        self.assertEqual(connector['stations'][1][0], domestic['fixture-route-ca']['stations'][0][0])
        self.assertTrue(connector['stations'][1][0].startswith('ca-'))
        self.assertEqual(source, baseline)

    def test_single_foreign_terminus_keeps_country_identity_and_surveyed_track(self):
        source = surveyed_line(3)
        regions, results = self.build(source, ['us', 'us', 'ca'])
        self.assert_complete(source, results)
        self.assertEqual(results['ca']['lines'], [])
        self.assertEqual(results['ca']['stationFeatures'], [])
        self.assertTrue(regions['ca'][0]['_stationOnly'])
        connector = next(line for line in results['us']['lines']
                         if line.get('borderConnector'))
        self.assertEqual(connector['stations'][1][1], 'Station C')
        self.assertTrue(connector['stations'][1][0].startswith('ca-'))
        foreign = next(feature for feature in results['us']['stationFeatures']
                       if feature['properties']['station_name'] == 'Station C')
        self.assertTrue(foreign['properties']['n02_station_code'].startswith('CA-'))
        self.assertEqual(foreign['properties']['n02_group_code'], connector['stations'][1][0])
        self.assertEqual(foreign['properties']['display_point'], source['anchors'][2])

    def test_one_station_country_run_is_not_absorbed_or_dropped(self):
        source = surveyed_line(3)
        self.assertEqual(builder.split_line_by_country(
            source, StationCountries(['us', 'ca', 'us']), 'us'),
            [('us', 0, 0), ('ca', 1, 1), ('us', 2, 2)])
        _, results = self.build(source, ['us', 'ca', 'us'])
        self.assert_complete(source, results)
        connectors = [line for result in results.values() for line in result['lines']]
        self.assertEqual(len(connectors), 2)
        self.assertEqual(connectors[0]['stations'][1][0], connectors[1]['stations'][0][0])
        self.assertTrue(connectors[0]['stations'][1][0].startswith('ca-'))

    def test_reverse_crossing_is_owned_once_by_departure_country(self):
        source = surveyed_line()
        _, results = self.build(source, ['ca', 'ca', 'us', 'us'])
        self.assert_complete(source, results)
        self.assertEqual(sum(bool(line.get('borderConnector'))
                             for line in results['ca']['lines']), 1)
        self.assertFalse(any(line.get('borderConnector') for line in results['us']['lines']))

    def test_domestic_line_keeps_its_original_identity_and_geometry(self):
        source = surveyed_line()
        regions, results = self.build(source, ['us'] * 4)
        self.assertIs(regions['us'][0], source)
        self.assertEqual(results['us']['lines'][0]['id'], 'fixture-route')
        self.assert_complete(source, results)

    def test_connector_reuses_reviewed_country_transfer_complex(self):
        source = surveyed_line()
        opts = options()
        opts.station_complexes = {
            'ca-official-reviewed-station-c': {
                'absorbs': ['ca-official-c'], 'center': source['anchors'][2],
                'maxMeters': 20, 'name': 'Reviewed Station C',
            }
        }
        regions = builder.assemble([source], StationCountries(['us', 'us', 'ca', 'ca']), opts)
        results = builder.build_regions(regions, opts, None)
        domestic = results['ca']['lines'][0]['stations'][0]
        connector = next(line for line in results['us']['lines'] if line.get('borderConnector'))
        self.assertEqual(connector['stations'][1][:2], domestic[:2])
        self.assertEqual(domestic[:2], ['ca-official-reviewed-station-c', 'Reviewed Station C'])

    def test_slice_remaps_interval_evidence_without_smoothing_track(self):
        source = surveyed_line()
        source['straightSurvey'] = {
            'intervals': [0, 1, 2],
            'records': [{'interval': i, 'basis': 'accepted-survey'} for i in range(3)],
        }
        source['needsRegroom'] = True
        sliced = builder.slice_line(source, 1, 2, 'us', '-border1')
        self.assertEqual(sliced['intervals'], [source['intervals'][1]])
        self.assertEqual(sliced['straightSurvey']['intervals'], [0])
        self.assertEqual(sliced['straightSurvey']['records'][0]['interval'], 0)
        self.assertNotIn('needsRegroom', sliced)

    def test_reviewed_country_operators_keep_exact_local_brands_and_geometry(self):
        source = surveyed_line()
        entry = {
            'operatorByCountryByRouteId': {'31849': {'us': 'Amtrak', 'ca': 'Via Rail Canada'}},
            'operatorByCountryEvidenceByRouteId': {'31849': [
                'Amtrak GTFS route 68 agency 51 and route 31849 agency 157',
                'Amtrak Maple Leaf and VIA Toronto-Niagara operator publications',
            ]},
            'operatorLogos': {'Amtrak': '/rail/operator-logos/na/amtrak.png',
                              'Via Rail Canada': '/rail/operator-logos/na/via.png'},
        }
        source.update(builder.reviewed_country_operators(entry, '31849'))
        baseline = copy.deepcopy(source['intervals'])
        _, results = self.build(source, ['us', 'us', 'ca', 'ca'])
        for region, operator, logo in [
                ('us', 'Amtrak', '/rail/operator-logos/na/amtrak.png'),
                ('ca', 'Via Rail Canada', '/rail/operator-logos/na/via.png')]:
            for line in results[region]['lines']:
                self.assertEqual(line['operator'], operator)
                self.assertEqual(line['operatorLogo'], logo)
                self.assertEqual(line['brandStatus'], 'audited-logo')
                self.assertEqual(line['operatorCountryEvidence']['country'], region)
                self.assertEqual(line['operatorCountryEvidence']['evidence'],
                                 entry['operatorByCountryEvidenceByRouteId']['31849'])
        self.assertEqual(source['intervals'], baseline)
        self.assert_complete(source, results)

    def test_country_operator_override_requires_evidence_and_approved_logos(self):
        entry = {'operatorByCountryByRouteId': {'68': {'us': 'Amtrak', 'ca': 'Via Rail Canada'}}}
        with self.assertRaisesRegex(ValueError, 'requires evidence'):
            builder.reviewed_country_operators(entry, '68')
        entry['operatorByCountryEvidenceByRouteId'] = {'68': ['Official operator evidence']}
        with self.assertRaisesRegex(ValueError, 'lacks approved operatorLogos'):
            builder.reviewed_country_operators(entry, '68')
        self.assertEqual(builder.reviewed_country_operators(entry, 'other-route'), {})

    def test_route_name_aliases_apply_to_country_operator_maps(self):
        entry = {'operatorByCountryByRouteId': {'Maple Leaf': {'us': 'Amtrak', 'ca': 'Via Rail Canada'}},
                 'operatorByCountryEvidenceByRouteId': {'Maple Leaf': ['Official operators']}}
        resolved = builder.resolve_route_keys(entry, [{'route_id': '31849',
                                                     'route_long_name': 'Maple Leaf'}])
        self.assertIn('31849', resolved['operatorByCountryByRouteId'])
        self.assertIn('31849', resolved['operatorByCountryEvidenceByRouteId'])

    @unittest.skipUnless(shutil.which('node'), 'Node is required for the actual Web client decoder')
    def test_real_web_client_decodes_and_indexes_foreign_endpoint(self):
        source = surveyed_line(3)
        _, results = self.build(source, ['us', 'us', 'ca'])
        package = {'format': 'compact-v1', 'country': 'US',
                   'timeZones': results['us']['zones'], 'lines': results['us']['lines']}
        script = r'''
const fs = require('node:fs');
const api = require(process.argv[1]);
const pkg = JSON.parse(fs.readFileSync(0, 'utf8'));
const network = api.buildNetworkFromCompactPackage(pkg);
const connector = pkg.lines.find(line => line.borderConnector);
process.stdout.write(JSON.stringify({
  decoded: api.decodeIntervals(connector),
  indexed: [...network.stationById.values()].some(station =>
    station.stationGroupId === connector.stations[1][0]),
  lineCount: network.lineById.size
}));
'''
        client = HERE.parents[1] / 'public' / 'rail-network.js'
        process = subprocess.run(['node', '-e', script, str(client)],
                                 input=json.dumps(package), text=True, capture_output=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        answer = json.loads(process.stdout)
        self.assertEqual(answer['decoded'], [source['intervals'][1]])
        self.assertTrue(answer['indexed'])
        self.assertEqual(answer['lineCount'], 2)


if __name__ == '__main__':
    unittest.main()
