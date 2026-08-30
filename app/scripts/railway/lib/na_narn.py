"""The FRA/BTS North American Rail Network as a routing graph.

``NTAD_North_American_Rail_Network_Lines`` is the official record of where the
railways of the United States and Canada are. It is published by the Federal
Railroad Administration through the Bureau of Transportation Statistics, it
carries the topology already built (every segment names the node at each end),
and it is an order of magnitude denser than the alignments the operators
publish in their own GTFS — a median of about ten vertices per kilometre
against Amtrak's one to four.

So the operator's feed and the FRA's network answer two different questions,
and this package family asks each the one it can answer:

* the operator says **which stations, in which order, under which name** — and
  publishes a coarse alignment that says *which way round* its trains go;
* the FRA says **where the track is**.

This module turns the FRA network into a graph, and routes an operator's
station list through it inside a corridor drawn by the operator's own shape.
A path that leaves the corridor is not cheaper for leaving it; a station that
cannot be reached inside the corridor is reported rather than bridged, because
a synthetic connector is a railway that does not exist.
"""
from __future__ import annotations

import heapq
import json
import math
from collections import defaultdict

import na_geo as geo


class Network:
    """The passenger-carrying part of the FRA network, as an undirected graph."""

    def __init__(self, features, country=None):
        self.edges = []             # (from_node, to_node, points, length_m, props)
        self.node_edges = defaultdict(list)
        self.grid = defaultdict(list)
        self.cell = 0.05
        for feature in features:
            props = feature.get('properties') or {}
            if country and props.get('COUNTRY') not in country:
                continue
            geom = feature.get('geometry') or {}
            if geom.get('type') != 'LineString':
                continue
            points = [[float(x), float(y)] for x, y, *_ in geom['coordinates']]
            if len(points) < 2:
                continue
            a = props.get('FRFRANODE')
            b = props.get('TOFRANODE')
            if a is None or b is None:
                continue
            index = len(self.edges)
            length = geo.line_length(points)
            self.edges.append((a, b, points, length, props))
            self.node_edges[a].append(index)
            self.node_edges[b].append(index)
            for p in points:
                self.grid[self._key(p)].append(index)

    def _key(self, p):
        return (int(math.floor(p[0] / self.cell)), int(math.floor(p[1] / self.cell)))

    # ------------------------------------------------------------------ lookup

    def edges_near(self, point, radius_cells=1):
        kx, ky = self._key(point)
        out = set()
        for dx in range(-radius_cells, radius_cells + 1):
            for dy in range(-radius_cells, radius_cells + 1):
                out.update(self.grid.get((kx + dx, ky + dy), ()))
        return out

    def edges_near_line(self, points, pad_cells=1):
        out = set()
        for p in points:
            out |= self.edges_near(p, pad_cells)
        return out

    def edges_in_box(self, low, high, pad_cells=1):
        """Every edge inside a rectangle, interior included.

        The difference from walking the rectangle's outline with
        ``edges_near_line`` is the whole rectangle: an outline collects the
        cells within ``pad_cells`` of the *perimeter*, so anything more than a
        few kilometres inside it is invisible. That is how the Alaska Railroad
        lost five of its seven trains. Its stations snap to within a hundred
        metres of the network's own ARR track, but the railway rounds the head
        of Knik Arm thirty kilometres east of the straight line between
        Anchorage and Wasilla, so it lies neither in the corridor nor on the
        edge of the box ``_direct`` drew around the pair, and the graph had
        nothing to route through.
        """
        kx0, ky0 = self._key(low)
        kx1, ky1 = self._key(high)
        out = set()
        for kx in range(kx0 - pad_cells, kx1 + pad_cells + 1):
            for ky in range(ky0 - pad_cells, ky1 + pad_cells + 1):
                out.update(self.grid.get((kx, ky), ()))
        return out

    def snap(self, point, candidates=None, max_m=4_000):
        """The closest place on the network to a station's published position."""
        pool = candidates if candidates is not None else self.edges_near(point, 2)
        best = None
        for index in pool:
            _, _, points, _, _ = self.edges[index]
            d, i, t, coord, measure = geo.project_to_line(point, points)
            if d > max_m:
                continue
            if best is None or d < best[0]:
                best = (d, index, measure, coord)
        return best

    # ----------------------------------------------------------------- routing

    def corridor_costs(self, corridors, pool, width_m):
        """How much each candidate edge costs inside this line's corridor.

        An edge whose midpoint is inside the corridor costs its own length. One
        outside costs its length multiplied by how far outside it is, which is
        what keeps a route from taking a parallel freight line for a shortcut
        while still letting it cross one.

        ``corridors`` is a LIST, and it has to be: an operator's published
        shape often covers only the busiest pattern of a route, so the corridor
        drawn from it alone leaves the outer stations in open country where
        every edge costs seven times its length — and a Dijkstra over that
        happily walks eighty kilometres round a city to stay on cheap track it
        can reach. The straight lines between the stations are added as a
        second corridor for exactly that reason. They are not an alignment and
        are never drawn; they only say "the railway is somewhere along here",
        which where the shape says nothing is the truth and better than a
        seven-times penalty on the real track.
        """
        index = geo.ReferenceIndex(cell_deg=0.05)
        for corridor in corridors:
            if corridor and len(corridor) > 1:
                index.add_line(corridor)
        costs = {}
        for e in pool:
            _, _, points, length, _ = self.edges[e]
            mid = points[len(points) // 2]
            d, _ = index.nearest(mid, search_cells=2)
            if d == float('inf'):
                d = width_m * 4
            factor = 1.0 if d <= width_m else 1.0 + (d - width_m) / width_m * 6.0
            costs[e] = length * factor
        return costs

    def shortest(self, start_node, goal_nodes, pool, costs):
        """Dijkstra over ``pool`` only, from one node to the nearest goal."""
        goals = set(goal_nodes)
        dist = {start_node: 0.0}
        prev = {}
        queue = [(0.0, start_node)]
        seen = set()
        while queue:
            d, node = heapq.heappop(queue)
            if node in seen:
                continue
            seen.add(node)
            if node in goals:
                return node, d, prev
            for e in self.node_edges.get(node, ()):
                if e not in costs:
                    continue
                a, b, _, _, _ = self.edges[e]
                other = b if a == node else a
                nd = d + costs[e]
                if nd < dist.get(other, float('inf')):
                    dist[other] = nd
                    prev[other] = (node, e)
                    heapq.heappush(queue, (nd, other))
        return None, float('inf'), prev

    def path_points(self, start_node, end_node, prev):
        """The geometry of a path found by ``shortest``, start to end."""
        chain = []
        node = end_node
        while node != start_node:
            step = prev.get(node)
            if step is None:
                return None
            parent, edge = step
            chain.append((parent, edge, node))
            node = parent
        chain.reverse()
        points = []
        for parent, edge, child in chain:
            a, _, pts, _, _ = self.edges[edge]
            piece = pts if a == parent else list(reversed(pts))
            if points and geo.haversine(points[-1], piece[0]) < 1.0:
                points.extend(piece[1:])
            else:
                points.extend(piece)
        return points


def _direct(net, start, end, max_snap_m, ratio_cap):
    """One station pair, over the official network, with no corridor at all.

    Bounded by a box around the pair rather than by a corridor, and accepted
    only if the answer is a plausible length for the distance — which is what
    keeps "no corridor" from meaning "any route the graph can find".
    """
    pad = max(0.05, abs(start[0] - end[0]) * 0.4, abs(start[1] - end[1]) * 0.4)
    pool = net.edges_in_box(
        [min(start[0], end[0]) - pad, min(start[1], end[1]) - pad],
        [max(start[0], end[0]) + pad, max(start[1], end[1]) + pad])
    if not pool:
        return None
    costs = {e: net.edges[e][3] for e in pool}
    splits = defaultdict(list)
    anchors = []
    for index, point in enumerate((start, end)):
        hit = net.snap(point, pool, max_snap_m)
        if hit is None:
            return None
        _, edge, measure, coord = hit
        node = ('D', index)
        splits[edge].append((measure, node, coord))
        anchors.append(node)
    path = RoutingGraph(net, pool, costs, splits).shortest(anchors[0], anchors[1])
    if path is None or len(path) < 2:
        return None
    straight = geo.haversine(start, end)
    if straight > 0 and geo.line_length(path) / straight > ratio_cap:
        return None
    return path


def load(path, country=None):
    with open(path) as fh:
        data = json.load(fh)
    return Network(data['features'], country=country)


# ---------------------------------------------------------------- station route

class RoutingGraph:
    """A corridor of the network with the line's own stations spliced into it.

    A station almost never sits on a node of the FRA network — it sits partway
    along an edge — so the edge it sits on is cut at that point and the station
    becomes a node of its own. Without that, an interval could only start and
    end at a junction, and every station would be drawn at the nearest one.
    """

    def __init__(self, net, pool, costs, splits):
        # splits: edge index -> [(measure, node_id, coordinate), …]
        self.net = net
        self.adj = defaultdict(list)     # node -> [(other, cost, points)]
        for e in pool:
            a, b, points, length, _ = net.edges[e]
            cumul = geo.cumulative(points)
            factor = costs[e] / length if length > 0 else 1.0
            cuts = sorted(splits.get(e, []))
            chain = [(0.0, a)] + [(m, n) for m, n, _ in cuts] + [(length, b)]
            for (m0, n0), (m1, n1) in zip(chain, chain[1:]):
                if n0 == n1:
                    continue
                piece = geo.slice_between(points, cumul, m0, m1)
                if len(piece) < 2:
                    continue
                cost = max(1e-6, (m1 - m0) * factor)
                self.adj[n0].append((n1, cost, piece))
                self.adj[n1].append((n0, cost, list(reversed(piece))))

    def shortest(self, start, goal):
        dist = {start: 0.0}
        prev = {}
        queue = [(0.0, 0, start)]
        seen = set()
        tick = 0
        while queue:
            d, _, node = heapq.heappop(queue)
            if node in seen:
                continue
            seen.add(node)
            if node == goal:
                break
            for other, cost, points in self.adj.get(node, ()):
                nd = d + cost
                if nd < dist.get(other, float('inf')):
                    dist[other] = nd
                    prev[other] = (node, points)
                    tick += 1
                    heapq.heappush(queue, (nd, tick, other))
        if goal not in dist:
            return None
        chain = []
        node = goal
        while node != start:
            parent, points = prev[node]
            chain.append(points)
            node = parent
        chain.reverse()
        out = []
        for piece in chain:
            if out and geo.haversine(out[-1], piece[0]) < 1.0:
                out.extend(piece[1:])
            else:
                out.extend(piece)
        return out


def route_stations(net, corridors, station_points, width_m=1_500,
                   max_snap_m=3_000, pad_cells=1):
    """Route one line's ordered stations through the official network.

    Returns ``(intervals, report)``. ``intervals[i]`` is the geometry from
    station ``i`` to station ``i+1``, or ``None`` where the network could not
    join them inside the corridor — reported, never bridged.
    """
    if corridors and isinstance(corridors[0][0], (int, float)):
        corridors = [corridors]
    pool = set()
    for corridor in corridors:
        pool |= net.edges_near_line(geo.densify(corridor, 2_000), pad_cells)
    if not pool:
        return [None] * (len(station_points) - 1), {'reason': 'no candidate track'}
    costs = net.corridor_costs(corridors, pool, width_m)
    splits = defaultdict(list)
    anchors = []
    unsnapped = []
    for i, p in enumerate(station_points):
        hit = net.snap(p, pool, max_snap_m)
        if hit is None:
            anchors.append(None)
            unsnapped.append(i)
            continue
        d, edge, measure, coord = hit
        node = ('S', i)
        splits[edge].append((measure, node, coord))
        anchors.append((node, coord, d))
    graph = RoutingGraph(net, pool, costs, splits)
    intervals = []
    misses = []
    rescued = []
    for i in range(len(station_points) - 1):
        a, b = anchors[i], anchors[i + 1]
        if a is None or b is None:
            intervals.append(None)
            misses.append(i)
            continue
        path = graph.shortest(a[0], b[0])
        if path is None or len(path) < 2:
            # The corridor is a preference, not a fact, and where the
            # operator's shape does not reach it can be a preference that
            # excludes the railway: the *Capitol Corridor*'s published shape
            # covers Sacramento to San Jose, so its two hops beyond Sacramento
            # had no corridor at all and the weighted graph could not join
            # them. Asked again over the same official network with no
            # corridor and a box around just those two stations, the answer is
            # the line that is actually there.
            path = _direct(net, station_points[i], station_points[i + 1],
                           max_snap_m, ratio_cap=2.2)
            if path is not None:
                rescued.append(i)
        if path is None or len(path) < 2:
            intervals.append(None)
            misses.append(i)
        else:
            intervals.append(path)
    report = {
        'rescued': rescued,
        'snapped': sum(1 for a in anchors if a is not None),
        'unsnapped': unsnapped,
        'unrouted': misses,
        'maxSnapMeters': max((a[2] for a in anchors if a), default=0.0),
        # How far the network had to reach for each station, which is the only
        # honest statement of whether this railway is *in* the network. A
        # station that snapped two kilometres was not found; a piece of
        # somebody else's railroad was. See ``FeedBuild.network_surveys``.
        'snapMeters': [None if a is None else a[2] for a in anchors],
        'anchors': [None if a is None else a[1] for a in anchors],
    }
    return intervals, report
