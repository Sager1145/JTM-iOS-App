import importlib.util
import os
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-east-official-networks.py'))
SPEC = importlib.util.spec_from_file_location('east_official', SCRIPT)
east = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(east)


def feature(**properties):
    return {
        'type': 'Feature',
        'properties': properties,
        'geometry': {
            'type': 'LineString',
            'coordinates': [[-71.1, 42.3], [-71.0, 42.4]],
        },
    }


class MBTAOfficialNetworkTests(unittest.TestCase):
    def test_rapid_routes_are_isolated_and_shared_track_is_retained(self):
        shared = feature(LINE='GREEN', ROUTE='B C D E')
        medford = feature(LINE='GREEN', ROUTE='E - Medford/Tufts')
        union = feature(LINE='GREEN', ROUTE='D - Union Square')
        groups = east.mbta_rapid_groups([
            feature(LINE='BLUE', ROUTE='Bowdoin to Wonderland'),
            feature(LINE='ORANGE', ROUTE='Forest Hills to Oak Grove'),
            feature(LINE='RED', ROUTE='A - Ashmont B - Braintree C - Alewife'),
            feature(LINE='RED', ROUTE='Mattapan Trolley'),
            shared,
            feature(LINE='GREEN', ROUTE='B - Boston College'),
            medford,
            union,
            feature(LINE='SILVER', ROUTE='SL1'),
        ])

        self.assertIn(shared, groups['mbta-rapid-green-b'])
        self.assertIn(shared, groups['mbta-rapid-green-e'])
        self.assertIn(medford, groups['mbta-rapid-green-b'])
        self.assertIn(medford, groups['mbta-rapid-green-c'])
        self.assertIn(union, groups['mbta-rapid-green-e'])
        self.assertNotIn(union, groups['mbta-rapid-green-b'])
        self.assertNotIn(
            feature(LINE='RED', ROUTE='Mattapan Trolley'),
            groups['mbta-rapid-red'])
        self.assertEqual(
            [row['properties']['ROUTE']
             for row in groups['mbta-rapid-mattapan']],
            ['Mattapan Trolley'])

    def test_commuter_branches_only_enter_their_gtfs_service(self):
        foxboro = feature(COMM_LINE='Foxboro', COMMRAIL='S')
        wildcat = feature(COMM_LINE='Wildcat Branch', COMMRAIL='Y')
        groups = east.mbta_commuter_groups([
            feature(COMM_LINE='Franklin', COMMRAIL='Y'),
            foxboro,
            feature(COMM_LINE='Fairmount', COMMRAIL='Y'),
            feature(COMM_LINE='Haverhill', COMMRAIL='Y'),
            wildcat,
            feature(COMM_LINE='Haverhill', COMMRAIL='P'),
        ])

        self.assertIn(foxboro, groups['mbta-commuter-cr-franklin'])
        self.assertIn(foxboro, groups['mbta-commuter-cr-foxboro'])
        self.assertIn(
            'Fairmount',
            [row['properties']['COMM_LINE']
             for row in groups['mbta-commuter-cr-franklin']])
        self.assertNotIn(wildcat, groups['mbta-commuter-cr-franklin'])
        self.assertIn(wildcat, groups['mbta-commuter-cr-haverhill'])
        self.assertEqual(
            len(groups['mbta-commuter-cr-haverhill']), 2,
            'proposed duplicate Haverhill line must remain excluded')


class SEPTAOfficialNetworkTests(unittest.TestCase):
    def test_high_speed_b_feature_is_available_to_local_and_spur_only(self):
        broad = feature(Route='B')
        groups = east.septa_high_speed_groups([
            broad, feature(Route='L'), feature(Route='M'),
        ])

        self.assertEqual(groups['septa-b1'], [broad])
        self.assertEqual(groups['septa-b3'], [broad])
        self.assertNotIn(broad, groups['septa-l1'])

    def test_trolley_route_ids_are_exact_not_name_guesses(self):
        routes = ['D1', 'D2', 'G1', 'T1', 'T2', 'T3', 'T4', 'T5']
        groups = east.septa_trolley_groups(
            [feature(Route=route) for route in routes])

        self.assertEqual(
            groups['septa-t2'][0]['properties']['Route'], 'T2')
        self.assertEqual(
            groups['septa-g1'][0]['properties']['Route'], 'G1')

    def test_unknown_official_route_fails_closed(self):
        with self.assertRaises(SystemExit):
            east.septa_trolley_groups([feature(Route='X')])


class ProvenanceTests(unittest.TestCase):
    def test_wmata_is_not_claimed_as_independent_spatial_gis(self):
        self.assertFalse(any('wmata' in key for key in east.SOURCES))

    def test_all_sources_are_public_agency_https_endpoints(self):
        for source in east.SOURCES.values():
            self.assertTrue(source['url'].startswith('https://'))
            self.assertTrue(source['metadataUrl'].startswith('https://'))


if __name__ == '__main__':
    unittest.main()
