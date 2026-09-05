"""Two services sharing trunk trackage must not be routed as one component.

MTA's F and M share the Manhattan trunk (6th Avenue) closely enough that
their independently-digitised centrelines coincide at hundreds of exact
coordinates there, which merges them into a single connected component the
moment the graph is built.  On Queens Blvd the same two services also run
close together, but *without* sharing a vertex: the source geojson draws F's
polyline about 300-400 m off the true local platform at 46 St and Steinway
St, while M's polyline tracks the real local alignment throughout.

``route_stations`` used to resolve the "which parallel track" ambiguity once,
globally, over the whole line: intersect every station's reachable graph
*components* and use whichever single component minimises total snap
distance.  That is the wrong grain twice over here. It is too coarse,
because F and M being one connected component (via the shared trunk) hides
that they are two different tracks on Queens Blvd.  And it is too broad,
because requiring one choice to cover the *entire* route fails outright the
moment a branch only one service reaches is included, discarding the
consistency check for the whole line — including the Queens Blvd stations
where a consistent choice was available and would have worked. The result:
a naive per-station-nearest fallback that snaps 46 St onto M (F is too far
away) and Northern Blvd onto F (marginally closer there than M), and the
shortest path between those two points is a fourteen-kilometre loop out to
where F and M's centrelines actually happen to touch, for what is really a
730 m hop.

This reproduces that shape at the real scale, with an ``M``-shaped detour
standing in for the round trip out to the shared trunk.
"""
import math
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'lib')))

import na_geo as geo  # noqa: E402
import na_official  # noqa: E402


ORIGIN = (-73.913333, 40.756312)  # near the real 46 St, so the scale is real


def at(east_m, north_m):
    return [ORIGIN[0] + east_m / (111_320.0 * math.cos(math.radians(ORIGIN[1]))),
            ORIGIN[1] + north_m / 110_540.0]


def line(*offsets, properties=None):
    return {'properties': properties or {},
            'geometry': {'type': 'LineString',
                         'coordinates': [at(*offset) for offset in offsets]}}


class SharedTrunkParallelTrackTests(unittest.TestCase):
    def test_local_stations_do_not_route_via_the_shared_trunk(self):
        # A long shared trunk, drawn identically (down to the coordinate) in
        # both features -- the two services' real shared trackage. This is
        # what puts F and M in one connected component.
        trunk = [(-8000, 0), (-6000, 0), (-4000, 0), (-2000, 0)]

        # The express/express-adjacent feature ("F"): correct on the trunk,
        # and back within a couple of metres of the true alignment by
        # Northern Blvd and 65 St -- close enough there to beat M's own
        # (still perfectly valid) candidate and be the one picked at those
        # two stations -- but bowed 380 m away from the true alignment
        # through 46 St and Steinway St. This is the defect actually observed
        # in the sourced geojson: MTA's mta-subway-service-f.geojson snaps
        # within 2 m of Northern Blvd and 65 St but sits 320-400 m off at
        # 46 St and Steinway St, while mta-subway-service-m.geojson tracks
        # the real local alignment throughout.
        service_f = line(
            *trunk, (-1200, 0), (-600, 380), (0, 380), (620, 1), (1300, 1),
            properties={'service': 'F'})

        # The local feature ("M"): correct along the real platform the
        # whole way, sharing the trunk's exact coordinates but its own,
        # independently digitised points on Queens Blvd -- so it does not
        # coincide with F's vertices there even though both are close to
        # the true track.
        service_m = line(
            *trunk, (-1200, 0), (-600, 6), (0, 4), (620, 8), (1300, 12),
            properties={'service': 'M'})

        network = na_official.PassengerNetwork([service_f, service_m])

        steinway_st = at(-600, 0)
        forty_sixth_st = at(0, 0)
        northern_blvd = at(620, 0)
        sixty_fifth_st = at(1300, 0)

        intervals, routing = network.route_stations(
            [steinway_st, forty_sixth_st, northern_blvd, sixty_fifth_st],
            max_snap_m=125.0)

        self.assertIsNotNone(intervals, routing)
        # Every station is within the real snap tolerance of *some* track.
        self.assertTrue(all(m is not None and m < 125.0
                             for m in routing['snapMeters']), routing)

        # 46 St -> Northern Blvd is a 620 m hop. Before this fix it routed
        # out to the shared trunk and back: roughly 2 * 1200 m plus the leg
        # across, on the order of several kilometres -- a detour ratio well
        # past what any real railway justifies. After it, the interval stays
        # on one consistent local track and is close to the straight line.
        forty_sixth_to_northern = intervals[1]
        straight = geo.haversine(forty_sixth_st, northern_blvd)
        routed = geo.line_length(forty_sixth_to_northern)
        self.assertLess(straight, 700.0)
        self.assertLess(routed / straight, 2.2,
                         f'routed {routed:.0f} m for a {straight:.0f} m hop')

        # And the whole four-station line should be short throughout, not
        # just the one interval directly examined above.
        all_stations = [steinway_st, forty_sixth_st, northern_blvd, sixty_fifth_st]
        for index, piece in enumerate(intervals):
            leg_straight = geo.haversine(all_stations[index], all_stations[index + 1])
            leg_routed = geo.line_length(piece)
            self.assertLess(leg_routed / leg_straight, 2.2,
                             f'interval {index}: routed {leg_routed:.0f} m '
                             f'for a {leg_straight:.0f} m hop')

        # 46 St's independently-best track (M) and Northern Blvd's
        # independently-best track (F, marginally) differ, which is exactly
        # what used to force the graph detour. Two intervals that share a
        # station must still end and begin at the identical point, or the
        # builder's own continuity check ("authoritative intervals do not
        # meet at their shared station") rejects the whole line downstream.
        for index in range(1, len(intervals)):
            gap = geo.haversine(intervals[index - 1][-1], intervals[index][0])
            self.assertLessEqual(
                gap, 1.0,
                f'intervals {index - 1} and {index} do not meet at '
                f'{all_stations[index]}: {gap:.1f} m apart')

    def test_a_branch_only_one_service_reaches_no_longer_spoils_the_shared_part(self):
        # The old whole-route intersection made a single station outside
        # M's reach (a branch F alone serves) discard the consistency check
        # for every other station on the line, including the ones where a
        # consistent choice existed. A fourth, far-away station present only
        # on F's own feature must not defeat the local disambiguation at
        # 46 St / Northern Blvd from the first test.
        trunk = [(-8000, 0), (-6000, 0), (-4000, 0), (-2000, 0)]
        service_f = line(
            *trunk, (-1200, 0), (-600, 380), (0, 380), (620, 1), (1300, 1),
            (5000, 1), (9000, 1),
            properties={'service': 'F'})
        service_m = line(
            *trunk, (-1200, 0), (-600, 6), (0, 4), (620, 8), (1300, 12),
            properties={'service': 'M'})

        network = na_official.PassengerNetwork([service_f, service_m])

        stations = [at(-600, 0), at(0, 0), at(620, 0), at(1300, 0), at(9000, 0)]
        intervals, routing = network.route_stations(stations, max_snap_m=125.0)

        self.assertIsNotNone(intervals, routing)
        for index in range(3):  # the Steinway St..65 St legs stay short
            straight = geo.haversine(stations[index], stations[index + 1])
            routed = geo.line_length(intervals[index])
            self.assertLess(routed / straight, 2.2,
                             f'interval {index}: routed {routed:.0f} m for a '
                             f'{straight:.0f} m hop')

    def test_a_service_that_terminates_mid_route_does_not_detour_at_the_handback(self):
        # MTA's M does not run the whole of F's route: it terminates near
        # Forest Hills-71 Av, one stop before its own polyline and F's
        # happen to run closest together. A fix that keeps one feature
        # "stuck" for as long as it stays reachable -- rather than choosing
        # independently per interval -- picks exactly that worst possible
        # handback point and reintroduces the same kind of detour this
        # module exists to avoid, just moved a few stops down the line.
        trunk = [(-8000, 0), (-6000, 0), (-4000, 0), (-2000, 0)]
        # F alone covers the whole route, close to every station.
        service_f = line(
            *trunk, (-1200, 0), (-600, 380), (0, 380), (620, 1), (1300, 1),
            (2000, 1), (2700, 1), (3400, 1),
            properties={'service': 'F'})
        # M covers only as far as the fourth local station, then stops --
        # it does not reach the last two stations on the route at all.
        service_m = line(
            *trunk, (-1200, 0), (-600, 6), (0, 4), (620, 8), (1300, 12),
            (2000, 10),
            properties={'service': 'M'})

        network = na_official.PassengerNetwork([service_f, service_m])
        stations = [at(-600, 0), at(0, 0), at(620, 0), at(1300, 0),
                    at(2000, 0), at(2700, 0), at(3400, 0)]
        intervals, routing = network.route_stations(stations, max_snap_m=125.0)

        self.assertIsNotNone(intervals, routing)
        for index, piece in enumerate(intervals):
            straight = geo.haversine(stations[index], stations[index + 1])
            routed = geo.line_length(piece)
            self.assertLess(routed / straight, 2.2,
                             f'interval {index}: routed {routed:.0f} m for a '
                             f'{straight:.0f} m hop -- M ending mid-route '
                             'should not force a detour anywhere on the line')
        for index in range(1, len(intervals)):
            gap = geo.haversine(intervals[index - 1][-1], intervals[index][0])
            self.assertLessEqual(gap, 1.0)


if __name__ == '__main__':
    unittest.main()
