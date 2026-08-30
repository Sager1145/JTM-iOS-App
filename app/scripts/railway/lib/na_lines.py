"""From an operator's timetable to the display lines a map draws.

A GTFS feed describes *services*, not lines: an operator publishes one route
per thing a passenger can board — the A train, the Acela, the Red Line — and
then runs several stopping patterns on each of them. A package needs one
ordered station list per drawn line, so somebody has to decide which pattern
that is, and what to do with the stations the chosen pattern never calls at.

That decision is here, and it is made the same way for every operator on the
continent so no system gets a hand-tuned answer nobody can check:

1. **The trunk is the most complete pattern.** Not the most frequent — an
   express run is often the busiest and is by definition the one that skips
   stations. A display line whose station list came from the express would be
   a map missing the stops.
2. **A pattern that reaches track the trunk never does becomes a branch**,
   under the trunk's own name, colour and operator, with its own id suffix.
   Hong Kong's package already ships two 東鐵綫 rows for exactly this reason:
   the branch is a different piece of railway, not a different service on the
   same one.
3. **Everything else is dropped.** A short-turn, a rush-hour skip-stop and a
   weekend variant all run over track the trunk already draws, so drawing them
   again would put a second stroke on top of the first.

None of the three steps invents a station, an order, or a name.
"""
from __future__ import annotations

from collections import defaultdict
import heapq

import na_geo as geo


class Pattern:
    __slots__ = ('stations', 'weight', 'trips', 'shape_ids', 'sample_trip')

    def __init__(self, stations, shape_id, trip_id):
        self.stations = stations
        self.weight = 0.0
        self.trips = 0
        self.shape_ids = defaultdict(float)
        self.sample_trip = trip_id

    @property
    def key(self):
        return tuple(self.stations)

    def __len__(self):
        return len(self.stations)


def canonical_direction(stations, reference):
    """Orient a pattern the same way as a reference sequence.

    Two directions of one service are two orderings of one railway, and a
    package that shipped both would draw the line twice. The reversal test is
    on the sequence rather than on a ``direction_id``, which several feeds set
    inconsistently between routes.
    """
    if not reference:
        return stations
    forward = _overlap(stations, reference)
    backward = _overlap(list(reversed(stations)), reference)
    return list(reversed(stations)) if backward > forward else stations


def _overlap(a, b):
    """How many of ``a``'s consecutive pairs appear in ``b`` in the same order."""
    index = {s: i for i, s in enumerate(b)}
    hits = 0
    for i in range(len(a) - 1):
        x, y = index.get(a[i]), index.get(a[i + 1])
        if x is not None and y is not None and y > x:
            hits += 1
    return hits


def fold_out_and_back(stations):
    """A pattern that runs out and comes back is one railway, not two.

    Several operators publish a round trip as a single GTFS trip — the
    Minneapolis METRO Green Line's block leaves Union Depot, reaches West
    Bank and returns to Union Depot, so its stop sequence is thirty-five rows
    for an eighteen-station railway. ``merge_directions`` cannot catch it: it
    folds a pattern against its own reverse, and a palindrome IS its own
    reverse, so the round trip survives as the longest pattern on the route
    and wins the trunk. What ships is a line whose station list doubles back
    and whose geometry is drawn twice over itself.

    The fold is the longest leading run of distinct stations, kept only when
    what follows it is that run being retraced — every station after the
    turnaround must already be in the run, and in falling order of position.
    Anything else is a railway that genuinely revisits a station (a balloon
    loop, a reverse at a terminus onto a different branch) and is returned
    untouched, because a fold there would delete track.
    """
    if len(stations) < 4:
        return stations
    seen = {}
    for turn, station in enumerate(stations):
        if station in seen:
            break
        seen[station] = turn
    else:
        return stations                     # no station repeats: nothing to fold
    out = stations[:turn]
    tail = stations[turn:]
    if len(out) < 2:
        return stations
    # A circular railway also repeats a station — its first — and folding one
    # would delete the closing leg and the `isLoop` flag that depends on it.
    # The two are told apart by where the repeat starts: an out-and-back turns
    # round at the far end and walks home, so its tail begins at the end of
    # the outward run and is at least two stations long; a loop's tail is the
    # single station it started from, reached over track it has not used.
    if len(tail) < 2 or seen.get(tail[0], -1) < len(out) - 2:
        return stations
    # The rest of the tail must keep walking back down the outward run.
    previous = len(out)
    for station in tail:
        position = seen.get(station)
        if position is None or position >= previous:
            return stations
        previous = position
    return out


def build_patterns(route_id, trips, sequences, stops, parent, weights):
    """Every distinct stopping pattern a route runs, with how much it runs."""
    found = {}
    for trip in trips:
        seq = sequences.get(trip['trip_id'])
        if not seq or len(seq) < 2:
            continue
        stations = []
        for stop_id in seq:
            row = stops.get(stop_id)
            if row is None:
                continue
            station = parent(row)
            if not stations or stations[-1] != station:
                stations.append(station)
        stations = fold_out_and_back(stations)
        if len(stations) < 2:
            continue
        key = tuple(stations)
        pattern = found.get(key)
        if pattern is None:
            pattern = found[key] = Pattern(stations, trip.get('shape_id'),
                                           trip['trip_id'])
        pattern.trips += 1
        pattern.weight += weights.get(trip.get('service_id'), 1)
        shape = (trip.get('shape_id') or '').strip()
        if shape:
            pattern.shape_ids[shape] += weights.get(trip.get('service_id'), 1)
    return list(found.values())


def merge_directions(patterns):
    """Fold each pattern into one canonical direction before they are compared."""
    if not patterns:
        return []
    patterns.sort(key=lambda p: (
        -len(p), -p.weight, tuple(map(str, p.stations))))
    reference = patterns[0].stations
    merged = {}
    for pattern in patterns:
        stations = canonical_direction(pattern.stations, reference)
        key = tuple(stations)
        hit = merged.get(key)
        if hit is None:
            hit = merged[key] = Pattern(stations, None, pattern.sample_trip)
        hit.trips += pattern.trips
        hit.weight += pattern.weight
        for shape, w in pattern.shape_ids.items():
            hit.shape_ids[shape] += w
    return sorted(merged.values(), key=lambda p: (
        -len(p), -p.weight, tuple(map(str, p.stations))))


def build_graph(patterns):
    """Every station-to-station step the route's own patterns describe.

    Weighted by how much service runs it, and directed, because a route's
    shape is a directed acyclic graph in all but the loop cases: two branches
    that join, a trunk with flag stops some trips skip, a seasonal extension.
    """
    succ = defaultdict(lambda: defaultdict(float))
    stations = set()
    for pattern in patterns:
        for i in range(len(pattern.stations) - 1):
            a, b = pattern.stations[i], pattern.stations[i + 1]
            if a == b:
                continue
            succ[a][b] += pattern.weight + 1.0
            stations.add(a)
            stations.add(b)
    return succ, stations


def break_cycles(succ):
    """Remove the lightest edge on each cycle, and say which were removed.

    A loop service — the Chicago Loop elevated, a circular streetcar — really
    is a cycle, and so is a route whose two directions call at a pair of
    stations in opposite orders. Both have to become an order before a station
    list can exist, so the lightest back edge of each cycle is set aside and
    reported: for a genuine loop it is the one step that closes the circle,
    which the caller restores as ``isLoop``.
    """
    removed = []
    colour = {}

    def visit(node, stack):
        colour[node] = 1
        for nxt in sorted(succ.get(node, ()), key=lambda k: -succ[node][k]):
            if succ[node].get(nxt) is None:
                continue
            state = colour.get(nxt, 0)
            if state == 1:
                removed.append((node, nxt, succ[node][nxt]))
                del succ[node][nxt]
                continue
            if state == 0:
                visit(nxt, stack)
        colour[node] = 2

    import sys as _sys
    limit = _sys.getrecursionlimit()
    _sys.setrecursionlimit(max(limit, 20000))
    try:
        for node in list(succ.keys()):
            if colour.get(node, 0) == 0:
                visit(node, [])
    finally:
        _sys.setrecursionlimit(limit)
    return removed


def topological(succ, stations):
    indegree = {s: 0 for s in stations}
    for a, outs in succ.items():
        for b in outs:
            indegree[b] = indegree.get(b, 0) + 1
    # ``stations`` is a set. Popping it through an ordinary list made equal-
    # weight branches depend on Python's per-process hash seed: NCTD rebuilt
    # as two lines in one run and three in the next from identical GTFS bytes.
    # A heap makes the same official station IDs produce the same order.
    queue = [s for s in stations if indegree.get(s, 0) == 0]
    heapq.heapify(queue)
    order = []
    while queue:
        node = heapq.heappop(queue)
        order.append(node)
        for b in sorted(succ.get(node, ())):
            indegree[b] -= 1
            if indegree[b] == 0:
                heapq.heappush(queue, b)
    return order if len(order) == len(stations) else None


def longest_path(succ, order):
    """The most complete run through the graph — stations first, service second.

    Stations before weight is the rule stated at the top of this module: the
    display line has to be the one that calls everywhere, not the one that is
    busiest.
    """
    best = {node: (1, 0.0, None) for node in order}
    for node in reversed(order):
        for nxt, weight in succ.get(node, {}).items():
            count, total, _ = best.get(nxt, (1, 0.0, None))
            candidate = (count + 1, total + weight, nxt)
            if candidate[:2] > best[node][:2]:
                best[node] = candidate
    start = max(order, key=lambda n: (best[n][0], best[n][1], str(n))) \
        if order else None
    path = []
    node = start
    while node is not None:
        path.append(node)
        node = best[node][2]
    return path


def select_lines(patterns, max_branches=8, min_branch_stations=2,
                 branch_weight_floor=0.0):
    """The trunk, then the branches, in the order they are drawn.

    Returns ``[(suffix, stations, pattern, is_loop), …]`` with ``suffix`` empty
    for the trunk. ``pattern`` is the pattern that best matches the emitted
    station list, and is what the alignment is taken from.
    """
    patterns = merge_directions(patterns)
    if not patterns:
        return []
    succ, stations = build_graph(patterns)
    if not stations:
        return []
    cut = break_cycles(succ)
    order = topological(succ, stations)
    if order is None:
        # A graph that still will not sort is one this rule cannot describe;
        # fall back to the single most complete pattern rather than invent an
        # order the operator never publishes.
        trunk = patterns[0]
        return [('', trunk.stations, trunk, is_loop(trunk.stations))]
    trunk = longest_path(succ, order)
    if len(trunk) < 2:
        trunk = patterns[0].stations

    position = {s: i for i, s in enumerate(trunk)}
    covered = set()

    def cover(path):
        index = {s: i for i, s in enumerate(path)}
        for a in index:
            for b in index:
                if index[a] < index[b]:
                    covered.add((a, b))

    cover(trunk)
    loop = bool(cut) and any(a == trunk[-1] and b == trunk[0] for a, b, _ in cut)
    out = [('', trunk, match_pattern(patterns, trunk), loop)]

    remaining = {(a, b): w for a, outs in succ.items() for b, w in outs.items()
                 if (a, b) not in covered}
    branches = 0
    while remaining and branches < max_branches:
        (a, b), weight = max(remaining.items(), key=lambda kv: kv[1])
        if weight <= branch_weight_floor:
            break
        chain = grow_chain(a, b, succ, remaining)
        for i in range(len(chain) - 1):
            remaining.pop((chain[i], chain[i + 1]), None)
        fresh = [s for s in chain if s not in position]
        if len(fresh) < min_branch_stations - 1 and len(chain) < min_branch_stations:
            continue
        cover(chain)
        for s in chain:
            position.setdefault(s, len(position))
        branches += 1
        out.append((f'-b{branches}', chain, match_pattern(patterns, chain), False))
    return out


def grow_chain(a, b, succ, remaining):
    """Extend one uncovered step into the longest run of uncovered steps."""
    chain = [a, b]
    while True:
        tail = chain[-1]
        options = [(w, n) for n, w in succ.get(tail, {}).items()
                   if (tail, n) in remaining and n not in chain]
        if not options:
            break
        chain.append(max(options)[1])
    while True:
        head = chain[0]
        options = [(w, p) for p, outs in succ.items() for n, w in outs.items()
                   if n == head and (p, head) in remaining and p not in chain]
        if not options:
            break
        chain.insert(0, max(options)[1])
    return chain


def match_pattern(patterns, stations):
    """The published pattern that best covers an emitted station list.

    Its shape is the alignment the line is drawn on, so "best" is measured in
    shared consecutive pairs rather than shared stations: a pattern that calls
    at the same places by a different route is not this line's alignment.
    """
    wanted = {(stations[i], stations[i + 1]) for i in range(len(stations) - 1)}
    best, score = patterns[0], -1
    for pattern in patterns:
        pairs = {(pattern.stations[i], pattern.stations[i + 1])
                 for i in range(len(pattern.stations) - 1)}
        hit = len(wanted & pairs)
        if hit > score or (hit == score and pattern.weight > best.weight):
            best, score = pattern, hit
    return best


def edges_of(stations):
    return {frozenset((stations[i], stations[i + 1])) for i in range(len(stations) - 1)}


def is_loop(stations):
    return len(stations) > 3 and stations[0] == stations[-1]


def shape_for(pattern, shapes):
    """The alignment the operator publishes for this pattern.

    The most-run shape wins, and the longest of equally-run shapes: a feed
    often carries several shapes for one pattern that differ only in which
    yard lead the trip starts from, and the longest is the one that reaches
    both terminals.
    """
    best = None
    for shape_id, weight in sorted(pattern.shape_ids.items(),
                                   key=lambda kv: (-kv[1], kv[0])):
        points = shapes.get(shape_id)
        if not points or len(points) < 2:
            continue
        length = geo.line_length(points)
        if best is None or weight > best[0] or (weight == best[0] and length > best[2]):
            best = (weight, shape_id, length, points)
    return (best[1], best[3]) if best else (None, None)
