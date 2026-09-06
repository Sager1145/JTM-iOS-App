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


def osm_relation_package(with_evidence=True):
    """A line drawn from an OpenStreetMap relation the build audited.

    The reference excludes OpenStreetMap as a self-reference, so it cannot
    disagree with this alignment: the deviation it reports is the distance to
    the nearest OTHER railway, and every vertex is unmatched because nothing
    independent covers the alignment at all. TTC Lines 1 and 2 are the real
    case -- 390 m to a freight subdivision, and no published survey of the
    subway tunnels.
    """
    line = straight_line()
    line['id'] = 'transit-1'
    line['geometrySource'] = 'osm'
    if with_evidence:
        line['osmRelationEvidence'] = {
            'relation': 102388,
            'evidence': 'city topographic survey',
            'validation': {'medianMeters': 0.4},
        }
    return {
        'country': 'CA',
        'lines': [line],
        'geometrySource': {'officialGeometryComparison': {'byLine': {
            'transit-1': {
                'builtFrom': 'osm',
                'maxDeviationMeters': 392.7,
                'vertices': 443,
                'unmatched': 305,
                'osmReferenceRetainedIntervals': [0, 1, 2],
            },
        }}},
    }


class OsmReferenceRetainedTests(unittest.TestCase):
    """The build writes the key; before this rung the audit never read it."""

    def _checks(self, package):
        findings = audit.Findings()
        audit.audit_package(package, findings, {'transit-1': 'metro'})
        return {row['check']: row['severity'] for row in findings.rows}

    def test_audited_relation_is_a_warning_not_an_error(self):
        checks = self._checks(osm_relation_package())
        self.assertEqual(checks.get('geometry.deviation.osmReferenceRetained'),
                         'WARN')
        self.assertEqual(checks.get('geometry.unchecked.osmReferenceRetained'),
                         'WARN')
        self.assertNotIn('geometry.deviation', checks)
        self.assertNotIn('geometry.unchecked', checks)

    def test_without_the_evidence_chain_it_is_still_an_error(self):
        # The exception is the reviewed evidence, not the word "osm". A line
        # built from a relation nobody audited must not inherit it.
        checks = self._checks(osm_relation_package(with_evidence=False))
        self.assertEqual(checks.get('geometry.deviation'), 'ERROR')
        self.assertEqual(checks.get('geometry.unchecked'), 'ERROR')
        self.assertNotIn('geometry.deviation.osmReferenceRetained', checks)

    def test_osm_is_not_promoted_to_a_verified_official_network(self):
        # The rung must not have been bought by widening provenance.
        package = osm_relation_package()
        findings = audit.Findings()
        verified = audit.verified_official_networks(package, findings)
        self.assertNotIn('osm', verified)


if __name__ == '__main__':
    unittest.main()
