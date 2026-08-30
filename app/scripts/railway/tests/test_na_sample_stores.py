import importlib.util
import os
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'make-na-sample-stores.py'))
SPEC = importlib.util.spec_from_file_location('na_sample_stores', SCRIPT)
samples = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(samples)


class CrossBorderSampleTests(unittest.TestCase):
    def test_overlapping_border_station_is_written_once(self):
        package = {'lines': [
            {
                'id': 'train-us', 'name': 'International', 'operator': 'Railway',
                'color': '#123456',
                'stations': [
                    ['US-A', 'Albany', -73.75, 42.65],
                    ['US-BORDER', 'Rouses Point', -73.37, 44.99],
                ],
            },
            {
                'id': 'train-ca', 'name': 'International', 'operator': 'Railway',
                'color': '#123456',
                'stations': [
                    # A separately coded copy of the same physical platform.
                    ['CA-BORDER', 'Rouses Point', -73.37001, 44.99001],
                    ['CA-Z', 'Montréal', -73.55, 45.50],
                ],
            },
        ]}
        spec = {
            'id': 'cross-border', 'date': '2026-01-01', 'number': '1',
            'trainType': 'intercity',
            'lines': [
                {'id': 'train-us', 'from': 'Albany', 'to': 'Rouses Point'},
                {'id': 'train-ca', 'from': 'Rouses Point', 'to': 'Montréal'},
            ],
        }

        result = samples.journey(package, {}, spec, 'us')

        self.assertIsNotNone(result)
        self.assertEqual([stop['name'] for stop in result['stops']],
                         ['Albany', 'Rouses Point', 'Montréal'])
        self.assertEqual(len(result['route_sections']), 2)
        self.assertTrue(all(
            section['from_n02_station_code'] != section['to_n02_station_code']
            for section in result['route_sections']))


if __name__ == '__main__':
    unittest.main()
