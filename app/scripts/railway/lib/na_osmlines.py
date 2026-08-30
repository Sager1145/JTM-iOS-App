"""Reading an OpenStreetMap route relation as a display line.

The source of last resort, and it is used as one: a railway reaches this
module only because no operator publishes a feed for it. See
`download-north-america-osm-routes.py` for which railways those are and why
the list is derived rather than written.

A route relation is close to what a display line needs and not identical to
it. It carries an ordered list of stops as node members, an alignment as way
members, and the operator's own name, colour and network in its tags — but the
ways arrive in the relation's own order and orientation, which is often
neither the direction of travel nor even consistently one direction, and the
stops arrive interleaved with platforms that name the same station twice.
Both are resolved here, and neither is guessed: a relation this module cannot
chain into one continuous alignment is returned with the pieces it could chain
and a note saying so, rather than joined across a gap that is not track.
"""
from __future__ import annotations

import gzip
import json
import os
import re

import na_geo as geo

#: Member roles that name a place a train calls at. A relation lists the stop
#: (a node on the track) and the platform (beside it) for the same station, so
#: both are read and the duplicate pair is collapsed below.
STOP_ROLES = (
    'stop', 'stop_entry_only', 'stop_exit_only',
    'platform', 'platform_entry_only', 'platform_exit_only',
)

#: How close two consecutive stop members have to be to be one station. A stop
#: node and its own platform are metres apart; two genuine stations on a
#: streetcar line are two hundred.
SAME_STATION_M = 400.0

#: How close two NON-consecutive stop members have to be to be one place.
#: Much tighter than `SAME_STATION_M`, which is a bound on how far a platform
#: sits from its own stop node and may be applied only to members standing
#: next to each other. Applied across a whole relation it deletes railway: at
#: four hundred metres AirTrain JFK's Terminal 8 becomes Terminal 1 (399 m
#: apart) and the Cincinnati Bell Connector loses three of its eight stops to
#: the other side of its own one-way couplet (226–437 m apart). The repeats
#: this constant is for are much closer than that — Rocky Mountaineer's
#: "Whistler" and "Whistler Station" are nine metres apart, and AirTrain JFK's
#: two Federal Circle platform nodes seventy-three.
REPEAT_STATION_M = 100.0

#: How far apart two way members may be and still be one alignment. OSM splits
#: a way at every tagging change, so consecutive members normally share a node
#: exactly; a few metres of tolerance covers the relations where they do not.
CHAIN_TOLERANCE_M = 12.0


def load_dir(path):
    """Every route relation in the downloaded extracts, as display-line input."""
    routes = []
    seen_relations = set()
    if not os.path.isdir(path):
        return routes
    for name in sorted(os.listdir(path)):
        if not name.endswith(('.json', '.json.gz')):
            continue
        full = os.path.join(path, name)
        try:
            raw = (gzip.decompress(open(full, 'rb').read())
                   if name.endswith('.gz') else open(full, 'rb').read())
            data = json.loads(raw)
        except Exception:                               # noqa: BLE001
            continue
        for route in from_elements(data.get('elements') or []):
            if route['relation'] in seen_relations:
                continue
            seen_relations.add(route['relation'])
            routes.append(route)
    return routes


def from_elements(elements):
    ways = {}
    nodes = {}
    relations = []
    for element in elements:
        kind = element.get('type')
        if kind == 'way':
            points = [[p['lon'], p['lat']] for p in (element.get('geometry') or ())]
            if len(points) > 1:
                ways[element['id']] = points
        elif kind == 'node':
            if 'lon' in element and 'lat' in element:
                nodes[element['id']] = element
        elif kind == 'relation':
            relations.append(element)

    out = []
    for relation in relations:
        tags = relation.get('tags') or {}
        if tags.get('type') != 'route':
            continue
        stations = stations_of(relation, nodes)
        parts = chain_ways(relation, ways)
        if len(stations) < 2 or not parts:
            continue
        out.append({
            'relation': relation['id'],
            'name': (tags.get('name') or tags.get('ref') or '').strip(),
            'ref': (tags.get('ref') or '').strip(),
            'operator': (tags.get('operator') or tags.get('network') or '').strip(),
            'network': (tags.get('network') or '').strip(),
            'kind': tags.get('route') or 'train',
            'colour': (tags.get('colour') or tags.get('color') or '').strip(),
            'stations': stations,
            'parts': parts,
        })
    return out


def stations_of(relation, nodes):
    """The relation's stops, in order, one entry per place.

    A relation lists the stop node and its platform separately and often
    repeats a terminus at both ends of a there-and-back variant. Consecutive
    members within ``SAME_STATION_M`` of each other are one station, and the
    first of them names it — which is the stop node, because relations are
    written stop-then-platform.
    """
    out = []
    for member in relation.get('members') or ():
        if member.get('type') != 'node':
            continue
        if (member.get('role') or '') not in STOP_ROLES:
            continue
        node = nodes.get(member.get('ref'))
        if node is None:
            continue
        point = [node['lon'], node['lat']]
        name = ((node.get('tags') or {}).get('name') or '').strip()
        if out and geo.haversine(out[-1]['point'], point) <= SAME_STATION_M:
            if not out[-1]['name'] and name:
                out[-1]['name'] = name
            continue
        out.append({'id': node['id'], 'name': name, 'point': point})
    return fold_return_leg([s for s in out if s['name']])


def fold_return_leg(stations):
    """Drop the members that are the relation walking back over itself.

    The consecutive-member collapse above catches a stop node beside its own
    platform. It cannot catch a place the relation reaches TWICE with other
    places in between, and three kinds of relation do that:

    * a there-and-back service listed as one relation — AirTrain JFK's Jamaica
      route is Jamaica, Federal Circle, T1, T4, T7, T8, Federal Circle,
      Jamaica, which is six places, not eight;
    * a relation whose stop members are simply in the wrong order — Rocky
      Mountaineer's *Rainforest to Gold Rush* lists Whistler fourth and
      "Whistler Station", a node ten metres away, sixth, which shipped as the
      only audit ERROR in the package pair (`station.repeat`,
      ``ca-official-whistler`` twice on one line);
    * a genuine loop, which is neither of the above and must survive intact.

    The three are told apart the same way `na_lines.fold_out_and_back` tells
    them apart, and for the same reason: everything after the last member that
    reaches somewhere new must be a return over places already reached, in
    falling order. A loop's closing member is the place it STARTED from, so a
    single trailing repeat of the first place is left alone — cutting it would
    delete the leg that closes the circle and the ``isLoop`` flag that depends
    on it. Anything the rule cannot explain is returned untouched, because a
    wrong fold here deletes a station.

    "The same place" is `REPEAT_STATION_M` and emphatically not
    `SAME_STATION_M`; the note on the constant says what four hundred metres
    costs when it is asked of members that are not neighbours.
    """
    if len(stations) < 3:
        return stations
    # `first[i]` is where the place member `i` stands at was first reached.
    first = []
    for index, station in enumerate(stations):
        match = index
        for earlier in range(index):
            if (first[earlier] == earlier
                    and geo.haversine(stations[earlier]['point'],
                                      station['point']) <= REPEAT_STATION_M):
                match = earlier
                break
        first.append(match)
    turn = max(i for i in range(len(stations)) if first[i] == i)
    if turn == len(stations) - 1:
        return stations                 # every member reaches somewhere new
    # A loop closes on its own first place, and that closing member is the
    # only single-member tail that is not a mistake.
    if turn == len(stations) - 2 and first[-1] == 0:
        return stations
    previous = turn + 1
    for offset in range(turn + 1, len(stations)):
        if first[offset] >= previous:
            return stations             # not a retrace; nothing safe to cut
        previous = first[offset]
    return stations[:turn + 1]


def chain_ways(relation, ways):
    """The relation's ways as one or more continuous alignments.

    Each way is flipped, if flipping makes it continue from the one before,
    and a way that continues from neither end starts a new part. Parts rather
    than one polyline because that is the truth about a relation with a gap in
    it, and because the caller can route a station interval through several
    parts but cannot un-join a join that was invented.
    """
    parts = []
    current = []
    for member in relation.get('members') or ():
        if member.get('type') != 'way':
            continue
        points = ways.get(member.get('ref'))
        if not points:
            continue
        if not current:
            current = [list(p) for p in points]
            continue
        tail = current[-1]
        head, last = points[0], points[-1]
        if geo.haversine(tail, head) <= CHAIN_TOLERANCE_M:
            current.extend(points[1:])
        elif geo.haversine(tail, last) <= CHAIN_TOLERANCE_M:
            current.extend(list(reversed(points))[1:])
        else:
            # A relation's first two ways can be listed in either order, so a
            # break at the very start is a flip of what is already there
            # rather than a gap.
            if len(current) and geo.haversine(current[0], head) <= CHAIN_TOLERANCE_M:
                current = list(reversed(current))
                current.extend(points[1:])
            elif len(current) and geo.haversine(current[0], last) <= CHAIN_TOLERANCE_M:
                current = list(reversed(current))
                current.extend(list(reversed(points))[1:])
            else:
                parts.append(current)
                current = [list(p) for p in points]
    if current:
        parts.append(current)
    return [geo.dedupe(p, 0.05) for p in parts if len(p) > 1]


def longest_part(parts):
    return max(parts, key=geo.line_length) if parts else None


def merge_parts(parts, tolerance_m=250.0):
    """Join parts whose ends meet, largest first, and leave the rest apart.

    A relation is often split into two or three pieces by a way this extract
    did not include, and their ends are then a few metres apart — a join worth
    making. Two pieces whose ends are a kilometre apart are two pieces of
    railway with something between them, and joining those would draw track
    that is not there.
    """
    remaining = sorted(parts, key=geo.line_length, reverse=True)
    if not remaining:
        return []
    merged = [remaining.pop(0)]
    changed = True
    while changed and remaining:
        changed = False
        for index, piece in enumerate(remaining):
            target = merged[0]
            options = (
                (geo.haversine(target[-1], piece[0]), 'append', piece),
                (geo.haversine(target[-1], piece[-1]), 'append', list(reversed(piece))),
                (geo.haversine(target[0], piece[-1]), 'prepend', piece),
                (geo.haversine(target[0], piece[0]), 'prepend', list(reversed(piece))),
            )
            best = min(options)
            if best[0] > tolerance_m:
                continue
            if best[1] == 'append':
                merged[0] = target + best[2][1:]
            else:
                merged[0] = best[2] + target[1:]
            remaining.pop(index)
            changed = True
            break
    return merged + remaining


def fold_directions(routes):
    """One display line per railway, not one per direction relation.

    The counterpart of `na_lines.merge_directions`, and the reason it has to
    exist separately: a GTFS route carries both of its directions inside one
    ``route_id``, so the GTFS path folds them while it is deciding a route's
    stopping patterns. OpenStreetMap has no such container. Each direction is
    its own ``type=route`` relation, so the two arrive here as two railways
    and — until this function existed — shipped as two lines drawn on top of
    each other. Roughly half of the forty-seven OpenStreetMap lines in
    `us-2025.json` were the other direction of another one: PATH's HOB–33,
    HOB–WTC, JSQ–33, JSQ–33 via HOB and NWK–WTC each twice, AirTrain Newark
    twice, Orlando's four Gate Link shuttles twice each, DART's Skylink, the
    IAH Skyway, Denver's AGTS, the Detroit ExpressTram, the Andrews Valley
    tour and the Strasburg Rail Road.

    Two relations are the same railway when **neither reaches a place the
    other does not**: every stop of each is within `SAME_STATION_M` of a stop
    of the other. Measured on position rather than on name, because a stop
    node and the platform across the track from it are two names for one
    place and OpenStreetMap frequently gives them different ones — the two
    directions of the AirTrain Newark loop call the same station "Terminal A"
    and "P3", and the two Strasburg relations call one stop "Groff's Grove"
    and the other "Cherry Crest Adventure Farm". `SAME_STATION_M` is the
    distance this module already declares to be one place, so nothing new is
    being asserted about how far apart two stations can be.

    Symmetric on purpose. The one-sided version of this test — "everywhere
    the shorter goes, the longer goes too" — folds railways that are
    genuinely different: PATH's HOB–33 would vanish into JSQ–33 via HOB, and
    AirTrain JFK's All Terminals Loop into its Jamaica route. What survives
    the symmetric test is a pair with nothing to choose between them but
    which one is written out more fully, and that is the one kept: most
    distinctly named stops first, then most stop members, then the longest
    alignment, then the lowest relation id so a rebuild is reproducible.

    Returns ``(kept, folded)`` where ``folded`` is ``(loser, winner)`` pairs,
    so the caller can report every drop instead of quietly shrinking.
    """
    order = sorted(routes, key=fullness, reverse=True)
    kept, folded = [], []
    for route in order:
        winner = next((k for k in kept if same_railway(route, k)), None)
        if winner is None:
            kept.append(route)
        else:
            folded.append((route, winner))
    kept.sort(key=lambda r: r['relation'])
    return kept, folded


def fullness(route):
    """How completely a relation writes its railway out, for choosing between
    two relations that describe the same one.

    Distinct names before stop count because a relation can carry the same
    name twice — Denver's AGTS is listed once as C/B/A Gates plus Jeppesen
    Terminal and once as "A Gates", "A Gates", B, C, and the first of those
    is the one that names all four places.
    """
    names = {s['name'].strip().lower() for s in route['stations'] if s['name']}
    return (len(names), len(route['stations']),
            sum(geo.line_length(p) for p in route['parts']),
            -route['relation'])


def same_railway(a, b, tolerance_m=SAME_STATION_M):
    """Whether two directional relations describe the same public line.

    Geography alone is insufficient in a shared downtown corridor.  Memphis'
    Main Street and Riverfront trolley lines, for example, put every stop
    within 400 metres of the other but remain distinct published lines.  A
    fold therefore needs route-identity evidence as well: the same non-empty
    ``ref``, or the same service name after removing only an explicit
    directional destination clause.
    """
    a_ref, b_ref = (a.get('ref') or '').strip(), (b.get('ref') or '').strip()
    same_ref = bool(a_ref and b_ref and a_ref == b_ref)
    same_name = _service_name(a.get('name')) == _service_name(b.get('name'))
    return ((same_ref or same_name)
            and _covered_by(a['stations'], b['stations'], tolerance_m)
            and _covered_by(b['stations'], a['stations'], tolerance_m))


def _service_name(value):
    """Stable line name with a written direction/destination removed."""
    text = ' '.join((value or '').strip().lower().split())
    # Parentheses are directional only when they actually say where the line
    # goes (``Skyway (Terminal A to Terminal D/E)``); ordinary qualifiers stay.
    text = re.sub(r'\s*\([^)]*\b(?:to|toward|towards)\b[^)]*\)\s*$', '', text)
    text = re.split(r'\s*(?::|→|=>|⇄|↔)\s*', text, maxsplit=1)[0]
    text = re.split(r'\s+vers\s+', text, maxsplit=1)[0]
    return text.strip()


def _covered_by(stations, others, tolerance_m):
    points = [s['point'] for s in others]
    names = {' '.join(s['name'].strip().lower().split())
             for s in others if s.get('name')}
    return all(
        (' '.join(s['name'].strip().lower().split()) in names if s.get('name') else False)
        or any(geo.haversine(s['point'], p) <= tolerance_m for p in points)
        for s in stations)
