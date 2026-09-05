import os
import sys
import unittest

LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib'))
if LIB not in sys.path:
    sys.path.insert(0, LIB)
import na_lines as lines


def pattern(stations):
    p = lines.Pattern(stations, None, 'sample-trip')
    p.weight = 1.0
    p.trips = 1
    return p


class DirectionDivergenceRunTests(unittest.TestCase):
    """Two independently routed alignments of ONE station list -- direction 0
    (the trunk's own canonical geometry) and direction 1 (the other physical
    track) -- coincide except over a single run of consecutive intervals,
    the SFMTA N/Embarcadero shape: a one-way couplet diverts direction 1
    while every other interval is shared track.
    """

    # Five trunk stations, A..E, one straight line 1000 m apart so that a
    # divergence is unambiguous against the coincident intervals either
    # side of it.
    STATIONS = ['A', 'B', 'C', 'D', 'E']

    @staticmethod
    def _interval(a, b):
        return [list(a), list(b)]

    def _coincident_intervals(self):
        # Interval i joins station i and i+1; every one of direction 0's and
        # direction 1's intervals is bit-for-bit the same track here.
        xs = [0.0, 0.01, 0.02, 0.03, 0.04]
        base = [[x, 0.0] for x in xs]
        return [self._interval(base[i], base[i + 1]) for i in range(4)]

    def test_single_diverging_run_produces_one_extra_segment(self):
        direction0 = self._coincident_intervals()
        direction1 = [list(interval) for interval in direction0]
        # B->C and C->D (intervals 1 and 2) run down a parallel street a
        # couple hundred metres east instead -- one continuous run.
        direction1[1] = self._interval([0.01, 0.002], [0.02, 0.002])
        direction1[2] = self._interval([0.02, 0.002], [0.03, 0.002])

        runs = lines.direction_divergence_runs(direction0, direction1)

        self.assertEqual(len(runs), 1)
        start, end, worst = runs[0]
        self.assertEqual((start, end), (1, 2))
        self.assertGreater(worst, lines.DIVERGENCE_THRESHOLD_M)
        # The run's station span -- what an extraSegments row's from/to name
        # -- covers stations B..D (indices 1..3), the ends of the run and
        # nothing past them.
        self.assertEqual(self.STATIONS[start], 'B')
        self.assertEqual(self.STATIONS[end + 1], 'D')

    def test_coincident_alignments_produce_no_runs(self):
        direction0 = self._coincident_intervals()
        direction1 = [list(interval) for interval in direction0]

        runs = lines.direction_divergence_runs(direction0, direction1)

        self.assertEqual(runs, [])

    def test_tiny_jitter_under_threshold_is_not_a_divergence(self):
        direction0 = self._coincident_intervals()
        direction1 = [list(interval) for interval in direction0]
        # ~1 m of resample jitter on one interval -- far under the 30 m gate.
        direction1[2] = self._interval([0.02, 0.00001], [0.03, 0.00001])

        runs = lines.direction_divergence_runs(direction0, direction1)

        self.assertEqual(runs, [])

    def test_mismatched_interval_counts_refuse_rather_than_guess(self):
        direction0 = self._coincident_intervals()
        direction1 = direction0[:-1]

        self.assertEqual(lines.direction_divergence_runs(direction0, direction1), [])

    def test_extra_segment_geometry_is_one_continuous_polyline(self):
        direction1 = [
            self._interval([0.01, 0.002], [0.02, 0.002]),
            self._interval([0.02, 0.002], [0.03, 0.002]),
        ]

        geometry = lines.extra_segment_for_run(direction1, 0, 1)

        # The shared vertex at the run's internal junction (C) is not
        # duplicated -- three vertices for two intervals, not four.
        self.assertEqual(geometry, [[0.01, 0.002], [0.02, 0.002], [0.03, 0.002]])

    def test_direction_only_stop_is_reported_not_invented_onto_trunk(self):
        trunk = ['A', 'B', 'C', 'D']
        # The raw direction-1 pattern calls at a stop the trunk's own
        # (folded) station list never does -- Powell/Hyde's Jackson-only
        # stop is the real case this models.
        raw_patterns = [
            pattern(trunk),                       # already the trunk's way
            pattern(list(reversed(['A', 'B', 'X', 'C', 'D']))),  # the other way
        ]

        extra_stops = lines.direction_only_stations(raw_patterns, trunk)

        self.assertEqual(extra_stops, ['X'])

    def test_no_direction_only_stops_when_both_ways_call_at_the_same_places(self):
        trunk = ['A', 'B', 'C', 'D']
        raw_patterns = [pattern(trunk), pattern(list(reversed(trunk)))]

        self.assertEqual(lines.direction_only_stations(raw_patterns, trunk), [])


class CanonicalStationsUnchangedTests(unittest.TestCase):
    """The whole point of `extraSegments` over the topology this replaces:
    a route whose two directions physically diverge still gets ONE trunk
    station list, chosen exactly as every other route's is -- divergence is
    recorded as an extra drawn segment, never as an extra station forced
    onto the canonical sequence.
    """

    def test_select_lines_trunk_is_untouched_by_a_divergent_direction(self):
        forward = pattern(['A', 'B', 'C', 'D', 'E'])
        forward.weight = 20.0
        forward.trips = 10
        backward = pattern(list(reversed(['A', 'B', 'C', 'D', 'E'])))
        backward.weight = 18.0
        backward.trips = 9

        selection = lines.select_lines([forward, backward])

        self.assertEqual(len(selection), 1)
        suffix, stations, matched_pattern, is_loop = selection[0]
        self.assertEqual(suffix, '')
        self.assertEqual(stations, ['A', 'B', 'C', 'D', 'E'])
        self.assertFalse(is_loop)


if __name__ == '__main__':
    unittest.main()
