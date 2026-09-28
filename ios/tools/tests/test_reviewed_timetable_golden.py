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
        self.assertEqual([self.stations[s['station_id']] for s in down['stop_times']],['岡山','松山'])
        self.assertEqual((down['stop_times'][0]['departure_seconds'],down['stop_times'][1]['arrival_seconds']),
                         (9*3600+25*60,12*3600+10*60))
        self.assertEqual((up['stop_times'][0]['departure_seconds'],up['stop_times'][1]['arrival_seconds']),
                         (6*3600+13*60,9*3600))
        status = {(r['entity_id'],r['dimension']):r['status'] for r in self.data['fact_completeness']}
        self.assertEqual(status[(down['trip_id'],'stops')],'partial')
        self.assertEqual(status[(down['trip_id'],'times')],'partial')


if __name__=='__main__': unittest.main()
