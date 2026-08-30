import importlib.util
import json
import os
import sys
import tempfile
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-intercity-official-networks.py'))
REGISTRY = os.path.join(os.path.dirname(SCRIPT), 'na-feeds.json')
sys.path.insert(0, os.path.dirname(SCRIPT))
SPEC = importlib.util.spec_from_file_location('intercity_official', SCRIPT)
normalizer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(normalizer)


def feature(property_name, name):
    return {
        'type': 'Feature',
        'properties': {property_name: name},
        'geometry': {'type': 'LineString',
                     'coordinates': [[-1.0, 1.0], [-0.9, 1.1]]},
    }


class IntercityOfficialNetworkTests(unittest.TestCase):
    def test_registry_has_no_duplicate_keys_and_exact_fail_closed_mappings(self):
        def reject_duplicate_keys(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise ValueError(f'duplicate JSON key: {key}')
                result[key] = value
            return result

        with open(REGISTRY, encoding='utf-8') as source_file:
            registry = json.load(
                source_file, object_pairs_hook=reject_duplicate_keys)
        by_slug = {entry['slug']: entry for entry in registry['feeds']}
        expected = {
            'amtrak': set(normalizer.AMTRAK.values()),
            'metro-north-railroad': set(normalizer.MNR.values()),
            'metrolink': set(normalizer.METROLINK.values()),
        }
        for slug, keys in expected.items():
            entry = by_slug[slug]
            self.assertTrue(entry['requireVerifiedOfficialNetwork'])
            self.assertEqual(set(entry['officialNetworkByRouteId'].values()), keys)

    def test_amtrak_names_are_exact_and_missing_service_fails_closed(self):
        features = [feature('name', name) for name in normalizer.AMTRAK]
        groups = normalizer.exact_groups(
            features, 'name', normalizer.AMTRAK)
        self.assertEqual(set(groups), set(normalizer.AMTRAK.values()))
        with self.assertRaisesRegex(SystemExit, 'expected exactly one'):
            normalizer.exact_groups(
                features[:-1], 'name', normalizer.AMTRAK)

    def test_metro_north_branches_include_official_new_haven_trunk(self):
        features = [feature('route_name', name) for name in normalizer.MNR]
        by_name = {row['properties']['route_name']: row for row in features}
        by_name['Hudson Line']['geometry']['coordinates'] = [
            [-1.1, 0.9], [-1.0, 1.0], [-0.9, 1.1]]
        by_name['Harlem Line']['geometry']['coordinates'] = [
            [-1.0, 1.0], [-0.95, 1.05], [-0.9, 1.1]]
        new_haven = next(row for row in features
                         if row['properties']['route_name'] == 'New Haven Line')
        new_haven['geometry']['coordinates'][0] = [-0.9501, 1.05]
        groups = normalizer.mnr_groups(features)
        self.assertEqual(len(groups['mnr-hudson']), 1)
        self.assertEqual(len(groups['mnr-harlem']), 2)
        self.assertEqual(len(groups['mnr-new-haven']), 3)
        self.assertEqual(len(groups['mnr-new-canaan']), 4)
        self.assertEqual(len(groups['mnr-waterbury']), 2)
        names = {row['properties']['route_name']
                 for row in groups['mnr-new-canaan']}
        self.assertEqual(names, {
            'Hudson Line', 'Harlem Line', 'New Haven Line',
            'New Canaan Branch'})
        normalized_new_haven = next(
            row for row in groups['mnr-new-haven']
            if row['properties']['route_name'] == 'New Haven Line')
        self.assertEqual(
            normalized_new_haven['geometry']['coordinates'][0], [-0.95, 1.05])
        self.assertEqual(
            new_haven['geometry']['coordinates'][0], [-0.9501, 1.05])
        new_haven_parts = {
            row['properties']['route_name']: row
            for row in groups['mnr-new-haven']}
        self.assertEqual(
            new_haven_parts['Hudson Line']['geometry']['coordinates'][-1],
            [-1.0, 1.0])
        self.assertEqual(
            new_haven_parts['Harlem Line']['geometry']['coordinates'][-1],
            [-0.95, 1.05])
        self.assertNotIn('Danbury Branch', new_haven_parts)

    def test_metro_north_shared_trunk_gap_change_fails_closed(self):
        features = [feature('route_name', name) for name in normalizer.MNR]
        by_name = {row['properties']['route_name']: row for row in features}
        by_name['Hudson Line']['geometry']['coordinates'] = [
            [-1.1, 0.9], [-1.0, 1.0], [-0.9, 1.1]]
        by_name['Harlem Line']['geometry']['coordinates'] = [
            [-1.0, 1.0], [-0.95, 1.05], [-0.9, 1.1]]
        new_haven = next(row for row in features
                         if row['properties']['route_name'] == 'New Haven Line')
        new_haven['geometry']['coordinates'][0] = [-0.951, 1.05]
        with self.assertRaisesRegex(SystemExit, 'junction gap changed'):
            normalizer.mnr_groups(features)

    def test_metrolink_has_exactly_the_seven_scrra_2025_lines(self):
        features = [feature('Name', name) for name in normalizer.METROLINK]
        groups = normalizer.exact_groups(
            features, 'Name', normalizer.METROLINK)
        self.assertEqual(len(groups), 7)

    def test_normalized_payload_records_raw_and_normalized_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            source = 'amtrak-ntad'
            record = normalizer.write_group(
                directory, 'amtrak-ntad-cascades',
                [feature('name', 'Amtrak Cascades')], source, 'a' * 64)
            with open(os.path.join(
                    directory, 'amtrak-ntad-cascades.geojson')) as source_file:
                payload = json.load(source_file)
            self.assertEqual(payload['source']['rawSha256'], 'a' * 64)
            self.assertEqual(len(record['sha256']), 64)
            self.assertEqual(record['features'], 1)


if __name__ == '__main__':
    unittest.main()
