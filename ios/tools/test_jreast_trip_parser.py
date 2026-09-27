import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('jreast_parser', HERE / 'parse-jreast-trip.py')
parser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser)


class JREastParserTests(unittest.TestCase):
    def setUp(self):
        self.html = (HERE / 'fixtures/jreast-shinano1-reduced.html').read_text()

    def test_published_number_stops_times_and_exact_calendar(self):
        value = parser.parse(self.html, 'fixture')
        self.assertEqual(value['train_number'], '1001M')
        self.assertEqual(value['operating_dates'], ['2026-09-27'])
        self.assertEqual(len(value['stop_times']), 12)
        self.assertEqual(value['stop_times'][0]['departure_time'], '07:00')
        self.assertEqual(value['stop_times'][-1]['arrival_time'], '10:03')
        self.assertEqual(value['stop_times'][7]['name_snapshot'], '塩尻')
        self.assertEqual(value['stop_times'][7]['departure_time'], '08:59')
        self.assertFalse(any(s['call_type'] == 'pass' for s in value['stop_times']))

    def test_rejects_unexplained_backwards_clock(self):
        with self.assertRaisesRegex(ValueError, 'midnight'):
            parser.parse(self.html.replace('10:03', '00:03'), 'fixture')

    def test_rejects_rapid(self):
        with self.assertRaisesRegex(ValueError, 'limited express'):
            parser.parse(self.html.replace('>特急<', '>快速<'), 'fixture')


if __name__ == '__main__':
    unittest.main()
