import copy
import importlib.util
import json
from pathlib import Path
import unittest

SAMPLES = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('sample_pass_cleanup', SAMPLES / 'remove-unverified-limited-express-passes.py')
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class SamplePassingStationEvidenceTests(unittest.TestCase):
    def seed(self):
        return {'id': 'fixture', 'date': '2026-07-29', 'train_type': '寝台特急',
                'stops': [{'name': 'A', 'n02_station_code': 'a', 'stop_type': 'origin', 'departure': '23:55'},
                          {'name': 'guessed', 'n02_station_code': 'g', 'stop_type': 'pass_through'},
                          {'name': '岡山', 'n02_station_code': 'o', 'stop_type': 'passenger_stop', 'arrival': '24:15'},
                          {'name': 'B', 'n02_station_code': 'b', 'stop_type': 'destination', 'arrival': '25:05'}],
                'route_sections': [{'from_n02_station_code': 'a', 'to_n02_station_code': 'g', 'line_names': ['guessed branch']}],
                'route_policy': {'jr_only': True, 'preferred_line_names': ['guessed branch'], 'preferred_operator_names': ['guessed operator']},
                'notes': 'existing'}

    def test_omitted_passes_do_not_become_union_of_guessed_line_constraints(self):
        original = self.seed()
        before = copy.deepcopy(original)
        result, removed = cleanup.clean_train(original)
        self.assertEqual(before, original)
        self.assertEqual(['guessed'], removed)
        self.assertEqual([original['stops'][i] for i in (0, 2, 3)], result['stops'])
        self.assertEqual([], result['route_sections'])
        self.assertEqual({'jr_only': True}, result['route_policy'])
        self.assertIn('existing', result['notes'])
        self.assertEqual((result, []), cleanup.clean_train(result))

    def test_exact_date_source_review_retains_explicit_passing_sequence(self):
        train = self.seed()
        self.assertEqual((train, []), cleanup.clean_train(train, {'date': train['date'], 'status': 'ridden_timetable_verified'}))
        with self.assertRaises(ValueError):
            cleanup.clean_train(train, {'date': '2026-09-30', 'status': 'ridden_timetable_verified'})

    def test_source_reviewed_numbers_survive_without_physical_line_claims(self):
        train = self.seed()
        review = {'date': train['date'], 'status': 'passenger_timetable_verified_route_gap',
                  'section_number_boundary': {'station': '岡山', 'before': '5031M', 'after': '4031M'}}
        result, _ = cleanup.clean_train(train, review)
        self.assertEqual(['5031M', '4031M'], [row['number'] for row in result['route_sections']])
        self.assertFalse(any('line_names' in row or 'operator_names' in row for row in result['route_sections']))
        self.assertEqual('25:05', result['stops'][-1]['arrival'])

    def test_reviewed_production_calls_remain_equal_to_independent_review(self):
        reviews = {r['train_id']: r for r in cleanup.read(cleanup.REVIEW)['reviews']}
        for path in cleanup.STORES:
            for train in cleanup.read(path)['trains']:
                review = reviews.get(train['id'])
                if review:
                    actual = [{k: stop.get(k) for k in ('name', 'arrival', 'departure', 'stop_type')}
                              for stop in train['stops'] if stop.get('stop_type') != 'pass_through']
                    self.assertEqual(review['verified_passenger_calls'], actual)


if __name__ == '__main__':
    unittest.main()
