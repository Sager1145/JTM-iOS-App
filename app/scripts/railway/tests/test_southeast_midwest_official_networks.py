import importlib.util
import json
import os
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-southeast-midwest-official-networks.py'))
SPEC = importlib.util.spec_from_file_location('se_midwest', SCRIPT)
networks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(networks)
REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def feature(**properties):
    return {'type': 'Feature', 'properties': properties,
            'geometry': {'type': 'LineString',
                         'coordinates': [[-84.4, 33.7], [-84.3, 33.8]]}}


class SoutheastMidwestOfficialTests(unittest.TestCase):
    def feeds(self):
        with open(REGISTRY, encoding='utf-8') as source:
            return {row['slug']: row for row in json.load(source)['feeds']}

    def test_marta_uses_only_exact_official_line_names(self):
        groups = networks.marta_groups([
            feature(Name='Blue'), feature(Name='Gold'),
            feature(Name='Green'), feature(Name='Red')])
        self.assertEqual(set(groups), {
            'marta-blue', 'marta-gold', 'marta-green', 'marta-red'})
        with self.assertRaises(SystemExit):
            networks.marta_groups([feature(Name='Unknown')])

    def test_maryland_only_publishes_active_authoritative_direction(self):
        selected = networks.active_maryland([
            feature(Line_Statu='Active', Direction='NB'),
            feature(Line_Statu='Active', Direction='SB'),
            feature(Line_Statu='Proposed', Direction='NB')],
            'test', {'NB'})
        self.assertEqual(len(selected), 1)

    def test_densification_preserves_authority_endpoints_and_segment(self):
        line = [[-80.3, 25.7], [-80.1, 25.9]]
        dense = networks.densify_line(line, max_segment_m=1_000)
        self.assertEqual(dense[0], line[0])
        self.assertEqual(dense[-1], line[-1])
        self.assertGreater(len(dense), 2)
        dx, dy = line[-1][0] - line[0][0], line[-1][1] - line[0][1]
        for point in dense:
            self.assertAlmostEqual(
                (point[0] - line[0][0]) * dy
                - (point[1] - line[0][1]) * dx, 0.0, places=12)

    def test_exact_route_network_ownership_and_fail_closed_blockers(self):
        feeds = self.feeds()
        self.assertEqual(
            feeds['metropolitan-atlanta-rapid-t']['officialNetworkByRouteId'], {
                '29224': 'marta-streetcar', '29226': 'marta-blue',
                '29227': 'marta-gold', '29228': 'marta-green',
                '29229': 'marta-red'})
        self.assertEqual(
            feeds['miami-dade-transit']['officialNetworkByRouteId'], {
                '31009': 'miami-metrorail',
                '14457': 'miami-metromover',
                '14456': 'miami-metromover'})
        self.assertEqual(
            feeds['maryland-transit-administrat-2']
            ['officialNetworkByRouteId'], {'11682': 'maryland-metro'})
        self.assertEqual(
            feeds['maryland-transit-administrat-light-rail']
            ['officialNetworkByRouteId'], {'11693': 'maryland-light-rail'})
        self.assertEqual(set(feeds['wmata']['blockedRouteIds']), {
            'RED', 'BLUE', 'GREEN', 'YELLOW', 'ORANGE', 'SILVER'})
        self.assertEqual(set(feeds['port-authority-of-allegheny']
                             ['blockedRouteIds']), {
            'BLUE', 'RED', 'SLVR', 'DQI', 'MI'})


if __name__ == '__main__':
    unittest.main()
