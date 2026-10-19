"""Scratch-only behavioral contracts for reviewed flat-column and batch staging."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import reviewed_timetable_staging as staging


class AdditionalStagingTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.base = self.root / 'data'
        self.base.mkdir()

    def json(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')

    def records(self, relative):
        return staging.read_jsonl(self.base / relative)

    def east_arguments(self):
        candidate = self.base / 'candidate.json'
        self.json(candidate, {'origin': '東京', 'destination': '甲府',
                              'source_locator': 'reviewed-column',
                              'stops': [['東京', None, '23:45'], ['甲府', '24:37', None]]})
        self.json(self.root / 'app/public/rail/jp-2025.json', {
            'lines': [{'operator': '東日本旅客鉄道',
                       'stations': [['003766', '東京'], ['999999', '東京'], ['004001', '甲府']]}]})
        return dict(
            base=self.base, candidate_path=candidate, suffix='test', trip_id='test.trip',
            day='2026-09-30', until='2026-10-01', source_id='official',
            weekdays=('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'),
            platforms={'東京': '１'}, validate=lambda candidate: None,
            station_ids=lambda stops: staging.jr_east_forced_station_ids(
                self.root, [{'stops': stops}], {}, forced_codes={'東京': {'003766'}}),
            rows=lambda pattern, exclude=None: staging.iter_jsonl(self.base, pattern, exclude),
            write=staging.emit_jsonl,
            statuses={'times': ('verified', 'high', 'Printed clocks'),
                      'station_refs': ('verified', 'high', 'Reviewed directory'),
                      'route_lines': ('unknown', 'low', 'Unresolved physical route')},
            copy={'source_record': {'source_id': 'official'}, 'edition_name': 'Reviewed day',
                  'trip_fields': {'service_id': 'kaiji', 'train_number': '5159M',
                                  'public_number': '59', 'service_class': 'limited_express'},
                  'summary': 'Staged test trip'})

    def test_flat_column_keeps_explicit_clock_policy_and_exact_date_evidence(self):
        args = self.east_arguments()
        args['clock_fields'] = lambda arrival, departure: {
            'arrival_time': None if arrival is None else f'{int(arrival[:2]) % 24:02d}' + arrival[2:],
            'departure_time': None if departure is None else f'{int(departure[:2]) % 24:02d}' + departure[2:],
            'day_offset': int((arrival or departure)[:2]) // 24}
        with contextlib.redirect_stdout(io.StringIO()):
            staging.stage_jr_east_single_trip(**args)
        stops = self.records('normalized/stop-times/test/seeds.jsonl')
        self.assertEqual([(r['arrival_time'], r['departure_time'], r['day_offset']) for r in stops],
                         [(None, '23:45', 0), ('00:37', None, 1)])
        self.assertEqual(stops[0]['station_id'], 'jp.n02.003766')
        self.assertEqual([(r['pickup_allowed'], r['dropoff_allowed']) for r in stops], [(1, 0), (0, 1)])
        calendar = self.records('normalized/calendars/test/seeds.jsonl')[0]
        self.assertEqual([calendar[day] for day in args['weekdays']], [0] * 7)
        self.assertEqual(self.records('normalized/calendar-exceptions/test/seeds.jsonl')[0]['service_date'], '2026-09-30')
        self.assertEqual(self.records('normalized/research-queue-test.jsonl')[0]['missing_dimension'], 'route_lines')
        station_fact = next(r for r in self.records('normalized/fact-sources-test.jsonl') if r['field_name'] == 'station_refs')
        self.assertEqual(station_fact['source_id'], 'jtm-current-station-directory')

    def test_flat_column_rejects_validation_before_writing(self):
        args = self.east_arguments()
        def reject(candidate):
            raise ValueError('Pinned column changed')
        args['validate'] = reject
        with self.assertRaisesRegex(ValueError, 'Pinned column changed'):
            staging.stage_jr_east_single_trip(**args)
        self.assertEqual(list(self.base.rglob('*.jsonl')), [])

    def west_arguments(self):
        expected, selected, sources = {}, [], []
        for public, equipment in [
                ('2', ['オーシャンアロー車両で運転', '女性専用席があります', 'グリーン車指定席', '普通車全車指定席']),
                ('3', ['女性専用車両があります', 'グリーン車指定席', '普通車全車指定席'])]:
            tid, number, page = 'test.' + public, '205' + public + 'M', 'page' + public
            source = f'jr-west-odekake-kuroshio{public}-{number.lower()}-20260930'
            url = f'https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930'
            calls = [('新大阪', '006911', None, '08:58', '2'), ('大阪', '007068', '09:03', None, None)]
            expected[tid] = {'identity': ('kuroshio', public, number, '毎日運転', page),
                             'equipment': equipment, 'calls': calls}
            selected.append({'trip_id': tid, 'service_id': 'kuroshio', 'public_number': public,
                             'train_number': number, 'operation_label': '毎日運転',
                             'source_id': source, 'source_url': url, 'printed_equipment': equipment,
                             'stops': [{'name': name, 'code': code, 'arrival': arrival, 'departure': departure,
                                        'platform': platform, 'call_type': 'origin' if i == 0 else 'destination'}
                                       for i, (name, code, arrival, departure, platform) in enumerate(calls)]})
            sources.append({'source_id': source, 'url_or_locator': url,
                            'effective_date': '2026-09-30', 'redistribution_status': 'verification_only'})
        self.json(self.base / 'candidates/jr-test.json', {
            'candidate_status': 'visually_reviewed_official_train_pages', 'canonical': False,
            'service_date': '2026-09-30', 'trips': selected})
        staging.emit_jsonl(self.base / 'sources/source-registry-test.jsonl', sources)
        staging.emit_jsonl(self.base / 'normalized/services-existing.jsonl', [{'service_id': 'kuroshio'}])
        self.json(self.root / 'app/public/rail/jp-2025.json', {
            'lines': [{'stations': [['006911', '新大阪'], ['007068', '大阪']]}]})
        spec = importlib.util.spec_from_file_location('equipment_policy', TOOLS / 'normalize-reviewed-west-kuroshio19-22-20260930.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return dict(base=self.base, root=self.root, suffix='test', day='2026-09-30', until='2026-10-01',
                    expected=expected, load_manifest=lambda base: {'as_of_date': '2026-09-30'},
                    rows=lambda pattern: [r for p in self.base.glob(pattern) if 'test' not in p.name for r in staging.read_jsonl(p)],
                    write=staging.emit_jsonl, equipment=module.equipment, source_count=2,
                    trip_count_error='Expected precisely two reviewed trips')

    def test_batch_preserves_vehicle_and_women_only_equipment_facts(self):
        args = self.west_arguments()
        with contextlib.redirect_stdout(io.StringIO()):
            staging.stage_odekake_expected_batch(**args)
        formations = self.records('normalized/trip-formations/test/seeds.jsonl')
        self.assertEqual([r.get('formation_label') for r in formations], ['オーシャンアロー車両', None])
        self.assertTrue(all(r['all_reserved'] and r['green_car_available'] for r in formations))
        facts = self.records('normalized/fact-sources-test.jsonl')
        self.assertIn(('test.2', 'formation.women_only_seat_available'), {(r['entity_id'], r['field_name']) for r in facts})
        self.assertIn(('test.3', 'formation.women_only_car_available'), {(r['entity_id'], r['field_name']) for r in facts})
        self.assertEqual(len(self.records('normalized/station-identities-test.jsonl')), 2)
        self.assertEqual([r['day_offset'] for r in self.records('normalized/stop-times/test/seeds.jsonl')], [0] * 4)
        self.assertEqual({r['status'] for r in self.records('normalized/fact-completeness-test.jsonl') if r['dimension'] == 'route_lines'}, {'unknown'})

    def test_batch_validates_last_trip_before_any_outputs_are_written(self):
        args = self.west_arguments()
        path = self.base / 'candidates/jr-test.json'
        candidate = json.loads(path.read_text())
        candidate['trips'][-1]['stops'][-1]['departure'] = '09:04'
        self.json(path, candidate)
        before = {p: p.read_bytes() for p in self.base.rglob('*.jsonl')}
        with self.assertRaisesRegex(ValueError, 'Printed passenger calls drift: test.3'):
            staging.stage_odekake_expected_batch(**args)
        self.assertEqual({p: p.read_bytes() for p in self.base.rglob('*.jsonl')}, before)

    def test_station_policy_can_leave_tokyo_unforced(self):
        self.east_arguments()
        with self.assertRaisesRegex(ValueError, 'Ambiguous JR East station'):
            staging.jr_east_forced_station_ids(self.root, [{'stops': [['東京', None, '08:00']]}], {}, forced_codes={})


if __name__ == '__main__':
    unittest.main()
