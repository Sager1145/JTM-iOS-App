import importlib.util
import json
import os
import unittest


HERE = os.path.dirname(__file__)
REGISTRY = os.path.abspath(os.path.join(HERE, '..', 'na-feeds.json'))
BUILDER_PATH = os.path.abspath(os.path.join(
    HERE, '..', 'build-north-america-rail-package.py'))
AUDIT_PATH = os.path.abspath(os.path.join(HERE, '..', 'audit-na-package.py'))


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load_module('east_station_builder', BUILDER_PATH)
audit = load_module('east_station_audit', AUDIT_PATH)


class EastStationSplitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            cls.registry = json.load(source)
        cls.feeds = {row['slug']: row for row in cls.registry['feeds']}

    def test_only_reviewed_bad_geometry_routes_are_blocked(self):
        mta = self.feeds['metropolitan-transit-authori']
        # Q's officialNetworkDefectByRouteId entry was removed: the fresh
        # mta-subway-service-q official network now builds Q cleanly (34
        # stations, 28.8 km) once na_lines.py accepts a preferred trunk in
        # either orientation, so there is no longer a defect to register.
        self.assertNotIn('officialNetworkDefectByRouteId', mta)
        self.assertEqual(mta['officialNetworkByRouteId']['E'],
                         'mta-subway-service-e')
        self.assertEqual(mta['officialNetworkByRouteId']['F'],
                         'mta-subway-service-f')
        path = self.feeds['port-authority-trans-hudson']
        self.assertEqual(set(path['officialNetworkDefectByRouteId']), {'862'})
        self.assertIn('26728', path['officialNetworkDefectByRouteId']['862'])
        septa = self.feeds['septa']
        # B1 and L1's officialNetworkDefectByRouteId entries were removed:
        # both fail-closed on a stale FRA/NARN cross-check (NARN does not
        # survey the Broad Street subway or Market-Frankford), and measuring
        # septa-b1.geojson/septa-l1.geojson directly against OpenStreetMap
        # (see normalize-east-official-networks.py) shows median 1-2 m
        # agreement over hundreds of samples, so both routes now build from
        # septa-b1/septa-l1 with no registered defect.
        self.assertNotIn('officialNetworkDefectByRouteId', septa)
        self.assertEqual(septa['officialNetworkByRouteId']['B1'], 'septa-b1')
        self.assertEqual(septa['officialNetworkByRouteId']['L1'], 'septa-l1')
        # B2's Fern Rock stop-identity problem (stop 841 vs the rail platform
        # 20965) is now fixed via stationIdentityGroups, so B2 no longer
        # carries a geometryReviewByRouteId entry of its own.
        self.assertNotIn('B2', septa['geometryReviewByRouteId'])
        self.assertIn('841', septa['stationIdentityEvidence'])
        self.assertIn('does not reach', septa['geometryReviewByRouteId']['T2'])
        self.assertEqual(septa['officialNetworkByRouteId']['T3'], 'septa-t3')

    def test_north_philadelphia_different_facilities_do_not_merge(self):
        septa = self.feeds['septa']
        self.assertEqual(set(septa['crossFeedDistinctStopIds']),
                         {'2439', '32150'})
        entries = [
            {
                'feedStop': '2439', 'identity': '2439',
                'name': 'North Philadelphia',
                'point': [-75.154629, 39.993944],
                'line': {
                    'feed': 'septa',
                    'crossFeedDistinctStopIds':
                        septa['crossFeedDistinctStopIds'],
                },
            },
            {
                'feedStop': 'PHN', 'identity': 'PHN',
                'name': 'North Philadelphia Amtrak Station',
                'point': [-75.155114, 39.996780],
                'line': {'feed': 'amtrak'},
            },
        ]
        self.assertEqual(len(builder.group_stations(entries)), 2)

        # The exception is per official stop id, not a broader Philadelphia
        # distance rule. An otherwise identical unreviewed pair still merges.
        entries[0]['feedStop'] = entries[0]['identity'] = 'other-septa'
        self.assertEqual(len(builder.group_stations(entries)), 1)

    def test_exact_reviewed_complex_span_is_auditable_not_global(self):
        findings = audit.Findings()
        exceptions = audit.read_station_split_exceptions(REGISTRY, findings)
        self.assertFalse(any(row['severity'] == 'ERROR'
                             for row in findings.rows))
        baseline = {
            'us-official-14-st', 'us-official-fulton-st',
            'us-official-59-st', 'us-official-grand-central',
            'us-official-mets-willets-point',
            'us-official-oceanside', 'us-official-jefferson-park',
            'us-official-capitol-hill', 'us-official-5th-jackson',
            'ca-official-south-keys', 'ca-official-waterfront',
            'ca-official-commercial-broadway',
            'ca-official-dufferin-gate-loop',
            'ca-official-queens-quay-loop-at-lower-spadina-ave',
            'ca-official-exhibition-loop',
        }
        self.assertTrue(baseline.issubset(exceptions))
        east_reviewed = {
            'us-official-lexington-market': 140,
            'us-official-readville': 95,
            'us-official-ashmont': 50,
            'us-official-north': 155,
            'us-official-marble-hill': 120,
            'us-official-times-sq-42-st': 130,
            'us-official-42-st-bryant-pk': 230,
            'us-official-jamaica': 95,
            'us-official-new-york-penn': 115,
            'us-official-world-trade-center': 55,
            'us-official-69th-street': 90,
        }
        for station_id, limit in east_reviewed.items():
            self.assertEqual(exceptions[station_id]['maxMeters'], limit)
        self.assertEqual(exceptions['us-official-14-st']['stopIds'],
                         ['132', 'D19', 'L02'])

        package = {
            'country': 'US',
            'lines': [
                {'id': 'one', 'stations': [
                    ['us-official-14-st', '14 St', -74.000201, 40.737826],
                ]},
                {'id': 'two', 'stations': [
                    ['us-official-14-st', '14 St', -73.996209, 40.738228],
                ]},
            ],
        }
        audit.audit_package(package, findings,
                            {'one': 'metro', 'two': 'metro'}, exceptions)
        reviewed = [row for row in findings.rows
                    if row['check'] == 'station.split.reviewed']
        self.assertEqual(len(reviewed), 1)
        self.assertEqual(reviewed[0]['station'], 'us-official-14-st')
        self.assertFalse(any(row['check'] == 'station.split'
                             for row in findings.rows))

        package['lines'][1]['stations'][0][2] = -73.9950
        over_limit = audit.Findings()
        audit.audit_package(package, over_limit,
                            {'one': 'metro', 'two': 'metro'}, exceptions)
        self.assertTrue(any(row['check'] == 'station.split'
                            for row in over_limit.rows))

    def test_path_33rd_street_is_distinct_from_mta_herald_square(self):
        path = self.feeds['port-authority-trans-hudson']
        self.assertEqual(path['crossFeedDistinctStopIds'], ['26724'])
        entries = [
            {'feedStop': '26724', 'identity': '26724',
             'name': '33rd Street', 'point': [-73.988273, 40.749114],
             'line': {'feed': 'port-authority-trans-hudson',
                      'crossFeedDistinctStopIds': ['26724']}},
            {'feedStop': 'D17', 'identity': 'D17',
             'name': '33rd Street', 'point': [-73.987823, 40.749719],
             'line': {'feed': 'metropolitan-transit-authori'}},
        ]
        self.assertEqual(len(builder.group_stations(entries)), 2)


if __name__ == '__main__':
    unittest.main()
