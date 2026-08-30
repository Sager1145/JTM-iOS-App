import importlib.util
import json
import os
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-midwest-official-networks.py'))
SPEC = importlib.util.spec_from_file_location('midwest_official', SCRIPT)
networks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(networks)
REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))


def kml(names):
    rows = ''.join(
        '<Placemark><name>{}</name><LineString><coordinates>'
        '-87.7,41.8,0 -87.6,41.9,0'
        '</coordinates></LineString></Placemark>'.format(name)
        for name in names)
    return ('<kml xmlns="http://earth.google.com/kml/2.2"><Document>'
            + rows + '</Document></kml>').encode()


class MidwestOfficialTests(unittest.TestCase):
    def feeds(self):
        with open(REGISTRY, encoding='utf-8') as source:
            return {row['slug']: row for row in json.load(source)['feeds']}

    def test_metra_uses_only_exact_government_line_names(self):
        groups = networks.parse_metra_kml(kml([
            'BNSF', 'Heritage', 'Milw-N', 'Milw-W', 'Electric', 'NCS',
            'Rock Is.', 'SWS', 'UP-N', 'UP-NW', 'UP-W']))
        self.assertEqual(set(groups), set(networks.METRA_EXACT_NAMES))
        self.assertTrue(all(groups.values()))
        with self.assertRaises(SystemExit):
            networks.parse_metra_kml(kml([
                'BNSF', 'Heritage', 'Milw-N', 'Milw-W', 'Electric', 'NCS',
                'Rock Is.', 'SWS', 'UP-N', 'UP-NW', 'Mystery']))

    def test_inverse_utm15_known_central_meridian_point(self):
        lon, lat = networks.inverse_utm15(500_000, 4_982_950.4)
        self.assertAlmostEqual(lon, -93.0, places=7)
        self.assertAlmostEqual(lat, 45.0, places=4)

    def test_densification_preserves_endpoints_and_source_segments(self):
        line = [[-93.3, 44.9], [-93.1, 45.0]]
        dense = networks.densify(line, max_segment_m=1_000)
        self.assertEqual(dense[0], line[0])
        self.assertEqual(dense[-1], line[-1])
        self.assertGreater(len(dense), 2)
        dx = line[-1][0] - line[0][0]
        dy = line[-1][1] - line[0][1]
        for point in dense:
            self.assertAlmostEqual(
                (point[0] - line[0][0]) * dy
                - (point[1] - line[0][1]) * dx, 0.0, places=12)

    def test_exact_route_ownership_and_fail_closed_blockers(self):
        feeds = self.feeds()
        self.assertEqual(
            feeds['metra']['officialNetworkByRouteId'], {
                'BNSF': 'metra-bnsf', 'HC': 'metra-hc',
                'MD-N': 'metra-md-n', 'MD-W': 'metra-md-w',
                'ME': 'metra-me', 'NCS': 'metra-ncs', 'RI': 'metra-ri',
                'SWS': 'metra-sws', 'UP-N': 'metra-up-n',
                'UP-NW': 'metra-up-nw', 'UP-W': 'metra-up-w'})
        self.assertEqual(
            feeds['metro-transit']['officialNetworkByRouteId'], {
                '901': 'metro-transit-blue',
                '902': 'metro-transit-green',
                '906': 'metro-transit-blue'})
        self.assertEqual(feeds['metro-transit']['stationIdentityGroups'],
                         [['56333', '56334', '56335', '56339']])
        self.assertEqual(set(feeds['cleveland-rta']['blockedRouteIds']),
                         {'66', '67', '68', '69'})
        self.assertEqual(set(feeds['qline-detroit']['blockedRouteIds']),
                         {'13578'})
        self.assertEqual(set(feeds['detroit-people-mover']['blockedRouteIds']),
                         {'DPM'})
        self.assertEqual(set(feeds['cincinnati-metro']['blockedRouteIds']),
                         {'100'})
        self.assertEqual(set(feeds['milwaukee-hop']['blockedRouteIds']),
                         {'TL-9'})


if __name__ == '__main__':
    unittest.main()
