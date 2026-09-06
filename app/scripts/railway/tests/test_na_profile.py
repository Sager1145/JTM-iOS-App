import os
import sys
import unittest


LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib'))
sys.path.insert(0, LIB)

import na_profile  # noqa: E402


class AdaptiveGeometryProfileTests(unittest.TestCase):
    def test_local_and_longhaul_lines_use_different_detail_bands(self):
        local = na_profile.profile_for(400, 20_000)
        longhaul = na_profile.profile_for(60_000, 2_500_000)

        self.assertEqual(local.name, 'street')
        self.assertEqual(longhaul.name, 'longhaul')
        # A streetcar keeps sub-metre fidelity; an intercity line is groomed
        # to a coarser but still faithful tolerance.
        self.assertLess(local.tolerance_m, longhaul.tolerance_m)
        # The street band still rounds artificial corners and holds a small
        # radius floor. The intercity bands invent nothing: no corner offset,
        # no radius floor, because the renderer rounds corners in pixel space
        # and a package-level floor replaced real curves (Horseshoe Curve,
        # ~190 m) with arcs that never existed (2026-09-05 measurement).
        self.assertGreater(local.min_radius_m, 0)
        self.assertGreater(local.corner_offset_m, 0)
        self.assertEqual(longhaul.min_radius_m, 0)
        self.assertEqual(longhaul.corner_offset_m, 0)

    def test_length_does_not_scale_smoothing(self):
        short = na_profile.profile_for(3_000, 100_000)
        long = na_profile.profile_for(3_000, 2_500_000)

        self.assertEqual(short.name, long.name)
        # The length multiplier was removed on purpose: on its own it created
        # 445 km of >30 m deviation across the Amtrak long-hauls. A line that
        # runs a long way is drawn at the same fidelity as a short one; the
        # zoomed-out case is handled by the pixel-space stroke simplifier.
        self.assertEqual(na_profile.length_factor(100_000), 1.0)
        self.assertEqual(na_profile.length_factor(2_500_000), 1.0)
        self.assertEqual(long.tolerance_m, short.tolerance_m)
        self.assertEqual(long.corner_offset_m, short.corner_offset_m)
        self.assertEqual(long.max_edge_m, short.max_edge_m)


if __name__ == '__main__':
    unittest.main()
