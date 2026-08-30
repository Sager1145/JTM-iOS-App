import importlib.util
import json
import os
import sys
import tempfile
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-ca-central-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
SPEC = importlib.util.spec_from_file_location('ca_central_official', SCRIPT)
central = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(central)
import na_provenance

REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def record(track_class='Main', status='Operational', area='Ontario'):
    return ({'TRACKCLASS': track_class, 'STATUS': status,
             'ADMINAREA': area, 'GEOACQTECH': 'Orthoimage',
             'GEOACCURA': 10, 'GEOPROVIDE': 'Provincial/Territorial'},
            [[[-79.40, 43.64], [-79.39, 43.65]]])


class CanadaCentralOfficialNetworkTests(unittest.TestCase):
    def test_orwn_route_selection_is_isolated_and_fail_closed(self):
        shapes = {'BR': [[[-79.40, 43.64], [-79.39, 43.65]]]}
        groups = central.route_groups([
            record(), record(status='Abandoned'), record(track_class='Yard'),
            record(area='Manitoba'),
        ], shapes, {'UP': shapes['BR']})
        self.assertEqual(set(groups), {'orwn-go-br', 'orwn-up-up'})
        self.assertTrue(all(len(rows) == 1 for rows in groups.values()))
        for rows in groups.values():
            self.assertEqual(rows[0]['properties']['GEOACQTECH'], 'Orthoimage')

    def test_manifest_merge_preserves_other_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, 'manifest.json'), 'w') as output:
                json.dump({'schemaVersion': 1,
                           'sources': {'mta': {'publisher': 'MTA'}},
                           'files': {'mta-subway-a': {'file': 'a.geojson'}}},
                          output)
            manifest = central.load_manifest(directory)
        self.assertIn('mta', manifest['sources'])
        self.assertIn('mta-subway-a', manifest['files'])

    def test_go_and_up_exact_mappings_require_verified_orwn(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        go = next(row for row in feeds if row['slug'] == 'go-transit')
        up = next(row for row in feeds
                  if row['slug'] == 'union-pearson-express-up-exp')
        self.assertTrue(go['requireVerifiedOfficialNetwork'])
        self.assertTrue(go['requireOfficialMappingForAllRoutes'])
        self.assertTrue(go['preserveRouteIds'])
        self.assertEqual(len(go['mergeRouteIdGroups']), 7)
        self.assertEqual(go['officialNetworkByRouteId']['06260926-GT'],
                         'orwn-go-ki')
        self.assertEqual(go['officialNetworkByRouteId']['09261126-LW'],
                         'orwn-go-lw')
        self.assertTrue(up['requireVerifiedOfficialNetwork'])
        self.assertEqual(up['officialNetworkByRouteId'],
                         {'UP': 'orwn-up-up'})
        self.assertIn('UP', up['blockedRouteIds'])
        self.assertIn('near-reversals', up['blockedRouteIds']['UP'])

    def test_quebec_routes_remain_blocked_without_independent_geometry(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        expected = {
            'exo': {'1', '3', '4', '5', '6'},
            'rem': {'S1', 'S2', 'S3'},
            'soci-t-de-transport-de-montr': {'1', '2', '4', '5'},
        }
        for slug, route_ids in expected.items():
            feed = next(row for row in feeds if row['slug'] == slug)
            self.assertTrue(feed['requireOfficialMappingForAllRoutes'])
            self.assertEqual(set(feed['blockedRouteIds']), route_ids)

    def test_orwn_provenance_is_exact_not_prefix_based(self):
        self.assertEqual(central.SOURCE['url'], (
            'https://ws.gisetl.lrc.gov.on.ca/fmedatadownload/Packages/'
            'ORWNTRK.zip'))
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['orwn-go-br'],
                         'ontario-orwn')
        self.assertEqual(na_provenance.KEY_SOURCE_EXACT['orwn-up-up'],
                         'ontario-orwn')
        self.assertNotIn('orwn-', na_provenance.KEY_SOURCE_PREFIXES)


if __name__ == '__main__':
    unittest.main()
