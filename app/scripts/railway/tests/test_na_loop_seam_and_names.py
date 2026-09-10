"""Loop-seam reconciliation and a directional-suffix name-stripping guard.

Two independent builder defects, both confirmed against a scoped rebuild
of real feeds:

1. ``PassengerNetwork.route_stations`` reconciles two intervals that meet
   at an *interior* station so they end/begin at the identical coordinate,
   but a loop (``stations + [stations[0]]``) never reconciles the seam
   where the closing interval's end and the first interval's start both
   represent station 0. Portland Streetcar A Loop's two seam candidates
   differ by 71.7 m, so ``validate_line_chain`` reports an endpoint gap on
   the closing interval and drops the whole line; Cincinnati's and
   Detroit's loops only happened to close because their seam candidates
   coincided.

2. ``strip_directional`` strips a trailing single-letter direction, so
   MTA's Culver-line station "Avenue N" becomes "Avenue" -- the letter is
   the name, not a direction.
"""
import math
import os
import sys
import unittest
import importlib.util

sys.path.insert(0, os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'lib')))

import na_geo as geo  # noqa: E402
import na_official  # noqa: E402

SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'build-north-america-rail-package.py'))
SPEC = importlib.util.spec_from_file_location(
    'na_package_builder_loop_seam_test', SCRIPT)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


ORIGIN = (-73.913333, 40.756312)


def at(east_m, north_m):
    return [ORIGIN[0] + east_m / (111_320.0 * math.cos(math.radians(ORIGIN[1]))),
            ORIGIN[1] + north_m / 110_540.0]


def line(*offsets, properties=None):
    return {'properties': properties or {},
            'geometry': {'type': 'LineString',
                         'coordinates': [at(*offset) for offset in offsets]}}


class LoopSeamReconciliationTests(unittest.TestCase):
    def test_closing_seam_reconciles_like_an_interior_station(self):
        # Two parallel, independently digitised features -- like a route's
        # directional track centrelines -- joined far away by a short
        # connector so the graph is one component (needed for the S1->S2
        # leg's path search) without the connector ever being a candidate
        # for any of the three stations below.
        service_f = line((-5000, 200), (0, 200), (1000, 500),
                         properties={'service': 'F'})
        service_m = line((-5000, 5), (0, 5), (1000, -500),
                         properties={'service': 'M'})
        connector = line((-5000, 200), (-5000, 5))

        network = na_official.PassengerNetwork(
            [service_f, service_m, connector])

        station0 = at(0, 0)
        station1 = at(1000, 500)
        station2 = at(1000, -500)

        # A loop: station 0, then round through 1 and 2, back to station 0.
        intervals, report = network.route_stations(
            [station0, station1, station2, station0], max_snap_m=400.0)

        self.assertIsNotNone(intervals, report)
        self.assertEqual(len(intervals), 3)

        # Before the fix, the first interval's start snapped onto F's
        # candidate (~200 m from the true station) while the closing
        # interval's end snapped onto M's candidate (~5 m away) -- the same
        # station, two different points, ~195 m apart. Reconciled, both
        # ends of the seam must be the identical coordinate.
        seam_start = intervals[0][0]
        seam_end = intervals[-1][-1]
        gap = geo.haversine(seam_start, seam_end)
        self.assertLessEqual(
            gap, 1.0,
            f'loop seam does not close: {gap:.1f} m apart '
            f'({seam_start} vs {seam_end})')

        # And it must have canonicalised toward the genuinely closer
        # candidate (M, ~5 m away), not the farther one (F, ~200 m away).
        self.assertLess(geo.haversine(seam_start, station0), 50.0)
        self.assertLess(geo.haversine(seam_end, station0), 50.0)

        # snapMeters for station 0 (index 0) reflects the reconciled point.
        self.assertLess(report['snapMeters'][0], 50.0)
        self.assertLess(report['snapMeters'][-1], 50.0)

    def test_non_loop_seam_endpoints_are_left_alone(self):
        # A straight (non-loop) line must not trigger the new wraparound
        # canonicalisation just because it happens to have >= 3 stations.
        feature = line((0, 0), (1000, 0))
        network = na_official.PassengerNetwork([feature])

        stations = [at(0, 0), at(500, 0), at(1000, 0)]
        intervals, report = network.route_stations(stations, max_snap_m=100)

        self.assertIsNotNone(intervals, report)
        self.assertAlmostEqual(intervals[0][0][0], stations[0][0], places=6)
        self.assertAlmostEqual(intervals[-1][-1][0], stations[-1][0], places=6)


class StripDirectionalNameTests(unittest.TestCase):
    def test_bare_street_type_letter_is_the_name_not_a_direction(self):
        # MTA's Culver-line "Avenue N" (GTFS parent F33): the N is the rest
        # of the station's name, not a direction qualifier.
        self.assertEqual(builder.strip_directional('Avenue N'), 'Avenue N')

    def test_avenue_u_is_unchanged(self):
        self.assertEqual(builder.strip_directional('Avenue U'), 'Avenue U')

    def test_stacked_platform_decorations_still_strip(self):
        self.assertEqual(
            builder.strip_directional('Bloor Station - Northbound Platform'),
            'Bloor Station')

    def test_real_directional_suffix_on_multi_word_name_still_strips(self):
        # "Main St N" is not a bare street-type remainder -- "Main St" has
        # another word besides the street type -- so the trailing direction
        # still strips, preserving current behaviour.
        self.assertEqual(builder.strip_directional('Main St N'), 'Main St')


if __name__ == '__main__':
    unittest.main()
