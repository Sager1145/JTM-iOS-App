"""Routing over provincial/state official railway centreline data.

NARN remains the continent-wide baseline, but a second official survey may
prove that its topology is broken.  Québec MTQ's open railway GeoJSON is the
first such source: it identifies the passenger users of each operational
segment and contains the missing CN connection that prevents NARN from
routing VIA's Montréal–Jonquière and Montréal–Senneterre services correctly.

This module deliberately routes only segments whose attributes explicitly
name the requested passenger operator.  It does not infer passenger service
from track proximity, and it rejects a line unless every published station
can be snapped and every adjacent station pair can be joined plausibly.
"""
from __future__ import annotations

import heapq
import math
from collections import defaultdict

import na_geo as geo


class PassengerNetwork:
    """Undirected graph made from one authority's audited centrelines.

    ``user_codes`` is used by Québec's province-wide inventory, where only
    features explicitly naming VIA are eligible.  Route-specific normalized
    extracts (for example MTA and CTA service files) have already been
    filtered by the downloader and therefore pass ``None``.  This distinction
    prevents a shortest-path search from silently switching to a neighbouring
    service in a dense metro network.
    """

    def __init__(self, features, user_codes=None, endpoint_join_m=0.0,
                 endpoint_line_join_m=0.0):
        wanted = ({str(code).strip().casefold() for code in user_codes}
                  if user_codes is not None else None)
        self.points = {}
        self.adj = defaultdict(list)
        self.grid = defaultdict(list)
        self.segment_grid = defaultdict(list)
        self.segments = []
        #: Which source feature drew each entry of ``self.segments``. Two
        #: services that share trackage for part of a route (MTA's F and M
        #: both centre-lined through the shared Manhattan trunk) end up in the
        #: same connected component the moment their coordinates coincide
        #: anywhere at all, even though they were digitised independently and
        #: diverge — without sharing a single vertex — over a genuinely
        #: parallel local/express stretch elsewhere. ``self.components`` can
        #: no longer tell those two stretches apart once that happens; this
        #: does, by keeping the origin feature of every edge.
        self.segment_feature = []
        self.cell = 0.025
        seen_segments = set()

        for feature_index, feature in enumerate(features):
            props = feature.get('properties') or {}
            if props.get('etat') not in (None, 'Opérationnel'):
                continue
            if wanted is not None:
                users = {
                    str(props.get('siguti1vo') or '').strip().casefold(),
                    str(props.get('siguti2vo') or '').strip().casefold(),
                }
                if not users.intersection(wanted):
                    continue
            geometry = feature.get('geometry') or {}
            coordinates = geometry.get('coordinates') or []
            lines = ([coordinates] if geometry.get('type') == 'LineString'
                     else coordinates if geometry.get('type') == 'MultiLineString'
                     else [])
            for line in lines:
                for a, b in zip(line, line[1:]):
                    ka, kb = self._node(a), self._node(b)
                    if ka == kb:
                        continue
                    weight = geo.haversine(self.points[ka], self.points[kb])
                    self.adj[ka].append((kb, weight))
                    self.adj[kb].append((ka, weight))
                    key = tuple(sorted((ka, kb)))
                    if key not in seen_segments:
                        seen_segments.add(key)
                        self.segments.append((ka, kb))
                        self.segment_feature.append(feature_index)

        self.joined_endpoints = []
        self._index_components()
        # The spatial grids have to exist before either join pass below: both
        # ``_join_close_endpoints`` (implicitly, via components already being
        # correct) and, especially, ``_join_endpoints_to_lines`` (explicitly
        # — it calls ``snap_candidates``, which reads ``self.segment_grid``)
        # need to search the geometry that is already there. Building them
        # first and never rebuilding them is safe: joining adds graph edges
        # between existing points, never new segments or new points.
        for node, point in self.points.items():
            self.grid[self._cell(point)].append(node)
        for index, (first, second) in enumerate(self.segments):
            ax, ay = self._cell(self.points[first])
            bx, by = self._cell(self.points[second])
            for cx in range(min(ax, bx), max(ax, bx) + 1):
                for cy in range(min(ay, by), max(ay, by) + 1):
                    self.segment_grid[(cx, cy)].append(index)
        if endpoint_join_m > 0:
            self._join_close_endpoints(endpoint_join_m)
            self._index_components()
        if endpoint_line_join_m > 0:
            # Endpoint-to-endpoint joining (above) deliberately never looks
            # at a line's interior, so a directional stub whose free end
            # merges into the *middle* of another already-modelled line —
            # not at either end of it — is left disconnected. That is a
            # different, unambiguous case: Ottawa's Trillium Line digitizes
            # its short Bayview double-track section as separate
            # ``T-ALIGN-NB``/``T-ALIGN-SB`` layers, and the southbound
            # layer's free end lands 0.0017 m from a vertex-free point on
            # the northbound polyline's interior at the merge south of
            # Corso Italia — sub-millimetre agreement that can only be the
            # same physical point recorded twice, never a real gap. Keep
            # ``endpoint_line_join_m`` tight (single-digit metres) so this
            # never bridges an actual gap between parallel tracks the way a
            # generous ``endpoint_join_m`` could.
            for _ in range(64):
                if not self._join_endpoints_to_lines(endpoint_line_join_m):
                    break
                self._index_components()

    def _index_components(self):
        self.components = {}
        component = 0
        for root in self.points:
            if root in self.components:
                continue
            stack = [root]
            self.components[root] = component
            while stack:
                node = stack.pop()
                for other, _ in self.adj.get(node, ()):
                    if other not in self.components:
                        self.components[other] = component
                        stack.append(other)
            component += 1

    def _join_close_endpoints(self, max_m):
        """Join sub-feature endpoints separated only by GIS precision gaps.

        This is opt-in for route-specific official extracts.  It deliberately
        considers degree-one endpoints only and never joins two points already
        connected through the authority's own linework.  Thus it can repair a
        MultiLineString boundary without creating a mid-line crossover between
        parallel tracks.
        """
        endpoints = [node for node in self.points
                     if len(self.adj.get(node, ())) == 1]
        candidates = []
        for index, first in enumerate(endpoints):
            for second in endpoints[index + 1:]:
                if self.components[first] == self.components[second]:
                    continue
                distance = geo.haversine(
                    self.points[first], self.points[second])
                if distance <= max_m:
                    candidates.append((distance, first, second))

        # Kruskal-style selection prevents redundant close-endpoint triangles
        # from manufacturing geometry not present in the official extract.
        parent = {component: component for component in set(self.components.values())}

        def root(value):
            while parent[value] != value:
                parent[value] = parent[parent[value]]
                value = parent[value]
            return value

        for distance, first, second in sorted(candidates):
            left = root(self.components[first])
            right = root(self.components[second])
            if left == right:
                continue
            parent[right] = left
            self.adj[first].append((second, distance))
            self.adj[second].append((first, distance))
            self.joined_endpoints.append({
                'from': list(self.points[first]),
                'to': list(self.points[second]),
                'meters': distance,
            })

    def _join_endpoints_to_lines(self, max_m):
        """Attach one degree-one endpoint per pass to another line's interior.

        Returns whether any join was made, so the caller can repeat until a
        fixed point (a chain of stubs merging one after another) settles.
        Only the *nearest* other-component snap within ``max_m`` is used,
        and never a snap onto the endpoint's own already-joined component,
        so this cannot manufacture a shortcut across two components that
        are merely close together over a longer stretch.
        """
        endpoints = [node for node in self.points
                     if len(self.adj.get(node, ())) == 1]
        best_join = None
        for node in endpoints:
            own_component = self.components[node]
            for (component, _feature), hit in self.snap_candidates(
                    self.points[node], max_m).items():
                if component == own_component:
                    continue
                if best_join is None or hit[0] < best_join[0]:
                    best_join = (hit[0], node, hit[1])
        if best_join is None:
            return False
        _, node, snap = best_join
        first, second, fraction, projected = snap
        length = geo.haversine(self.points[first], self.points[second])
        for endpoint, edge_distance in (
                (first, length * fraction),
                (second, length * (1.0 - fraction))):
            self.adj[node].append((endpoint, edge_distance))
            self.adj[endpoint].append((node, edge_distance))
        self.joined_endpoints.append({
            'from': list(self.points[node]),
            'to': list(projected),
            'meters': best_join[0],
        })
        return True

    def _node(self, point):
        node = (round(float(point[0]), 6), round(float(point[1]), 6))
        self.points.setdefault(node, [float(point[0]), float(point[1])])
        return node

    def _cell(self, point):
        return (int(math.floor(point[0] / self.cell)),
                int(math.floor(point[1] / self.cell)))

    def snap_candidates(self, point, max_m=600.0):
        """The best reachable point on each origin feature within ``max_m``.

        Keyed by ``(component, feature)`` rather than by component alone.
        Two features that are the same connected component — because they
        share trackage, and so share vertices, *somewhere* on the route —
        are not necessarily the same track at any *particular* station, and
        collapsing them to one candidate here would silently prefer whichever
        one happens to be a few centimetres closer, independently at every
        station. ``route_stations`` is what turns this into a single choice,
        and it needs both candidates to do that per interval, not just one.
        """
        cx, cy = self._cell(point)
        latitude_scale = max(0.2, math.cos(math.radians(float(point[1]))))
        radius_x = max(1, int(math.ceil(
            max_m / (111_000.0 * latitude_scale * self.cell))))
        radius_y = max(1, int(math.ceil(
            max_m / (111_000.0 * self.cell))))
        best_by_group = {}
        nearby_segments = set()
        for dx in range(-radius_x, radius_x + 1):
            for dy in range(-radius_y, radius_y + 1):
                nearby_segments.update(
                    self.segment_grid.get((cx + dx, cy + dy), ()))
        for index in nearby_segments:
            first, second = self.segments[index]
            a, b = self.points[first], self.points[second]
            distance, fraction = geo.point_segment_distance(point, a, b)
            if distance > max_m:
                continue
            projected = [
                a[0] + (b[0] - a[0]) * fraction,
                a[1] + (b[1] - a[1]) * fraction,
            ]
            group = (self.components[first], self.segment_feature[index])
            previous = best_by_group.get(group)
            if previous is None or distance < previous[0]:
                best_by_group[group] = (
                    distance, (first, second, fraction, projected))
        return best_by_group

    def snap(self, point, max_m=600.0):
        candidates = self.snap_candidates(point, max_m)
        return min(candidates.values(), default=None)

    def shortest(self, start, end):
        queue = [(0.0, start)]
        distance = {start: 0.0}
        previous = {}
        while queue:
            cost, node = heapq.heappop(queue)
            if cost != distance.get(node):
                continue
            if node == end:
                break
            for other, weight in self.adj.get(node, ()):
                candidate = cost + weight
                if candidate < distance.get(other, float('inf')):
                    distance[other] = candidate
                    previous[other] = node
                    heapq.heappush(queue, (candidate, other))
        if end not in distance:
            return None
        nodes = [end]
        while nodes[-1] != start:
            nodes.append(previous[nodes[-1]])
        nodes.reverse()
        return [list(self.points[node]) for node in nodes]

    def shortest_projections(self, start, end):
        """Shortest graph path between two points projected onto its edges.

        The base graph keeps the authority's original vertices.  Two virtual
        nodes attach each projected station point to both ends of its surveyed
        edge for this search only, so sparse source sampling cannot move a
        station hundreds of metres to the nearest stored vertex.  When both
        points lie on one edge, their direct subsegment is also available.
        """
        start_node = ('projection', 0)
        end_node = ('projection', 1)
        extra = defaultdict(list)
        virtual_points = {
            start_node: list(start[3]),
            end_node: list(end[3]),
        }

        def attach(node, snap):
            first, second, fraction, _ = snap
            length = geo.haversine(self.points[first], self.points[second])
            for endpoint, distance in (
                    (first, length * fraction),
                    (second, length * (1.0 - fraction))):
                extra[node].append((endpoint, distance))
                extra[endpoint].append((node, distance))

        attach(start_node, start)
        attach(end_node, end)
        if start[:2] == end[:2]:
            edge_length = geo.haversine(
                self.points[start[0]], self.points[start[1]])
            direct = edge_length * abs(start[2] - end[2])
            extra[start_node].append((end_node, direct))
            extra[end_node].append((start_node, direct))

        queue = [(0.0, 0, start_node)]
        sequence = 1
        distance = {start_node: 0.0}
        previous = {}
        while queue:
            cost, _, node = heapq.heappop(queue)
            if cost != distance.get(node):
                continue
            if node == end_node:
                break
            for other, weight in tuple(self.adj.get(node, ())) + tuple(extra.get(node, ())):
                candidate = cost + weight
                if candidate < distance.get(other, float('inf')):
                    distance[other] = candidate
                    previous[other] = node
                    heapq.heappush(queue, (candidate, sequence, other))
                    sequence += 1
        if end_node not in distance:
            return None
        nodes = [end_node]
        while nodes[-1] != start_node:
            nodes.append(previous[nodes[-1]])
        nodes.reverse()
        return self.drop_junction_stubs(geo.dedupe([
            list(virtual_points[node]) if node in virtual_points
            else list(self.points[node])
            for node in nodes
        ]))

    #: A routed interval that turns further than this at one vertex has not
    #: taken a corner, it has doubled back.  155 degrees is where the builder
    #: calls an interval impossible (`FeedBuild.has_internal_reversal`); the
    #: repair starts lower so the residual barb left behind by removing the
    #: tip is removed with it rather than shipped just under the gate.
    STUB_TURN_DEG = 120.0
    #: How far past a junction the doubling-back may reach before the shape is
    #: something other than a stub.  Every removal moves the line by at most
    #: this much and never off the authority's own linework, because both
    #: neighbours of a removed vertex are vertices of it.
    STUB_MAX_M = 40.0

    @classmethod
    def drop_junction_stubs(cls, points):
        """Remove the out-and-back a junction marker puts in a routed path.

        Route-specific official extracts are published as many short pieces
        that meet at one shared coordinate per junction, and that coordinate
        is the interlocking's own point rather than a point on either through
        alignment.  Two cases, both seen in the sources this module routes:

        * Chicago's Loop file joins the Van Buren leg, the Wabash leg and the
          south leg at "Tower 12".  The Van Buren piece is drawn curving into
          the *south* leg, so a service that turns the corner there — Brown,
          Pink, Purple — enters the node 11 m past the corner and leaves it
          172 degrees back the way it came.  Orange, which runs straight
          through the same node, is unaffected.
        * Pittsburgh's North Shore Connector is two parallel directional
          tracks joined only at their east end.  A station 20 m from one track
          and 25 m from the other snaps to the near one while the path arrives
          on the far one, so the path runs out to the shared end and back.

        Neither is a wrong route: in both the shortest path is the only path,
        and it is the *shape at the shared node* that is wrong.  So the repair
        is local — drop the vertex the path doubles back at, and keep dropping
        while the barb it leaves behind is still a reversal — rather than a
        different search.  A path with no such vertex is returned untouched,
        which is every line these extracts route today except the five above.
        """
        if not points or len(points) < 3:
            return points
        trimmed = [list(point) for point in points]
        changed = True
        while changed and len(trimmed) > 2:
            changed = False
            for index in range(1, len(trimmed) - 1):
                before, here, after = trimmed[index - 1:index + 2]
                if geo.turn_degrees(before, here, after) < cls.STUB_TURN_DEG:
                    continue
                stub = min(geo.haversine(before, here),
                           geo.haversine(here, after))
                if stub > cls.STUB_MAX_M:
                    continue
                del trimmed[index]
                changed = True
                break
        return trimmed

    def route_stations(self, stations, max_snap_m=600.0, ratio_cap=None):
        # Directional track centrelines are often separate parallel features,
        # and picking each station's individually nearest rail can alternate
        # between two tracks that only meet far from either station — making
        # a complete official route look like it needs a giant detour to get
        # between two stations a block apart. ``snap_candidates`` already
        # groups by ``(component, feature)`` so a station touching two such
        # tracks offers a candidate on each; the fix here is which candidate
        # each *interval* uses.
        #
        # It is chosen per interval, independently, the same as an ordinary
        # nearest-track snap: the group shared by both of an interval's
        # stations if one reaches both of them, otherwise each station's own
        # nearest. This alone already keeps every interval short — including
        # on MTA's F, where 46 St only reaches the M-tagged track (F's own
        # polyline bows 300-400 m off the true platform there) while Northern
        # Blvd, one stop over, reaches both and is legitimately a few metres
        # closer to the F-tagged one.
        #
        # That difference is real: a shortest path forced to travel from the
        # M-tagged point at 46 St to the F-tagged point at Northern Blvd has
        # to do it over the graph, and MTA's F and M only share vertices on
        # their common Manhattan trunk, kilometres from Queens Blvd — so the
        # "shortest" such path is a many-kilometre loop out to the trunk and
        # back for what is really a 725 m hop. Requiring every interval that
        # touches a shared station to agree on the *same* graph-connected
        # point manufactures exactly that loop. What the caller actually
        # needs is only that the two intervals meeting at a station end and
        # begin at the identical coordinate — and the two independently
        # chosen points, metres apart, are both legitimately that station,
        # so the fix is to make them coincide, not to route between them.
        choices = [self.snap_candidates(point, max_snap_m)
                   for point in stations]
        snap_meters = [min((hit[0] for hit in row.values()), default=None)
                       for row in choices]
        if any(hit is None for hit in snap_meters):
            return None, {'snapMeters': snap_meters}
        intervals = []
        for index in range(len(stations) - 1):
            left, right = choices[index], choices[index + 1]
            common = set(left) & set(right)
            if common:
                group = min(
                    common,
                    key=lambda value: left[value][0] + right[value][0])
                start, end = left[group], right[group]
            else:
                start = min(left.values(), key=lambda hit: hit[0])
                end = min(right.values(), key=lambda hit: hit[0])
            piece = self.shortest_projections(start[1], end[1])
            if not piece:
                return None, {'snapMeters': snap_meters, 'failed': index}
            straight = geo.haversine(stations[index], stations[index + 1])
            length = geo.line_length(piece)
            if ratio_cap is not None and straight > 0 and length / straight > ratio_cap:
                return None, {
                    'snapMeters': snap_meters,
                    'failed': index,
                    'ratio': length / straight,
                }
            intervals.append(piece)
        # A station whose two neighbouring intervals independently picked a
        # different — but each individually legitimate, within max_snap_m —
        # candidate ends up with two projected points a few metres apart
        # instead of one. Both really are the station; reconcile by using
        # whichever of the two sits closer to the published position at
        # both ends, a coordinate swap on the pieces already computed, never
        # a new path search.
        for index in range(1, len(stations) - 1):
            left_piece, right_piece = intervals[index - 1], intervals[index]
            if not left_piece or not right_piece:
                continue
            if geo.haversine(left_piece[-1], right_piece[0]) <= 1.0:
                continue
            canonical = min(
                (left_piece[-1], right_piece[0]),
                key=lambda point: geo.haversine(point, stations[index]))
            left_piece[-1] = list(canonical)
            right_piece[0] = list(canonical)
        return intervals, {'snapMeters': snap_meters}


def load_geojson(path, user_codes, endpoint_join_m=0.0):
    import json
    with open(path) as fh:
        payload = json.load(fh)
    return PassengerNetwork(payload.get('features') or (), user_codes,
                            endpoint_join_m=endpoint_join_m)
