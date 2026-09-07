import importlib.util
import json
import os
import sys
import tempfile
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-caltrans-official-networks.py'))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
SPEC = importlib.util.spec_from_file_location('caltrans_official', SCRIPT)
caltrans = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(caltrans)
import na_provenance

REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def feature(operator, network, status=1):
    return {
        'type': 'Feature',
        'properties': {'COMM_OP': operator, 'COMM_NETWO': network,
                       'STATUS': status},
        'geometry': {'type': 'LineString',
                     'coordinates': [[-122.4, 37.7], [-122.3, 37.8]]},
    }


class WestStrictOfficialTests(unittest.TestCase):
    def test_caltrans_selection_is_exact_and_operational(self):
        rows = [feature('PCJPB', 'Caltrain'),
                feature('PCJPB,SJRRC', 'ACE,Caltrain'),
                feature('SDTI', 'San Diego Light Rail Trolley (Blue Line)'),
                feature('SDTI', 'San Diego Light Rail Trolley (Orange Line)'),
                feature('SDTI', 'San Diego Light Rail Trolley (Green Line)'),
                feature('PCJPB', 'Caltrain', status=2)]
        rows.extend(feature(' ', ' ') for _ in range(2_000))

        groups = caltrans.route_groups({'features': rows})

        self.assertEqual(len(groups['caltrans-caltrain']), 2)
        self.assertEqual(len(groups['caltrans-sd-blue']), 1)
        self.assertEqual(len(groups['caltrans-sd-orange']), 1)

    def test_manifest_merge_preserves_other_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, 'manifest.json'), 'w') as output:
                json.dump({'schemaVersion': 1,
                           'sources': {'mta': {'publisher': 'MTA'}},
                           'files': {'mta-a': {'file': 'a.geojson'}}}, output)
            manifest = caltrans.load_manifest(directory)
        self.assertIn('mta', manifest['sources'])
        self.assertIn('mta-a', manifest['files'])

    def test_caltrain_and_san_diego_are_exact_and_fail_closed(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        caltrain = next(row for row in feeds if row['slug'] == 'caltrain')
        mts = next(row for row in feeds
                   if row['slug'] == 'san-diego-international-airp')
        self.assertTrue(caltrain['requireVerifiedOfficialNetwork'])
        self.assertTrue(caltrain['requireOfficialMappingForAllRoutes'])
        self.assertTrue(caltrain['forbidOfficialNetworkFallback'])
        self.assertEqual(set(caltrain['officialNetworkByRouteId']),
                         {'77119', '77120', '77121', '77122', '77123'})
        self.assertEqual(mts['officialNetworkByRouteId'], {
            '510': 'caltrans-sd-blue', '520': 'caltrans-sd-orange'})
        # The San Diego half of the Caltrans layer is stale — 23 of the Blue
        # Line's 66 published stops are unreachable on it and the Mid-Coast
        # extension is missing — so it is declared defective for those two
        # routes and MTS ships from its own published alignment instead.
        self.assertEqual(set(mts['officialNetworkDefectByRouteId']),
                         {'510', '520'})
        self.assertEqual(set(mts['blockedRouteIds']), {'540'})
        self.assertEqual(set(mts['geometryReviewByRouteId']),
                         {'535', '530', '550'})

    def test_remaining_west_routes_are_explicitly_blocked(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        expected = {
            'regional-transportation-dist': 10,
            'sacramento-regional-transit': 3,
            'suntran': 3,
            'trimet-portland-streetcar': 9,
            'valley-metro-vm': 4,
        }
        # None of these five has an official surveyed centreline, so there
        # is no mapping to require and nothing to declare defective: each
        # route ships from the operator's own alignment carrying the reason
        # its verification is incomplete.
        for slug, count in expected.items():
            feed = next(row for row in feeds if row['slug'] == slug)
            self.assertEqual(len(feed['geometryReviewByRouteId']), count)

    def test_sound_and_vta_known_failures_are_blocked(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        sound = next(row for row in feeds if row['slug'] == 'sound-transit')
        vta = next(row for row in feeds
                   if row['slug'] == 'santa-clara-valley-transport')
        self.assertEqual(set(sound['blockedRouteIds']),
                         {'100479', '2LINE', 'SNDR_TL'})
        self.assertEqual(set(sound['referenceValidatedGeometryByRouteId']),
                         {'SNDR_EV', 'TLINE'})
        self.assertNotIn('officialNetworkByRouteId', sound)
        self.assertEqual(set(vta['officialNetworkDefectByRouteId']), {'Blue', 'Green'})

    def test_caltrans_provenance_is_exact(self):
        for key in ('caltrans-caltrain', 'caltrans-sd-blue',
                    'caltrans-sd-orange'):
            self.assertEqual(na_provenance.KEY_SOURCE_EXACT[key],
                             'caltrans-crn')


if __name__ == '__main__':
    unittest.main()
