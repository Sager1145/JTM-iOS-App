"""Contract checks for the eight dated JR Central summer supplement rows."""
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'app/data/train-service-history'
BATCH = 'reviewed-central-2026-summer'


def read(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line]


class CentralSummer2026Tests(unittest.TestCase):
    def test_source_is_official_and_scope_is_explicit(self):
        candidate = json.loads((BASE / 'candidates/jr-central-20260526-hida-nanki-summer.json').read_text(encoding='utf-8'))
        self.assertEqual(candidate['source']['url_or_locator'], 'https://jr-central.co.jp/news/release/_pdf/000045605.pdf')
        self.assertEqual(candidate['source']['publication_date'], '2026-05-26')
        self.assertEqual(candidate['promotion_scope'], 'only_the_eight_printed_trips_on_explicit_2026_dates_with_endpoint_times')
        self.assertEqual(len(candidate['trips']), 8)

    def test_exact_date_groups_and_endpoints(self):
        trips = read(BASE / f'normalized/trips/{BATCH}/seeds.jsonl')
        calls = read(BASE / f'normalized/stop-times/{BATCH}/seeds.jsonl')
        exceptions = read(BASE / f'normalized/calendar-exceptions/{BATCH}/seeds.jsonl')
        self.assertEqual(len(trips), 8)
        self.assertEqual(len(calls), 16)
        self.assertEqual(len(exceptions), 80)
        expected = {'hida': {'81': 17, '82': 17, '83': 5, '84': 5},
                    'nanki': {'81': 4, '82': 4, '83': 14, '84': 14}}
        by_calendar = {}
        for row in exceptions:
            by_calendar.setdefault(row['calendar_id'], set()).add(row['service_date'])
        for trip in trips:
            self.assertEqual(len(by_calendar[trip['calendar_id']]), expected[trip['service_id']][trip['public_number']])
            self.assertIsNone(trip['train_number'])
            trip_calls = sorted((row for row in calls if row['trip_id'] == trip['trip_id']), key=lambda row: row['stop_sequence'])
            self.assertEqual([row['call_type'] for row in trip_calls], ['origin', 'destination'])
            self.assertIsNone(trip_calls[0]['arrival_time'])
            self.assertIsNone(trip_calls[1]['departure_time'])
        first = next(row for row in trips if row['service_id'] == 'hida' and row['public_number'] == '81')
        first_calls = sorted((row for row in calls if row['trip_id'] == first['trip_id']), key=lambda row: row['stop_sequence'])
        self.assertEqual((first_calls[0]['departure_time'], first_calls[1]['arrival_time']), ('10:18', '13:00'))


if __name__ == '__main__':
    unittest.main()
