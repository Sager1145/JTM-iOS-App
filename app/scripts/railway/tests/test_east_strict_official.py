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
        # Q's officialNetworkDefectByRouteId entry was removed: see
        # test_east_station_splits.test_only_reviewed_bad_geometry_routes_are_blocked
        # for why -- Q now builds cleanly from mta-subway-service-q.
        self.assertNotIn('officialNetworkDefectByRouteId', mta)
        for route in ('2', '3', '4', 'FX', 'R', 'W'):
            self.assertIn(route, mta['officialNetworkByRouteId'])
            self.assertEqual(mta['officialNetworkByRouteId'][route],
                             f'mta-subway-service-{route.lower()}')
        septa = next(row for row in feeds if row['slug'] == 'septa')
        self.assertTrue(septa['requireVerifiedOfficialNetwork'])
        self.assertEqual(set(septa['forbidOfficialNetworkFallbackByRouteId']),
                         {'B1', 'L1'})
        # B1 and L1's officialNetworkDefectByRouteId entries were removed:
        # both fail-closed on a stale FRA/NARN cross-check that does not
        # survey rapid transit (NARN is a mainline-track network), and
        # septa-b1.geojson/septa-l1.geojson measure at median 1-2 m against
        # OpenStreetMap over hundreds of samples (see
        # normalize-east-official-networks.py). forbidOfficialNetworkFallback
        # ByRouteId stays, so the routes still refuse a silent operator-shape
        # fallback if septa-b1/septa-l1 ever stop routing.
        self.assertNotIn('officialNetworkDefectByRouteId', septa)
        self.assertEqual(set(septa['geometryReviewByRouteId']),
                         {'G1', 'T2'})
        # D1/D2/T1/T3/T4/T5 route cleanly against SEPTA Planning Division's
        # own trolley GIS layer (septa-trolley) and ship off it directly; only
        # G1 and T2 still lack a complete independent alignment and fall
        # through to the operator's own accepted GTFS shape instead.
        self.assertEqual(set(septa['officialNetworkByRouteId']),
                         {'B1', 'B3', 'L1', 'M1', 'D1', 'D2', 'T1', 'T3', 'T4',
                          'T5'})
        self.assertEqual(set(septa['acceptOperatorShapeByRouteId']),
                         {'G1', 'T2'})
        mbta = next(row for row in feeds if row['slug'] == 'mbta')
        self.assertEqual(mbta['forbidOfficialNetworkFallbackByRouteId'],
                         ['Blue'])
        # Blue and Red's officialNetworkDefectByRouteId entries were removed
        # on the same OSM evidence (mbta-rapid-blue.geojson median 1.1 m,
        # mbta-rapid-red.geojson median 0.9 m; see
        # normalize-northeast2-official-networks.py).
        self.assertNotIn('officialNetworkDefectByRouteId', mbta)

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
        # 88 (Northeast Regional) and 94 (Keystone Service) both failed
        # station snapping only at EWR: Amtrak's own GTFS publishes Newark
        # Liberty International Airport 1006 m from the nearest FRA NTAD
        # Northeast Regional vertex, while the OpenStreetMap Amtrak/NJ
        # Transit station node for the same stop sits 0.3 m from that same
        # official alignment. New York Penn Station itself was never
        # disconnected -- it snaps onto the same giant component as
        # everything else. The fix is the published coordinate, not the
        # official network, so it lives in stationCoordinateOverrides and
        # neither route carries an officialNetworkDefectByRouteId entry.
        self.assertNotIn('88', amtrak['officialNetworkDefectByRouteId'])
        self.assertNotIn('94', amtrak['officialNetworkDefectByRouteId'])
        self.assertNotIn('58', amtrak['officialNetworkDefectByRouteId'])
        ewr = amtrak['stationCoordinateOverrides']['EWR']
        self.assertAlmostEqual(ewr['published'][0], -74.18229, places=3)
        self.assertAlmostEqual(ewr['corrected'][0], -74.1907347, places=3)
        self.assertGreaterEqual(len(ewr['evidence']), 2)
        self.assertIn('internal reversals', amtrak['officialNetworkDefectByRouteId']['61'])


if __name__ == '__main__':
    unittest.main()
