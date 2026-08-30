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
            'septa-': {'septa'},
            'sfmta-': {'san-francisco-municipal-tran'},
            'sound-link-': {'sound-transit'},
            'sounder-': {'sound-transit'},
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

    def test_ttc_306_and_its_branches_stay_blocked_with_unresolved_station_identity(self):
        feed = next(row for row in self.registry()['feeds']
                    if row['slug'] == 'ttc')
        self.assertEqual(set(feed.get('blockedRouteIds') or {}), {'306', '506'})
        self.assertIn('255 m', feed['blockedRouteIds']['306'])
        self.assertIn('294.45 m', feed['blockedRouteIds']['506'])


if __name__ == '__main__':
    unittest.main()
