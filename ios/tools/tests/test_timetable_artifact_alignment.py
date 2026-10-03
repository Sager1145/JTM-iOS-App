import importlib.util
from pathlib import Path
import sqlite3
import unittest

import test_train_timetable as fixtures
import train_timetable as timetable


spec = importlib.util.spec_from_file_location(
    'artifact_alignment', Path(__file__).resolve().parents[1] / 'verify-train-timetable-artifact.py')
alignment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(alignment)


class TimetableArtifactAlignmentTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.TrainTimetablePipelineTests()
        self.fixture.setUp()
        self.canonical = self.fixture.canonical
        self.database, _, _ = timetable.build_database(self.canonical)

    def tearDown(self):
        self.fixture.tearDown()

    def verify(self):
        return alignment.verify_artifact(self.canonical, self.database, check_runtime=False)

    def test_matching_historical_snapshot_is_accepted(self):
        self.assertTrue(self.verify()['snapshotAligned'])

    def test_old_history_revision_is_rejected(self):
        with sqlite3.connect(self.database) as connection:
            connection.execute("UPDATE metadata SET value='old' WHERE key='rail_history_revision'")
        self.assertEqual(['rail_history_revision'], [r['field'] for r in self.verify()['errors']])

    def test_changed_history_with_same_revision_is_rejected(self):
        with sqlite3.connect(self.database) as connection:
            connection.execute("UPDATE metadata SET value='old-hash' WHERE key='rail_history_hash'")
        self.assertEqual(['rail_history_hash'], [r['field'] for r in self.verify()['errors']])

    def test_different_service_day_timezone_is_rejected(self):
        with sqlite3.connect(self.database) as connection:
            connection.execute("UPDATE metadata SET value='America/Toronto' WHERE key='timezone'")
        self.assertEqual(['timezone'], [r['field'] for r in self.verify()['errors']])

    def test_missing_runtime_copy_is_rejected(self):
        report = alignment.verify_artifact(self.canonical, self.database)
        self.assertIn('runtime_database', [r['field'] for r in report['errors']])


    def test_exact_copy_presence_and_removal_keep_artifact_aligned(self):
        source = self.canonical / "normalized/operators-test.jsonl"
        duplicate = source.with_name("operators-test 2.jsonl")
        duplicate.write_bytes(source.read_bytes())
        self.assertTrue(self.verify()['snapshotAligned'])
        duplicate.unlink()
        self.assertTrue(self.verify()['snapshotAligned'])

    def test_differing_copy_is_fingerprinted_and_still_validated(self):
        source = self.canonical / "normalized/operators-test.jsonl"
        duplicate = source.with_name("operators-test 2.jsonl")
        row = timetable.json.loads(source.read_text())
        row['display_name'] = 'Different retained fact'
        duplicate.write_text(timetable.canonical_json(row) + '\n')
        self.assertIn('source_hash', [r['field'] for r in self.verify()['errors']])
        manifest = timetable.load_manifest(self.canonical)
        data, origins = timetable.load_dataset(self.canonical, manifest)
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any('duplicate canonical key' in error for error in errors), errors)


if __name__ == '__main__':
    unittest.main()
