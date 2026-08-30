"""Which country a point is in, and where a line crosses between two.

The North American packages are per country, like every other package family
in this app, and three passenger railways do not respect that: Amtrak's
*Maple Leaf* runs to Toronto, its *Adirondack* to Montréal, its *Cascades* to
Vancouver. A line that crosses is SPLIT at the border and shipped as one
display line in each package — the same treatment Hong Kong's 東鐵綫 gets for
its two northern branches, and for the same reason: a package says what the
railways of one country are, and half of the Maple Leaf is not one of Canada's.

Splitting is what makes the journey genuinely cross-border rather than
pretending the border is not there, which is the point of the support added
alongside these packages.
"""
from __future__ import annotations

import json
import math

from na_geo import haversine


class Countries:
    """Point-in-country over an admin-0 boundary set.

    A bounding-box prefilter then an even-odd ray cast per ring. The boundary
    file is the authority; nothing here rounds a coastline or approximates the
    49th parallel, because the border this has to get right is the one along
    the St Lawrence and through the Great Lakes, where a rule of thumb is
    wrong by a country.
    """

    def __init__(self, path, wanted=('United States of America', 'Canada')):
        with open(path) as fh:
            data = json.load(fh)
        self.polygons = []          # (code, minlon, minlat, maxlon, maxlat, rings)
        codes = {'United States of America': 'us', 'Canada': 'ca'}
        for feature in data['features']:
            name = feature['properties'].get('ADMIN') or feature['properties'].get('admin')
            if name not in wanted:
                continue
            code = codes[name]
            geom = feature['geometry']
            polys = (geom['coordinates'] if geom['type'] == 'MultiPolygon'
                     else [geom['coordinates']])
            for poly in polys:
                rings = [[(float(x), float(y)) for x, y in ring] for ring in poly]
                xs = [p[0] for p in rings[0]]
                ys = [p[1] for p in rings[0]]
                self.polygons.append((code, min(xs), min(ys), max(xs), max(ys), rings))

    def code_at(self, lon, lat):
        for code, x0, y0, x1, y1, rings in self.polygons:
            if not (x0 <= lon <= x1 and y0 <= lat <= y1):
                continue
            if _in_ring(lon, lat, rings[0]) and not any(
                    _in_ring(lon, lat, hole) for hole in rings[1:]):
                return code
        return None

    def code_for(self, lon, lat, fallback=None):
        """The country a point is in, or the nearest one within ~30 km.

        A station on a bridge over the Detroit River, or a coastal terminal
        whose published coordinate lands a few metres offshore of a 1:10m
        coastline, is not in any polygon. Answering ``None`` there would drop
        the station out of both packages, so the nearest boundary within a
        short reach decides instead — and beyond that reach the caller's own
        fallback (the operator's country) does.
        """
        hit = self.code_at(lon, lat)
        if hit:
            return hit
        best = (float('inf'), None)
        for code, x0, y0, x1, y1, rings in self.polygons:
            if not (x0 - 0.5 <= lon <= x1 + 0.5 and y0 - 0.5 <= lat <= y1 + 0.5):
                continue
            for ring in rings[:1]:
                for i in range(0, len(ring) - 1, 3):
                    d = haversine([lon, lat], ring[i])
                    if d < best[0]:
                        best = (d, code)
        if best[0] <= 30_000:
            return best[1]
        return fallback


class NetworkCountries:
    """Which country a point is in, taken from the FRA network's own answer.

    Every segment of the North American Rail Network carries ``COUNTRY``, so
    the border question a railway package actually asks — *which country is
    this station's track in* — is answered by the same official file the track
    comes from, rather than by a coastline drawn at some other scale. It is
    also the right answer at Niagara Falls and Windsor, where the two
    countries' stations are a kilometre apart across a river and a boundary
    generalised for a world map is not to be trusted.

    A point with no track within ``reach_m`` gets the caller's fallback, which
    is the country the operator is registered in.
    """

    def __init__(self, features, reach_m=25_000, cell_deg=0.05):
        self.cell = cell_deg
        self.reach = reach_m
        self.buckets = {}
        for feature in features:
            props = feature.get('properties') or {}
            code = (props.get('COUNTRY') or '').strip().lower()
            if code not in ('us', 'ca'):
                continue
            geometry = feature.get('geometry') or {}
            if geometry.get('type') != 'LineString':
                continue
            points = geometry['coordinates']
            for i in range(0, len(points), 2):
                lon, lat = points[i][0], points[i][1]
                key = (int(math.floor(lon / self.cell)), int(math.floor(lat / self.cell)))
                self.buckets.setdefault(key, []).append((lon, lat, code))

    def code_for(self, lon, lat, fallback=None):
        cell = self.cell
        kx, ky = int(math.floor(lon / cell)), int(math.floor(lat / cell))
        span = max(1, int(math.ceil(self.reach / 111_000.0 / cell)))
        best = (float('inf'), None)
        for radius in range(0, span + 1):
            for dx in range(-radius, radius + 1):
                for dy in range(-radius, radius + 1):
                    if radius and max(abs(dx), abs(dy)) != radius:
                        continue
                    for plon, plat, code in self.buckets.get((kx + dx, ky + dy), ()):
                        d = haversine([lon, lat], [plon, plat])
                        if d < best[0]:
                            best = (d, code)
            if best[1] is not None and radius >= 1:
                break
        if best[0] <= self.reach:
            return best[1]
        return fallback

    def code_at(self, lon, lat):
        return self.code_for(lon, lat, None)


def _in_ring(x, y, ring):
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y):
            denom = (yj - yi)
            if denom != 0 and x < (xj - xi) * (y - yi) / denom + xi:
                inside = not inside
        j = i
    return inside


def split_runs(codes):
    """Turn a per-station country list into contiguous runs.

    Returns ``[(code, first_index, last_index), …]``. A single station of one
    country between two runs of another — which is what a coordinate landing
    on the wrong side of the drawn coastline looks like — is absorbed into its
    neighbours rather than becoming a one-station display line.
    """
    if not codes:
        return []
    cleaned = list(codes)
    for i in range(1, len(cleaned) - 1):
        if cleaned[i] != cleaned[i - 1] and cleaned[i - 1] == cleaned[i + 1]:
            cleaned[i] = cleaned[i - 1]
    runs = []
    start = 0
    for i in range(1, len(cleaned) + 1):
        if i == len(cleaned) or cleaned[i] != cleaned[start]:
            runs.append((cleaned[start], start, i - 1))
            start = i
    return runs
