import importlib.util
import os
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'audit-na-package.py'))
SPEC = importlib.util.spec_from_file_location('na_package_audit', SCRIPT)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def straight_line():
    return {
        'id': 'metro-red', 'name': 'Red', 'operator': 'Metro',
        'geometrySource': 'authority-red', 'smoothingProfile': 'metro',
        'colorReference': '#ff0000', 'colorSource': 'official GTFS',
        'stations': [
            ['us-a', 'A', -73.0, 40.0],
            ['us-b', 'B', -73.0, 40.01],
        ],
        'segments': [[1.111, 0, [
            [-73.0, 40.0], [-73.0, 40.005], [-73.0, 40.01],
        ]]],
    }


class PackageAuditTests(unittest.TestCase):
    def test_verified_official_straight_track_is_not_called_a_guess(self):
        findings = audit.Findings()
        audit.audit_line(straight_line(), 'US', findings, {'authority-red'})
        self.assertFalse(any(row['check'] == 'interval.straight'
                             for row in findings.rows))

    def test_unverified_straight_track_remains_an_error(self):
        findings = audit.Findings()
        audit.audit_line(straight_line(), 'US', findings)
        self.assertTrue(any(row['check'] == 'interval.straight'
                            for row in findings.rows))

    def test_colour_requires_official_source(self):
        line = straight_line()
        line.pop('colorSource')
        findings = audit.Findings()
        audit.audit_line(line, 'US', findings, {'authority-red'})
        self.assertTrue(any(row['check'] == 'colour.source'
                            for row in findings.rows))


if __name__ == '__main__':
    unittest.main()
