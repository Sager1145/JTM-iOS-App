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


def official_network_keys(mapping):
    """Every key an `officialNetworkByRouteId` map can name.

    A route's value is either its one official-network key (a plain string)
    or a per-direction map (`{"0": key, "1": key}`) for a route whose two
    physical directions diverge -- see SFMTA's K/L/M/N/F/PH/PM. Mirrors
    `official_keys_for_entry` in build-north-america-rail-package.py.
    """
    keys = []
    for value in mapping.values():
        if isinstance(value, dict):
            keys.extend(v for v in value.values() if v)
        elif value:
            keys.append(value)
    return keys


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
            # Checked before the general 'septa-' entry below (dict order
            # matters here: the lookup takes the first prefix match) --
            # septa-regional-rail's own official networks are named
            # 'septa-rail-<branch>', which also starts with 'septa-'.
            'septa-rail-': {'septa-regional-rail'},
            'septa-': {'septa'},
            'sfmta-': {'san-francisco-municipal-tran'},
            'translink-': {'translink'},
            'ttc-subway-': {'ttc'},
            'uta-': {'utah-transit-authority-uta'},
            'vta-': {'santa-clara-valley-transport'},
        }
        for feed in self.registry()['feeds']:
            for network in official_network_keys(
                    feed.get('officialNetworkByRouteId') or {}):
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
        # 503 and 507 are the ones that must not ship: TTC publishes every
        # current trip on both as a replacement bus, so neither is a railway
        # this season. The subway questions are alignment questions, and a
        # question about where a railway is drawn is not a reason to leave it
        # off the map: Lines 1 and 2 are drawn from audited OSM relations
        # because the City's own topographic survey prefers them to the
        # City's schematic route layer (validate-ttc-subway-osm.py).
        self.assertEqual(set(feed['blockedRouteIds']), {'503', '507'})
        self.assertEqual(
            set(feed.get('officialNetworkDefectByRouteId') or {}), {'1', '2'})
        self.assertNotIn('geometryReviewByRouteId', feed)
        self.assertEqual(feed['officialNetworkByRouteId']['306'],
                         'ttc-streetcar-306')
        self.assertEqual(feed['officialNetworkByRouteId']['506'],
                         'ttc-streetcar-506')
        for route_id, relation in (('1', 102388), ('2', 102386)):
            defect = feed['officialNetworkDefectByRouteId'][route_id]
            self.assertIn('schematic route line', defect)
            self.assertIn('COTGEO_TOPO_RAILWAY', defect)
            self.assertIn('validate-ttc-subway-osm.py', defect)
            self.assertEqual(feed['osmRelationByRouteId'][route_id], relation)
            evidence = feed['osmRelationEvidenceByRouteId'][route_id]
            self.assertIn(str(relation), evidence)
            self.assertIn('validate-ttc-subway-osm.py', evidence)
            self.assertIn('ODbL', evidence)
        # The day routes carry the streetcar network's identity; the 3xx
        # Blue Night routes fold into them rather than naming them.
        self.assertEqual(feed['primaryRouteIds'],
                         ['501', '504', '505', '506', '510', '512'])
        self.assertEqual(feed['excludeTripHeadsignPattern'], 'Replacement Bus')
        for route_id in ('503', '507'):
            self.assertIn('Replacement Bus', feed['blockedRouteIds'][route_id])
            self.assertIn('not railway geometry',
                          feed['blockedRouteIds'][route_id])

    def test_septa_g1_directional_platforms_use_exact_official_stop_ids(self):
        feed = next(row for row in self.registry()['feeds']
                    if row['slug'] == 'septa')
        self.assertEqual(feed['stationIdentityGroups'], [
            ['649', '650'],
            ['21105', '25779'],
            ['20986', '21103'],
            ['20965', '841'],
        ])
        self.assertIn('SEPTA official GTFS', feed['stationIdentityEvidence'])
        self.assertIn('exact stop-id', feed['stationIdentityEvidence'])
        # The fourth pair lists the rail platform (20965, called by B1/B2/B3)
        # first so it stays the merge's canonical stop; the default same-
        # name merge would otherwise pick the unrelated bus stop 841.
        self.assertIn('Fern Rock', feed['stationIdentityEvidence'])

    def test_mta_service_specific_networks_cover_every_route(self):
        feed = next(row for row in self.registry()['feeds']
                    if row['slug'] == 'metropolitan-transit-authori')
        self.assertTrue(feed['requireOfficialMappingForAllRoutes'])
        self.assertTrue(feed['forbidOfficialNetworkFallbackForBranches'])
        self.assertFalse(feed.get('forbidOfficialNetworkFallback', False))
        # Q's officialNetworkDefectByRouteId entry was removed: see
        # test_east_station_splits.test_only_reviewed_bad_geometry_routes_are_blocked
        # for why -- Q now builds cleanly from mta-subway-service-q (34
        # stations, 28.8 km) with no near-reversal defect left to register.
        self.assertNotIn('officialNetworkDefectByRouteId', feed)
        self.assertIn('Q', feed['officialNetworkByRouteId'])
        self.assertEqual(feed['officialNetworkByRouteId']['Q'],
                         'mta-subway-service-q')
        self.assertEqual(len(feed['officialNetworkByRouteId']), 29)
        self.assertEqual(feed['officialNetworkByRouteId']['2'],
                         'mta-subway-service-2')
        self.assertEqual(feed['officialNetworkByRouteId']['R'],
                         'mta-subway-service-r')


if __name__ == '__main__':
    unittest.main()
