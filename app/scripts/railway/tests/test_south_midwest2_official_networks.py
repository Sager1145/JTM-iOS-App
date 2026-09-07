import importlib.util
import json
import os
import sys
import unittest


HERE = os.path.dirname(__file__)
SCRIPT = os.path.abspath(os.path.join(
    HERE, '..', 'normalize-south-midwest2-official-networks.py'))
REGISTRY = os.path.abspath(os.path.join(HERE, '..', 'na-feeds.json'))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
import na_provenance

SPEC = importlib.util.spec_from_file_location('south_midwest2', SCRIPT)
networks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(networks)


class SouthMidwest2OfficialNetworkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            cls.feeds = {row['slug']: row for row in json.load(source)['feeds']}

    def test_normalizer_and_provenance_use_identical_source_signatures(self):
        for source_id, source in networks.SOURCES.items():
            expected = na_provenance.SOURCES[source_id]
            self.assertEqual(source['publisher'], expected['publisher'])
            self.assertEqual(source['url'], expected['url'])

    def test_every_published_key_has_one_reviewed_owner(self):
        # The City QLINE layer is normalized for comparison but intentionally
        # remains untrusted until its independence from GTFS is established.
        self.assertNotIn('qline', na_provenance.KEY_SOURCE_EXACT)
        for key, source_id in networks.KEY_SOURCE.items():
            if key == 'qline':
                continue
            self.assertEqual(na_provenance.KEY_SOURCE_EXACT[key], source_id)

    def test_repaired_registry_routes_are_exact_and_fail_closed(self):
        dart = self.feeds['dallas-area-rapid-transit-da']
        self.assertEqual(set(dart['officialNetworkByRouteId']), {
            '27224', '27243', '27251', '27252', '27253', '27254',
            '27255', '27257'})
        self.assertTrue(dart['requireVerifiedOfficialNetwork'])
        self.assertTrue(dart['requireOfficialMappingForAllRoutes'])
        self.assertEqual(set(dart['officialNetworkDefectByRouteId']),
                         {'27224'})
        self.assertEqual(
            self.feeds['detroit-people-mover']['officialNetworkByRouteId'],
            {'DPM': 'detroit-dpm'})
        self.assertEqual(
            self.feeds['cincinnati-metro']['officialNetworkByRouteId'],
            {'100': 'cincinnati-connector'})
        self.assertEqual(
            self.feeds['milwaukee-hop']['officialNetworkByRouteId'],
            {'TL-9': 'milwaukee-hop'})
        self.assertEqual(
            self.feeds['fort-worth-transit-authority']
            ['officialNetworkByRouteId'], {'8305': 'texrail'})

    def test_unresolved_qline_and_gold_line_color_remain_blocked(self):
        qline = self.feeds['qline-detroit']
        self.assertEqual(set(qline['geometryReviewByRouteId']), {'13578'})
        self.assertNotIn('officialNetworkByRouteId', qline)
        cats = self.feeds['charlotte-area-transit-syste']
        self.assertEqual(cats['officialNetworkByRouteId']['510'], 'cats-gold')
        self.assertIn('route_color', cats['blockedRouteIds']['510'])


if __name__ == '__main__':
    unittest.main()
