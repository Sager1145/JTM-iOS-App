import copy
import importlib.util
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'lib'))
from na_station_ids import apply_repairs
spec = importlib.util.spec_from_file_location('station_audit', HERE / 'audit-na-package.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class StationIdentityRepairTests(unittest.TestCase):
    def setUp(self):
        self.package = {'country': 'US', 'lines': [
            {'id': code, 'operator': code, 'name': code,
             'stations': [['same', 'Same', *point]], 'segments': []}
            for code, point in [('a', [-87, 41]), ('b', [-118, 34]), ('c', [-118, 34.001])]]}
        self.stations = {'features': [
            {'properties': {'operator': line['operator'], 'line_name': line['name'],
                            'n02_group_code': 'same', 'n02_station_code': line['id'] + '-SAME',
                            'display_point': line['stations'][0][2:4]}}
            for line in self.package['lines']]}
        self.catalog = {'repairs': [{'country': 'US', 'oldId': 'same', 'places': [
            {'id': code, 'members': [{'lineId': self.package['lines'][i]['id'],
                                     'point': self.package['lines'][i]['stations'][0][2:4]}
                                    for i in indices]}
            for code, indices in [('same', [0]), ('same--local', [1, 2])]]}]}

    def test_splits_remote_places_preserves_local_transfer_and_is_idempotent(self):
        before = copy.deepcopy((self.package, self.stations))
        package, stations, changes = apply_repairs(self.package, self.stations, self.catalog)
        self.assertEqual([l['stations'][0][0] for l in package['lines']],
                         ['same', 'same--local', 'same--local'])
        self.assertEqual(len(changes), 2)
        self.assertEqual((self.package, self.stations), before)
        restored = copy.deepcopy(package)
        for line in restored['lines']:
            line['stations'][0][0] = 'same'
        self.assertEqual(restored, self.package)
        again, features, changes = apply_repairs(package, stations, self.catalog)
        self.assertEqual((again, features, changes), (package, stations, []))

    def test_rejects_changed_anchor_without_mutating_inputs(self):
        self.package['lines'][1]['stations'][0][2] += 1
        before = copy.deepcopy(self.package)
        with self.assertRaisesRegex(ValueError, 'moved or is ambiguous'):
            apply_repairs(self.package, self.stations, self.catalog)
        self.assertEqual(self.package, before)

    def test_rejects_missing_solver_membership(self):
        self.stations['features'].pop()
        with self.assertRaisesRegex(ValueError, 'missing solver station'):
            apply_repairs(self.package, self.stations, self.catalog)

    def test_rejects_new_id_that_already_belongs_to_a_remote_place(self):
        foreign = copy.deepcopy(self.package['lines'][0])
        foreign['id'] = 'foreign'
        foreign['stations'][0][0] = 'same--local'
        self.package['lines'].append(foreign)
        with self.assertRaisesRegex(ValueError, 'still spans different places'):
            apply_repairs(self.package, self.stations, self.catalog)

    def test_audit_finds_worst_pair_even_after_nearby_platform(self):
        self.package['lines'][1]['stations'][0][2:4] = [-87, 41.002]
        for lines in [self.package['lines'], list(reversed(self.package['lines']))]:
            found = audit.Findings()
            audit.audit_package({'country': 'US', 'lines': lines}, found, {})
            collisions = [r for r in found.rows if r['check'] == 'station.identityCollision']
            self.assertEqual(len(collisions), 1)
            self.assertEqual(collisions[0]['severity'], 'ERROR')
            self.assertGreater(collisions[0]['metres'], 2000000)

    def test_audit_preserves_reviewed_local_complex(self):
        self.package['lines'] = self.package['lines'][1:]
        found = audit.Findings()
        audit.audit_package(self.package, found, {}, {'same': {'maxMeters': 150}})
        self.assertFalse(any(r['check'] == 'station.identityCollision' for r in found.rows))
        self.assertTrue(any(r['check'] == 'station.split.reviewed' for r in found.rows))


if __name__ == '__main__':
    unittest.main()
