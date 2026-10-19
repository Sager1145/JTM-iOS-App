"""Synthetic checks for the N02 snapshot comparator.

Geometry is invented. The tests pin missing/extra runs, identity mismatches,
shinkansen-versus-conventional separation, and half-open probe dates.
"""

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parent.parent / 'history' / 'compare-jp-history-snapshots.py'
SPEC = importlib.util.spec_from_file_location('compare_jp_history_snapshots', SCRIPT)
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def section(line, operator, coordinates, institution='2', **extra):
    props = {
        'N02_003': line,
        'N02_004': operator,
        'line_name': line,
        'operator': operator,
        'N02_002': institution,
    }
    props.update(extra)
    return {
        'type': 'Feature',
        'properties': props,
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
    }


def station(name, operator, line, lon, lat, **extra):
    props = {
        'station_name': name,
        'operator': operator,
        'line_name': line,
        'N02_003': line,
        'N02_004': operator,
    }
    props.update(extra)
    return {
        'type': 'Feature',
        'properties': props,
        'geometry': {'type': 'Point', 'coordinates': [lon, lat]},
    }


def overlay(sections=None, stations=None, retirements=None, identity_periods=None):
    return {
        'schema_version': '1',
        'revision': 'test',
        'sections': sections or [],
        'stations': stations or [],
        'retirements': retirements or [],
        'identity_periods': identity_periods or [],
    }


def names(rows):
    return [row['line_name'] for row in rows]


class CompareSnapshotTests(unittest.TestCase):
    def test_cover_threshold_keeps_only_runs_of_at_least_300m(self):
        # A 5 km edge crosses many grid cells. A 400 m piece 30 m off its middle
        # is covered; the same piece 80 m off is a missing run. A 200 m spur is dropped.
        base = mod.line_east(139.0, 35.0, 5000)
        near_start = mod.offset_metres(139.0, 35.0, 2300, -30)
        far_start = mod.offset_metres(139.0, 35.0, 2300, -80)
        near = mod.line_east(near_start[0], near_start[1], 400)
        far = mod.line_east(far_start[0], far_start[1], 400)
        short = mod.line_east(139.0, 35.05, 200)
        long = mod.line_east(139.0, 35.06, 400)
        added = mod.line_east(139.0, 35.08, 1000)
        partial = mod.line_east(139.0, 35.10, 1000)
        snap = [
            section('Main', 'Op', near),
            section('Main', 'Op', far),
            section('Spur', 'Op', short),
            section('Gone', 'Op', long),
        ]
        current = [
            section('Main', 'Op', base),
            section('Partial', 'Op', partial, valid_to='2008-06-01'),
        ]
        history = overlay([section('Added', 'Op', added, history_id='h-added', valid_from='1990-01-01')])
        report = mod.compare_on_dates(
            snap, [], current, [], history, '2008-01-01', '2009-03-31')

        missing = {row['line_name']: row for row in report['missing_sections']}
        self.assertEqual(set(missing), {'Main', 'Gone'})
        self.assertGreater(missing['Main']['length_m'], 350)
        self.assertLess(missing['Main']['length_m'], 500)
        self.assertAlmostEqual(missing['Gone']['length_m'], 400, delta=5)
        self.assertNotIn('Spur', missing)

        extra = {row['line_name']: row for row in report['extra_sections']}
        self.assertIn('Added', extra)
        self.assertEqual(extra['Added']['history_id'], 'h-added')
        self.assertAlmostEqual(extra['Added']['length_m'], 1000, delta=5)
        self.assertNotIn('Partial', extra)
        self.assertGreater(report['totals']['missing_km'], 0.7)
        self.assertGreater(report['totals']['extra_km'], 0.9)

    def test_identity_mismatch_uses_normalized_names_on_covered_geometry(self):
        geom = mod.line_east(139.0, 36.0, 800)
        same = mod.line_east(139.0, 36.02, 800)
        report = mod.compare_on_dates(
            [section('Old', 'JR', geom), section('Ａ 線', 'ＪＲ', same)],
            [],
            [section('New', 'Metro', geom), section('A線', 'JR', same)],
            [], overlay(), '2008-01-01', '2009-03-31')
        self.assertEqual(report['missing_sections'], [])
        self.assertEqual(report['extra_sections'], [])
        self.assertEqual(len(report['identity_mismatches']), 1)
        mismatch = report['identity_mismatches'][0]
        self.assertEqual(mismatch['snapshot'], {'operator': 'JR', 'line': 'Old'})
        self.assertEqual(mismatch['reconstruction'], {'operator': 'Metro', 'line': 'New'})
        self.assertAlmostEqual(mismatch['length_m'], 800, delta=5)
        self.assertGreaterEqual(mismatch['length_m'], 500)
        self.assertAlmostEqual(report['totals']['identity_km'], 0.8, delta=0.01)

    def test_identity_period_reconstructs_old_identity_without_geometry_copy(self):
        geom = mod.line_east(139.0, 36.0, 800)
        history = overlay(identity_periods=[{
            'history_id': 'rename',
            'match': {'line_name': 'New', 'operator': 'Metro',
                      'bbox': [138.0, 35.0, 140.0, 37.0], 'targets': ['sections']},
            'valid_to': '2019-10-01',
            'as': {'N02_003': 'Old', 'N02_004': 'JR'},
            'source': 'synthetic',
        }])
        before = mod.compare_on_dates(
            [section('Old', 'JR', geom)], [], [section('New', 'Metro', geom)], [],
            history, '2019-09-30', '2019-09-30')
        self.assertEqual(before['identity_mismatches'], [])
        after = mod.compare_on_dates(
            [section('New', 'Metro', geom)], [], [section('New', 'Metro', geom)], [],
            history, '2019-10-01', '2019-10-01')
        self.assertEqual(after['identity_mismatches'], [])

    def test_shinkansen_does_not_cover_a_parallel_conventional_line(self):
        geom = mod.line_east(139.0, 36.4, 1000)
        report = mod.compare_on_dates(
            [section('Local', 'Op', geom, institution='2')],
            [],
            [section('Local', 'Op', geom, institution='1')],
            [], overlay(), '2008-01-01', '2009-03-31')
        self.assertEqual([row['class'] for row in report['missing_sections']], ['conventional'])
        self.assertEqual([row['class'] for row in report['extra_sections']], ['shinkansen'])
        self.assertAlmostEqual(report['missing_sections'][0]['length_m'], 1000, delta=5)
        self.assertEqual(report['identity_mismatches'], [])

    def test_probe_dates_are_half_open_for_retirements_and_history_sections(self):
        retired = mod.line_east(140.0, 35.0, 1000)
        opened = mod.line_east(140.0, 35.02, 1000)
        current = [section('Retired', 'Op', retired)]
        history = overlay(
            sections=[section('Opened', 'Op', opened, history_id='h-open', valid_from='2009-04-01')],
            retirements=[{
                'history_id': 'h-ret',
                'match': {
                    'line_name': 'Retired',
                    'operator': 'Op',
                    'bbox': [138.0, 34.0, 142.0, 37.0],
                },
                'valid_to': '2008-06-01',
            }])
        snap = [section('Retired', 'Op', retired)]

        # D1 is inside the retirement; D2 is before the opening. Covered, not extra.
        during = mod.compare_on_dates(
            snap, [], current, [], history, '2008-01-01', '2009-03-31')
        self.assertEqual(during['missing_sections'], [])
        self.assertEqual(during['extra_sections'], [])

        # Opening day is active. The retired line is already out, so only Opened is extra.
        after = mod.compare_on_dates(
            [], [], current, [], history, '2009-04-01', '2010-03-31')
        self.assertEqual(names(after['extra_sections']), ['Opened'])
        self.assertEqual(after['extra_sections'][0]['history_id'], 'h-open')
        self.assertEqual(after['missing_sections'], [])

        # valid_to itself is not active, and the opening has not started.
        on_end = mod.compare_on_dates(
            snap, [], current, [], history, '2008-06-01', '2008-06-02')
        self.assertEqual(names(on_end['missing_sections']), ['Retired'])
        self.assertEqual(on_end['extra_sections'], [])

        # Active only on D2 (the opening day): not extra, and it does cover the snapshot.
        opening_day = mod.compare_on_dates(
            [section('Opened', 'Op', opened)], [], current, [], history,
            '2009-03-30', '2009-04-01')
        self.assertEqual(opening_day['extra_sections'], [])
        self.assertEqual(opening_day['missing_sections'], [])

    def test_retirement_targets_do_not_stamp_the_other_collection(self):
        geom = mod.line_east(139.2, 35.2, 1000)
        history = overlay(retirements=[{
            'history_id': 'sections-only',
            'match': {
                'line_name': 'L',
                'operator': 'O',
                'bbox': [138.0, 34.0, 142.0, 37.0],
                'targets': ['sections'],
            },
            'valid_to': '2000-01-01',
        }])
        report = mod.compare_on_dates(
            [], [],
            [section('L', 'O', geom)],
            [station('S', 'O', 'L', 139.2, 35.2)],
            history, '2005-01-01', '2006-03-31')
        self.assertEqual(report['extra_sections'], [])
        self.assertEqual([row['station_name'] for row in report['extra_stations']], ['S'])
        self.assertEqual(report['missing_stations'], [])

    def test_stations_match_by_name_within_300m_and_report_renames(self):
        kept = station('Kept', 'Op', 'L', 141.0, 35.0)
        same_name = station('Shared', 'Op', 'L1', 141.1, 35.0)
        shared_recon_at = mod.offset_metres(141.1, 35.0, 100, 0)
        old_at = (141.3, 35.0)
        new_at = mod.offset_metres(141.3, 35.0, 50, 0)
        gone = station('Gone', 'Op', 'L', 141.5, 35.0)
        added = station('Added', 'Op', 'L', 141.7, 35.0, history_id='h-st', valid_from='1990-01-01')
        temporary = station('Temp', 'Op', 'L', 141.9, 35.0, valid_to='2008-06-01')
        old = station('OldName', 'Op', 'L', old_at[0], old_at[1])
        new = station('NewName', 'Op', 'L', new_at[0], new_at[1], valid_from='1990-01-01')
        report = mod.compare_on_dates(
            [],
            [kept, same_name, gone, old],
            [],
            [kept,
             station('Shared', 'Op', 'L2', shared_recon_at[0], shared_recon_at[1]),
             added, temporary, new],
            overlay(), '2008-01-01', '2009-03-31')
        self.assertEqual([row['station_name'] for row in report['missing_stations']],
                         ['Gone', 'OldName'])
        self.assertEqual([row['station_name'] for row in report['extra_stations']],
                         ['Added', 'NewName'])
        self.assertEqual(report['extra_stations'][0]['history_id'], 'h-st')
        self.assertEqual(len(report['renamed_station_candidates']), 1)
        pair = report['renamed_station_candidates'][0]
        self.assertEqual(pair['snapshot']['station_name'], 'OldName')
        self.assertEqual(pair['reconstruction']['station_name'], 'NewName')
        self.assertLessEqual(pair['distance_m'], 150)
        self.assertEqual(report['totals']['missing_stations'], 2)
        self.assertEqual(report['totals']['extra_stations'], 2)

    def test_probe_date_defaults_and_overrides(self):
        self.assertEqual(mod.default_probe_dates(2008), ('2008-01-01', '2009-03-31'))
        self.assertEqual(
            mod.resolve_probe_dates(2008, {'2008': ['2008-04-01', '2009-03-31']}),
            ('2008-04-01', '2009-03-31'))
        self.assertEqual(mod.resolve_probe_dates(2005, {}), ('2005-01-01', '2006-03-31'))


if __name__ == '__main__':
    unittest.main()
