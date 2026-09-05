import importlib.util
import os
import unittest

SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'audit-straight-intervals.py'))
SPEC = importlib.util.spec_from_file_location('straight_intervals_audit', SCRIPT)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


# A straight north-south line at 40 degrees latitude. Station spacing here
# (~1.1 km per 0.01 degree of latitude) keeps every distance well above the
# 1,500 m STRAIGHT_INTERVAL chord floor with round numbers of stations.
STATION_A = [-100.000000, 40.000000]
STATION_B = [-100.000000, 40.020000]
STATION_C = [-100.000000, 40.040000]
MIDPOINT_AB = [-100.000000, 40.010000]
MIDPOINT_BC = [-100.000000, 40.030000]


def straight_two_station_line(**overrides):
    """One interval, several interior vertices, all exactly on the chord."""
    coordinates = [
        STATION_A,
        [-100.000000, 40.005000],
        MIDPOINT_AB,
        [-100.000000, 40.015000],
        STATION_B,
    ]
    declared_km = sum(
        audit.haversine(coordinates[i], coordinates[i + 1])
        for i in range(len(coordinates) - 1)
    ) / 1000.0
    line = {
        'id': 'test-straight',
        'smoothingProfile': 'commuter',
        'geometrySource': 'test-source',
        'stations': [
            ['t-a', 'A', STATION_A[0], STATION_A[1]],
            ['t-b', 'B', STATION_B[0], STATION_B[1]],
        ],
        'segments': [[declared_km, 0, coordinates]],
    }
    line.update(overrides)
    return line


def curved_two_station_line():
    """Same endpoints as `straight_two_station_line`, but one interior vertex
    is pushed well past the deviation floor -- a real curve, not a chord."""
    line = straight_two_station_line()
    coordinates = line['segments'][0][2]
    # Push the midpoint ~200 m east: comfortably past the 25 m floor.
    coordinates[2] = [MIDPOINT_AB[0] + 0.0023, MIDPOINT_AB[1]]
    declared_km = sum(
        audit.haversine(coordinates[i], coordinates[i + 1])
        for i in range(len(coordinates) - 1)
    ) / 1000.0
    line['segments'][0][0] = declared_km
    return line


def three_station_continuation_line():
    """Two intervals across three stations, where the second segment row
    OMITS the vertex it shares with the first -- the `continuesFromPrevious`
    trap this whole format lives or dies by. If a reader fails to prepend
    the previous row's last vertex, this interval's first endpoint silently
    becomes `MIDPOINT_AB` instead of station B, and its walked length comes
    up short of what `km` declares.
    """
    first_leg = [STATION_A, MIDPOINT_AB, STATION_B]
    second_leg_full = [STATION_B, MIDPOINT_BC, STATION_C]
    first_km = sum(
        audit.haversine(first_leg[i], first_leg[i + 1]) for i in range(len(first_leg) - 1)
    ) / 1000.0
    second_km = sum(
        audit.haversine(second_leg_full[i], second_leg_full[i + 1])
        for i in range(len(second_leg_full) - 1)
    ) / 1000.0
    return {
        'id': 'test-continuation',
        'smoothingProfile': 'commuter',
        'geometrySource': 'test-source',
        'stations': [
            ['t-a', 'A', STATION_A[0], STATION_A[1]],
            ['t-b', 'B', STATION_B[0], STATION_B[1]],
            ['t-c', 'C', STATION_C[0], STATION_C[1]],
        ],
        'segments': [
            [first_km, 0, first_leg],
            # continuesFromPrevious == 1: MIDPOINT_AB/STATION_B's shared
            # vertex (STATION_B) is dropped from this row's own coordinates.
            [second_km, 1, [MIDPOINT_BC, STATION_C]],
        ],
    }


class ReconstructionContractTests(unittest.TestCase):
    """`reconstruct_intervals` is the one thing every other check in this
    script depends on. If it decodes `continuesFromPrevious` wrong, every
    downstream number is wrong while looking clean -- which is exactly what
    happened to an earlier audit generation (5,575 mis-measured intervals,
    still printing "0 errors"). These tests exist to catch that class of bug
    directly, not just its symptoms.
    """

    def test_continuing_row_is_reassembled_with_its_shared_vertex(self):
        intervals, sanity = audit.reconstruct_intervals(three_station_continuation_line())

        self.assertEqual(sanity['endpointMismatches'], 0)
        self.assertEqual(sanity['kmMismatches'], 0)

        second = intervals[1]
        self.assertIsNotNone(second)
        # The reconstructed polyline must start at station B (the shared
        # vertex the row dropped), not at MIDPOINT_BC.
        self.assertEqual(second['path'][0], STATION_B)
        self.assertEqual(second['path'][-1], STATION_C)
        self.assertAlmostEqual(second['walked'], second['declaredKm'] * 1000.0, delta=1.0)

    def test_naive_read_without_the_shared_vertex_would_be_wrong(self):
        """Demonstrates the trap the contract exists to prevent: reading a
        continuing row's coordinates on their own -- the mistake the format
        note in both this script and the skill's preflight warns against --
        understates the interval and mislocates its first endpoint.
        """
        line = three_station_continuation_line()
        naive_path = list(line['segments'][1][2])  # no prepended previous_end
        naive_walked = sum(
            audit.haversine(naive_path[i], naive_path[i + 1]) for i in range(len(naive_path) - 1)
        )

        intervals, _sanity = audit.reconstruct_intervals(line)
        correct = intervals[1]

        self.assertNotEqual(naive_path[0], STATION_B)
        self.assertLess(naive_walked, correct['walked'])

    def test_declared_km_drift_is_caught_not_swallowed(self):
        line = three_station_continuation_line()
        line['segments'][1][0] = 0.001  # absurdly wrong declared length
        _intervals, sanity = audit.reconstruct_intervals(line)
        self.assertEqual(sanity['kmMismatches'], 1)


class StraightIntervalDetectionTests(unittest.TestCase):
    def test_long_densified_straight_chord_is_flagged(self):
        findings, sanity = audit.find_straight_intervals('us', straight_two_station_line(), set())
        self.assertEqual(sanity['endpointMismatches'], 0)
        self.assertEqual(len(findings), 1)
        finding = findings[0]
        self.assertGreaterEqual(finding['chordKm'] * 1000.0, audit.CHORD_MIN_M)
        self.assertLess(finding['deviationM'], audit.DEVIATION_MAX_M)
        self.assertFalse(finding['markedByPackage'])

    def test_real_curve_of_the_same_span_is_not_flagged(self):
        findings, _sanity = audit.find_straight_intervals('us', curved_two_station_line(), set())
        self.assertEqual(findings, [])

    def test_bare_two_point_chord_is_left_to_straight_chord_not_this_class(self):
        """A raw two-vertex interval (no densification at all) is exactly
        what the existing STRAIGHT_CHORD check already covers at a much
        lower 250 m floor; this class must not double-report it.
        """
        line = straight_two_station_line()
        line['segments'][0][2] = [STATION_A, STATION_B]
        findings, _sanity = audit.find_straight_intervals('us', line, set())
        self.assertEqual(findings, [])

    def test_short_straight_interval_under_the_chord_floor_is_not_flagged(self):
        line = straight_two_station_line()
        short_b = [-100.000000, 40.005000]
        coordinates = [STATION_A, [-100.000000, 40.002000], short_b]
        declared_km = sum(
            audit.haversine(coordinates[i], coordinates[i + 1])
            for i in range(len(coordinates) - 1)
        ) / 1000.0
        line['stations'][1] = ['t-b', 'B', short_b[0], short_b[1]]
        line['segments'] = [[declared_km, 0, coordinates]]
        findings, _sanity = audit.find_straight_intervals('us', line, set())
        self.assertEqual(findings, [])

    def test_verified_official_network_is_recorded_as_the_exemption_reason(self):
        line = straight_two_station_line()
        findings, _sanity = audit.find_straight_intervals(
            'us', line, verified_official={line['geometrySource']})
        self.assertEqual(len(findings), 1)
        self.assertIn('verifiedOfficialNetwork', findings[0]['auditNaPackageInterval_straight'])

    def test_own_marker_is_recorded_as_the_exemption_reason(self):
        line = straight_two_station_line(straightIntervals={'intervals': [0]})
        findings, _sanity = audit.find_straight_intervals('us', line, set())
        self.assertEqual(len(findings), 1)
        self.assertTrue(findings[0]['markedByPackage'])
        self.assertIn('straightIntervals marker', findings[0]['auditNaPackageInterval_straight'])

    def test_unmarked_unverified_straight_interval_would_fire_the_strict_check(self):
        findings, _sanity = audit.find_straight_intervals('us', straight_two_station_line(), set())
        self.assertEqual(len(findings), 1)
        self.assertTrue(findings[0]['auditNaPackageInterval_straight'].startswith('WOULD FIRE'))


if __name__ == '__main__':
    unittest.main()
