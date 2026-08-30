"""Turning one operator's feed into finished display lines.

The stages, in the order they run, and what each is allowed to change:

1. **read** — the operator's routes, patterns, stations and alignment. Nothing
   is invented; a feed that does not say something is recorded as not saying it.
2. **route** — mainline lines are re-laid over the FRA network inside the
   corridor the operator's own alignment draws (``na_narn``); everything else
   keeps the operator's alignment, which for rapid transit and light rail is
   the more detailed of the two by a wide margin.
3. **anchor** — every station is projected onto the routed line and the two
   intervals it separates are cut at that exact coordinate, so a train runs
   *through* a station instead of turning into a platform and back out.
4. **groom** — sawteeth relaxed, geometry simplified, corners rounded and held
   to a minimum radius, long chords subdivided. How hard each of those pushes
   is decided per line by ``na_profile`` from the line's own scale and length.
5. **check** — every vertex is measured against the reference geometry that is
   allowed to say where this railway is, and the worst disagreement is recorded
   in the package.
"""
from __future__ import annotations

import math
from collections import defaultdict

import na_geo as geo
import na_profile as prof


# ------------------------------------------------------------------ anchoring

def orient(points, station_points):
    """Turn an alignment round when it runs against the station order.

    An operator publishes a shape per direction and a display line has one
    order, so half of them arrive backwards — and cutting a backwards shape at
    a forwards station list is not slightly wrong, it is catastrophic: every
    interval is then measured the long way round the line and BART's four-mile
    Transbay Tube came out at twenty-seven kilometres.

    Decided by counting, not by comparing the ends: a line whose two terminals
    are close together (a loop, a horseshoe) has no informative pair of ends,
    while the number of consecutive station pairs that advance along the shape
    is right for every shape.
    """
    if len(points) < 2 or len(station_points) < 2:
        return points
    cumul = geo.cumulative(points)
    measures = [geo.project_to_line(p, points, cumul)[4] for p in station_points]
    forward = sum(1 for i in range(len(measures) - 1)
                  if measures[i + 1] > measures[i])
    backward = (len(measures) - 1) - forward
    return list(reversed(points)) if backward > forward else points


#: How many places on one alignment a single station is allowed to be
#: projecting onto. Two is the usual answer — the outbound and return passes
#: of a round-trip shape — and more than a handful means the alignment runs
#: past the station so often that arc length has stopped identifying it.
MAX_PROJECTIONS = 6

#: How much worse than the station's nearest point a rival projection may be
#: and still be considered. Wide, because the whole difficulty is that the two
#: passes of a round trip are the same place to within the width of a
#: formation, and it is the walk between stations rather than these few metres
#: that says which one is meant.
PROJECTION_SLACK_M = 250.0

#: Two projections closer together than this along the alignment are the same
#: place twice, not a choice.
PROJECTION_APART_M = 40.0


def cut_at_stations(points, station_points, max_offset_m):
    """Split one routed alignment into station-to-station intervals.

    Returns ``(intervals, anchors, report)``. A station whose published
    position is further than ``max_offset_m`` from the alignment keeps its own
    coordinate rather than being dragged onto the track: the alignment is then
    the thing that is wrong, and moving the marker to it would hide that.
    """
    points = orient(points, station_points)
    cumul = geo.cumulative(points)
    chosen = _walk(points, cumul, station_points)

    anchors = []
    far = []
    for i, (d, measure, coord) in enumerate(chosen):
        if d <= max_offset_m:
            anchors.append((measure, coord))
        else:
            anchors.append((measure, list(station_points[i])))
            far.append((i, round(d, 1)))

    intervals = []
    for i in range(len(anchors) - 1):
        start, end = anchors[i][0], anchors[i + 1][0]
        piece = geo.slice_between(points, cumul, start, end)
        # ``slice_between`` answers "which part of the line lies between these
        # two measures", which has no direction; an interval does. Where the
        # pattern runs back down the alignment it came up — the second half of
        # every out-and-back streetcar whose operator publishes one direction's
        # shape — the slice arrives head-first and the two ends are then
        # stamped on backwards, so the drawn interval leaves the station, runs
        # the block, comes back past it, and runs the block again. That is
        # exactly the 3.0x that twenty-four of the Canal Streetcar's forty-eight
        # intervals shipped at. The slice is turned round instead.
        if end < start:
            piece.reverse()
        piece[0] = list(anchors[i][1])
        piece[-1] = list(anchors[i + 1][1])
        intervals.append(geo.dedupe(piece, 0.05))
    return intervals, [a[1] for a in anchors], {'offAlignment': far}


def _walk(points, cumul, station_points):
    """Where each station sits along the alignment, chosen as a journey.

    One station at a time, "which point of the line is nearest" is not a
    question the geometry can answer. An operator publishes one shape for a
    round trip, so its outbound and return tracks lie a formation's width
    apart and every station has two nearest points, tens of metres apart in
    space and tens of kilometres apart in arc length. Whichever is marginally
    closer wins, station by station, independently — and the "interval"
    between two stations that happened to pick different passes is the entire
    railway. The CTA's Brown Line shipped its first hop, 410 m from Kimball to
    Kedzie, as 32.6 km of drawn track, and the line as 190 km of an 18 km
    railway.

    So the choice is made for the list rather than for each station: of all
    the ways to assign every station to one of its candidate projections, the
    one that walks the least track beyond the distance the stations actually
    span. Ordinary lines have one candidate per station and are unaffected;
    where there are two, the assignment that walks 400 m between stations 400 m
    apart beats the one that walks 32 km, by 32 km, and no tie-break on which
    rail is three metres nearer can outweigh it.
    """
    candidates = [_projections(p, points, cumul) for p in station_points]
    straight = [geo.haversine(station_points[i], station_points[i + 1])
                for i in range(len(station_points) - 1)]
    # Viterbi over the candidates: the cost of standing at a projection is how
    # far it leaves the station from the track, and the cost of moving between
    # two is how much further along the alignment that is than the stations are
    # apart on the ground. Excess only — a railway is never shorter than the
    # chord, and charging for the part that is genuinely there would prefer
    # assignments that skip track.
    cost = [d for d, _, _ in candidates[0]]
    back = []
    for i in range(1, len(candidates)):
        row = []
        step = []
        for d, measure, _ in candidates[i]:
            best, best_k = float('inf'), 0
            for k, (_, previous, _) in enumerate(candidates[i - 1]):
                value = cost[k] + max(0.0, abs(measure - previous) - straight[i - 1])
                if value < best:
                    best, best_k = value, k
            row.append(best + d)
            step.append(best_k)
        cost = row
        back.append(step)

    k = min(range(len(cost)), key=lambda j: cost[j])
    picked = [k]
    for step in reversed(back):
        k = step[k]
        picked.append(k)
    picked.reverse()
    return [candidates[i][k] for i, k in enumerate(picked)]


def _projections(p, points, cumul):
    """Every place on the alignment a station could plausibly be at.

    The local minima of its distance to the line, nearest first: one for a
    line that passes the station once, two for a round-trip shape, more where
    a shape loops. Only the minima — a distance that is still falling is the
    same projection a segment early.
    """
    measured = []
    for i in range(len(points) - 1):
        d, t = geo.point_segment_distance(p, points[i], points[i + 1])
        measured.append((d, i, t))
    minima = []
    for i, (d, index, t) in enumerate(measured):
        if i and measured[i - 1][0] < d:
            continue
        if i + 1 < len(measured) and measured[i + 1][0] < d:
            continue
        a, b = points[index], points[index + 1]
        minima.append((d,
                       cumul[index] + (cumul[index + 1] - cumul[index]) * t,
                       [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]))
    if not minima:
        d, _, _, coord, measure = geo.project_to_line(p, points, cumul)
        return [(d, measure, coord)]
    minima.sort(key=lambda row: row[0])
    out = []
    for row in minima:
        if row[0] > minima[0][0] + PROJECTION_SLACK_M:
            break
        if any(abs(row[1] - kept[1]) < PROJECTION_APART_M for kept in out):
            continue
        out.append(row)
        if len(out) >= MAX_PROJECTIONS:
            break
    return out


# -------------------------------------------------------------------- grooming

def groom(intervals, profile):
    """Everything between a surveyed alignment and a drawn one.

    Interval by interval, because the boundaries are stations and a station
    must not move: each pass is free inside an interval and fixed at its ends.
    """
    out = []
    for piece in intervals:
        if piece is None or len(piece) < 2:
            out.append(piece)
            continue
        ends = (list(piece[0]), list(piece[-1]))
        work = geo.relax_spikes(piece, profile.spike_edge_m,
                                profile.spike_turn_deg, profile.spike_deviation_m)
        work = geo.simplify(work, profile.tolerance_m)
        work = geo.round_corners(work, profile.corner_offset_m)
        work = geo.enforce_min_radius(work, profile.min_radius_m,
                                      profile.radius_window_m, profile.anchor_m)
        work = geo.simplify(work, profile.tolerance_m * 0.5)
        work = geo.densify(work, profile.max_edge_m)
        work[0], work[-1] = ends
        out.append(geo.dedupe(work, 0.05))
    return out


def profile_for_line(intervals):
    lengths = [geo.line_length(p) for p in intervals if p and len(p) > 1]
    total = sum(lengths)
    return prof.profile_for(prof.median_spacing_m(lengths), total), total


# ---------------------------------------------------------------- cross-check

def deviation(intervals, reference: geo.ReferenceIndex, sample_every=1):
    """The worst distance from a drawn vertex to the reference centreline."""
    worst = 0.0
    checked = 0
    unmatched = 0
    for piece in intervals:
        if not piece:
            continue
        for i in range(0, len(piece), sample_every):
            d, _ = reference.nearest(piece[i], search_cells=2)
            checked += 1
            if d == float('inf'):
                unmatched += 1
                continue
            worst = max(worst, d)
    return {'vertices': checked, 'unmatched': unmatched,
            'maxDeviationMeters': round(worst, 2)}


# --------------------------------------------------------------- shape quality

def shape_is_schematic(points, station_points, tolerance_m=60.0):
    """Whether an alignment is really just the straight lines between stops.

    Several feeds publish a ``shapes.txt`` generated from their own stop list,
    which draws a railway as a polygon through its stations. It is still the
    operator's statement of which way the trains go — which is why it is kept
    as the routing corridor — but it must never be *drawn*, so the caller has
    to be told.
    """
    if not points or len(points) < 2 or len(station_points) < 2:
        return True
    chords = geo.densify(station_points, 500)
    index = geo.ReferenceIndex(cell_deg=0.05)
    index.add_line(chords)
    off = 0
    for p in points:
        d, _ = index.nearest(p, search_cells=2)
        if d > tolerance_m:
            off += 1
    return off < max(2, len(points) * 0.02)


# ---------------------------------------------------------------- compact rows

def segments_for(intervals, anchors):
    """The package's ``segments`` rows for one line.

    ``continuesFromPrevious`` is set on every interval after the first, and the
    shared vertex is dropped, which is exactly how the format stores a chain
    without repeating a coordinate in two rows.
    """
    rows = []
    for i, piece in enumerate(intervals):
        if not piece or len(piece) < 2:
            rows.append([0.0, 1 if i else 0, []])
            continue
        km = round(geo.line_length(piece) / 1000.0, 3)
        if i:
            rows.append([km, 1, [[round(x, 6), round(y, 6)] for x, y in piece[1:]]])
        else:
            rows.append([km, 0, [[round(x, 6), round(y, 6)] for x, y in piece]])
    return rows


def station_rows(codes, names, anchors, roma, roma_source, tz_index=None):
    rows = []
    for i, code in enumerate(codes):
        row = [code, names[i], round(anchors[i][0], 6), round(anchors[i][1], 6),
               roma[i], roma_source[i]]
        if tz_index is not None:
            row.append(tz_index[i])
        rows.append(row)
    return rows
