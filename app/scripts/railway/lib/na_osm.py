"""OpenStreetMap track, as the second opinion a built line is measured against.

Nothing in either package is BUILT from OpenStreetMap. This module exists so
that the geometry which has only one official source — the street and transit
track the FRA does not survey — is still checked against an independent one
before it ships, and so that the disagreement is written into the package
rather than left for a reader to notice on the map.

The extracts are whatever ``download-north-america-osm-crosscheck.py`` fetched:
one gzipped Overpass response per bounding-box tile, holding the ways tagged
``railway`` inside it. They are indexed on a coarse grid so a query touches a
few hundred segments rather than a city's worth.
"""
from __future__ import annotations

import gzip
import json
import math
import os

import na_geo as geo


class Track:
    """Every OSM railway way in the downloaded tiles, on a lookup grid."""

    def __init__(self, cell_deg=0.02):
        self.cell = cell_deg
        self.ways = []              # [[lon, lat], …]
        self.kinds = []             # the way's own `railway` value
        self.buckets = {}
        self.tiles = 0

    def _key(self, lon, lat):
        return (int(math.floor(lon / self.cell)), int(math.floor(lat / self.cell)))

    def add_way(self, points, kind):
        if len(points) < 2:
            return
        index = len(self.ways)
        self.ways.append(points)
        self.kinds.append(kind)
        for i in range(len(points) - 1):
            a, b = points[i], points[i + 1]
            k0 = self._key(min(a[0], b[0]), min(a[1], b[1]))
            k1 = self._key(max(a[0], b[0]), max(a[1], b[1]))
            for kx in range(k0[0], k1[0] + 1):
                for ky in range(k0[1], k1[1] + 1):
                    self.buckets.setdefault((kx, ky), []).append((index, i))

    def load_dir(self, path):
        if not os.path.isdir(path):
            return self
        for name in sorted(os.listdir(path)):
            full = os.path.join(path, name)
            if not name.endswith(('.json', '.json.gz')):
                continue
            try:
                raw = (gzip.decompress(open(full, 'rb').read())
                       if name.endswith('.gz') else open(full, 'rb').read())
                data = json.loads(raw)
            except Exception:                       # noqa: BLE001
                continue
            self.tiles += 1
            for element in data.get('elements', ()):
                if element.get('type') != 'way':
                    continue
                geometry = element.get('geometry') or ()
                points = [[p['lon'], p['lat']] for p in geometry]
                self.add_way(points, (element.get('tags') or {}).get('railway', ''))
        return self

    def nearest(self, point, search_cells=1):
        """Metres to the closest OSM railway segment, and its `railway` value."""
        kx, ky = self._key(point[0], point[1])
        best = (float('inf'), None)
        for dx in range(-search_cells, search_cells + 1):
            for dy in range(-search_cells, search_cells + 1):
                for way, i in self.buckets.get((kx + dx, ky + dy), ()):
                    points = self.ways[way]
                    d, _ = geo.point_segment_distance(point, points[i], points[i + 1])
                    if d < best[0]:
                        best = (d, self.kinds[way])
        return best

    @property
    def way_count(self):
        return len(self.ways)
