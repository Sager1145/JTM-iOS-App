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

    def __init__(self, features, user_codes=None, endpoint_join_m=0.0):
        wanted = ({str(code).strip().casefold() for code in user_codes}
                  if user_codes is not None else None)
        self.points = {}
        self.adj = defaultdict(list)
        self.grid = defaultdict(list)
        self.cell = 0.025

        for feature in features:
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

        self.joined_endpoints = []
        self._index_components()
        if endpoint_join_m > 0:
            self._join_close_endpoints(endpoint_join_m)
            self._index_components()
        for node, point in self.points.items():
            self.grid[self._cell(point)].append(node)

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

    def _node(self, point):
        node = (round(float(point[0]), 6), round(float(point[1]), 6))
        self.points.setdefault(node, [float(point[0]), float(point[1])])
        return node

    def _cell(self, point):
        return (int(math.floor(point[0] / self.cell)),
                int(math.floor(point[1] / self.cell)))

    def snap_candidates(self, point, max_m=600.0):
        cx, cy = self._cell(point)
        radius = max(1, int(math.ceil(max_m / 2_000.0)))
        best_by_component = {}
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                for node in self.grid.get((cx + dx, cy + dy), ()):
                    distance = geo.haversine(point, self.points[node])
                    component = self.components[node]
                    previous = best_by_component.get(component)
                    if (distance <= max_m
                            and (previous is None or distance < previous[0])):
                        best_by_component[component] = (distance, node)
        return best_by_component

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

    def route_stations(self, stations, max_snap_m=600.0, ratio_cap=None):
        # Directional track centrelines are often separate parallel features.
        # Picking each station's individually nearest rail can alternate
        # between the two disconnected directions and make a complete official
        # route appear unroutable. Choose the single connected component that
        # reaches every station and has the least total snap distance.
        choices = [self.snap_candidates(point, max_snap_m)
                   for point in stations]
        common = set(choices[0]) if choices else set()
        for candidates in choices[1:]:
            common.intersection_update(candidates)
        if common:
            component = min(
                common,
                key=lambda value: sum(row[value][0] for row in choices))
            snaps = [row[component] for row in choices]
        else:
            snaps = [min(row.values(), default=None) for row in choices]
        snap_meters = [hit[0] if hit else None for hit in snaps]
        if any(hit is None for hit in snaps):
            return None, {'snapMeters': snap_meters}
        intervals = []
        for index in range(len(stations) - 1):
            piece = self.shortest(snaps[index][1], snaps[index + 1][1])
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
        return intervals, {'snapMeters': snap_meters}


def load_geojson(path, user_codes, endpoint_join_m=0.0):
    import json
    with open(path) as fh:
        payload = json.load(fh)
    return PassengerNetwork(payload.get('features') or (), user_codes,
                            endpoint_join_m=endpoint_join_m)
