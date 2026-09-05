import os
import sys
import unittest

LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib'))
if LIB not in sys.path:
    sys.path.insert(0, LIB)
import na_lines as lines


def pattern(stations, weight, trips):
    p = lines.Pattern(stations, None, 'sample-trip')
    p.weight = weight
    p.trips = trips
    return p


class PreferredTrunkDirectionTests(unittest.TestCase):
    """A GTFS refresh can flip which direction a route's equal-length
    patterns merge onto (merge_directions folds onto the heavier one). The
    preferred trunk is a station sequence, not a direction claim, so
    select_lines() must accept it forwards or reversed against whatever the
    fresh feed actually publishes, and draw the trunk in the orientation
    that matches -- never invent an edge that isn't in the graph.
    """

    STATIONS = ['A', 'B', 'C', 'D', 'E']

    def test_accepts_preferred_trunk_matching_forward_edges(self):
        patterns = [pattern(self.STATIONS, 10.0, 5)]

        selection = lines.select_lines(patterns, preferred_trunk=self.STATIONS)

        self.assertEqual(len(selection), 1)
        suffix, stations, matched_pattern, is_loop = selection[0]
        self.assertEqual(suffix, '')
        self.assertEqual(stations, self.STATIONS)
        self.assertFalse(is_loop)

    def test_accepts_preferred_trunk_matching_only_reversed_edges(self):
        # Only the reverse direction (E->A) is what the fresh feed publishes,
        # mirroring the NYCT N situation: the preferred trunk was written
        # D43...R01 but the refreshed GTFS now merges the heavier direction
        # as R01...D43 (116 trips one way vs 106 the other), so the graph's
        # published edges only run E->D->C->B->A.
        reversed_stations = list(reversed(self.STATIONS))
        patterns = [pattern(reversed_stations, 10.0, 5)]

        selection = lines.select_lines(patterns, preferred_trunk=self.STATIONS)

        self.assertEqual(len(selection), 1)
        suffix, stations, matched_pattern, is_loop = selection[0]
        self.assertEqual(suffix, '')
        # The trunk is emitted in the orientation that matches the published
        # edges, not the orientation the preferred-trunk list happened to be
        # written in.
        self.assertEqual(stations, reversed_stations)

    def test_rejects_preferred_trunk_matching_neither_direction(self):
        patterns = [pattern(['A', 'B', 'X', 'Y'], 10.0, 5)]

        selection = lines.select_lines(patterns, preferred_trunk=self.STATIONS)

        self.assertEqual(selection, [])


if __name__ == '__main__':
    unittest.main()
