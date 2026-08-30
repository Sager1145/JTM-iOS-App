import importlib.util
import json
import os
import unittest


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
AUDIT = os.path.join(ROOT, 'audit-north-america-packages.py')
SPEC = importlib.util.spec_from_file_location('strict_audit', AUDIT)
strict_audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(strict_audit)


class ColourBrandMetadataTests(unittest.TestCase):
    def test_only_gtfs_or_exact_audited_override_sources_are_approved(self):
        errors = []
        sources = strict_audit.approved_colour_sources({
            'feeds': [{
                'slug': 'sample',
                'officialColorByRouteId': {'R': '123ABC'},
                'officialColorSourceByRouteId': {
                    'R': 'Operator official design standard'},
            }],
        }, errors)
        self.assertEqual(errors, [])
        self.assertEqual(sources, {
            strict_audit.GTFS_COLOUR_SOURCE,
            'Operator official design standard',
        })

    def test_mismatched_or_generated_colour_metadata_fails_closed(self):
        errors = []
        strict_audit.approved_colour_sources({
            'feeds': [{
                'slug': 'bad',
                'officialColorByRouteId': {'R': '123ABC', 'S': 'not-hex'},
                'officialColorSourceByRouteId': {
                    'R': 'random generated palette'},
                'color': '112233',
            }],
        }, errors)
        self.assertTrue(any('route ids differ' in row for row in errors))
        self.assertTrue(any('non-official colour' in row for row in errors))
        self.assertTrue(any('must be paired' in row for row in errors))

    def test_houston_and_airport_mac_are_explicitly_audited_unbranded(self):
        with open(os.path.join(ROOT, 'na-operator-brands.json'),
                  encoding='utf-8') as source:
            unbranded = json.load(source)['unbranded']
        self.assertIn('houston-metro', unbranded)
        self.assertIn('metro-transit', unbranded)
        self.assertIn('METRO', unbranded['houston-metro']['operator'])
        self.assertIn('Airport', unbranded['metro-transit']['operator'])


if __name__ == '__main__':
    unittest.main()
