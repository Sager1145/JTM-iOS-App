import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'lib'))
from na_release import release_locks, inherited_lock_fds
from na_build_inputs import merge_inputs, digest_file


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load('repair_builder', 'build-north-america-rail-package.py')
audit = load('repair_audit', 'audit-na-package.py')


class PublicationDedupTests(unittest.TestCase):
    def test_a_candidate_rejected_at_final_encoding_does_not_suppress_fallback(self):
        candidates = {'us': [{'lineId': 'kenosha-streetcar-sc'}]}
        options = SimpleNamespace(geometry_blockers=[])

        def reject(region, lines, opts, reference):
            lines[0]['changed'] = True
            opts.geometry_blockers.append({'line': lines[0]['lineId']})
            return {'lines': []}

        with patch.object(builder, 'build_region', side_effect=reject):
            published = builder.published_feed_references(candidates, options, None)
        route = {'relation': 123, 'name': 'Kenosha', 'operator': 'Kenosha',
                 'stations': [{'point': [-87.8, 42.5]}, {'point': [-87.81, 42.5]}]}
        report = {'dropped': []}
        self.assertEqual(builder.refuse_already_built([route], published, report), [route])
        self.assertEqual(report['dropped'], [])
        self.assertEqual(options.geometry_blockers, [])
        self.assertEqual(candidates, {'us': [{'lineId': 'kenosha-streetcar-sc'}]})

    def test_a_published_line_still_suppresses_its_osm_duplicate(self):
        compact = {'id': 'feed-sc', 'operator': 'Operator',
                   'stations': [['a', 'A', -87.8, 42.5], ['b', 'B', -87.81, 42.5]],
                   'segments': [[1, 0, [[-87.8, 42.5], [-87.805, 42.5]]],
                                [1, 1, [[-87.81, 42.5]]]]}
        with patch.object(builder, 'build_region', return_value={'lines': [compact]}):
            published = builder.published_feed_references(
                {'us': []}, SimpleNamespace(geometry_blockers=[]), None)
        self.assertEqual(published[0]['intervals'][1][0], [-87.805, 42.5])
        route = {'relation': 1, 'name': 'Streetcar', 'operator': 'Operator',
                 'stations': [{'point': p} for p in published[0]['stationPoints']]}
        report = {'dropped': []}
        self.assertEqual(builder.refuse_already_built([route], published, report), [])
        self.assertIn('feed-sc', report['dropped'][0]['why'])

    def test_an_operator_with_one_published_line_can_gain_another(self):
        route = {'relation': 1, 'operator': 'Operator', 'name': 'Other Line',
                 'kind': 'tram', 'ref': 'O', 'stations': [], 'parts': []}
        options = SimpleNamespace(osm_routes='unused', osm_line_colours={})
        with patch.object(builder.na_osmlines, 'load_dir', return_value=[route]), \
             patch.object(builder.na_osmlines, 'fold_directions', return_value=([route], [])), \
             patch.object(builder, 'country_of', return_value='us'), \
             patch.object(builder.OsmBuild, 'run', return_value=[{'lineId': 'osm-new'}]) as run:
            result = builder.build_osm_systems(options, None, None,
                                               [{'lineId': 'old', 'operator': 'Operator'}], [])
        run.assert_called_once()
        self.assertEqual(result[0]['lineId'], 'osm-new')


class BuildInputTests(unittest.TestCase):
    def test_partial_line_provenance_is_checked_without_certifying_its_siblings(self):
        with tempfile.TemporaryDirectory() as directory:
            registry = Path(directory) / 'registry.json'
            registry.write_text('{}')
            package = {'country': 'US', 'lines': [
                {'id': 'f-a', 'sourceFeed': 'f'}, {'id': 'f-b', 'sourceFeed': 'f'}],
                'buildInputsByFeed': {},
                'buildInputsByLine': {'f-a': {'registry.json': '0' * 64}}}
            found = audit.Findings()
            audit.audit_freshness(package, str(registry), directory, None, found)
        self.assertTrue(any(r['check'] == 'package.stale' and r['line'] == 'f-a'
                            for r in found.rows))
        self.assertTrue(any(r['check'] == 'package.freshness' and r['feed'] == 'f'
                            for r in found.rows))

    def test_narn_coverage_warning_requires_recorded_survey_and_does_not_excuse_drift(self):
        package = {'country': 'US', 'lines': [
            {'id': 'f-a', 'sourceFeed': 'f', 'geometrySource': 'narn'}],
            'geometrySource': {'officialGeometryComparison': {'byLine': {
                'f-a': {'builtFrom': 'narn', 'vertices': 100, 'unmatched': 80,
                        'maxDeviationMeters': 90}}}}}
        found = audit.Findings()
        audit.audit_package(package, found, {'f-a': 'longhaul'})
        self.assertTrue(any(r['check'] == 'geometry.unchecked' for r in found.rows))
        package['buildInputsByFeed'] = {'f': {'app/data/raw/na-rail/narn/tile.json.gz': 'a' * 64}}
        found = audit.Findings()
        audit.audit_package(package, found, {'f-a': 'longhaul'})
        self.assertTrue(any(r['check'] == 'geometry.unchecked.narnReferenceMissing'
                            and r['severity'] == 'WARN' for r in found.rows))
        self.assertTrue(any(r['check'] == 'geometry.deviation'
                            and r['severity'] == 'ERROR' for r in found.rows))

    def test_scoped_merge_keeps_old_inputs_for_untouched_feed(self):
        old = {'lines': [{'sourceFeed': 'a'}, {'sourceFeed': 'b'}],
               'buildInputs': {'registry.json': 'old'}}
        new = {'buildInputs': {'registry.json': 'new'}}
        self.assertEqual(merge_inputs(old, new, 'a'), {
            'a': new['buildInputs'], 'b': old['buildInputs']})
        self.assertEqual(merge_inputs(old, new, 'a', partial=True), {
            'b': old['buildInputs']})

    def test_audit_reports_stale_retained_feed_and_uncertified_feed(self):
        with tempfile.TemporaryDirectory() as directory:
            registry = Path(directory) / 'registry.json'
            registry.write_text('{}')
            package = {'country': 'US', 'lines': [
                {'sourceFeed': 'fresh'}, {'sourceFeed': 'old'}, {'sourceFeed': 'unknown'}],
                'buildInputsByFeed': {
                    'fresh': {'registry.json': digest_file(registry)},
                    'old': {'registry.json': '0' * 64}}}
            found = audit.Findings()
            audit.audit_freshness(package, str(registry), directory, None, found)
        self.assertEqual([(r['check'], r['feed']) for r in found.rows], [
            ('package.stale', 'old'), ('package.freshness', 'unknown')])


class ReleaseLockTests(unittest.TestCase):
    def child(self, directory, shared=False, inherit=False):
        code = ('import sys; sys.path.insert(0, %r); '
                'from na_release import release_locks; '
                'ctx=release_locks([%r], shared=%r); ctx.__enter__(); ctx.__exit__(None,None,None)'
                % (str(HERE / 'lib'), directory, shared))
        return subprocess.run([sys.executable, '-c', code], capture_output=True,
                              pass_fds=inherited_lock_fds() if inherit else ())

    def test_writer_excludes_other_writers_and_readers_but_allows_child_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            with release_locks([directory]):
                self.assertNotEqual(self.child(directory).returncode, 0)
                self.assertNotEqual(self.child(directory, shared=True).returncode, 0)
                self.assertEqual(self.child(directory, shared=True, inherit=True).returncode, 0)
            self.assertEqual(self.child(directory).returncode, 0)

    def test_readers_can_share_but_exclude_writers(self):
        with tempfile.TemporaryDirectory() as directory:
            with release_locks([directory], shared=True):
                self.assertEqual(self.child(directory, shared=True).returncode, 0)
                self.assertNotEqual(self.child(directory).returncode, 0)


if __name__ == '__main__':
    unittest.main()
