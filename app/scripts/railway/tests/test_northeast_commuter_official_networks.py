import importlib.util
import json
import os
import sys
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-northeast-commuter-official-networks.py'))
REGISTRY = os.path.join(os.path.dirname(SCRIPT), 'na-feeds.json')
sys.path.insert(0, os.path.dirname(SCRIPT))
SPEC = importlib.util.spec_from_file_location('northeast_official', SCRIPT)
normalizer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(normalizer)


def feature(property_name, name):
    return {
        'type': 'Feature',
        'properties': {property_name: name},
        'geometry': {'type': 'LineString',
                     'coordinates': [[-74.0, 40.7], [-73.9, 40.8]]},
    }


class NortheastOfficialNetworkTests(unittest.TestCase):
    def test_lirr_routes_get_only_their_exact_official_branches(self):
        names = sorted({name for values in normalizer.LIRR.values()
                        for name in values})
        rows = [feature('route_name', name) for name in names]
        groups = normalizer.exact_groups(
            rows, 'route_name', normalizer.LIRR)
        ronkonkoma = {
            row['properties']['route_name']
            for row in groups['lirr-4-ronkonkoma']}
        self.assertEqual(ronkonkoma, {
            'CITY TERMINAL ZONE', 'HEMPSTEAD', 'PORT JEFFERSON',
            'RONKONKOMA'})
        self.assertNotIn('OYSTER BAY', ronkonkoma)
        port_jefferson = {
            row['properties']['route_name']
            for row in groups['lirr-10-port-jefferson']}
        self.assertNotIn('RONKONKOMA', port_jefferson)

    def test_lirr_only_closes_the_three_guarded_published_junctions(self):
        old_a = [-73.80483358499998, 40.70080943700003]
        new_a = [-73.80492778599995, 40.70073068500005]
        old_b = [-73.80695534299997, 40.70011911100005]
        new_b = [-73.80702235799998, 40.70019521000006]
        old_west = [-73.80464297899994, 40.700408234000065]
        rows = [
            feature('route_name', 'CITY TERMINAL ZONE'),
            feature('route_name', 'HEMPSTEAD'),
            feature('route_name', 'FAR ROCKAWAY'),
            feature('route_name', 'WEST HEMPSTEAD'),
        ]
        rows[0]['geometry']['coordinates'] = [old_a, new_a, old_b, new_b]
        rows[1]['geometry']['coordinates'][0] = old_a
        rows[2]['geometry']['coordinates'][0] = old_b
        rows[3]['geometry']['coordinates'][0] = old_west
        normalized = normalizer.close_lirr_published_junctions(rows)
        by_name = {row['properties']['route_name']: row for row in normalized}
        self.assertEqual(
            by_name['HEMPSTEAD']['geometry']['coordinates'][0], new_a)
        self.assertEqual(
            by_name['FAR ROCKAWAY']['geometry']['coordinates'][0], new_b)
        self.assertEqual(
            by_name['WEST HEMPSTEAD']['geometry']['coordinates'][0], new_a)
        self.assertEqual(rows[1]['geometry']['coordinates'][0], old_a)

    def test_njt_main_bergen_and_port_jervis_composites_are_exact(self):
        names = sorted({name for values in normalizer.NJT_RAIL.values()
                        for name in values})
        rows = [feature('LINE_NAME', name) for name in names]
        groups = normalizer.exact_groups(
            rows, 'LINE_NAME', normalizer.NJT_RAIL)
        main_bergen = {
            row['properties']['LINE_NAME']
            for row in groups['njt-rail-5-main-bergen']}
        self.assertEqual(main_bergen, {'Main Line', 'Bergen County Line'})
        port_jervis = {
            row['properties']['LINE_NAME']
            for row in groups['njt-rail-6-port-jervis']}
        self.assertEqual(port_jervis, {
            'Main Line', 'Bergen County Line', 'Southern Tier'})
        self.assertNotIn('Pascack Valley Line', port_jervis)

    def test_njt_light_feature_counts_fail_closed(self):
        rows = ([feature('LINE_CODE', 'HB') for _ in range(3)]
                + [feature('LINE_CODE', 'Newark Light Rail') for _ in range(2)]
                + [feature('LINE_CODE', 'RiverLINE')])
        groups = normalizer.light_groups(rows)
        self.assertEqual(len(groups['njt-light-4-hblr']), 3)
        with self.assertRaisesRegex(SystemExit, 'expected 3'):
            normalizer.light_groups(rows[1:])

    def test_path_maps_only_the_five_officially_published_services(self):
        rows = [feature('SERVICE', name) for name in normalizer.PATH.values()]
        groups = normalizer.path_groups(rows)
        self.assertEqual(set(groups), set(normalizer.PATH))
        self.assertNotIn('path-njt-77285-wtc-33', groups)

    def test_registry_has_no_duplicate_keys_and_exact_route_ownership(self):
        def reject_duplicates(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise ValueError(f'duplicate JSON key: {key}')
                result[key] = value
            return result

        with open(REGISTRY, encoding='utf-8') as source_file:
            registry = json.load(
                source_file, object_pairs_hook=reject_duplicates)
        by_slug = {entry['slug']: entry for entry in registry['feeds']}
        expected = {
            'mta-long-island-rail-road': set(normalizer.LIRR),
            'new-jersey-transit-nj-transi': (
                set(normalizer.NJT_RAIL) | set(normalizer.NJT_LIGHT)),
            'port-authority-trans-hudson': set(normalizer.PATH),
        }
        for slug, keys in expected.items():
            entry = by_slug[slug]
            self.assertTrue(entry['requireVerifiedOfficialNetwork'])
            self.assertEqual(set(entry['officialNetworkByRouteId'].values()), keys)


if __name__ == '__main__':
    unittest.main()
