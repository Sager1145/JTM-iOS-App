import importlib.util
import sqlite3
import unittest
from pathlib import Path

path = Path(__file__).parents[1] / 'align-sample-timetable-fields.py'
spec = importlib.util.spec_from_file_location('alignment', path)
alignment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(alignment)


class AlignmentTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
        CREATE TABLE timetable_versions(timetable_version_id, effective_from, effective_until);
        CREATE TABLE calendars(calendar_id, valid_from, valid_until, holiday_policy,
          monday,tuesday,wednesday,thursday,friday,saturday,sunday);
        CREATE TABLE calendar_exceptions(calendar_id,service_date,exception_type);
        CREATE TABLE holiday_calendar_years(year,status);
        CREATE TABLE holiday_dates(service_date);
        CREATE TABLE trips(trip_id,service_id,public_number);
        CREATE TABLE service_name_periods(service_id,name);
        CREATE TABLE station_identities(station_id,current_source_code,name_snapshot);
        CREATE TABLE stop_times(trip_id,stop_sequence,station_id);
        INSERT INTO timetable_versions VALUES('v','2026-07-01','2026-08-01');
        INSERT INTO calendars VALUES('c','2026-07-01','2026-07-31','none',1,1,1,1,1,0,0);
        ''')
        self.trip = {'timetable_version_id': 'v', 'calendar_id': 'c'}

    def tearDown(self):
        self.db.close()

    def test_calendar_exceptions_cannot_extend_version(self):
        self.db.execute("INSERT INTO calendar_exceptions VALUES('c','2026-08-01','add')")
        self.assertFalse(alignment.active(self.db, self.trip, '2026-08-01'))
        self.assertFalse(alignment.active(self.db, self.trip, '2026-06-30'))
        self.assertFalse(alignment.active(self.db, self.trip, '2026-07-31'))

    def test_weekday_and_exception(self):
        self.assertTrue(alignment.active(self.db, self.trip, '2026-07-03'))
        self.assertFalse(alignment.active(self.db, self.trip, '2026-07-04'))
        self.db.execute("INSERT INTO calendar_exceptions VALUES('c','2026-07-04','add')")
        self.assertTrue(alignment.active(self.db, self.trip, '2026-07-04'))
        self.db.execute("INSERT INTO calendar_exceptions VALUES('c','2026-07-03','remove')")
        self.assertFalse(alignment.active(self.db, self.trip, '2026-07-03'))

    def test_unverified_holiday_calendar_does_not_guess(self):
        self.db.execute("UPDATE calendars SET holiday_policy='treat_as_sunday'")
        self.assertFalse(alignment.active(self.db, self.trip, '2026-07-03'))
        self.db.execute("INSERT INTO holiday_calendar_years VALUES(2026,'verified')")
        self.assertTrue(alignment.active(self.db, self.trip, '2026-07-03'))
        self.db.execute("INSERT INTO holiday_dates VALUES('2026-07-03')")
        self.assertFalse(alignment.active(self.db, self.trip, '2026-07-03'))

    def test_identity_uses_brand_public_number_not_operating_number(self):
        self.db.execute("INSERT INTO service_name_periods VALUES('nanpu','南風')")
        self.db.executemany('INSERT INTO trips VALUES(?,?,?)', [('9','nanpu','9'), ('90','nanpu','90'), ('39','nanpu','39')])
        self.assertEqual([t['trip_id'] for t in alignment.identity_candidates(self.db, {'number': '南風9号（39D）'})], ['9'])
        self.assertEqual([t['trip_id'] for t in alignment.identity_candidates(self.db, {'number': '南風90号'})], ['90'])
        self.assertFalse(alignment.identity_candidates(self.db, {'number': 'しおかぜ9号（39D）'}))

    def test_overnight_seconds_keep_service_day(self):
        self.assertEqual(alignment.hhmm(88200), '24:30')
        self.assertEqual(alignment.hhmm(122400), '34:00')
        self.assertIsNone(alignment.hhmm(None))

    def test_ridden_endpoints_require_order_and_unambiguous_identity(self):
        self.db.executemany('INSERT INTO station_identities VALUES(?,?,?)', [('a','A','Alpha'), ('b','B','Beta'), ('c','C','Gamma')])
        self.db.executemany('INSERT INTO stop_times VALUES(?,?,?)', [('t',0,'a'), ('t',1,'b'), ('t',2,'c')])
        train = {'stops': [{'n02_station_code': 'A'}, {'n02_station_code': 'C'}]}
        self.assertEqual(len(alignment.ridden_calls(self.db, {'trip_id': 't'}, train)), 3)
        train['stops'].reverse()
        self.assertIsNone(alignment.ridden_calls(self.db, {'trip_id': 't'}, train))
        train['stops'].reverse()
        self.db.execute("INSERT INTO stop_times VALUES('t',3,'a')")
        self.db.execute("INSERT INTO stop_times VALUES('t',4,'c')")
        self.assertIsNone(alignment.ridden_calls(self.db, {'trip_id': 't'}, train))

    def test_enrichment_preserves_ridden_boundaries_and_route_metadata(self):
        self.db.executescript("""
        CREATE TABLE trip_stop_time_overrides(trip_id, service_date, stop_sequence,
          arrival_override, arrival_seconds_override, departure_override, departure_seconds_override,
          platform_override_present, platform_override);
        CREATE TABLE trip_formations(trip_id,service_date,vehicle_series);
        """)
        train = {'date': '2026-07-03', 'direction': 'unknown',
                 'route_sections': [{'number': '6M'}],
                 'stops': [{'n02_station_code': 'A', 'arrival': None, 'departure': '08:00'},
                           {'n02_station_code': 'B', 'arrival': '09:00', 'departure': None}]}
        rows = [{'current_source_code': 'A', 'call_type': 'passenger_stop', 'time_accuracy': 'minute',
                 'stop_sequence': 1, 'arrival_seconds': 28080, 'departure_seconds': 28860, 'platform': '2'},
                {'current_source_code': 'B', 'call_type': 'passenger_stop', 'time_accuracy': 'minute',
                 'stop_sequence': 2, 'arrival_seconds': 32520, 'departure_seconds': 32700, 'platform': '2/3'}]
        revised, fields = alignment.enrich(self.db, train, {'trip_id': 't', 'direction': None}, rows)
        self.assertIsNone(revised['stops'][0]['arrival'])
        self.assertIsNone(revised['stops'][-1]['departure'])
        self.assertEqual(revised['stops'][0]['departure'], '08:01')
        self.assertEqual(revised['stops'][-1]['arrival'], '09:02')
        self.assertEqual(revised['stops'][0]['platform_number'], 2)
        self.assertNotIn('platform_number', revised['stops'][1])
        self.assertEqual(revised['route_sections'], train['route_sections'])
        self.assertEqual(train['stops'][0]['departure'], '08:00')

    def test_english_caption_uses_shared_splitter_without_inventing_numbers(self):
        captions = alignment.latin_captions()
        self.assertEqual(captions['20260708_02_shirasagi2'], 'Shirasagi 6')
        self.assertEqual(captions['20260729_05_sunrise_izumo'], 'Sunrise Izumo')
        self.assertNotIn('20260722_01_ibusuki_1321d_kagoshima_yamakawa', captions)

    def test_caption_vehicle_does_not_confuse_route_system_numbers(self):
        self.assertEqual(alignment.caption_vehicle('ソニック54号（885系「白いソニック」）'), '885系')
        self.assertEqual(alignment.caption_vehicle('こだま970号（500系）'), '500系')
        self.assertIsNone(alignment.caption_vehicle('函館市電５系統'))
        self.assertIsNone(alignment.caption_vehicle('鹿児島市電2系統'))

    def test_region_inventory_covers_all_seven_regions(self):
        self.assertEqual({region for _, region, _, _ in alignment.datasets()}, {'jp','tw','hk','mo','kr','us','ca'})
        self.assertEqual(len(list(alignment.datasets())), 9)


if __name__ == '__main__':
    unittest.main()
