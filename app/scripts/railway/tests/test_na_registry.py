import json
import os
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
REGISTRY = os.path.join(HERE, '..', 'na-feeds.json')


def reject_duplicate_keys(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f'duplicate JSON key: {key}')
        value[key] = item
    return value


class RegistryIntegrityTests(unittest.TestCase):
    def registry(self):
        with open(REGISTRY, encoding='utf-8') as source:
            return json.load(source, object_pairs_hook=reject_duplicate_keys)

    def test_feed_registry_has_no_duplicate_json_keys(self):
        self.registry()

    def test_route_specific_official_networks_belong_to_the_right_feed(self):
        owners = {
            'amtrak-ntad-': {'amtrak'},
            'calgary-': {'calgary-transit'},
            'cta-': {'cta'},
            'edmonton-': {'edmonton-transit-system'},
            'la-metro-': {'los-angeles-county-metropoli'},
            'mbta-': {'mbta'},
            'metrolink-scrra-': {'metrolink'},
            'mnr-': {'metro-north-railroad'},
            'mta-subway-': {'metropolitan-transit-authori'},
            'norta-': {'new-orleans-rta'},
            'ottawa-trillium-': {'ottawa-carleton-regional-tra'},
            'septa-': {'septa'},
            'sfmta-': {'san-francisco-municipal-tran'},
            'translink-': {'translink'},
            'ttc-subway-': {'ttc'},
            'uta-': {'utah-transit-authority-uta'},
            'vta-': {'santa-clara-valley-transport'},
        }
        for feed in self.registry()['feeds']:
            for network in (feed.get('officialNetworkByRouteId') or {}).values():
                expected = next((slugs for prefix, slugs in owners.items()
                                 if network.startswith(prefix)), None)
                if expected is not None:
                    self.assertIn(feed['slug'], expected,
                                  f'{network} is attached to {feed["slug"]}')

    def test_mapped_official_networks_are_fail_closed(self):
        for feed in self.registry()['feeds']:
            if feed.get('officialNetworkByRouteId'):
                self.assertTrue(
                    feed.get('requireVerifiedOfficialNetwork'),
                    f'{feed["slug"]} may fall back after official GIS fails')

    def test_ttc_verified_streetcars_and_replacement_bus_are_exact(self):
        feed = next(row for row in self.registry()['feeds']
                    if row['slug'] == 'ttc')
        # 503 is the one that must not ship: TTC publishes every current
        # trip on it as a replacement bus, so it is not a railway this season.
        # The other four are alignment questions, and a question about where a
        # railway is drawn is not a reason to leave it off the map.
        self.assertEqual(set(feed['blockedRouteIds']), {'503'})
        self.assertEqual(
            set(feed.get('officialNetworkDefectByRouteId') or {}), {'1', '2'})
        self.assertNotIn('geometryReviewByRouteId', feed)
        self.assertEqual(feed['officialNetworkByRouteId']['306'],
                         'ttc-streetcar-306')
        self.assertEqual(feed['officialNetworkByRouteId']['506'],
                         'ttc-streetcar-506')
        self.assertIn('125.2 m', feed['officialNetworkDefectByRouteId']['1'])
        self.assertIn('second independent official survey',
                      feed['officialNetworkDefectByRouteId']['1'])
        self.assertIn('78.8 m', feed['officialNetworkDefectByRouteId']['2'])
        self.assertIn('second independent official survey',
                      feed['officialNetworkDefectByRouteId']['2'])
        self.assertIn('Replacement Bus', feed['blockedRouteIds']['503'])
        self.assertIn('not railway geometry', feed['blockedRouteIds']['503'])

    def test_septa_g1_directional_platforms_use_exact_official_stop_ids(self):
        feed = next(row for row in self.registry()['feeds']
                    if row['slug'] == 'septa')
        self.assertEqual(feed['stationIdentityGroups'], [
            ['649', '650'],
            ['21105', '25779'],
            ['20986', '21103'],
        ])
        self.assertIn('SEPTA official GTFS', feed['stationIdentityEvidence'])
        self.assertIn('exact stop-id', feed['stationIdentityEvidence'])

    def test_mta_service_specific_networks_cover_every_route(self):
        feed = next(row for row in self.registry()['feeds']
                    if row['slug'] == 'metropolitan-transit-authori')
        self.assertTrue(feed['requireOfficialMappingForAllRoutes'])
        self.assertTrue(feed['forbidOfficialNetworkFallbackForBranches'])
        self.assertFalse(feed.get('forbidOfficialNetworkFallback', False))
        self.assertEqual(set(feed['officialNetworkDefectByRouteId']), {'Q'})
        self.assertIn('near-reversal',
                      feed['officialNetworkDefectByRouteId']['Q'])
        self.assertEqual(len(feed['officialNetworkByRouteId']), 29)
        self.assertEqual(feed['officialNetworkByRouteId']['2'],
                         'mta-subway-service-2')
        self.assertEqual(feed['officialNetworkByRouteId']['R'],
                         'mta-subway-service-r')


if __name__ == '__main__':
    unittest.main()
