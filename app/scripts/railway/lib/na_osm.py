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
import re

import na_geo as geo


_CURRENT_TILE_RE = re.compile(
    r'^tile-([+-]\d+\.\d{5})_([+-]\d+\.\d{5})_'
    r'([+-]\d+\.\d{5})_([+-]\d+\.\d{5})\.json(?:\.gz)?$')
_LEGACY_TILE_RE = re.compile(
    r'^tile-([+-]\d+\.\d{3})([+-]\d+\.\d{3})\.json(?:\.gz)?$')


def _newest(paths):
    """The newest path, with the name as a deterministic tie breaker."""
    return max(paths, key=lambda p: (os.stat(p).st_mtime_ns, os.path.basename(p)))


def osm_tile_paths(path):
    """Return one internally consistent set of cached Overpass responses.

    The original cache name contained only the south/west corner. A failed
    parent request and its southwest quarter therefore had the same name, so
    a quarter could overwrite the parent and later masquerade as complete.
    Current names contain all four bounds.

    A directory containing any current name is a current-generation cache:
    legacy names are left on disk for the owner but are not mixed into the
    result. A legacy-only directory remains readable. If a completed current
    parent and old split children coexist, the parent alone represents that
    area; when the parent is absent, all completed children remain effective.
    Unrecognised JSON response names retain the historical loader behaviour
    and are included alongside the selected generation.
    """
    if not os.path.isdir(path):
        return []

    current = {}
    legacy = {}
    other = []
    for name in os.listdir(path):
        if not name.endswith(('.json', '.json.gz')):
            continue
        full = os.path.join(path, name)
        match = _CURRENT_TILE_RE.fullmatch(name)
        if match:
            bounds = tuple(float(value) for value in match.groups())
            current.setdefault(bounds, []).append(full)
            continue
        match = _LEGACY_TILE_RE.fullmatch(name)
        if match:
            corner = tuple(float(value) for value in match.groups())
            legacy.setdefault(corner, []).append(full)
            continue
        other.append(full)

    selected = []
    if current:
        candidates = [(bounds, _newest(paths))
                      for bounds, paths in current.items()]
        for inner, inner_path in candidates:
            contained = any(
                outer != inner
                and outer[0] <= inner[0] and outer[1] <= inner[1]
                and outer[2] >= inner[2] and outer[3] >= inner[3]
                for outer, _ in candidates)
            if not contained:
                selected.append(inner_path)
    else:
        selected.extend(_newest(paths) for paths in legacy.values())
    selected.extend(other)
    return sorted(selected, key=lambda p: (
        os.stat(p).st_mtime_ns, os.path.basename(p)))


def load_osm_way_elements(path, ignore_errors=False):
    """Load effective tiles and keep only the newest copy of each OSM way.

    Overlapping tiles commonly repeat a way. If OSM changes during a resumed
    download, file modification time is the only local freshness signal, so
    files are read oldest-to-newest and the newest occurrence of a way id
    wins. Anonymous ways cannot be matched and are retained independently.
    Returns ``(way_elements, successfully_read_tile_count)``.
    """
    ways = {}
    anonymous = []
    tiles = 0
    for full in osm_tile_paths(path):
        try:
            with open(full, 'rb') as fh:
                raw = fh.read()
            if full.endswith('.gz'):
                raw = gzip.decompress(raw)
            data = json.loads(raw)
        except Exception:                       # noqa: BLE001
            if ignore_errors:
                continue
            raise
        tiles += 1
        for element in data.get('elements', ()):
            if element.get('type') != 'way':
                continue
            way_id = element.get('id')
            if way_id is None:
                anonymous.append(element)
            else:
                ways[way_id] = element
    return list(ways.values()) + anonymous, tiles


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
        elements, loaded_tiles = load_osm_way_elements(path, ignore_errors=True)
        self.tiles += loaded_tiles
        for element in elements:
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
