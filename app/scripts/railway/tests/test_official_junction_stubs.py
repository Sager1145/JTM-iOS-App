"""A routed official interval may not double back at a junction marker.

Two shapes in the route-specific official extracts produce the same fault,
and both are reproduced here at the scale they occur at in the sources:

* Chicago's CTA Loop file joins the Van Buren leg, the Wabash leg and the
  south leg at one coordinate called "Tower 12", and draws the Van Buren
  piece curving into the *south* leg.  A service that turns the corner there
  — Brown, Pink, Purple — enters the node about 11 m past the corner and
  leaves it 172 degrees back the way it came.  Orange, which runs straight
  through the same node, is unaffected, which is why one file publishes some
  of its services and withholds others.
* Pittsburgh's North Shore Connector is two parallel directional tracks
  joined only at their east end.  A station that is 20 m from one track and
  25 m from the other snaps to the near one while the path arrives on the
  far one, so the path runs out to the shared end and comes back.

In both the shortest path is the only path: there is nothing for a different
search to find.  What is wrong is the shape at the shared node, so that is
what is repaired — and only that, which the last two tests hold it to.
"""
import math
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'lib')))

import na_geo as geo  # noqa: E402
import na_official  # noqa: E402


ORIGIN = (-87.626030, 41.876704)  # CTA Tower 12, so the scale is the real one


def at(east_m, north_m):
    """A coordinate ``east_m``/``north_m`` metres from the junction."""
    return [ORIGIN[0] + east_m / (111_320.0 * math.cos(math.radians(ORIGIN[1]))),
            ORIGIN[1] + north_m / 110_540.0]


def line(*offsets):
    return {'properties': {},
            'geometry': {'type': 'LineString',
                         'coordinates': [at(*offset) for offset in offsets]}}


def sharpest(points):
    return max((geo.turn_degrees(a, b, c)
                for a, b, c in zip(points, points[1:], points[2:])),
               default=0.0)


class JunctionStubTests(unittest.TestCase):
    def test_loop_corner_does_not_reverse_through_the_junction_marker(self):
        # The Van Buren leg runs east 29 m north of the junction and curves
        # down into it; the Wabash leg leaves the same coordinate due north.
        network = na_official.PassengerNetwork([
            line((-260, 29), (-160, 29), (-24, 29), (-11, 22), (-3, 11), (0, 0)),
            line((0, 0), (2, 160), (4, 300)),
        ])

        intervals, report = network.route_stations(
            [at(-200, 33), at(4, 300)], max_snap_m=125.0)

        self.assertIsNotNone(intervals)
        self.assertLess(max(report['snapMeters']), 10.0)
        # 165 degrees before the repair: out to the marker and straight back.
        self.assertLess(sharpest(intervals[0]), 120.0)
        # The corner is still turned on the authority's own linework, not cut
        # across the block: the path stays inside the two legs' bounding box.
        for point in intervals[0]:
            self.assertGreaterEqual(point[0], at(-260, 0)[0] - 1e-9)
            self.assertLessEqual(point[0], at(5, 0)[0] + 1e-9)

    def test_station_on_the_other_parallel_track_does_not_reverse(self):
        # Two directional tracks 4 m apart, joined only at their east end.
        network = na_official.PassengerNetwork([
            line((-300, 4), (-20, 4), (0, 0)),
            line((-300, 0), (-40, 0), (0, 0)),
        ])

        intervals, _ = network.route_stations(
            [at(-280, 8), at(-40, -6)], max_snap_m=125.0)

        self.assertIsNotNone(intervals)
        # 169 degrees before the repair: east to the shared end, west back.
        self.assertLess(sharpest(intervals[0]), 120.0)
        self.assertLess(geo.line_length(intervals[0]), 260.0)

    def test_a_reversal_too_long_to_be_a_junction_stub_is_left_for_the_gate(self):
        # 60 m out and back is not a marker artefact, and the builder's
        # reversal check — not this repair — is what must see it.
        doubled = [at(-300, 0), at(-100, 0), at(-40, 3), at(-100, 6)]
        self.assertEqual(
            na_official.PassengerNetwork.drop_junction_stubs(doubled), doubled)

    def test_an_ordinary_corner_is_not_a_stub(self):
        corner = [at(-300, 0), at(0, 0), at(0, 300)]
        self.assertEqual(
            na_official.PassengerNetwork.drop_junction_stubs(corner), corner)


if __name__ == '__main__':
    unittest.main()
