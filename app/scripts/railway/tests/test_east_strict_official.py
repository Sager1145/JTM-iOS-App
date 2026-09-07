import importlib.util
import json
import os
import sys
import tempfile
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'normalize-vre-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
SPEC = importlib.util.spec_from_file_location('vre_official', SCRIPT)
vre_official = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(vre_official)
import na_provenance


REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def line(name, latitude):
    return {
        'type': 'Feature', 'properties': {'NAME': name},
        'geometry': {'type': 'LineString', 'coordinates': [
            [-77.5 + index * 0.001, latitude] for index in range(101)
        ]},
    }


class EastStrictOfficialTests(unittest.TestCase):
    def test_vre_source_is_exactly_two_drpt_lines(self):
        payload = {'type': 'FeatureCollection', 'features': [
            line('Fredericksburg Line', 38.0),
            line('Manassas Line', 38.5),
        ]}
        with tempfile.TemporaryDirectory() as directory:
            source = os.path.join(directory, 'vre.geojson')
            with open(source, 'w', encoding='utf-8') as output:
                json.dump(payload, output)
            raw, by_name = vre_official.read_source(source)
        self.assertTrue(raw)
        self.assertEqual(set(by_name), set(vre_official.ROUTES))

    def test_vre_rejects_unknown_or_missing_official_route(self):
        payload = {'type': 'FeatureCollection', 'features': [
            line('Fredericksburg Line', 38.0),
            line('Unknown Line', 38.5),
        ]}
        with tempfile.TemporaryDirectory() as directory:
            source = os.path.join(directory, 'vre.geojson')
            with open(source, 'w', encoding='utf-8') as output:
                json.dump(payload, output)
            with self.assertRaises(SystemExit):
                vre_official.read_source(source)

    def test_vre_registry_and_provenance_are_exact_and_fail_closed(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        vre = next(row for row in feeds if row['slug'] == 'vre')
        self.assertTrue(vre['requireVerifiedOfficialNetwork'])
        self.assertTrue(vre['requireOfficialMappingForAllRoutes'])
        self.assertTrue(vre['forbidOfficialNetworkFallback'])
        self.assertIn('362 m unmatched', vre['officialNetworkDefectByRouteId']['2'])
        self.assertIn('725 m', vre['officialNetworkDefectByRouteId']['4'])
        self.assertEqual(vre['officialNetworkByRouteId'], {
            '2': 'vre-fredericksburg', '4': 'vre-manassas'})
        for key in vre['officialNetworkByRouteId'].values():
            self.assertEqual(na_provenance.KEY_SOURCE_EXACT[key],
                             'virginia-drpt-vre')
        self.assertNotIn('vre-', na_provenance.KEY_SOURCE_PREFIXES)

    def test_mta_and_septa_cannot_fallback_from_failed_official_network(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        mta = next(row for row in feeds
                   if row['slug'] == 'metropolitan-transit-authori')
        self.assertTrue(mta['requireVerifiedOfficialNetwork'])
        self.assertTrue(mta['forbidOfficialNetworkFallbackForBranches'])
        self.assertEqual(set(mta['officialNetworkDefectByRouteId']), {'Q'})
        for route in ('2', '3', '4', 'FX', 'R', 'W'):
            self.assertIn(route, mta['officialNetworkByRouteId'])
            self.assertEqual(mta['officialNetworkByRouteId'][route],
                             f'mta-subway-service-{route.lower()}')
        septa = next(row for row in feeds if row['slug'] == 'septa')
        self.assertTrue(septa['requireVerifiedOfficialNetwork'])
        self.assertEqual(set(septa['forbidOfficialNetworkFallbackByRouteId']),
                         {'B1', 'L1'})
        self.assertEqual(set(septa['officialNetworkDefectByRouteId']),
                         {'B1', 'L1'})
        self.assertEqual(set(septa['geometryReviewByRouteId']),
                         {'B2', 'D1', 'D2', 'G1', 'T1', 'T2', 'T3', 'T4', 'T5'})
        self.assertIn('57.35 m', septa['officialNetworkDefectByRouteId']['B1'])
        self.assertIn('41.04 m', septa['officialNetworkDefectByRouteId']['L1'])
        self.assertEqual(set(septa['officialNetworkByRouteId']),
                         {'B1', 'B3', 'L1', 'M1'})
        for route in ('D1', 'D2', 'G1', 'T1', 'T2', 'T3', 'T4', 'T5'):
            self.assertIn('not an independent surveyed alignment',
                          septa['geometryReviewByRouteId'][route])
        mbta = next(row for row in feeds if row['slug'] == 'mbta')
        self.assertEqual(mbta['forbidOfficialNetworkFallbackByRouteId'],
                         ['Blue'])
        self.assertIn('40.4 m', mbta['officialNetworkDefectByRouteId']['Blue'])

        lirr = next(row for row in feeds
                    if row['slug'] == 'mta-long-island-rail-road')
        self.assertEqual(set(lirr['officialNetworkDefectByRouteId']), {'9'})
        self.assertIn('near-reversal',
                      lirr['officialNetworkDefectByRouteId']['9'])
        self.assertEqual(lirr['officialNetworkByRouteId']['9'],
                         'lirr-seam-9-port-washington')
        self.assertEqual(lirr['officialNetworkByRouteId']['12'],
                         'lirr-seam-12-city-terminal')

        amtrak = next(row for row in feeds if row['slug'] == 'amtrak')
        self.assertIn('New York Penn Station', amtrak['officialNetworkDefectByRouteId']['88'])
        self.assertIn('Newark Airport', amtrak['officialNetworkDefectByRouteId']['94'])
        self.assertIn('internal reversals', amtrak['officialNetworkDefectByRouteId']['61'])


if __name__ == '__main__':
    unittest.main()
