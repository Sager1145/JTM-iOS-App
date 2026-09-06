"""The two main-line bands are drawn faithfully now, and measurably so.

``regional`` and ``longhaul`` used to be groomed with a 9-16 m simplifier
budget, a 140-260 m corner fillet and a 200-400 m minimum-radius floor, all
multiplied by up to 2x again for a long line.  On track whose geometry is an
actual survey of an actual main line that is not smoothing, it is
replacement: the fillet and the radius floor invent arcs the railway does not
have, and the measured cost was 445 km of built North American line more than
30 m from the FRA centreline.

So both bands are now tolerance 3 m, no fillet, no radius floor, and the
length multiplier is gone.  The argument the multiplier was making -- that a
line drawn zoomed out does not need its detail -- was never wrong, only
measured in the wrong units; the pixel-space stroke DP makes it at the zoom
the line is actually drawn at.

The other three bands are untouched, and the last test here is the reason the
change is safe to make: the same 190 m-radius curve that the old longhaul
profile deforms by tens of metres is now reproduced to within a chord's sag.
"""
import math
import os
import sys
import unittest


LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib'))
sys.path.insert(0, LIB)

import na_build  # noqa: E402
import na_geo as geo  # noqa: E402
import na_profile  # noqa: E402


#: Today's values for the three bands that must NOT have moved, copied out by
#: hand so that editing ``BANDS`` cannot make this test agree with itself.
UNTOUCHED = {
    # name, max_spacing, tolerance, spike_edge, spike_turn, spike_deviation,
    # corner_offset, min_radius, radius_window, anchor, max_edge
    'street': ('street', 700, 0.8, 6, 80, 0.6, 12, 15, 30, 3, 120),
    'metro': ('metro', 1_800, 1.6, 12, 70, 1.2, 25, 30, 70, 5, 160),
    'commuter': ('commuter', 6_000, 4.0, 24, 60, 2.5, 60, 80, 180, 10, 220),
}

CENTRE = (-97.345, 38.046)
ARC_RADIUS_M = 190.0
ARC_STEP_M = 20.0
#: A 270 degree sweep, so the curve is a balloon loop / wye leg rather than a
#: single bend: the point of the fixture is that the grooming has room to
#: destroy it, and a lone semicircle's pinned ends flatter the old profile.
ARC_SWEEP_DEG = 270.0


def arc_points(radius_m=ARC_RADIUS_M, step_m=ARC_STEP_M, sweep_deg=ARC_SWEEP_DEG):
    """A circular arc of ``radius_m``, sampled every ``step_m`` along it."""
    sweep = math.radians(sweep_deg)
    steps = max(2, int(round(radius_m * sweep / step_m)))
    kx = 111_320.0 * math.cos(math.radians(CENTRE[1]))
    out = []
    for i in range(steps + 1):
        theta = sweep * i / steps
        out.append([CENTRE[0] + radius_m * math.cos(theta) / kx,
                    CENTRE[1] + radius_m * math.sin(theta) / 110_540.0])
    return out


def worst_arc_deviation(points, radius_m=ARC_RADIUS_M):
    """How far the DRAWN line strays from the circle, not just its vertices.

    Simplification only ever drops vertices, so measuring the survivors would
    read zero however hard the line was chorded.  The polyline is resampled
    finely first and every sample measured against the circle.
    """
    dense = geo.densify(points, 2.0)
    return max(abs(geo.haversine(CENTRE, p) - radius_m) for p in dense)


class LengthFactorTests(unittest.TestCase):
    def test_length_no_longer_coarsens_anything(self):
        for length_m in (100_000.0, 1_000_000.0, 5_000_000.0):
            self.assertEqual(na_profile.length_factor(length_m), 1.0)

    def test_profile_for_is_the_band_itself_at_every_length(self):
        for spacing in (400, 1_500, 3_000, 20_000, 90_000):
            band = na_profile.band_for(spacing)
            for length_m in (100_000.0, 1_000_000.0, 5_000_000.0):
                self.assertIs(na_profile.profile_for(spacing, length_m), band)


class FaithfulBandTests(unittest.TestCase):
    def test_longhaul_is_faithful(self):
        p = na_profile.profile_for(90_000, 3_900_000)
        self.assertEqual(p.name, 'longhaul')
        self.assertEqual(p.tolerance_m, 3.0)
        self.assertEqual(p.corner_offset_m, 0)
        self.assertEqual(p.min_radius_m, 0)
        # Sawtooth relaxation and the chord cap are unrelated to the fidelity
        # question and must not have moved.
        self.assertEqual(p.spike_edge_m, 60)
        self.assertEqual(p.spike_turn_deg, 55)
        self.assertEqual(p.spike_deviation_m, 6.0)
        self.assertEqual(p.max_edge_m, 600)

    def test_regional_is_faithful(self):
        p = na_profile.profile_for(20_000, 400_000)
        self.assertEqual(p.name, 'regional')
        self.assertEqual(p.tolerance_m, 3.0)
        self.assertEqual(p.corner_offset_m, 0)
        self.assertEqual(p.min_radius_m, 0)
        self.assertEqual(p.spike_edge_m, 40)
        self.assertEqual(p.spike_turn_deg, 55)
        self.assertEqual(p.spike_deviation_m, 4.0)
        self.assertEqual(p.max_edge_m, 350)

    def test_the_other_three_bands_are_byte_identical(self):
        for spacing, name in ((400, 'street'), (1_500, 'metro'),
                              (3_000, 'commuter')):
            p = na_profile.profile_for(spacing, 2_500_000)
            self.assertEqual(p.name, name)
            self.assertEqual(
                (p.name, p.max_spacing_m, p.tolerance_m, p.spike_edge_m,
                 p.spike_turn_deg, p.spike_deviation_m, p.corner_offset_m,
                 p.min_radius_m, p.radius_window_m, p.anchor_m, p.max_edge_m),
                UNTOUCHED[name])


class ZeroIsANoOpTests(unittest.TestCase):
    """Switching the fillet and the radius floor off must change nothing.

    Both passes already return an untouched copy at zero, so ``groom`` needs
    no guard of its own -- but that is a property of ``na_geo`` this file is
    now relying on, so it is asserted rather than assumed.
    """

    def test_round_corners_at_zero_returns_the_same_vertices(self):
        points = arc_points()
        self.assertEqual(geo.round_corners(points, 0), [list(p) for p in points])

    def test_enforce_min_radius_at_zero_returns_the_same_vertices(self):
        points = arc_points()
        self.assertEqual(geo.enforce_min_radius(points, 0, 900, 35),
                         [list(p) for p in points])


class ArcFidelityRegressionTests(unittest.TestCase):
    """The proof: a real curve, groomed old and new.

    190 m is a tight but entirely ordinary main-line curve -- a 25 mph
    connection, a yard throat, the inside of a river bend.  The old longhaul
    profile's own radius floor is 400 m before the length multiplier and 800 m
    after it, so this curve is by construction something the old grooming
    considered too sharp to exist and straightened out.
    """

    def test_new_longhaul_profile_reproduces_the_curve(self):
        points = arc_points()
        profile = na_profile.profile_for(90_000, 3_900_000)
        self.assertEqual(profile.name, 'longhaul')

        groomed = na_build.groom([points], profile)[0]

        self.assertLessEqual(worst_arc_deviation(groomed), 3.5)
        # Stations are the interval boundaries: both ends stay exactly put.
        self.assertEqual(groomed[0], list(points[0]))
        self.assertEqual(groomed[-1], list(points[-1]))

    def test_the_old_longhaul_profile_destroyed_it(self):
        points = arc_points()
        # The longhaul band as it shipped, times the 2.0 length multiplier a
        # 3,900 km transcontinental route earned: tolerance 32 m, a 520 m
        # corner fillet, an 800 m minimum radius.
        old = na_profile.Profile(
            name='longhaul', max_spacing_m=float('inf'), tolerance_m=32.0,
            spike_edge_m=120, spike_turn_deg=55, spike_deviation_m=12.0,
            corner_offset_m=520, min_radius_m=800, radius_window_m=1_800,
            anchor_m=70, max_edge_m=600)

        groomed = na_build.groom([points], old)[0]

        self.assertGreater(worst_arc_deviation(groomed), 30.0)


if __name__ == '__main__':
    unittest.main()
