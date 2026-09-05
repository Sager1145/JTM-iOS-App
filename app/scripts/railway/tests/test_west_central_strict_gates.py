import importlib.util
import json
import os
import sys
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-west-central-strict-official-networks.py'))
SPEC = importlib.util.spec_from_file_location('west_central_strict', SCRIPT)
networks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(networks)
REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
import na_provenance


def feature(**properties):
    return {'type': 'Feature', 'properties': properties,
            'geometry': {'type': 'LineString',
                         'coordinates': [[-97.3, 32.7], [-97.2, 32.8]]}}


class WestCentralStrictGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            cls.feeds = {row['slug']: row
                         for row in json.load(source)['feeds']}

    def test_texrail_selection_is_exact_revenue_service(self):
        rows = [
            feature(Line='TEXRail', Agency='Trinity Metro',
                    ServiceStatus='In Revenue Service')
            for _ in range(8)]
        self.assertEqual(len(networks.texrail_group(rows)), 8)
        rows[0]['properties']['ServiceStatus'] = 'Construction'
        with self.assertRaises(SystemExit):
            networks.texrail_group(rows)

    def test_sunmetro_layer_shape_is_fail_closed(self):
        rows = [feature(Id=0), feature(Id=0), feature(Id=1)]
        self.assertEqual(len(networks.sunmetro_group(rows)), 3)
        with self.assertRaises(SystemExit):
            networks.sunmetro_group(rows[:2])

    def test_new_network_keys_have_exact_provenance(self):
        self.assertEqual(
            na_provenance.KEY_SOURCE_EXACT['sunmetro-streetcar'],
            'sunmetro-streetcar')
        self.assertEqual(
            na_provenance.KEY_SOURCE_EXACT['nctcog-texrail'],
            'nctcog-existing-rail-lines')

    def test_sunmetro_and_texrail_require_verified_geometry(self):
        sun = self.feeds['sun-metro']
        self.assertEqual(sun['officialNetworkByRouteId'],
                         {'14847': 'sunmetro-streetcar'})
        self.assertEqual(set(sun['officialNetworkDefectByRouteId']), {'14847'})
        self.assertEqual(sun['officialColorByRouteId'], {'14847': '009994'})
        self.assertTrue(sun['requireVerifiedOfficialNetwork'])
        self.assertTrue(sun['requireOfficialMappingForAllRoutes'])
        self.assertTrue(sun['forbidOfficialNetworkFallback'])

        texrail = self.feeds['trinity-metro']
        self.assertEqual(texrail['officialNetworkByRouteId'],
                         {'8305': 'nctcog-texrail'})
        self.assertTrue(texrail['requireVerifiedOfficialNetwork'])
        self.assertTrue(texrail['requireOfficialMappingForAllRoutes'])
        self.assertTrue(texrail['forbidOfficialNetworkFallback'])

    def test_deviation_and_unchecked_routes_are_exactly_blocked(self):
        expected = {
            'kansas-city-area-transportat': {'601'},
            'los-angeles-county-metropoli': {'802'},
            # UP-N's officialNetworkDefectByRouteId entry (a stale FRA/NARN
            # cross-check disagreement near Kenosha) was removed: the RTA/
            # CMAP "Metra Rail Lines" layer's own 'UPN' feature routes it
            # cleanly (see RTA_METRA_NAMES in
            # normalize-south-midwest2-official-networks.py), so metra now
            # has no declared defect at all.
            'metro-transit': {'901', '906'},
            'rio-metro-regional-transit-d': {'rr'},
            'rock-region-metro': {'BL'},
            # SFMTA's N/PH/PM officialNetworkDefectByRouteId entries (their
            # inbound/outbound alignments diverge near Embarcadero and
            # Jackson/Washington) were removed: officialNetworkByRouteId now
            # names direction 0 and direction 1 separately for those routes,
            # and direction 1's own track ships as `extraSegments` wherever
            # it disagrees with direction 0, so nothing is declared
            # defective any more -- see test_us_west_metro_official.py and
            # test_west_station_anchor_review.py.
        }
        # An official layer that is wrong for a route is named as a defect
        # in that layer; a route with no official layer at all carries an open
        # review note instead. Both ship, and both say why.
        for slug, route_ids in expected.items():
            feed = self.feeds[slug]
            declared = set(feed.get('officialNetworkDefectByRouteId') or ())
            declared |= set(feed.get('geometryReviewByRouteId') or ())
            self.assertEqual(declared, route_ids, slug)


if __name__ == '__main__':
    unittest.main()
