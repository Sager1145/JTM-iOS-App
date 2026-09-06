"""Snapping a station onto the railway it is actually served by.

``Network.snap`` is nearest-wins, and nearest-wins is decided by survey noise
wherever somebody else's track passes closer to a published stop than the
line's own railway does.  Newton, Kansas is the clean case and the numbers
below are the real ones: the Amtrak stop is 27.6 m from a ``NET='S'`` BNSF
siding stub that forms a four-edge island the router can never leave, and
36.7 m from the ``NET='M'``, ``PASSNGR='A'`` main line the Southwest Chief is
on.  Nine metres decide it, the station is spliced onto the island, and both
adjacent intervals die.

``prefer_m`` says how wide a band of candidates counts as "the same stop, to
within the accuracy of the survey".  Inside that band the choice is made on
what a railway would say -- connected first, then near the operator's own
corridor, then carrying a passenger tag, then nearest -- and outside it
nothing changes.  At the default of zero nothing changes at all, which is
what the first test here is for: every existing caller must get the old
answer, byte for byte.
"""
import math
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'lib')))

import na_geo as geo  # noqa: E402
import na_narn as narn  # noqa: E402


NEWTON = (-97.345, 38.046)


def at(origin, east_m, north_m):
    return [origin[0] + east_m / (111_320.0 * math.cos(math.radians(origin[1]))),
            origin[1] + north_m / 110_540.0]


def feature(origin, a, b, offsets, **props):
    """One NARN edge: two node ids, a polyline, and the FRA's own properties.

    Three or more points per edge on purpose -- ``corridor_costs`` and the
    corridor tie-break both read ``points[len(points) // 2]``, which on a
    two-point line is the far end rather than the middle.
    """
    row = {'COUNTRY': 'US', 'FRFRANODE': a, 'TOFRANODE': b}
    row.update(props)
    return {'properties': row,
            'geometry': {'type': 'LineString',
                         'coordinates': [at(origin, *o) for o in offsets]}}


def chain(origin, prefix, north_m, xs, **props):
    """A run of edges along a constant northing, node-linked end to end."""
    out = []
    for i in range(len(xs) - 1):
        x0, x1 = xs[i], xs[i + 1]
        out.append(feature(origin, f'{prefix}{i}', f'{prefix}{i + 1}',
                           [(x0, north_m), ((x0 + x1) / 2.0, north_m),
                            (x1, north_m)], **props))
    return out


def nearest_wins(net, point, pool, max_m):
    """``Network.snap`` exactly as it read before ``prefer_m`` existed."""
    best = None
    for index in pool:
        _, _, points, _, _ = net.edges[index]
        d, i, t, coord, measure = geo.project_to_line(point, points)
        if d > max_m:
            continue
        if best is None or d < best[0]:
            best = (d, index, measure, coord)
    return best


def newton_network():
    """The main line, and the siding island that sits nine metres nearer."""
    main = chain(NEWTON, 'M', 36.7, [-3_000, -2_000, -1_000, 0, 1_000, 2_000,
                                     3_000], NET='M', PASSNGR='A')
    siding = chain(NEWTON, 'S', -27.6, [-160, -80, 0, 80, 160], NET='S')
    return narn.Network(main + siding), len(main)


class SnapPreferenceDefaultTests(unittest.TestCase):
    """``prefer_m=0`` is the old code, and must stay the old code."""

    def test_zero_preference_is_nearest_wins(self):
        net, main_edges = newton_network()
        stop = at(NEWTON, 0, 0)
        pool = list(range(len(net.edges)))

        expected = nearest_wins(net, stop, pool, 3_000)
        self.assertIsNotNone(expected)
        # The nearest edge is the siding -- that is the whole problem.
        self.assertGreaterEqual(expected[1], main_edges)
        self.assertAlmostEqual(expected[0], 27.6, delta=0.5)

        got = net.snap(stop, pool, 3_000, prefer_m=0.0)
        self.assertEqual(got[1], expected[1])          # same edge
        self.assertEqual(got[3], expected[3])          # same point on it
        self.assertEqual(got, expected)

        # And the default argument is that same zero.
        self.assertEqual(net.snap(stop, pool, 3_000), expected)

    def test_route_stations_default_matches_an_explicit_zero(self):
        net, _ = newton_network()
        stations = [at(NEWTON, -2_000, 0), at(NEWTON, 0, 0), at(NEWTON, 2_000, 0)]
        corridors = [stations]

        base, base_report = narn.route_stations(
            net, corridors, stations, width_m=1_500, max_snap_m=3_000)
        zero, zero_report = narn.route_stations(
            net, corridors, stations, width_m=1_500, max_snap_m=3_000,
            prefer_m=0.0)

        self.assertEqual(base, zero)
        self.assertEqual(base_report, zero_report)
        self.assertEqual(base_report['preferMeters'], 0.0)


class SnapPreferenceNewtonTests(unittest.TestCase):
    """The band is wide enough to see the main line, or it is not."""

    def test_connected_component_is_the_largest_one(self):
        net, main_edges = newton_network()
        connected = net.connected_edges()
        self.assertEqual(connected, set(range(main_edges)))
        # Memoised, not recomputed.
        self.assertIs(net.connected_edges(), connected)

    def test_a_thirty_metre_band_reaches_the_main_line(self):
        net, main_edges = newton_network()
        stop = at(NEWTON, 0, 0)
        pool = list(range(len(net.edges)))

        got = net.snap(stop, pool, 3_000, prefer_m=30.0)
        self.assertLess(got[1], main_edges)
        self.assertAlmostEqual(got[0], 36.7, delta=0.5)
        self.assertEqual(net.edges[got[1]][4]['NET'], 'M')

    def test_a_five_metre_band_does_not(self):
        net, main_edges = newton_network()
        stop = at(NEWTON, 0, 0)
        pool = list(range(len(net.edges)))

        got = net.snap(stop, pool, 3_000, prefer_m=5.0)
        self.assertGreaterEqual(got[1], main_edges)
        self.assertAlmostEqual(got[0], 27.6, delta=0.5)


class SnapCorridorKeyTests(unittest.TestCase):
    """Two candidates a train could equally be on: the corridor decides.

    Both tracks here are connected (they are joined at one end) and both carry
    a passenger tag, so the only thing separating them is where the operator
    says its own line runs.  ``A`` is 20 m from the stop, ``B`` is 30 m.
    """

    def build(self):
        a = feature(NEWTON, 'A0', 'A1', [(-500, 20), (0, 20), (500, 20)],
                    NET='M', PASSNGR='A')
        b = feature(NEWTON, 'B0', 'B1', [(-500, 30), (0, 30), (500, 30)],
                    NET='M', PASSNGR='A')
        join = feature(NEWTON, 'A1', 'B1',
                       [(500, 20), (500, 25), (500, 30)], NET='M', PASSNGR='A')
        net = narn.Network([a, b, join])
        self.assertEqual(net.connected_edges(), {0, 1, 2})
        return net

    def test_equal_corridor_bucket_lets_the_nearer_track_win(self):
        net = self.build()
        stop = at(NEWTON, 0, 0)
        # Halfway between the two: 5 m from each midpoint, one 25 m bucket.
        corridor = narn.corridor_index(
            [[at(NEWTON, -500, 25), at(NEWTON, 500, 25)]])

        got = net.snap(stop, [0, 1], 3_000, prefer_m=30.0, corridor=corridor)
        self.assertEqual(got[1], 0)
        self.assertAlmostEqual(got[0], 20.0, delta=0.5)

    def test_a_nearer_corridor_beats_ten_metres_of_nearness(self):
        net = self.build()
        stop = at(NEWTON, 0, 0)
        # 22.4 m from A's midpoint (bucket 1), 12.4 m from B's (bucket 0).
        corridor = narn.corridor_index(
            [[at(NEWTON, -500, 42.4), at(NEWTON, 500, 42.4)]])

        got = net.snap(stop, [0, 1], 3_000, prefer_m=30.0, corridor=corridor)
        self.assertEqual(got[1], 1)
        self.assertAlmostEqual(got[0], 30.0, delta=0.5)
        # Without the corridor opinion the nearer one still wins, which is
        # what says the corridor key is what moved the answer.
        self.assertEqual(
            net.snap(stop, [0, 1], 3_000, prefer_m=30.0, corridor=None)[1], 0)


class CorridorIndexSplitTests(unittest.TestCase):
    """The extracted index must not have changed what the costs are."""

    def test_costs_from_index_match_the_wrapper(self):
        net, _ = newton_network()
        pool = set(range(len(net.edges)))
        corridors = [[at(NEWTON, -3_000, 0), at(NEWTON, 3_000, 0)]]

        wrapped = net.corridor_costs(corridors, pool, 1_500)
        split = net.corridor_costs_from_index(
            narn.corridor_index(corridors), pool, 1_500)
        self.assertEqual(wrapped, split)


if __name__ == '__main__':
    unittest.main()
