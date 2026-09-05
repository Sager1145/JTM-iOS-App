import importlib.util
import json
import os
import sys
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-via-ontario-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
SPEC = importlib.util.spec_from_file_location('via_ontario_official', SCRIPT)
via_ontario = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(via_ontario)
import na_provenance
import na_official


REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


class ViaOntarioOfficialNetworkTests(unittest.TestCase):
    def test_route_isolation_uses_only_surveyed_orwn_coordinates(self):
        route_data = {}
        orwn = []
        for index, route_id in enumerate(via_ontario.TARGETS):
            latitude = 42.0 + index * 0.1
            line = [[-81.0, latitude], [-80.99, latitude],
                    [-80.98, latitude]]
            properties = {
                'TRACKCLASS': 'Main', 'STATUS': 'Operational',
                'ADMINAREA': 'Ontario', 'GEOACQTECH': 'Orthoimage',
                'GEOACCURA': 10, 'GEOPROVIDE': 'Provincial/Territorial',
            }
            orwn.append((properties, [line]))
            route_data[route_id] = {
                'shapes': [line],
                'patterns': [{
                    'stationPoints': [line[0], line[-1]],
                    'shape': line, 'tripId': f'trip-{route_id}',
                }],
            }
        groups = via_ontario.route_groups(orwn, route_data)
        self.assertEqual(set(groups), set(via_ontario.TARGETS.values()))
        for route_id, key in via_ontario.TARGETS.items():
            self.assertTrue(groups[key])
            expected_latitude = route_data[route_id]['shapes'][0][0][1]
            for feature in groups[key]:
                self.assertEqual(feature['properties']['routeKey'], key)
                for _, latitude in feature['geometry']['coordinates']:
                    self.assertAlmostEqual(latitude, expected_latitude,
                                           places=8)

    def test_via_registry_is_exact_and_fail_closed(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        via = next(row for row in feeds if row['slug'] == 'via')
        self.assertNotIn('officialNetwork', via)
        self.assertTrue(via['requireVerifiedOfficialNetwork'])
        self.assertTrue(via['forbidOfficialNetworkFallback'])
        self.assertEqual(via['officialNetworkEndpointJoinMeters'], 5)
        self.assertIn('Ottawa-Fallowfield', via['officialNetworkDefectByRouteId']['617-119'])
        for route_id, key in via_ontario.TARGETS.items():
            self.assertEqual(via['officialNetworkByRouteId'][route_id], key)
            self.assertEqual(na_provenance.KEY_SOURCE_EXACT[key],
                             'ontario-orwn')
        self.assertNotIn('orwn-', na_provenance.KEY_SOURCE_PREFIXES)

    def test_sarnia_join_is_limited_to_the_measured_digitizing_gap(self):
        # Consecutive ORWN-routed VIA intervals end at these two independently
        # published coordinates near London.  Their 4.29 m gap must be joined
        # by the audited five-metre tolerance, while four metres stays closed.
        first = [-80.9757323999999, 43.3644038000001]
        second = [-80.97574218886625, 43.36436588259236]
        features = [
            {'type': 'Feature', 'properties': {},
             'geometry': {'type': 'LineString',
                          'coordinates': [[-80.976, 43.3645], first]}},
            {'type': 'Feature', 'properties': {},
             'geometry': {'type': 'LineString',
                          'coordinates': [second, [-80.9755, 43.3642]]}},
        ]
        closed = na_official.PassengerNetwork(features, endpoint_join_m=4.0)
        joined = na_official.PassengerNetwork(features, endpoint_join_m=5.0)
        self.assertEqual(closed.joined_endpoints, [])
        self.assertEqual(len(joined.joined_endpoints), 1)
        self.assertGreater(joined.joined_endpoints[0]['meters'], 4.0)
        self.assertLess(joined.joined_endpoints[0]['meters'], 5.0)

    def test_amtrak_incomplete_ntad_routes_are_explicitly_blocked(self):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        amtrak = next(row for row in feeds if row['slug'] == 'amtrak')
        self.assertTrue(amtrak['forbidOfficialNetworkFallback'])
        # 42985 is the only one that must not ship: it is a GTFS route named
        # "Commuter Rail" with no published FRA identity, so there is no
        # railway to draw. The other entries name a defect in the NTAD
        # extract — split components, a spike, a deviation, or a pattern it cannot cover —
        # which disqualifies that layer, not the service.
        #
        # 88 and 94 were removed from this list: both failed station
        # snapping only at EWR, whose published GTFS coordinate is 1006 m
        # from the nearest FRA NTAD Northeast Regional vertex while the
        # OpenStreetMap Amtrak/NJ Transit station node for the same stop is
        # 0.3 m from it. The fix is stationCoordinateOverrides, not a
        # network defect. 58 was removed because the 118.6 degree spike
        # near Ashland no longer reproduces: PassengerNetwork.
        # drop_junction_stubs now removes the junction-marker doubling-back
        # that produced it, and the worst turn angle left on route 58's
        # routed path is 34.9 degrees.
        self.assertEqual(set(amtrak['blockedRouteIds']), {'42985'})
        self.assertEqual(set(amtrak['officialNetworkDefectByRouteId']),
                         {'55', '61', '77', '78', '96',
                          '36923', '40751', '42946', '42947', '42951',
                          '42956', '42957', '42992', '42994'})
        self.assertNotIn('58', amtrak['officialNetworkDefectByRouteId'])
        self.assertNotIn('88', amtrak['officialNetworkDefectByRouteId'])
        self.assertNotIn('94', amtrak['officialNetworkDefectByRouteId'])
        self.assertIn('complete published station pattern',
                      amtrak['officialNetworkDefectByRouteId']['36923'])
        self.assertIn('complete published station pattern',
                      amtrak['officialNetworkDefectByRouteId']['42947'])
        self.assertIn('141.1 m', amtrak['officialNetworkDefectByRouteId']['42957'])
        self.assertIn('392.3-414.5 m', amtrak['officialNetworkDefectByRouteId']['42994'])


if __name__ == '__main__':
    unittest.main()
