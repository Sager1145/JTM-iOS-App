"""Independent source-pinned expectations; fixtures do not claim route coverage."""
from pathlib import Path
import sys
import unittest

TOOLS=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(TOOLS))
import train_timetable as timetable


class ReviewedTimetableGoldenTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest=timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.data,origins=timetable.load_dataset(timetable.DEFAULT_CANONICAL,manifest)
        errors=timetable.validate_dataset(cls.data,origins,manifest)
        if errors: raise AssertionError(errors)
        cls.stations={r['station_id']:r['name_snapshot'] for r in cls.data['station_identities']}

    def trip(self,service,number,day):
        values=[r for r in timetable.materialize(self.data,day)
                if r['service_id']==service and r['public_number']==number]
        self.assertEqual(len(values),1)
        return values[0]

    def test_shinano1_official_station_sequence_and_clocks(self):
        trip=self.trip('shinano','1','2026-09-27')
        self.assertEqual(trip['train_number'],'1001M')
        self.assertEqual([self.stations[s['station_id']] for s in trip['stop_times']],
            ['名古屋','千種','多治見','中津川','南木曽','上松','木曽福島','塩尻','松本','明科','篠ノ井','長野'])
        self.assertEqual(trip['stop_times'][0]['departure_seconds'],7*3600)
        self.assertEqual(trip['stop_times'][-1]['arrival_seconds'],10*3600+3*60)

    def test_official_english_service_names_are_language_tagged(self):
        names = {
            row['service_id']: row['name']
            for row in self.data['service_name_periods']
            if row['language'] == 'en' and row['valid_from'] <= '2026-09-30'
               and (row.get('valid_until') is None or '2026-09-30' < row['valid_until'])
        }
        self.assertEqual(names['shinano'], 'Shinano')
        self.assertEqual(names['hitachi'], 'Hitachi')
        self.assertEqual(names['ibusuki-no-tamatebako'], 'IBUSUKI NO TAMATEBAKO')
        self.assertEqual(names['yufuin-no-mori'], 'YUFUIN NO MORI')
        self.assertNotIn('niseko', names)

    def test_september_30_retains_source_pinned_baseline(self):
        trips = timetable.materialize(self.data, '2026-09-30')
        counts = {}
        for trip in trips:
            counts[trip['service_id']] = counts.get(trip['service_id'], 0) + 1
        baseline = {
            'sarobetsu': 2, 'azusa': 1, 'hitachi': 1, 'shinano': 1,
            'west-express-ginga': 1, 'ibusuki-no-tamatebako': 6,
            'yufuin-no-mori': 6, 'shiokaze': 1,
        }
        for service_id, minimum in baseline.items():
            self.assertGreaterEqual(counts.get(service_id, 0), minimum)
        self.assertEqual(counts.get('ishizuchi'), 7)

    def test_ishizuchi_september_30_uses_exact_dated_evidence(self):
        # Independent expectations from the reviewed dated pages, separate from Silver Week.
        expected = {
            '1': ('18541', 'jr-odekake-shiokaze1-20260930-train', '07:37', '松山', '10:06'),
            '3': ('33291', 'jr-odekake-ishizuchi3-20260930-train', '08:45', '松山', '11:15'),
            '5': ('292', 'jr-odekake-ishizuchi5-20260930-train', '09:42', '松山', '12:10'),
            '7': ('362', 'jr-odekake-ishizuchi7-20260930-train', '10:47', '松山', '13:16'),
            '9': ('125062', 'jr-odekake-ishizuchi9-20260930-train', '11:50', '松山', '14:13'),
            '29': ('99561', 'jr-odekake-ishizuchi29-20260930-train', '22:20', '伊予西条', '23:59'),
            '30': ('28651', 'jr-odekake-ishizuchi30-20260930-train', '18:39', '高松', '21:11'),
        }
        trips = [t for t in timetable.materialize(self.data, '2026-09-30')
                 if t['service_id'] == 'ishizuchi']
        self.assertEqual(len(trips), len(expected))
        self.assertEqual({t['public_number'] for t in trips}, set(expected))
        sources = {r['source_id']: r for r in self.data['source_documents']}
        exact_ids = set()
        for trip in trips:
            public = trip['public_number']
            page, source_id, departure, destination, arrival = expected[public]
            number = f'{1000 + int(public)}M'
            trip_id = f'jr-shikoku.ishizuchi.{public}.{number.lower()}.exact-2026-09-30'
            exact_ids.add(trip_id)
            with self.subTest(public=public):
                self.assertEqual((trip['trip_id'], trip['train_number']), (trip_id, number))
                stops = trip['stop_times']
                self.assertEqual((self.stations[stops[0]['station_id']], stops[0]['departure_time']),
                                 ('松山' if public == '30' else '高松', departure))
                self.assertEqual((self.stations[stops[-1]['station_id']], stops[-1]['arrival_time']),
                                 (destination, arrival))
                self.assertEqual(sources[source_id]['effective_date'], '2026-09-30')
                self.assertEqual(sources[source_id]['url_or_locator'],
                                 f'https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930')
                for field in ('identity', 'train_number', 'stops', 'times'):
                    self.assertEqual({r['source_id'] for r in self.data['fact_sources']
                                      if r['entity_id'] == trip_id and r['field_name'] == field},
                                     {source_id})
        for day in ('2026-09-19', '2026-09-29', '2026-10-01'):
            self.assertFalse(exact_ids & {t['trip_id'] for t in timetable.materialize(self.data, day)})

    def test_lilac95_retains_previous_service_day_after_midnight(self):
        trip=self.trip('lilac','95','2026-05-16')
        self.assertEqual(trip['stop_times'][-1]['arrival_seconds'],24*3600+32*60)
        self.assertFalse(any(t['service_id']=='lilac' for t in timetable.materialize(self.data,'2026-05-17')))
        self.assertEqual(len([t for t in timetable.materialize(self.data,'2026-05-17') if t['service_id']=='kamui']),1)

    def test_kyushu_later_plan_and_missing_arrival_preserved(self):
        trips=[t for t in timetable.materialize(self.data,'2026-09-27') if t['service_id']=='yufuin-no-mori']
        self.assertEqual(sorted(t['public_number'] for t in trips),['1','2','3','4','5','6'])
        trip=self.trip('yufuin-no-mori','1','2026-09-27')
        self.assertEqual(trip['stop_times'][0]['departure_seconds'],9*3600+17*60)
        self.assertIsNone(trip['stop_times'][1]['arrival_seconds'])
        self.assertFalse(any(t['service_id']=='yufuin-no-mori' for t in timetable.materialize(self.data,'2026-09-18')))

    def test_conservative_zero_period_kept_separate_from_source_gap(self):
        row=self.data['verified_zero_service_intervals'][0]
        self.assertEqual((row['valid_from'],row['valid_until']),('1944-05-01','1949-09-01'))
        self.assertEqual(row['operator_scope'],'jr-ancestral-national-railways')
        evidence=[r for r in self.data['fact_sources'] if r['entity_id']==row['interval_id']]
        self.assertEqual(len(evidence),3)
        self.assertEqual(timetable.materialize(self.data,'1947-06-01'),[])

    def test_shiokaze_obon_announcement_covers_only_its_four_explicit_dates(self):
        for day in ['2026-08-08','2026-08-09','2026-08-15','2026-08-16']:
            trips = [t for t in timetable.materialize(self.data,day) if t['service_id']=='shiokaze']
            self.assertEqual(sorted(int(t['public_number']) for t in trips),list(range(5,29)))
        for day in ['2026-08-07','2026-08-10','2026-08-14','2026-08-17']:
            self.assertFalse(any(t['service_id']=='shiokaze' for t in timetable.materialize(self.data,day)))
        down = self.trip('shiokaze','5','2026-08-08')
        up = self.trip('shiokaze','6','2026-08-08')
        self.assertEqual([self.stations[s['station_id']] for s in down['stop_times']],
                         ['岡山','児島','宇多津','丸亀','多度津','観音寺','川之江',
                          '伊予三島','新居浜','伊予西条','壬生川','今治','松山'])
        self.assertEqual((down['stop_times'][0]['departure_seconds'],down['stop_times'][-1]['arrival_seconds']),
                         (9*3600+25*60,12*3600+10*60))
        self.assertEqual((up['stop_times'][0]['departure_seconds'],up['stop_times'][-1]['arrival_seconds']),
                         (6*3600+13*60,9*3600))
        status = {(r['entity_id'],r['dimension']):r['status'] for r in self.data['fact_completeness']}
        self.assertEqual(status[(down['trip_id'],'stops')],'verified')
        self.assertEqual(status[(down['trip_id'],'times')],'verified')

    def test_central_2013_source_totals_and_explicit_dates(self):
        # JR Central 2013-05-17 announcement, physical pages 1, 3 and 4.
        from datetime import date, timedelta
        counts = {'shinano': 0, 'hida': 0, 'nanki': 0}
        day = date(2013,7,1)
        while day < date(2013,10,1):
            for trip in timetable.materialize(self.data,day.isoformat()):
                if trip['trip_id'].endswith('2013-summer'):
                    counts[trip['service_id']] += 1
            day += timedelta(days=1)
        self.assertEqual(counts, {'shinano':52, 'hida':33, 'nanki':80})
        shinano_dates = {
            number: [
                day.isoformat()
                for day in (date(2013, 7, 1) + timedelta(days=offset)
                            for offset in range(92))
                if any(t['service_id'] == 'shinano' and t['public_number'] == number
                       for t in timetable.materialize(self.data, day.isoformat()))
            ]
            for number in ['81', '82', '84', '85']
        }
        self.assertEqual({number: len(days) for number, days in shinano_dates.items()},
                         {'81': 21, '82': 4, '84': 4, '85': 23})
        self.assertEqual(shinano_dates['82'], ['2013-09-14', '2013-09-16',
                                               '2013-09-21', '2013-09-23'])
        self.assertEqual(shinano_dates['84'], shinano_dates['82'])
        self.assertFalse(any(t['trip_id'].endswith('2013-summer')
                             for t in timetable.materialize(self.data,'2013-07-07')))

    def test_shinano81_2013_seven_day_departure_footnote(self):
        for day in ['2013-08-02','2013-08-09','2013-08-12','2013-08-13',
                    '2013-08-14','2013-08-15','2013-08-16']:
            trip = self.trip('shinano','81',day)
            self.assertEqual(trip['stop_times'][0]['departure_time'],'08:25')
            self.assertEqual(trip['stop_times'][0]['departure_seconds'],8*3600+25*60)
            self.assertEqual(trip['stop_times'][1]['arrival_time'],'12:02')
        self.assertEqual(self.trip('shinano','81','2013-08-03')
                         ['stop_times'][0]['departure_time'],'08:28')
        self.assertFalse(any(t['service_id']=='shinano' and t['public_number']=='81'
                             for t in timetable.materialize(self.data,'2013-08-01')))

    def test_nanki2013_missing_calls_and_historical_identity_not_promoted(self):
        trip = self.trip('nanki','81','2013-08-09')
        self.assertEqual([self.stations[s['station_id']] for s in trip['stop_times']],
                         ['名古屋','紀伊勝浦'])
        self.assertEqual(trip['stop_times'][-1]['arrival_time'],'12:48')
        self.assertIsNone(trip['stop_times'][0].get('arrival_time'))
        self.assertIsNone(trip['train_number'])
        status = {(r['entity_id'],r['dimension']):r['status'] for r in self.data['fact_completeness']}
        self.assertEqual(status[(trip['trip_id'],'stops')],'partial')
        self.assertEqual(status[(trip['trip_id'],'station_refs')],'partial')
        self.assertEqual(status[(trip['trip_id'],'route_lines')],'unknown')


    def test_hokuto_summer_announcement_keeps_unprinted_intermediate_times_empty(self):
        trip = self.trip('hokuto','84','2026-08-07')
        self.assertEqual(len(trip['stop_times']),16)
        self.assertEqual([self.stations[s['station_id']] for s in trip['stop_times']],
            ['札幌','新札幌','南千歳','苫小牧','白老','登別','東室蘭','伊達紋別',
             '洞爺','長万部','八雲','森','大沼公園','新函館北斗','五稜郭','函館'])
        self.assertEqual(trip['stop_times'][0]['departure_time'],'07:43')
        self.assertEqual(trip['stop_times'][-1]['arrival_time'],'11:54')
        for stop in trip['stop_times'][1:-1]:
            self.assertIsNone(stop.get('arrival_time'))
            self.assertIsNone(stop.get('departure_time'))
        up = self.trip('hokuto','91','2026-09-20')
        self.assertEqual(up['stop_times'][0]['departure_time'],'13:00')
        self.assertEqual(up['stop_times'][-1]['arrival_time'],'17:00')
        self.assertFalse(any(t['service_id']=='hokuto' and t['public_number'] in ['84','91']
                             for t in timetable.materialize(self.data,'2026-08-17')))


    def test_kamui_lower_date_cell_is_not_the_upper_full_summer_calendar(self):
        for day in ['2026-08-07','2026-08-08','2026-08-09']:
            self.trip('kamui','15',day)
            self.trip('kamui','36',day)
        for day in ['2026-07-04','2026-08-10','2026-09-19']:
            trips=timetable.materialize(self.data,day)
            self.assertTrue(any(t['service_id']=='kamui' and t['public_number']=='9' for t in trips))
            self.assertFalse(any(t['service_id']=='kamui' and t['public_number'] in ['15','36'] for t in trips))

    def test_niseko_directions_keep_their_distinct_printed_stop_lists(self):
        trips=[t for t in timetable.materialize(self.data,'2026-09-05') if t['service_id']=='niseko']
        self.assertEqual(len(trips),2)
        down=next(t for t in trips if self.stations[t['origin_station_id']]=='札幌')
        up=next(t for t in trips if self.stations[t['origin_station_id']]=='函館')
        self.assertEqual(len(down['stop_times']),14)
        self.assertEqual(len(up['stop_times']),15)
        self.assertNotIn('大沼公園',[self.stations[s['station_id']] for s in down['stop_times']])
        self.assertIn('大沼公園',[self.stations[s['station_id']] for s in up['stop_times']])
        self.assertIsNone(down['public_number'])
        self.assertIsNone(up['public_number'])

    def test_sarobetsu_september_30_official_columns_preserve_partial_clocks(self):
        trip=self.trip('sarobetsu','4','2026-09-30')
        self.assertEqual(trip['train_number'],'6064D')
        self.assertEqual([self.stations[s['station_id']] for s in trip['stop_times']],
            ['稚内','南稚内','豊富','幌延','天塩中川','音威子府',
             '美深','名寄','士別','和寒','旭川'])
        stops={self.stations[s['station_id']]:s for s in trip['stop_times']}
        self.assertEqual(stops['稚内']['departure_time'],'13:01')
        self.assertIsNone(stops['南稚内']['arrival_time'])
        self.assertEqual(stops['南稚内']['departure_time'],'13:05')
        self.assertEqual((stops['幌延']['arrival_time'],stops['幌延']['departure_time']),
                         ('13:56','13:57'))
        self.assertEqual(stops['旭川']['arrival_time'],'16:45')

        down=self.trip('sarobetsu','3','2026-09-30')
        self.assertEqual(down['train_number'],'6063D')
        self.assertEqual([self.stations[s['station_id']] for s in down['stop_times']],
            ['旭川','和寒','士別','名寄','美深','音威子府',
             '天塩中川','幌延','豊富','南稚内','稚内'])
        status={(r['entity_id'],r['dimension']):r['status']
                for r in self.data['fact_completeness']}
        self.assertEqual(status[(trip['trip_id'],'stops')],'verified')
        self.assertEqual(status[(trip['trip_id'],'times')],'partial')
        self.assertEqual(status[(trip['trip_id'],'operator')],'verified')
        self.assertEqual(status[(trip['trip_id'],'route_lines')],'partial')
        operators=[r for r in self.data['trip_operator_segments']
                   if r['trip_id']==trip['trip_id']]
        self.assertEqual(operators,[{'trip_id':trip['trip_id'],'from_sequence':1,
                                     'to_sequence':11,'operator_id':'jr-hokkaido'}])
        lines=[r for r in self.data['trip_line_segments']
               if r['trip_id']==trip['trip_id']]
        self.assertEqual(len(lines),10)
        self.assertEqual({r['line_name'] for r in lines},{'宗谷線'})

    def test_ginga_night_dwell_retains_verbatim_clocks_on_separate_civil_days(self):
        trips=[t for t in timetable.materialize(self.data,'2026-07-03')
               if t['trip_id'].startswith('jr-west.west-express-ginga.kumano-night.')]
        self.assertEqual(len(trips),1)
        trip=trips[0]
        wakayama=next(s for s in trip['stop_times'] if self.stations[s['station_id']]=='和歌山')
        self.assertEqual((wakayama['arrival_time'],wakayama['departure_time']),('23:42','0:30'))
        self.assertEqual((wakayama['arrival_seconds'],wakayama['departure_seconds']),(85320,88200))
        self.assertEqual((wakayama['arrival_day_offset'],wakayama['departure_day_offset']),(0,1))
        self.assertEqual(wakayama['call_type'],'operational_stop')
        self.assertEqual((wakayama['pickup_allowed'],wakayama['dropoff_allowed']),(0,0))
        self.assertEqual(trip['stop_times'][-1]['arrival_seconds'],120900)
        self.assertTrue(any(t['trip_id']==trip['trip_id'] for t in timetable.materialize(self.data,'2026-09-28')))
        self.assertFalse(any(t['trip_id']==trip['trip_id'] for t in timetable.materialize(self.data,'2026-09-29')))

    def test_ginga_day_holiday_clocks_come_from_parenthesized_source_values(self):
        def stops(day):
            trip=next(t for t in timetable.materialize(self.data,day)
                      if t['trip_id'].startswith('jr-west.west-express-ginga.kumano-day.'))
            return {self.stations[s['station_id']]:s for s in trip['stop_times']}
        holiday=stops('2026-07-05')
        regular=stops('2026-07-08')
        self.assertEqual(holiday['海南']['departure_time'],'18:45')
        self.assertEqual(regular['海南']['departure_time'],'18:46')
        self.assertEqual(holiday['和歌山']['arrival_time'],'18:55')
        self.assertEqual(holiday['和歌山']['departure_time'],'18:57')
        self.assertEqual(holiday['日根野']['arrival_time'],'19:28')
        self.assertEqual(holiday['日根野']['departure_time'],'19:31')
        self.assertEqual(holiday['新大阪']['departure_time'],'20:23')


if __name__=='__main__': unittest.main()
