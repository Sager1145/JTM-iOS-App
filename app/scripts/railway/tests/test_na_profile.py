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
        self.assertLess(local.tolerance_m, longhaul.tolerance_m)
        self.assertLess(local.min_radius_m, longhaul.min_radius_m)

    def test_length_scales_smoothing_but_not_chord_cap(self):
        short = na_profile.profile_for(3_000, 100_000)
        long = na_profile.profile_for(3_000, 2_500_000)

        self.assertEqual(short.name, long.name)
        self.assertGreater(long.tolerance_m, short.tolerance_m)
        self.assertGreater(long.corner_offset_m, short.corner_offset_m)
        self.assertEqual(long.max_edge_m, short.max_edge_m)


if __name__ == '__main__':
    unittest.main()
