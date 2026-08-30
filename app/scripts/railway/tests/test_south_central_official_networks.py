import importlib.util
import json
import os
import sys
import tempfile
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-south-central-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
SPEC = importlib.util.spec_from_file_location('south_central', SCRIPT)
networks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(networks)
ATI_SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'download-puerto-rico-official.py'))
ATI_SPEC = importlib.util.spec_from_file_location('ati_official', ATI_SCRIPT)
ati = importlib.util.module_from_spec(ATI_SPEC)
ATI_SPEC.loader.exec_module(ati)
import na_provenance

REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def feature(properties, coordinates=None):
    return {'type': 'Feature', 'properties': properties,
            'geometry': {'type': 'LineString', 'coordinates': coordinates or [
                [-80.8, 35.2], [-80.79, 35.21],
            ]}}


class SouthCentralOfficialNetworkTests(unittest.TestCase):
    def feeds(self):
        with open(REGISTRY, encoding='utf-8') as source:
            return {row['slug']: row for row in json.load(source)['feeds']}

    def test_route_selection_excludes_parallel_and_future_tracks(self):
        parsed = {
            'cats-blue-line': [
                feature({'TrackDescr': 'NorthBound-Track 1'}),
                feature({'TrackDescr': 'BLE Northbound-Track 1'}),
                feature({'TrackDescr': 'Southbound-Track 2'}),
                feature({'TrackDescr': 'BLE Southbound-Track 2'}),
            ],
            'dcgis-streetcar': [
                feature({'LINE_STATUS': 'Active',
                         'LINE': 'Union Station - Benning Rd',
                         'DIRECTION': 'To Union Station'}),
                feature({'LINE_STATUS': 'Active',
                         'LINE': 'Union Station - Benning Rd',
                         'DIRECTION': 'To Benning Rd'}),
            ],
            'fdot-brightline': [
                feature({'PASSENGER': 'Brightline'}),
                feature({'PASSENGER': 'Other'}),
            ],
            'fdot-sunrail': [
                feature({'COMMUTERRL': 'SunRail', 'RRCO': 'CSX'}),
                feature({'COMMUTERRL': 'SunRail', 'RRCO': 'ORUZ'}),
            ],
        }
        groups = networks.route_groups(parsed)
        self.assertEqual(len(groups['cats-blue']), 2)
        self.assertEqual(len(groups['dc-streetcar']), 2)
        self.assertEqual(len(groups['fdot-brightline']), 1)
        self.assertEqual(len(groups['fdot-sunrail']), 1)

    def test_simplification_and_densification_preserve_authority(self):
        line = [[-80.8, 35.2], [-80.79999, 35.20001], [-80.7, 35.3]]
        result = networks.normalized_feature(
            feature({}, line), simplify_m=0.5)['geometry']['coordinates']
        self.assertEqual(result[0], line[0])
        self.assertEqual(result[-1], line[-1])
        self.assertGreater(len(result), 3)
        # RDP chooses only source vertices; densification then stays on the
        # exact retained government segments rather than inventing curves.
        retained = networks.geo.simplify(networks.geo.dedupe(line), 0.5)
        for point in retained:
            self.assertIn(point, result)

    def test_manifest_merge_preserves_unrelated_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, 'manifest.json'), 'w') as output:
                json.dump({'schemaVersion': 1,
                           'sources': {'mta': {'publisher': 'MTA'}},
                           'files': {'mta-subway-a': {'file': 'a.geojson'}}},
                          output)
            manifest = networks.load_manifest(directory)
        self.assertIn('mta', manifest['sources'])
        self.assertIn('mta-subway-a', manifest['files'])

    def test_exact_registry_mappings_and_fail_closed_blockers(self):
        feeds = self.feeds()
        cats = feeds['charlotte-area-transit-syste']
        self.assertEqual(cats['officialNetworkByRouteId'],
                         {'501': 'cats-blue'})
        self.assertEqual(set(cats['blockedRouteIds']), {'510'})
        self.assertEqual(cats['officialColorByRouteId'], {'501': '004DA8'})
        self.assertTrue(cats['requireVerifiedOfficialNetwork'])
        self.assertTrue(cats['requireOfficialMappingForAllRoutes'])
        self.assertEqual(feeds['dc-streetcar']['officialNetworkByRouteId'],
                         {'12420': 'dc-streetcar'})
        self.assertEqual(feeds['brightline-trains-llc']
                         ['officialNetworkByRouteId'],
                         {'1': 'fdot-brightline'})
        self.assertEqual(feeds['florida-department-of-transp']
                         ['officialNetworkByRouteId'],
                         {'1': 'fdot-sunrail'})
        self.assertEqual(set(feeds['dallas-area-rapid-transit-da']
                             ['blockedRouteIds']), {
            '27224', '27243', '27251', '27252', '27253', '27254', '27255',
            '27257'})
        self.assertEqual(set(feeds['fort-worth-transit-authority']
                             ['blockedRouteIds']), {'8305'})
        self.assertEqual(set(feeds['hampton-roads-transit-hrt']
                             ['blockedRouteIds']), {'800'})
        self.assertEqual(set(feeds['puerto-rico-ati']
                             ['blockedRouteIds']), {'TU'})

    def test_provenance_keys_are_exact_not_prefix_based(self):
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['cats-blue'],
                         'cats-blue-line')
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['dc-streetcar'],
                         'dcgis-streetcar')
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['fdot-brightline'],
                         'fdot-brightline')
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['fdot-sunrail'],
                         'fdot-sunrail')
        for prefix in ('cats-', 'dc-', 'fdot-'):
            self.assertNotIn(prefix, na_provenance.KEY_SOURCE_PREFIXES)

    def test_ati_gtfs_derived_shp_is_not_accepted_as_independent(self):
        with self.assertRaises(SystemExit):
            ati.assert_independent({
                'map_name': 'PRITA_GTFS_16MAY2025',
                'url': 'https://platform.remix.com/project/example',
            })


if __name__ == '__main__':
    unittest.main()
