"""Geodesy, simplification and display grooming for the North American packages.

Everything here works on ``[lon, lat]`` pairs in WGS84 — the CRS every
``compact-v1`` package declares — and measures in metres by projecting a small
neighbourhood to a local tangent plane. Nothing in this module knows what a
railway is; the policy that decides how hard to groom one lives in
``na_profile.py`` beside the reasons for it.
"""
from __future__ import annotations

import math

EARTH_RADIUS_M = 6371008.8


# ---------------------------------------------------------------- distances

def haversine(a, b):
    """Great-circle metres between two ``[lon, lat]`` points."""
    lat1, lat2 = math.radians(a[1]), math.radians(b[1])
    dlat = lat2 - lat1
    dlon = math.radians(b[0] - a[0])
    h = (math.sin(dlat / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(h)))


def line_length(points):
    return sum(haversine(points[i], points[i + 1]) for i in range(len(points) - 1))


def cumulative(points):
    out = [0.0]
    for i in range(len(points) - 1):
        out.append(out[-1] + haversine(points[i], points[i + 1]))
    return out


# ------------------------------------------------- local tangent projection

class Plane:
    """An equirectangular tangent plane, metres, centred on ``lat0/lon0``.

    Railway grooming is a metre-scale operation over spans of at most a few
    kilometres, and every step of it — perpendicular distance to a chord, the
    radius of a corner, the position of a Bézier control point — is stated in
    metres. Doing that arithmetic in degrees means a different answer at
    Anchorage than at Miami for the same railway geometry, so each operation
    projects its own neighbourhood, works in metres, and projects back.
    """

    __slots__ = ('lon0', 'lat0', 'kx', 'ky')

    def __init__(self, lon0, lat0):
        self.lon0 = lon0
        self.lat0 = lat0
        self.ky = math.pi * EARTH_RADIUS_M / 180.0
        self.kx = self.ky * math.cos(math.radians(lat0))

    @classmethod
    def around(cls, points):
        lon = sum(p[0] for p in points) / len(points)
        lat = sum(p[1] for p in points) / len(points)
        return cls(lon, lat)

    def to_xy(self, p):
        return ((p[0] - self.lon0) * self.kx, (p[1] - self.lat0) * self.ky)

    def to_lonlat(self, xy):
        return [self.lon0 + xy[0] / self.kx, self.lat0 + xy[1] / self.ky]


# ------------------------------------------------------------- point/segment

def point_segment_distance(p, a, b):
    """Metres from ``p`` to segment ``a``–``b``, and the fraction along it."""
    plane = Plane(a[0], a[1])
    px, py = plane.to_xy(p)
    ax, ay = plane.to_xy(a)
    bx, by = plane.to_xy(b)
    dx, dy = bx - ax, by - ay
    denom = dx * dx + dy * dy
    if denom <= 0:
        return math.hypot(px - ax, py - ay), 0.0
    t = ((px - ax) * dx + (py - ay) * dy) / denom
    t = max(0.0, min(1.0, t))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy), t


def project_to_line(p, points, cumul=None):
    """Nearest point on a polyline.

    Returns ``(distance_m, index, t, coordinate, measure_m)`` where ``index``
    and ``t`` locate the projection on segment ``index`` and ``measure`` is its
    arc length from the start of the line.
    """
    if cumul is None:
        cumul = cumulative(points)
    best = (float('inf'), 0, 0.0, points[0], 0.0)
    for i in range(len(points) - 1):
        d, t = point_segment_distance(p, points[i], points[i + 1])
        if d < best[0]:
            a, b = points[i], points[i + 1]
            coord = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
            measure = cumul[i] + (cumul[i + 1] - cumul[i]) * t
            best = (d, i, t, coord, measure)
    return best


def slice_between(points, cumul, start_m, end_m):
    """The part of a polyline between two arc-length measures, inclusive."""
    if end_m < start_m:
        start_m, end_m = end_m, start_m
    out = [interpolate(points, cumul, start_m)]
    for i, m in enumerate(cumul):
        if start_m < m < end_m:
            out.append(list(points[i]))
    out.append(interpolate(points, cumul, end_m))
    return dedupe(out)


def interpolate(points, cumul, measure):
    if measure <= 0:
        return list(points[0])
    if measure >= cumul[-1]:
        return list(points[-1])
    lo, hi = 0, len(cumul) - 1
    while lo < hi - 1:
        mid = (lo + hi) // 2
        if cumul[mid] <= measure:
            lo = mid
        else:
            hi = mid
    span = cumul[hi] - cumul[lo]
    t = 0.0 if span <= 0 else (measure - cumul[lo]) / span
    a, b = points[lo], points[hi]
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]


def dedupe(points, epsilon_m=0.05):
    out = []
    for p in points:
        if not out or haversine(out[-1], p) > epsilon_m:
            out.append(list(p))
    if len(out) == 1 and len(points) > 1:
        out.append(list(points[-1]))
    return out


# ------------------------------------------------------------ simplification

def simplify(points, tolerance_m):
    """Douglas–Peucker, with the perpendicular distance measured in metres.

    Endpoints are never moved: a display interval's two ends are the stations
    it runs between, and a simplifier that shaved a terminal would move a
    station marker off its platform.
    """
    if tolerance_m <= 0 or len(points) < 3:
        return [list(p) for p in points]
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        if last <= first + 1:
            continue
        worst, index = -1.0, -1
        a, b = points[first], points[last]
        for i in range(first + 1, last):
            d, _ = point_segment_distance(points[i], a, b)
            if d > worst:
                worst, index = d, i
        if worst > tolerance_m:
            keep[index] = True
            stack.append((first, index))
            stack.append((index, last))
    return [list(p) for p, k in zip(points, keep) if k]


# -------------------------------------------------------------- sawtooth fix

def relax_spikes(points, edge_m, turn_deg, deviation_m):
    """Drop a vertex that runs out and straight back.

    The same shape ``rail-network.js`` calls a micro-kink and grooms at draw
    time. Doing it again here is not redundancy: the renderer's pass is capped
    so it can run on every frame budget, and a source with dense digitising
    noise needs the barbs gone before the simplifier measures deviation
    against them.

    Two tests, because a barb and a kink are different shapes. A *kink* is a
    corner with one short edge, and how far it may move the line when it goes
    is the question ``deviation_m`` answers. A *barb* is the line leaving a
    point and coming back to it, and for that shape the deviation test asks
    nothing: the distance from the tip to the chord between its neighbours is
    the length of the excursion by construction, so no barb longer than
    ``deviation_m`` can ever pass it — which is why the reversal branch skips
    the test. That left the absolute edge cap as the only limit, and it is a
    micro-kink's cap: WMATA publishes ``RBLU_28`` with one pair of coordinates
    18 m apart repeated four times, and eighty-four such near-reversals
    survived every pass of the grooming on six Washington metro lines because
    18 m is more than the 12 m a metro's kinks are measured against.

    So the barb is recognised by its shape instead of its size: the two
    neighbours are nearer to each other than the vertex is to either of them,
    which no corner satisfies and every out-and-back does, at any scale.
    """
    if len(points) < 3:
        return [list(p) for p in points]
    out = [list(points[0])]
    i = 1
    while i < len(points) - 1:
        prev, here, nxt = out[-1], points[i], points[i + 1]
        a = haversine(prev, here)
        b = haversine(here, nxt)
        if haversine(prev, nxt) <= min(a, b) and turn_degrees(prev, here, nxt) >= 150.0:
            i += 1
            continue
        if min(a, b) <= edge_m:
            turn = turn_degrees(prev, here, nxt)
            if turn >= 150.0:
                i += 1
                continue
            if turn >= turn_deg:
                dev, _ = point_segment_distance(here, prev, nxt)
                if dev <= deviation_m:
                    i += 1
                    continue
        out.append(list(here))
        i += 1
    out.append(list(points[-1]))
    return out


def turn_degrees(a, b, c):
    """Deflection at ``b`` — 0° for straight ahead, 180° for a reversal."""
    plane = Plane(b[0], b[1])
    ax, ay = plane.to_xy(a)
    bx, by = plane.to_xy(b)
    cx, cy = plane.to_xy(c)
    v1 = (bx - ax, by - ay)
    v2 = (cx - bx, cy - by)
    n1 = math.hypot(*v1)
    n2 = math.hypot(*v2)
    if n1 <= 0 or n2 <= 0:
        return 0.0
    cosine = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / (n1 * n2)))
    return math.degrees(math.acos(cosine))


# ------------------------------------------------------------ corner rounding

def round_corners(points, max_offset_m, samples=6, reversal_min_deg=150.0):
    """Replace each corner with a bounded quadratic arc.

    The fillet is cut at most ``max_offset_m`` back along each of the corner's
    two edges — and never more than a third of the shorter edge, so two
    adjacent corners cannot eat the segment between them. A reversal (a
    switchback tail, a stub terminal a train backs out of) is left alone: it is
    the one corner where the sharpness is the fact.
    """
    if len(points) < 3 or max_offset_m <= 0:
        return [list(p) for p in points]
    out = [list(points[0])]
    for i in range(1, len(points) - 1):
        a, b, c = points[i - 1], points[i], points[i + 1]
        turn = turn_degrees(a, b, c)
        if turn < 6.0 or turn >= reversal_min_deg:
            out.append(list(b))
            continue
        la = haversine(a, b)
        lb = haversine(b, c)
        cut = min(max_offset_m, la / 3.0, lb / 3.0)
        if cut < 0.5:
            out.append(list(b))
            continue
        plane = Plane(b[0], b[1])
        ax, ay = plane.to_xy(a)
        bx, by = plane.to_xy(b)
        cx, cy = plane.to_xy(c)
        p0 = (bx + (ax - bx) * (cut / la), by + (ay - by) * (cut / la))
        p2 = (bx + (cx - bx) * (cut / lb), by + (cy - by) * (cut / lb))
        for s in range(samples + 1):
            t = s / samples
            u = 1.0 - t
            x = u * u * p0[0] + 2 * u * t * bx + t * t * p2[0]
            y = u * u * p0[1] + 2 * u * t * by + t * t * p2[1]
            out.append(plane.to_lonlat((x, y)))
    out.append(list(points[-1]))
    return dedupe(out, 0.2)


def enforce_min_radius(points, radius_m, window_m, anchor_tolerance_m,
                       reversal_min_deg=150.0, passes=4):
    """Relax any corner tighter than ``radius_m``, measured over an arc window.

    Measuring between neighbouring vertices is what the Taiwan package's own
    2025.5.2 note found insufficient: where two sources are welded the vertices
    can sit metres apart, and the corner between them reads as a barb rather
    than a curve however gentle the angle between those two short edges looks.
    So the turn is measured between the points ``window_m`` back and forward
    along the line, and the vertex is nudged toward the chord until the implied
    radius clears the floor — never further than ``anchor_tolerance_m`` from
    where the rest of the grooming left it.
    """
    if len(points) < 3 or radius_m <= 0:
        return [list(p) for p in points]
    pts = [list(p) for p in points]
    for _ in range(passes):
        cumul = cumulative(pts)
        moved = False
        for i in range(1, len(pts) - 1):
            back = interpolate(pts, cumul, cumul[i] - window_m)
            fwd = interpolate(pts, cumul, cumul[i] + window_m)
            turn = turn_degrees(back, pts[i], fwd)
            if turn < 1.0 or turn >= reversal_min_deg:
                continue
            # Radius of the circle through the three sample points.
            arc = min(window_m, cumul[i], cumul[-1] - cumul[i])
            if arc <= 0:
                continue
            radius = arc / math.radians(turn) if turn > 0 else float('inf')
            if radius >= radius_m:
                continue
            need = min(1.0, 1.0 - radius / radius_m)
            target = [(back[0] + fwd[0]) / 2.0, (back[1] + fwd[1]) / 2.0]
            step = [pts[i][0] + (target[0] - pts[i][0]) * need * 0.5,
                    pts[i][1] + (target[1] - pts[i][1]) * need * 0.5]
            if haversine(step, points[i]) > anchor_tolerance_m:
                continue
            pts[i] = step
            moved = True
        if not moved:
            break
    return pts


def densify(points, max_edge_m):
    """Split any edge longer than ``max_edge_m`` collinearly.

    A two-coordinate chord is drawn as a straight line by both renderers, and
    over tens of kilometres a straight line in WGS84 is not where the railway
    is. Splitting changes no alignment — every inserted vertex lies on the
    chord it splits — it only stops the chord being drawn whole.
    """
    if max_edge_m <= 0 or len(points) < 2:
        return [list(p) for p in points]
    out = [list(points[0])]
    for i in range(len(points) - 1):
        a, b = points[i], points[i + 1]
        d = haversine(a, b)
        if d > max_edge_m:
            steps = int(math.ceil(d / max_edge_m))
            for s in range(1, steps):
                t = s / steps
                out.append([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t])
        out.append(list(b))
    return out


# ------------------------------------------------------------- cross-checking

class ReferenceIndex:
    """A grid index over reference centrelines, for deviation measurement.

    The check every package makes before it is shipped — "is every vertex we
    drew within tolerance of a source that is allowed to say where the railway
    is" — is a nearest-segment query run hundreds of thousands of times, so the
    references are bucketed into a degree grid and only the buckets around a
    query point are scanned.
    """

    def __init__(self, cell_deg=0.02):
        self.cell = cell_deg
        self.buckets = {}
        self.count = 0

    def _key(self, lon, lat):
        return (int(math.floor(lon / self.cell)), int(math.floor(lat / self.cell)))

    def add_line(self, points, tag=None):
        for i in range(len(points) - 1):
            a, b = points[i], points[i + 1]
            self.count += 1
            k0 = self._key(min(a[0], b[0]), min(a[1], b[1]))
            k1 = self._key(max(a[0], b[0]), max(a[1], b[1]))
            for kx in range(k0[0], k1[0] + 1):
                for ky in range(k0[1], k1[1] + 1):
                    self.buckets.setdefault((kx, ky), []).append((a, b, tag))

    def nearest(self, p, search_cells=1):
        kx, ky = self._key(p[0], p[1])
        best = (float('inf'), None)
        for dx in range(-search_cells, search_cells + 1):
            for dy in range(-search_cells, search_cells + 1):
                for a, b, tag in self.buckets.get((kx + dx, ky + dy), ()):
                    d, _ = point_segment_distance(p, a, b)
                    if d < best[0]:
                        best = (d, tag)
        return best
