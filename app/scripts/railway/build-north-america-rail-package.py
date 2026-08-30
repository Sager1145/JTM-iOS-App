#!/usr/bin/env python3
"""Build the United States and Canada rail packages.

    python3 scripts/railway/build-north-america-rail-package.py \
        --source-dir /private/tmp/na-rail \
        --registry scripts/railway/na-feeds.json

Writes, under the same rules every other country package family follows:

    public/rail/us-2025.json          the drawn network
    public/rail/ca-2025.json
    data/stations-us.json             the route solver's station table
    data/rail-sections-us.json        the route solver's graph
    data/station-readings-us.json     the four-language station name table
    …and the Canadian half of each.

The three authorities, and what each is asked:

* the **operator's own GTFS** — which stations, in what order, under what name
  and colour, and which way round its trains run;
* the **FRA/BTS North American Rail Network** — where mainline track is, to a
  median of ten vertices per kilometre;
* **OpenStreetMap** — where street and transit track is, and the cross-check
  every built line is measured against before it ships.

No stage invents a station, an order, a name or a connector. A line that
cannot be built from what those three say is reported and left out, and the
package records how many there were.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import os
import re
import sys
import time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))

import na_attractions               # noqa: E402
import na_build as build            # noqa: E402
import na_classify as classify      # noqa: E402
import na_geo as geo                # noqa: E402
import na_gtfs as gtfs              # noqa: E402
import na_lines as lines            # noqa: E402
import na_narn as narn              # noqa: E402
import na_official                  # noqa: E402
import na_provenance                # noqa: E402
import na_osm                       # noqa: E402
import na_osmlines                  # noqa: E402
import na_profile as profile        # noqa: E402
from na_border import Countries, NetworkCountries, split_runs   # noqa: E402

PACKAGE_VERSION = '2026.2.0'
GENERATED_AT = '2026-08-30T00:00:00.000Z'
MAX_LOOP_CLOSURE_M = 2_000.0


def plausible_loop_closure(points, maximum_m=MAX_LOOP_CLOSURE_M):
    """Whether the last published stop can be adjacent to the first.

    A cycle in the stop-order graph is necessary but not sufficient: two
    direction variants of Metro-North Hudson produced a cycle whose supposed
    closing stations were seven kilometres apart.  Real urban/tourist loops
    in the feeds close from adjacent stops (Atlanta 223 m, New Orleans 359 m,
    Galveston 1.25 km).  This spatial veto preserves those official cycles and
    rejects a direction-induced cycle without inventing a replacement order.
    """
    return (len(points) > 2
            and geo.haversine(points[0], points[-1]) <= maximum_m)


def station_order_reversals(points, minimum_turn=150.0, minimum_leg_m=1_000.0):
    """Indices where a selected station list doubles back over long track.

    A streetcar can turn a sharp corner; a railway cannot run ninety
    kilometres to a terminal and immediately return along the same corridor
    while still being one ordered display line. That shape comes from mixing
    direction variants (Hudson) or rotating a cross-border sub-pattern (Maple
    Leaf), so it is rejected before any geometry source can make it look
    plausible.
    """
    found = []
    for index in range(1, len(points) - 1):
        a, b, c = points[index - 1], points[index], points[index + 1]
        incoming = geo.haversine(a, b)
        outgoing = geo.haversine(b, c)
        if min(incoming, outgoing) < minimum_leg_m:
            continue
        latitude = b[1]
        xscale = math.cos(math.radians(latitude))
        ux, uy = ((b[0] - a[0]) * xscale, b[1] - a[1])
        vx, vy = ((c[0] - b[0]) * xscale, c[1] - b[1])
        nu, nv = math.hypot(ux, uy), math.hypot(vx, vy)
        if not nu or not nv:
            continue
        cosine = max(-1.0, min(1.0, (ux * vx + uy * vy) / (nu * nv)))
        turn = math.degrees(math.acos(cosine))
        if turn >= minimum_turn:
            found.append(index)
    return found


def partition_station_order_reversals(points, station_ids,
                                      allowed_triples=()):
    """Split geometric reversals into operator-proved turnarounds and faults.

    The exception is deliberately a complete ordered station triple, not a
    stop id or a distance threshold. VIA's Churchill trains enter Thompson on
    a spur and leave over the same spur; its official forward and reverse GTFS
    trips prove ``165 -> 503 -> 290``. No other neighbours at Thompson, and no
    other reversal on the route, inherit that permission.
    """
    approved_triples = {tuple(str(value) for value in triple)
                        for triple in allowed_triples if len(triple) == 3}
    approved_triples |= {tuple(reversed(triple))
                         for triple in tuple(approved_triples)}
    approved = []
    blocked = []
    for index in station_order_reversals(points):
        triple = tuple(str(value) for value
                       in station_ids[index - 1:index + 2])
        (approved if triple in approved_triples else blocked).append(index)
    return blocked, approved


def feed_cache_fingerprint(entry, source_dir):
    """Invalidate routed output when either GTFS bytes or build rules change.

    The build rules are this file *and* ``lib``: routing, anchoring, grooming
    and the profile bands all live there, and a fingerprint that watched only
    this file would hand back a cached line built by geometry code that has
    since been corrected — silently, and with nothing in the output to say so.
    """
    digest = hashlib.sha256()
    digest.update(PACKAGE_VERSION.encode())
    digest.update(json.dumps(entry, sort_keys=True,
                             ensure_ascii=False).encode('utf-8'))
    library = os.path.join(HERE, 'lib')
    modules = sorted(os.path.join(library, name)
                     for name in (os.listdir(library)
                                  if os.path.isdir(library) else ())
                     if name.endswith('.py'))
    source_paths = [os.path.join(source_dir, 'gtfs', f"{entry['mdb']}.zip")]
    official_keys = set((entry.get('officialNetworkByRouteId') or {}).values())
    if entry.get('officialNetwork'):
        official_keys.add(entry['officialNetwork'])
    for key in sorted(official_keys):
        if key == 'quebec-mtq-via':
            source_paths.append(os.path.join(source_dir,
                                             'quebec-rail.geojson'))
        else:
            source_paths.append(os.path.join(
                source_dir, 'official-networks', f'{key}.geojson'))
    for path in [__file__] + modules + source_paths:
        if not os.path.exists(path):
            digest.update(b'missing')
            continue
        with open(path, 'rb') as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b''):
                digest.update(chunk)
    return digest.hexdigest()


# --------------------------------------------------------------------- naming

def slugify(text, fallback='x'):
    out = re.sub(r'[^a-z0-9]+', '-', (text or '').lower()).strip('-')
    return out or fallback


def title_case_station(name):
    """A station name as its operator writes it, with the shouting undone.

    Several feeds publish stop names in capitals, which is a rendering choice
    of their own passenger displays rather than the station's name. Names that
    are already mixed case are left exactly as published — this must never
    "correct" ``McCormick`` or ``LaSalle``.
    """
    if not name:
        return name
    letters = [c for c in name if c.isalpha()]
    if not letters or any(c.islower() for c in letters):
        return name
    small = {'of', 'the', 'and', 'at', 'on', 'in', 'to', 'de', 'du', 'la', 'le'}
    words = []
    for i, word in enumerate(name.split(' ')):
        low = word.lower()
        if i and low in small:
            words.append(low)
        elif len(word) > 1 and word.isupper() and len(word) <= 4 and word.isalpha():
            words.append(word)          # NYP, BWI, SFO …
        else:
            words.append(low[:1].upper() + low[1:])
    return ' '.join(words)


#: Three-letter words that are words, not initialisms. The acronym exemption
#: above would otherwise leave them shouting inside a name it is lowering:
#: "MTA NEW YORK CITY TRANSIT" came back as "MTA NEW York City Transit".
#:
#: The list is this short because the case is rare — of the 67 agency names
#: the feeds publish, ten are in capitals and only two of those are more than
#: one word — so it is a list of the words that actually turn up in a
#: continent's transit agencies rather than an attempt at English.
SHORT_WORDS = frozenset((
    'new', 'old', 'all', 'one', 'two', 'san', 'los', 'las', 'bay', 'air',
    'sun', 'red', 'key', 'via', 'car', 'rio', 'fox', 'elm', 'oak', 'big',
))


def title_case_operator(name):
    """An operator's name with the feed's shouting undone — and only that.

    Nine of the two countries' operators arrive in capitals, and they are two
    different things wearing one appearance:

    * **The company's own wordmark.** MBTA, SEPTA, WMATA, CATS, EMBARK and
      METRO are how those operators write their names, on their trains and on
      their letterhead. "Septa" is not a tidier spelling of SEPTA, it is the
      wrong name.
    * **A passenger display's capitals.** DALLAS AREA RAPID TRANSIT, NJ TRANSIT
      RAIL and CONN DOT are ordinary names typed into a feed by a system whose
      signs are upper case, exactly as with the stop names
      ``title_case_station`` already handles.

    What separates them is the word count, and that is the whole rule: a
    wordmark is one word, and a sentence in capitals is a sentence. Tokens of
    three letters or fewer keep their capitals inside a name that is otherwise
    lowered, which is what leaves NJ and DOT alone.

    It is a rule about typography, not about identity: an operator that wants
    a different name than its feed publishes gets one through the registry's
    ``operatorOverride``, which is applied before this and is never touched by
    it.
    """
    if not name:
        return name
    words = name.split()
    letters = [c for c in name if c.isalpha()]
    if len(words) < 2 or not letters or any(c.islower() for c in letters):
        return name
    small = {'of', 'the', 'and', 'at', 'on', 'in', 'to', 'de', 'du', 'la', 'le'}
    out = []
    for i, word in enumerate(words):
        low = word.lower()
        if i and low in small:
            out.append(low)
        elif (len(word) <= 3 and word.isupper() and word.isalpha()
                and low not in SHORT_WORDS):
            out.append(word)
        else:
            out.append(low[:1].upper() + low[1:])
    return ' '.join(out)


# ---------------------------------------------------------------------- colour

def parse_hex(value):
    value = (value or '').strip().lstrip('#')
    if len(value) != 6:
        return None
    try:
        return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return None


def luminance(rgb):
    def channel(c):
        c /= 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def to_hsl(rgb):
    r, g, b = (c / 255.0 for c in rgb)
    hi, lo = max(r, g, b), min(r, g, b)
    light = (hi + lo) / 2
    if hi == lo:
        return 0.0, 0.0, light
    span = hi - lo
    sat = span / (2 - hi - lo) if light > 0.5 else span / (hi + lo)
    if hi == r:
        hue = ((g - b) / span) % 6
    elif hi == g:
        hue = (b - r) / span + 2
    else:
        hue = (r - g) / span + 4
    return hue * 60.0, sat, light


def from_hsl(hue, sat, light):
    c = (1 - abs(2 * light - 1)) * sat
    x = c * (1 - abs(((hue / 60.0) % 2) - 1))
    m = light - c / 2
    table = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)]
    r, g, b = table[int(hue // 60) % 6]
    return tuple(max(0, min(255, int(round((v + m) * 255)))) for v in (r, g, b))


def to_hex(rgb):
    return '#%02x%02x%02x' % rgb


#: The lightness a line may not be paler than on the light basemap, and the
#: one it may not be darker than on the dark basemap.
LIGHT_THEME_MAX_L = 0.46
DARK_THEME_MIN_L = 0.42
MIN_SATURATION = 0.42


def display_colours(reference):
    """The published colour, and the two the map can actually draw it in.

    The operator's own value is kept verbatim as ``colorReference`` — it is a
    fact about the railway and the package must not lose it. What is drawn is
    that colour moved along its own **lightness** until it is legible, with the
    hue held exactly and the saturation only ever raised.

    Why lightness rather than a flat multiply: Amtrak publishes ``#CAE4F1``
    for every one of its forty-odd routes, and multiplying a pale colour
    towards black takes the saturation with it — the Northeast Corridor came
    out the grey of a disused siding. Moving the same colour down its own
    lightness axis keeps the blue that the operator chose and only makes it
    dark enough to see.
    """
    rgb = parse_hex(reference)
    if rgb is None:
        raise ValueError('an operator-published six-digit colour is required')
    hue, sat, light = to_hsl(rgb)
    sat_out = max(sat, MIN_SATURATION) if sat > 0.04 else sat
    light_theme = from_hsl(hue, sat_out, min(light, LIGHT_THEME_MAX_L))
    dark_theme = from_hsl(hue, sat_out, max(light, DARK_THEME_MIN_L))
    return to_hex(light_theme), to_hex(dark_theme), to_hex(rgb)


def published_route_colour(entry, route, route_id):
    """Resolve an exact operator/government-published route colour.

    Some official GTFS feeds leave ``route_color`` blank even though the same
    operator or city publishes an exact route palette with its surveyed GIS.
    Registry overrides are deliberately route-id exact and must carry their
    own source; a malformed declared override fails closed instead of quietly
    turning into a generated/default colour.
    """
    overrides = entry.get('officialColorByRouteId') or {}
    if route_id in overrides:
        sources = entry.get('officialColorSourceByRouteId') or {}
        return overrides[route_id], sources.get(route_id)
    published = route.get('route_color')
    if parse_hex(published) is not None:
        return published, 'operator GTFS routes.txt route_color'
    return entry.get('color'), entry.get('colorSource')


def partition_fail_closed_routes(routes, entry):
    """Remove exact routes whose independent alignment is still unverified."""
    blocked = entry.get('blockedRouteIds') or {}
    kept = []
    refused = []
    for route in routes:
        route_id = route.get('route_id')
        if route_id not in blocked:
            kept.append(route)
            continue
        reason = str(blocked.get(route_id) or '').strip()
        refused.append({
            'route': route_id,
            'why': ('fail-closed: ' + reason if reason else
                    'fail-closed: independent official alignment unavailable'),
        })
    return kept, refused


def median_snap(routing):
    """How far the FRA network had to reach for this line's median station.

    ``None`` when nothing snapped at all. The upper of the two middles on an
    even count, the same way ``na_profile.median_spacing_m`` takes a median,
    so the build has one answer to "what does the middle of this list say".
    """
    snaps = sorted(v for v in (routing.get('snapMeters') or ()) if v is not None)
    return snaps[len(snaps) // 2] if snaps else None


# ------------------------------------------------------------------ one feed

class FeedBuild:
    def __init__(self, entry, sources, countries, network, options):
        self.entry = entry
        self.slug = entry['slug']
        self.sources = sources
        self.countries = countries
        self.network = network
        self.options = options
        self.report = {'slug': self.slug, 'lines': 0, 'dropped': [], 'notes': [],
                       'syntheticConnectors': 0}
        self.synthetic = 0

    # ................................................................ reading

    def run(self):
        path = os.path.join(self.sources, 'gtfs', f"{self.entry['mdb']}.zip")
        if not os.path.exists(path):
            self.report['notes'].append('feed not downloaded')
            return []
        feed = gtfs.Feed(path)
        stops = feed.stops()
        stops = self.drop_non_stations(stops)
        stops = self.apply_station_coordinate_overrides(stops)
        agencies = feed.agencies()
        weights = feed.service_weights()
        include_routes = set(self.entry.get('includeRouteIds') or ())
        routes = [row for row in feed.rows('routes.txt')
                  if (gtfs.is_rail_type(row.get('route_type'))
                      or row.get('route_id') in include_routes)]
        drop = set(self.entry.get('excludeRoutes') or ())
        routes = [r for r in routes if r.get('route_id') not in drop]
        routes, refused = partition_fail_closed_routes(routes, self.entry)
        self.report['dropped'].extend(refused)
        if not routes:
            self.report['notes'].append('no verified rail routes')
            return []
        shapes = feed.shapes()
        trips = feed.trips_by_route([r['route_id'] for r in routes])
        sampled_trips = {}
        preferred_by_route = self.entry.get('preferredTripByRouteId') or {}
        for route_id, rows in trips.items():
            sampled = sample_trips(rows, self.options.max_trips_per_route)
            preferred_id = preferred_by_route.get(route_id)
            preferred = next((row for row in rows
                              if row.get('trip_id') == preferred_id), None)
            if preferred is not None and all(
                    row.get('trip_id') != preferred_id for row in sampled):
                sampled.append(preferred)
            sampled_trips[route_id] = sampled
        trips = sampled_trips
        every_trip = [t['trip_id'] for v in trips.values() for t in v]
        sequences = feed.stop_sequences(every_trip)

        configured_name_near = self.entry.get('stationIdentityNameNearMeters')
        feed_parents = canonical_feed_parents(
            stops, self.entry.get('stationIdentityGroups') or (),
            near_m=(200.0 if configured_name_near is None
                    else float(configured_name_near)),
            coordinate_near_m=float(
                self.entry.get('stationIdentityNearMeters') or 0.0),
            identity_field=self.entry.get('stationIdentityField'))
        self.station_complex_by_stop = {}
        if self.entry.get('stationComplexesFromTransfers'):
            self.station_complex_by_stop = official_transfer_complexes(
                stops, feed.rows('transfers.txt'))
            complex_count = len(set(self.station_complex_by_stop.values()))
            self.report['notes'].append(
                f'official transfers.txt supplies {complex_count} station '
                f'complexes ({len(self.station_complex_by_stop)} stations)')

        def parent(row):
            return feed_parents.get(row.get('stop_id'),
                                    gtfs.parent_of(row, stops))

        built = []
        for group in group_routes(
                routes, trips, sequences, stops, parent, agencies,
                preserve_route_ids=bool(self.entry.get('preserveRouteIds')),
                merge_route_id_groups=self.entry.get('mergeRouteIdGroups') or ()):
            built.extend(self.build_route(group, trips, sequences, stops, shapes,
                                          weights, agencies, parent))
        built = drop_subsets(
            built,
            preserve_route_ids=bool(self.entry.get('preserveRouteIds')))
        built = absorb_duplicate_branches(built)
        built = drop_redundant_branches(built)
        built = unique_ids(built)
        self.report['lines'] = len(built)
        self.report['syntheticConnectors'] = self.synthetic
        return built

    #: Published timing points that are not stations. Amtrak lists the
    #: international boundary as a stop (`CBN`, "Canadian Border") on the
    #: *Maple Leaf* and the *Adirondack* because a train really does stand
    #: there for customs — but nobody boards it, no platform is there, and a
    #: display line that called at it would put a station dot in the middle of
    #: the Niagara River.
    #:
    #: Matched on the whole name rather than on a substring: there are real
    #: stations called Border and Borderland, and a rule that removed them
    #: would delete a railway to tidy up a timing point.
    NON_STATION_NAMES = {
        'canadian border', 'us border', 'u.s. border', 'international border',
        'border crossing', 'customs',
    }

    def drop_non_stations(self, stops):
        kept = {}
        dropped = []
        excluded_ids = {str(stop_id) for stop_id in
                        (self.entry.get('excludeStopIds') or ())}
        for stop_id, row in stops.items():
            name = (row.get('stop_name') or '').strip().lower()
            if stop_id in excluded_ids or name in self.NON_STATION_NAMES:
                dropped.append(f"{stop_id} ({row.get('stop_name')})")
                continue
            kept[stop_id] = row
        if dropped:
            self.report['notes'].append(
                'not stations, dropped: ' + ', '.join(sorted(dropped)))
        return kept

    def apply_station_coordinate_overrides(self, stops):
        """Replace a proved-bad feed coordinate, never a surprising one.

        Operator GTFS remains the primary source for station identity, but it
        is not allowed to be its own coordinate validator. An override must
        name the bad published point, the corrected point and at least two
        independent pieces of evidence. The published-point guard matters:
        when an operator fixes its feed, a stale registry entry must not move
        the station back to yesterday's answer.
        """
        overrides = self.entry.get('stationCoordinateOverrides') or {}
        if not overrides:
            return stops
        out = dict(stops)
        for stop_id, rule in overrides.items():
            stop_id = str(stop_id)
            row = out.get(stop_id)
            if row is None:
                self.report['notes'].append(
                    f'{stop_id}: coordinate override no longer matches a stop')
                continue
            evidence = rule.get('evidence') or ()
            if len(evidence) < 2:
                raise ValueError(
                    f'{self.slug} {stop_id}: coordinate override requires '
                    'at least two independent evidence records')
            published = rule.get('published')
            corrected = rule.get('corrected')
            if not (isinstance(published, list) and len(published) == 2
                    and isinstance(corrected, list) and len(corrected) == 2):
                raise ValueError(
                    f'{self.slug} {stop_id}: coordinate override requires '
                    '[lon, lat] published and corrected points')
            try:
                current = [float(row['stop_lon']), float(row['stop_lat'])]
                corrected = [float(corrected[0]), float(corrected[1])]
            except (KeyError, TypeError, ValueError) as exc:
                raise ValueError(
                    f'{self.slug} {stop_id}: invalid coordinate override') from exc
            guard_m = float(rule.get('publishedToleranceMeters') or 100.0)
            if geo.haversine(current, corrected) <= guard_m:
                continue
            if geo.haversine(current, published) > guard_m:
                raise ValueError(
                    f'{self.slug} {stop_id}: published coordinate changed; '
                    'refusing a stale override')
            fixed = dict(row)
            fixed['stop_lon'] = str(corrected[0])
            fixed['stop_lat'] = str(corrected[1])
            out[stop_id] = fixed
            self.report['notes'].append(
                f'{stop_id} ({row.get("stop_name")}): corrected a '
                f'{geo.haversine(current, corrected) / 1000:.1f} km GTFS '
                f'coordinate error after {len(evidence)}-source validation')
        return out

    # ............................................................... one route

    def build_route(self, group, trips, sequences, stops, shapes, weights,
                    agencies, parent):
        routes = group['routes']
        route = routes[0]
        rid = route['route_id']
        route_trips = [t for r in routes for t in trips.get(r['route_id'], [])]
        patterns = lines.build_patterns(rid, route_trips, sequences, stops,
                                        parent, weights)
        selection = lines.select_lines(patterns)
        preferred_trip = (self.entry.get('preferredTripByRouteId') or {}).get(rid)
        if preferred_trip:
            trip = next((row for row in route_trips
                         if row.get('trip_id') == preferred_trip), None)
            raw_sequence = sequences.get(preferred_trip) or ()
            selected_stations = []
            for stop_id in raw_sequence:
                stop = stops.get(stop_id)
                if stop is None:
                    continue
                station = parent(stop)
                if not selected_stations or selected_stations[-1] != station:
                    selected_stations.append(station)
            if trip is None or len(selected_stations) < 2:
                self.report['dropped'].append({
                    'route': rid, 'why': 'preferred official trip unavailable',
                    'trip': preferred_trip,
                })
                return []
            selected_pattern = lines.Pattern(
                selected_stations, trip.get('shape_id'), preferred_trip)
            selected_pattern.trips = 1
            selected_pattern.weight = 1.0
            shape_id = (trip.get('shape_id') or '').strip()
            if shape_id:
                selected_pattern.shape_ids[shape_id] = 1.0
            selection = [('', selected_stations, selected_pattern, False)]
            self.report['notes'].append(
                f'{rid}: station membership/order from official trip '
                f'{preferred_trip}')
        official_order = (self.entry.get('stationOrderByRouteId') or {}).get(rid)
        if official_order:
            evidence = ((self.entry.get('stationOrderEvidenceByRouteId') or {})
                        .get(rid) or ())
            if len(evidence) < 2:
                raise ValueError(
                    f'{self.slug} {rid}: explicit station order requires '
                    'at least two evidence records')
            selected_stations = []
            missing = []
            for stop_id in map(str, official_order):
                stop = stops.get(stop_id)
                if stop is None:
                    missing.append(stop_id)
                    continue
                station = parent(stop)
                if not selected_stations or selected_stations[-1] != station:
                    selected_stations.append(station)
            published = {station for pattern in patterns
                         for station in pattern.stations}
            unpublished = [station for station in selected_stations
                           if station not in published]
            if missing or unpublished or len(selected_stations) < 2:
                self.report['dropped'].append({
                    'route': rid,
                    'why': 'explicit official station order no longer matches feed',
                    'missingStopIds': missing,
                    'unpublishedStations': unpublished,
                })
                return []
            selection = [('', selected_stations,
                          lines.match_pattern(patterns, selected_stations), False)]
            self.report['notes'].append(
                f'{rid}: station order pinned to {len(selected_stations)} '
                f'official stops after {len(evidence)}-source validation')
        if not selection:
            self.report['dropped'].append({'route': rid, 'why': 'no pattern'})
            return []
        agency = agencies.get((route.get('agency_id') or '').strip()) \
            or next(iter(agencies.values()), {})
        agency_name = (self.entry.get('operatorOverride')
                       or title_case_operator(agency.get('agency_name'))
                       or self.entry['name'])
        kind = ((self.entry.get('kindOverrideByRouteId') or {}).get(rid)
                or self.entry.get('kindOverride')
                or gtfs.route_type_kind(route.get('route_type')))
        route_name = group['name'] or agency_name
        out = []
        for selection_index, (suffix, station_ids, pattern, loop) in enumerate(selection):
            line = self.build_line(route, rid, suffix, station_ids, pattern, loop,
                                   stops, shapes, agency, agency_name, kind,
                                   route_name, group['slug'], patterns)
            # Closing a loop asks the geometry for one interval more than the
            # station list contains, and where that one interval cannot be
            # built the whole railway was being lost: Oklahoma City's Downtown
            # Loop and San Diego's Silver Line both left the package the day
            # the closure was asked for. A railway drawn with its ends open is
            # a far smaller fault than a railway that is not drawn at all, so
            # the closure is best effort — and giving it up leaves the line
            # with the interval count an open line is supposed to have.
            if line is None and loop:
                line = self.build_line(route, rid, suffix, station_ids, pattern,
                                       False, stops, shapes, agency, agency_name,
                                       kind, route_name, group['slug'], patterns)
                if line:
                    self.report['notes'].append(
                        f'{rid}{suffix}: closing interval not buildable, '
                        f'shipped as an open line')
            if line:
                out.append(line)
            elif selection_index == 0:
                suppressed = max(0, len(selection) - 1)
                if suppressed:
                    self.report['dropped'].append({
                        'route': rid,
                        'why': 'trunk has no usable alignment; branches suppressed',
                        'branches': suppressed,
                    })
                return []
        return out

    def build_line(self, route, rid, suffix, station_ids, pattern, loop, stops,
                   shapes, agency, agency_name, kind, route_name, route_slug,
                   route_patterns=()):
        published_colour, colour_source = published_route_colour(
            self.entry, route, rid)
        if parse_hex(published_colour) is None or not colour_source:
            self.report['dropped'].append({
                'route': rid, 'suffix': suffix,
                'why': 'no operator-published line colour with source',
            })
            return None

        points = []
        ok = True
        for sid in station_ids:
            row = stops.get(sid)
            if row is None:
                ok = False
                break
            try:
                points.append([float(row['stop_lon']), float(row['stop_lat'])])
            except (KeyError, TypeError, ValueError):
                ok = False
                break
        if not ok or len(points) < 2:
            self.report['dropped'].append({'route': rid, 'why': 'stop without position'})
            return None

        if loop and not plausible_loop_closure(points):
            self.report['notes'].append(
                f'{rid}{suffix}: stop-order cycle is not a physical loop; '
                f'end stations are {geo.haversine(points[0], points[-1]):.0f} m '
                'apart')
            loop = False

        allowed_turnarounds = (
            (self.entry.get('stationTurnaroundTriplesByRouteId') or {})
            .get(rid) or ())
        reversals, approved_turnarounds = (
            partition_station_order_reversals(
                points, station_ids, allowed_turnarounds)
            if not loop else ([], []))
        if approved_turnarounds:
            self.report['notes'].append(
                f'{rid}{suffix}: retained operator-published station '
                f'turnaround at {", ".join(station_ids[index] for index in approved_turnarounds)}')
        if reversals:
            self.report['dropped'].append({
                'route': rid, 'suffix': suffix,
                'why': 'station order contains a long-distance reversal',
                'stations': reversals,
            })
            return None

        # A circular railway needs an interval for every station, including
        # the one that returns to the first — `compact-v1` pairs interval *i*
        # with stations *i* and *i+1 mod n*, and Japan, Taiwan and Hong Kong
        # all ship their loops that way. Built from an open station list the
        # closing leg is simply absent, and the line draws as an arc with its
        # ends hanging: twenty-six lines shipped like that, among them six TTC
        # streetcars and the Detroit People Mover, whose whole railway is the
        # leg that was missing.
        #
        # The closure is asked of the geometry, not drawn afterwards, so the
        # returning track is routed and groomed exactly like every other
        # interval. The station tables stay open — `station_ids` is what the
        # package ships — because the wrap is the format's own.
        route_points = (points + [points[0]]) if loop else points

        shape_id, shape = lines.shape_for(pattern, shapes)
        # Some authorities publish one authoritative shape on every selected
        # trip.  In that case keep the trip's own shape: looking for a second
        # candidate is both unnecessary and, on branched systems such as
        # WMATA, can reject every otherwise-valid route when another trip's
        # branch does not pass all of this pattern's stations.  The geometry
        # still goes through ``geometry_for`` below, including the interval
        # detour/reversal checks and final station-anchor validation.
        trust_selected_shape = (
            self.entry.get('trustSelectedPatternShape') and shape is not None)
        if self.entry.get('trustOfficialShapes') and not trust_selected_shape:
            trusted_id, trusted_shape = trusted_shape_fallback(
                points, route_patterns, shapes, self.options.anchor_m)
            shape_id, shape = trusted_id, trusted_shape
            if shape is not None and not pattern.shape_ids.get(shape_id):
                self.report['notes'].append(
                    f'{rid}{suffix}: selected pattern had no shape; used '
                    f'same-route official shape {shape_id} after every station '
                    'matched it in order')
        if shape is not None and self.entry.get('removeExactShapeReturnSpikes'):
            shape, removed_spikes = remove_exact_return_spikes(shape)
            if removed_spikes:
                self.report['notes'].append(
                    f'{rid}{suffix}: removed {removed_spikes} exact A-B-A '
                    'return spikes from the operator-published shape')
        chords = geo.densify(route_points, 1_000)
        # Two corridors, not one. See ``Network.corridor_costs``: the operator's
        # shape is the better statement of which way round the trains go, and
        # the straight lines between the stations are what keeps a station the
        # shape does not reach from being routed to round three sides of a city.
        corridors = [c for c in (shape, chords) if c and len(c) > 1]
        # Trust means that the operator's alignment may win over another
        # pattern's shape; it never means that a polyline manufactured from
        # straight station chords becomes surveyed track.
        schematic = shape is None or build.shape_is_schematic(shape, points)

        chords = [geo.haversine(route_points[i], route_points[i + 1])
                  for i in range(len(route_points) - 1)]
        spacing = profile.median_spacing_m(chords)
        span = sum(chords)
        kindname = classify.classify(kind, agency_name, route_name, spacing, span,
                                     heritage=bool(self.entry.get('heritage')))
        kindname = ((self.entry.get('classificationByRouteId') or {}).get(rid)
                    or kindname)

        intervals, source = self.geometry_for(route_points, shape, corridors,
                                              kindname, schematic, rid, suffix)
        if intervals is None:
            return None

        if not intervals or not intervals[0]:
            self.report['dropped'].append(
                {'route': rid, 'suffix': suffix, 'why': 'empty first interval'})
            return None
        anchors = [list(intervals[0][0])]
        for piece in intervals:
            anchors.append(list(piece[-1]) if piece else list(anchors[-1]))
        if len(anchors) != len(route_points):
            anchors = list(route_points)

        groomed, band = groom_with_final_profile(intervals)
        anchors = [list(groomed[0][0])] + [list(p[-1]) for p in groomed]
        # The closing interval's far end IS the first station; the station
        # table carries it once, so the extra anchor is dropped rather than
        # shipped as a station the railway calls at twice.
        if loop:
            anchors = anchors[:len(station_ids)]

        rank, institution, klass = classify.codes_for(
            kindname, private_operator=bool(self.entry.get('private')))
        colour, colour_dark, reference = display_colours(published_colour)
        line_id = f'{self.slug}-{route_slug}{suffix}'
        return {
            'lineId': line_id,
            # Internal provenance used by the de-duplication passes before
            # compact-v1 is encoded.  It is intentionally not serialized.
            'sourceRouteId': rid,
            'branchOf': f'{self.slug}-{route_slug}' if suffix else None,
            'feed': self.slug,
            'name': route_name,
            'shortName': (route.get('route_short_name') or '').strip(),
            'operator': agency_name,
            # A package-level path, not a boolean line badge.  North American
            # operators generally publish one company/network mark for many
            # services, so duplicating it under every line id would waste
            # space and make branding drift between routes.  The registry is
            # the audited owner of this association.
            'operatorLogo': self.entry.get('operatorLogo'),
            'operatorShort': self.entry.get('operatorShort'),
            'agencyTimezone': agency.get('agency_timezone') or 'America/New_York',
            'kind': kindname,
            'rank': rank,
            'institution': institution,
            'class': klass,
            'color': colour,
            'colorDark': colour_dark,
            'colorReference': reference,
            'colorSource': colour_source,
            'isLoop': loop,
            'geometrySource': source,
            'shapeId': shape_id,
            'stationIds': station_ids,
            # Official station-complex identity is carried to the final
            # cross-line grouping without replacing the physical GTFS parent
            # station.  A line therefore keeps its own platform/track anchor
            # even when several differently named parents form one transfer
            # complex (MTA 14 St/6 Av is the canonical example).
            'stationComplexByStop': self.station_complex_by_stop,
            'stationNames': [title_case_station(stops[s].get('stop_name'))
                             for s in station_ids],
            'stationZones': [(stops[s].get('stop_timezone') or '').strip()
                             or (agency.get('agency_timezone') or '')
                             for s in station_ids],
            'stationPoints': points,
            'anchors': anchors,
            'intervals': groomed,
            'profile': band.name,
            'lengthKm': round(sum(geo.line_length(p) for p in groomed) / 1000.0, 3),
        }

    def geometry_for(self, points, shape, corridors, kindname, schematic,
                     rid='', suffix=''):
        """One line's station-to-station geometry, and which source gave it.

        The one place the three sources are ordered, and the order is the
        argument of this whole build: the FRA network first for the track it
        surveys, the operator's own alignment where it does not, and a
        straight line — counted, and only ever between two stations the
        stronger sources could not join — after that.
        """
        intervals = None
        source = None
        official_key = ((self.entry.get('officialNetworkByRouteId') or {})
                        .get(rid) or self.entry.get('officialNetwork'))
        official_network = (getattr(self.options, 'official_networks', {})
                            .get(official_key))
        official_required = bool(
            official_key and self.entry.get('requireVerifiedOfficialNetwork'))
        if (self.entry.get('requireOfficialMappingForAllRoutes')
                and not official_key):
            self.report['dropped'].append({
                'route': rid, 'suffix': suffix,
                'why': 'required official route mapping is unavailable',
            })
            return None, None
        if official_required and official_network is None:
            self.report['dropped'].append({
                'route': rid, 'suffix': suffix,
                'why': 'required verified official route network is unavailable',
                'officialNetwork': official_key,
            })
            return None, None
        if official_network is not None:
            official_snap_m = min(
                self.options.anchor_m,
                float(self.entry.get('officialNetworkMaxSnapMeters')
                      or self.options.anchor_m))
            intervals, routing = official_network.route_stations(
                points, max_snap_m=official_snap_m)
            if intervals:
                checked = self.reject_detours(
                    intervals, points, None, False, kindname)
                if checked and all(checked):
                    intervals = checked
                    source = official_key
                    self.report['notes'].append(
                        f'{rid}{suffix}: geometry from {official_key}; operator '
                        'GTFS supplies station identity and order')
                else:
                    intervals = None
                    self.report['dropped'].append({
                        'route': rid, 'suffix': suffix,
                        'why': 'official route network contains an implausible interval',
                        'officialNetwork': official_key,
                    })
            else:
                self.report['dropped'].append({
                    'route': rid, 'suffix': suffix,
                    'why': 'official route network does not reach every station',
                    'officialNetwork': official_key,
                    'snapMeters': routing.get('snapMeters'),
                    'limitMeters': official_snap_m,
                })
                intervals = None
            if official_required and source is None:
                self.report['dropped'].append({
                    'route': rid, 'suffix': suffix,
                    'why': 'required verified official route network failed; '
                           'fallback forbidden',
                    'officialNetwork': official_key,
                })
                return None, None
        if (source is None
                and kindname in ('intercity', 'highspeed', 'commuter', 'heritage')
                and self.network):
            # A complete, operator-tagged provincial survey is stronger than
            # the continent graph for the territory it covers.  Only fall
            # back to NARN when that official survey could not join every
            # station on this line.
            intervals, routing = narn.route_stations(
                self.network, corridors, points,
                width_m=self.options.corridor_m,
                max_snap_m=self.options.snap_m)
            intervals = self.reject_far_snap_intervals(
                intervals, routing, rid, suffix)
            if shape and not schematic and not self.network_surveys(routing):
                self.report['dropped'].append({
                    'route': rid, 'suffix': suffix,
                    'why': 'railway is not in the surveyed network',
                    'medianSnapMeters': round(median_snap(routing) or 0.0, 1),
                    'usedInstead': self.SHAPE_SOURCE,
                })
                intervals = None
            else:
                intervals = self.reject_detours(intervals, points, shape,
                                                schematic, kindname)
                covered = sum(1 for x in intervals if x)
                if covered >= max(1, int(0.8 * (len(points) - 1))):
                    had_gap = any(x is None for x in intervals)
                    intervals = self.patch_with_shape(intervals, points, shape,
                                                      schematic, kindname)
                    source = self.SHAPE_SOURCE if had_gap and intervals else 'narn'
                else:
                    intervals = None
        if intervals is None and shape and not schematic:
            cut, _, _ = build.cut_at_stations(
                shape, points, self.options.anchor_m)
            # The same plausibility test the routed path gets: an alignment
            # that does not reach a station produces an interval that is not an
            # interval, and it must not be drawn as one.
            intervals = self.patch_with_shape(
                self.reject_detours(cut, points, shape, schematic, kindname),
                points, None, True, kindname)
            # Here the operator alignment is the last source. A known detour
            # cannot be kept merely to preserve a line count: that turns a
            # route-selection/topology error into a railway visibly wandering
            # across the map. Leave the service blocked until a complete
            # official/OSM alignment can be selected without guessing.
            if intervals is None:
                self.report['dropped'].append({
                    'route': rid, 'suffix': suffix,
                    'why': 'operator alignment contains an implausible interval',
                })
                return None, None
            source = self.SHAPE_SOURCE
        if intervals is None:
            relation_id = (self.entry.get('osmRelationByRouteId') or {}).get(rid)
            osm_shape = getattr(self.options, 'osm_relation_shapes', {}).get(
                int(relation_id)) if relation_id is not None else None
            if osm_shape:
                cut, _, report = build.cut_at_stations(
                    osm_shape, points, self.options.anchor_m)
                if cut and all(piece and len(piece) > 1 for piece in cut):
                    intervals = cut
                    source = 'osm'
                    self.report['notes'].append(
                        f'{rid}{suffix}: alignment from audited OSM relation '
                        f'{relation_id}; station identity/order remain from '
                        'the operator GTFS')
        if intervals is None and kindname == 'funicular' and len(points) == 2:
            # The one railway where the straight line between two stations is
            # not a guess at the alignment but the alignment itself: an
            # incline is a single straight track up a hillside, and its two
            # stations are its two ends. Pittsburgh publishes the Duquesne and
            # Monongahela Inclines with 472 and 475 trips a day and no
            # ``shape_id`` at all, and no surveyed network contains them — the
            # nearest FRA track is the freight line along the Mon, which is a
            # different railway — so without this they are simply absent, and
            # they are passenger railways.
            #
            # Counted in ``syntheticConnectors`` like every other drawn rather
            # than surveyed interval, because a reader of the package is
            # entitled to know which is which.
            self.synthetic += 1
            self.report['notes'].append(
                f'{rid}{suffix}: an incline with no published alignment, drawn '
                f'as the straight track between its two stations')
            return [[list(points[0]), list(points[1])]], 'station-chord'
        if intervals is None:
            self.report['dropped'].append(
                {'route': rid, 'suffix': suffix, 'why': 'no usable alignment',
                 'schematicShape': schematic})
            return None, None

        # NARN occasionally represents a curved station interval as one
        # straight edge. If the operator publishes a complete, non-schematic
        # alignment for the same ordered stations, prefer that complete shape
        # rather than densifying the NARN chord and pretending detail was
        # added. Replacing the whole line preserves one consistent set of
        # station anchors; mixing individual intervals would create seams.
        straight = [i for i, piece in enumerate(intervals)
                    if i + 1 < len(points)
                    and piece_is_station_chord(piece, points[i], points[i + 1])]
        # This repair is specific to coarse NARN edges.  A reviewed municipal
        # centreline may legitimately contain a surveyed straight segment;
        # replacing the whole official route with GTFS because of that one
        # segment both discards the stronger source and loses its provenance.
        if source == 'narn' and straight and shape and not schematic:
            probe = [None if i in straight else piece
                     for i, piece in enumerate(intervals)]
            replacement = self.patch_with_shape(
                probe, points, shape, False, kindname)
            if replacement:
                checked = self.reject_detours(
                    replacement, points, shape, False, kindname)
                if checked and all(checked):
                    intervals = checked
                    source = self.SHAPE_SOURCE
                    self.report['notes'].append(
                        f'{rid}{suffix}: replaced {len(straight)} straight '
                        'NARN interval(s) with the complete operator alignment')
        for i in range(1, len(intervals)):
            if (not intervals[i - 1] or not intervals[i]
                    or geo.haversine(intervals[i - 1][-1], intervals[i][0]) > 1.0):
                self.report['dropped'].append({
                    'route': rid, 'suffix': suffix,
                    'why': 'authoritative intervals do not meet at their shared station',
                    'interval': i,
                })
                return None, None
        return intervals, source

    def reject_far_snap_intervals(self, intervals, routing, rid='', suffix=''):
        """Reject NARN hops whose endpoint is not this railway's station.

        A line-wide median can prove that NARN surveys most of a railway while
        hiding one station snapped to a different formation kilometres away.
        Mixed with an operator-shape fallback on the neighbouring hop, that
        creates a discontinuity which compact-v1 then renders as a direct jump.
        Test both endpoint snaps per interval; the operator shape may replace a
        rejected hop later, but no distant NARN anchor is allowed to survive.
        """
        snaps = routing.get('snapMeters') or []
        out = []
        for i, piece in enumerate(intervals):
            endpoint_snaps = snaps[i:i + 2]
            far = [d for d in endpoint_snaps
                   if d is None or d > self.options.anchor_m]
            if far:
                self.report['dropped'].append({
                    'route': rid, 'suffix': suffix,
                    'why': 'NARN interval endpoint snapped too far from station',
                    'interval': i,
                    'snapMeters': endpoint_snaps,
                    'limitMeters': self.options.anchor_m,
                })
                out.append(None)
            else:
                out.append(piece)
        return out

    def network_surveys(self, routing):
        """Whether the FRA network is a statement about *this* railway.

        ``route_stations`` snaps every station to the nearest track it can
        find within three kilometres, which is the right generosity for a
        prairie halt whose published position is a car park and quite the
        wrong one for a railway the network does not contain at all. PATH
        publishes ``route_type=2``, so it is read as a commuter railroad and
        routed; its tunnels are not in the FRA network, and its Manhattan
        stations snapped between 0.7 and 1.8 km onto Amtrak's Empire
        Connection and Metro-North's West Side track. The line that came back
        was routed, cut and groomed impeccably — along somebody else's
        railroad, and "33rd Street to 23rd Street" shipped at 17.8 times the
        750 m that separates them.

        Judged on the median station rather than the worst: one station a
        kilometre from the track is a station whose published position is
        wrong, and half of them is a different railway. The two populations do
        not overlap — every line the network really does survey has a median
        under 130 m, and the six it does not start at 690 m — so the threshold
        is the one the build already owns for "the alignment, not the station,
        is what is wrong".
        """
        median = median_snap(routing)
        return median is not None and median <= self.options.anchor_m

    #: What ``geometry_for`` calls the operator's own alignment. Overridden by
    #: the OpenStreetMap builder, which has a different one.
    SHAPE_SOURCE = 'gtfs-shape'

    #: How far round a station pair a routed interval may go before it is
    #: disbelieved. Real railways do wander — a mountain line's ratio to the
    #: straight line is routinely 1.6, and a river crossing forces worse — so
    #: this is set where an interval stops looking like track and starts
    #: looking like the graph having found a way round.
    DETOUR_RATIO = 2.2
    DETOUR_MIN_KM = 4.0

    def detour_ratio(self, kindname):
        # One cap for every railway.  The former 2.6 long-haul exception was
        # based on VIA Anjou–Joliette, but Québec MTQ's official railway GIS
        # proves that NARN's 109 km answer is a topology detour: the surveyed
        # CN route is about 52.3 km.  Sparse stops do not justify accepting a
        # path that the independent official network disproves.
        return self.DETOUR_RATIO

    def reject_detours(self, intervals, points, shape, schematic, kindname):
        """Throw away an interval the network routed the long way round.

        A shortest path is only as good as the corridor it is confined to, and
        where an operator's published shape does not reach — the outer end of a
        route whose shape covers only its busiest pattern — the corridor is
        drawn from the straight lines between stations alone. That is enough to
        keep the path near the railway, and not always enough: at Sacramento
        the *Capitol Corridor* came back eighty kilometres for a twenty-six
        kilometre hop, having found cheaper track by going round the city.

        Rejected rather than repaired, because there is nothing here that could
        repair it: what is known is that the answer is wrong, and the caller
        has a second source — the operator's own alignment — for exactly the
        intervals this hands back as `None`.
        """
        out = []
        ratio_cap = self.detour_ratio(kindname)
        for i, piece in enumerate(intervals):
            if not piece:
                out.append(piece)
                continue
            straight = geo.haversine(points[i], points[i + 1])
            length = geo.line_length(piece)
            reversal = self.has_internal_reversal(piece)
            if reversal is not None:
                self.report['dropped'].append({
                    'why': 'routed interval contains an internal reversal',
                    'interval': i,
                    'turnDegrees': round(reversal, 1),
                })
                out.append(None)
            elif (length > self.DETOUR_MIN_KM * 1_000
                    and straight > 0
                    and length / straight > ratio_cap):
                self.report['dropped'].append({
                    'why': 'routed interval is a detour',
                    'interval': i,
                    'routedKm': round(length / 1000, 2),
                    'straightKm': round(straight / 1000, 2),
                })
                out.append(None)
            else:
                out.append(piece)
        return out

    @staticmethod
    def has_internal_reversal(piece, minimum_turn=155.0, minimum_leg_m=20.0):
        """A train cannot reverse direction between two ordinary stations."""
        if not piece or len(piece) < 3:
            return None
        latitude = sum(point[1] for point in piece) / len(piece)
        xscale = 111_320.0 * math.cos(math.radians(latitude))
        yscale = 110_540.0
        # ``cut_at_stations`` puts the published station marker at each end
        # of a piece and then connects it to the projected track centreline.
        # A platform entrance can be tens of metres beyond that projection,
        # so either endpoint turn may legitimately be close to 180 degrees.
        # A reversal *between* centreline vertices remains impossible.  Test
        # only those truly internal turns, excluding the first and last.
        for a, b, c in zip(piece[1:-3], piece[2:-2], piece[3:-1]):
            ux, uy = ((b[0] - a[0]) * xscale, (b[1] - a[1]) * yscale)
            vx, vy = ((c[0] - b[0]) * xscale, (c[1] - b[1]) * yscale)
            nu, nv = math.hypot(ux, uy), math.hypot(vx, vy)
            if nu < minimum_leg_m or nv < minimum_leg_m:
                continue
            cosine = max(-1.0, min(1.0, (ux * vx + uy * vy) / (nu * nv)))
            turn = math.degrees(math.acos(cosine))
            if turn >= minimum_turn:
                return turn
        return None

    def patch_with_shape(self, intervals, points, shape, schematic, kindname):
        """Replace an incomplete official-network route with one operator shape.

        Mixing a NARN interval with an operator-shape interval at one station
        can join two different projected anchors and create a direct jump. If
        any NARN hop is absent or rejected, use the operator's complete shape
        for the complete display line. The cut is accepted only when every hop
        has plausible length, because a shape that does not reach a station can
        project it onto an unrelated place and return most of the line.

        What is left after both is not invented.  A straight chord between two
        stations looks plausible at national zoom and is nevertheless not a
        railway position; it also defeats the independent geometry audit by
        manufacturing the very alignment that is supposed to be checked.
        Reject the whole display pattern and name the gap in the build report.
        """
        if not any(x is None for x in intervals):
            return intervals
        if not shape or schematic:
            return None
        cut, _, _ = build.cut_at_stations(shape, points, self.options.anchor_m)
        ratio_cap = self.detour_ratio(kindname)
        for i, candidate in enumerate(cut or ()):
            straight = geo.haversine(points[i], points[i + 1])
            if candidate and len(candidate) > 1:
                length = geo.line_length(candidate)
                plausible = (straight <= 0
                             or length <= max(self.DETOUR_MIN_KM * 1_000,
                                              straight * ratio_cap))
                if plausible:
                    continue
            self.report['dropped'].append({
                'why': 'interval absent from both surveyed network and operator shape',
                'interval': i,
                'from': list(points[i]),
                'to': list(points[i + 1]),
            })
            return None
        return cut if cut and len(cut) == len(intervals) else None


#: Route names that name no route — a feed's word for "the trains", used where
#: an operator publishes one rail route and does not name it.
GENERIC_ROUTE_NAMES = {
    'rail', 'train', 'trains', 'commuter rail', 'rail service', 'railway',
    'metro', 'subway', 'light rail', 'streetcar', 'monorail', 'tram',
}

DIRECTION_SUFFIX = re.compile(
    r'(?i)[\s\-–—/]+(n|s|e|w|nb|sb|eb|wb|north|south|east|west|northbound|'
    r'southbound|eastbound|westbound|inbound|outbound|inner|outer)$')
DIRECTION_WORD = re.compile(
    r'(?i)\b(northbound|southbound|eastbound|westbound|inbound|outbound)\b')


def strip_direction(text):
    """A route's name with the direction it is published under removed.

    BART publishes each of its lines twice, once per direction, as two routes
    with different ids and different names — ``Yellow-N`` running
    "Millbrae/SF Int'l SFO to Antioch" and ``Yellow-S`` the reverse. They are
    one railway, and building them separately produces two lines that draw
    over each other and neither of which calls everywhere.
    """
    out = DIRECTION_WORD.sub(' ', text or '').strip()
    out = DIRECTION_SUFFIX.sub('', out).strip()
    return ' '.join(out.split())


def jaccard(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / float(len(a | b))


def group_routes(routes, trips, sequences, stops, parent, agencies,
                 preserve_route_ids=False, merge_route_id_groups=()):
    """Fold the several routes one railway is published as into one.

    Two feeds' worth of reasons, and the rules are one each:

    * **One train, two routes.** Amtrak publishes the *Maple Leaf* twice —
      once as its own service, once as the six Canadian stations VIA operates
      under a second agency id. They carry the same name and share stations.
    * **One line, two directions.** BART, and several light-rail operators,
      publish a route per direction. The names differ (they are "A to B" and
      "B to A"), so the name cannot be the test; what they share is the
      operator's own line colour and almost all of their stations.

    The two rules are deliberately narrow. Name alone would merge Amtrak's two
    unrelated routes both called "Commuter Rail", four hundred kilometres
    apart; colour alone would merge every one of Amtrak's forty-odd routes,
    which all carry the same published colour.

    Some authorities explicitly use one ``route_id`` per public line while
    deliberately reusing colours across related services.  New York City's
    subway is the important case: 2/3, 4/5, A/C, B/D, J/Z and N/R/W are
    distinct official lines, not directional publications of one line.  A
    registry entry may therefore set ``preserveRouteIds``; for that feed the
    operator's route identity wins and neither heuristic is applied.
    """
    merge_group = {}
    for index, route_ids in enumerate(merge_route_id_groups):
        for route_id in route_ids:
            merge_group[str(route_id)] = index
    prepared = []
    for route in routes:
        long_name = (route.get('route_long_name') or '').strip()
        short_name = (route.get('route_short_name') or '').strip()
        stations = set()
        for trip in trips.get(route['route_id'], ())[:600]:
            for sid in sequences.get(trip['trip_id']) or ():
                row = stops.get(sid)
                if row is not None:
                    stations.add(parent(row))
        prepared.append({
            'route': route,
            'label': strip_direction(long_name or short_name),
            'short': strip_direction(short_name),
            'colour': (route.get('route_color') or '').strip().upper(),
            'stations': stations,
        })

    groups = []
    for item in prepared:
        key = item['label'].lower()
        hit = None
        for group in groups:
            agency = (item['route'].get('agency_id') or '').strip()
            same_agency = any(
                (route.get('agency_id') or '').strip() == agency
                for route in group['routes'])
            same_name = (same_agency and group['key'] == key and (
                group['stations'] & item['stations'] or not item['stations']))
            item_merge = merge_group.get(str(item['route']['route_id']))
            explicit_merge = (item_merge is not None
                              and bool(group['stations'] & item['stations'])
                              and any(merge_group.get(str(route['route_id']))
                                      == item_merge
                                      for route in group['routes']))
            # Colour and shared track are not route identity. NJ Transit uses
            # the same colour for Main/Bergen and Port Jervis, and PATH uses
            # shared stations for the direct and via-Hoboken services.  Both
            # were silently fused by the old heuristic.  It is available only
            # behind explicit route-id groups proved from that operator's
            # official feed and map to be the two directions of one line.
            # ``preserveRouteIds`` disables heuristic same-name folding, but
            # an explicit reviewed merge remains authoritative. This is used
            # when one operator publishes the same public line under two
            # timetable-period ids while other same-name routes must remain
            # distinct (GO Lakeshore East versus Lakeshore West).
            if ((not preserve_route_ids and same_name) or explicit_merge):
                hit = group
                break
        if hit is None:
            groups.append({'key': key, 'labels': [item['label']],
                           'shorts': [item['short']],
                           'colour': item['colour'],
                           'routes': [item['route']],
                           'stations': set(item['stations'])})
        else:
            hit['routes'].append(item['route'])
            hit['labels'].append(item['label'])
            hit['shorts'].append(item['short'])
            hit['stations'] |= item['stations']

    short_counts = Counter()
    for group in groups:
        short = Counter(s for s in group['shorts'] if s).most_common(1)
        group['short'] = short[0][0] if short else ''
        if group['short']:
            short_counts[group['short'].lower()] += 1

    used = set()
    for group in groups:
        route = group['routes'][0]
        labels = Counter(l for l in group['labels'] if l)
        name = labels.most_common(1)[0][0] if labels else ''
        if not name or name.lower() in GENERIC_ROUTE_NAMES:
            name = group['short'] or name
        if not name or name.lower() in GENERIC_ROUTE_NAMES:
            agency = agencies.get((route.get('agency_id') or '').strip())
            name = (agency or {}).get('agency_name') or name or route['route_id']
        group['name'] = name
        # The short name is the id when it is a real route symbol — the A
        # train, the Red Line — and useless when every route in the feed
        # carries the same one, which is how VIA publishes its network.
        base_source = (group['short']
                       if group['short'] and short_counts[group['short'].lower()] == 1
                       else name)
        base = slugify(base_source, route.get('route_id'))
        slug, n = base, 1
        while slug in used:
            n += 1
            slug = f'{base}-{n}'
        used.add(slug)
        group['slug'] = slug
    return groups


def sample_trips(rows, cap):
    """At most ``cap`` of a route's trips, spread evenly through the timetable.

    A year of the New York subway is two million stop times, and reading every
    one of them to discover the six stopping patterns the A train runs is work
    that answers nothing. A stride sample keeps every pattern that is run more
    than once in ``cap`` trips — which is every pattern a display line could be
    built from — and drops the repetition.

    Evenly rather than the first ``cap``: a feed's trips are usually in service
    order, so the first thousand of them are one Monday and a display line
    built from them would be missing whatever only runs at the weekend.
    """
    if cap <= 0 or len(rows) <= cap:
        return rows
    stride = len(rows) / float(cap)
    return [rows[int(i * stride)] for i in range(cap)]


def trusted_shape_fallback(station_points, patterns, shapes, anchor_m):
    """Choose a shape from another pattern of the same official route.

    NYC's 3 and 6X longest (night/local) station patterns have no shape_id,
    while their heavily used express patterns publish dense surveyed shapes.
    A fallback is accepted only when every target station projects within the
    normal anchor limit and the projected measures are monotonic.  This lets a
    local stop sit on an express alignment; it cannot borrow another route or
    jump to a nearby parallel railway.
    """
    candidates = {}
    for pattern in patterns:
        for shape_id, weight in pattern.shape_ids.items():
            candidates[shape_id] = max(candidates.get(shape_id, 0.0), weight)
    best = None
    for shape_id, weight in candidates.items():
        shape = shapes.get(shape_id)
        if not shape or len(shape) < 2:
            continue
        cumulative = geo.cumulative(shape)
        projected = [geo.project_to_line(point, shape, cumulative)
                     for point in station_points]
        if not projected or max(row[0] for row in projected) > anchor_m:
            continue
        measures = [row[4] for row in projected]
        forward = all(b + 20.0 >= a for a, b in zip(measures, measures[1:]))
        backward = all(b <= a + 20.0 for a, b in zip(measures, measures[1:]))
        if not forward and not backward:
            continue
        oriented = shape if forward else list(reversed(shape))
        cut, _, _ = build.cut_at_stations(oriented, station_points, anchor_m)
        plausible = bool(cut) and len(cut) == len(station_points) - 1
        for index, piece in enumerate(cut or ()):
            if not piece or len(piece) < 2:
                plausible = False
                break
            direct = geo.haversine(station_points[index],
                                   station_points[index + 1])
            length = geo.line_length(piece)
            if (length <= 1.0
                    or FeedBuild.has_internal_reversal(piece) is not None
                    or (length > FeedBuild.DETOUR_MIN_KM * 1_000
                        and direct > 0
                        and length / direct > FeedBuild.DETOUR_RATIO)):
                plausible = False
                break
        if not plausible:
            continue
        score = (max(row[0] for row in projected), -weight,
                 -geo.line_length(shape), shape_id)
        if best is None or score < best[0]:
            best = (score, shape_id, oriented)
    return (best[1], best[2]) if best else (None, None)


def remove_exact_return_spikes(points, tolerance_m=1.0):
    """Remove an indisputable ``A -> B -> A`` shape defect.

    WMATA's current official rail GTFS contains thousands of these excursions;
    its cumulative distance advances out to ``B`` and immediately back to the
    identical coordinate ``A``. This is deliberately not a general simplifier:
    the outer coordinates must agree within one metre, and a feed must opt in.
    """
    cleaned = []
    removed = 0
    for point in points or ():
        cleaned.append(point)
        while (len(cleaned) >= 3
               and geo.haversine(cleaned[-3], cleaned[-1]) <= tolerance_m):
            del cleaned[-2:]
            removed += 1
    return cleaned, removed


class OsmBuild(FeedBuild):
    """The same builder, fed by an OpenStreetMap route relation.

    A subclass rather than a second builder because everything after "which
    stations, in what order, along what alignment" is identical and must stay
    identical: the same FRA routing, the same anchoring, the same grooming
    bands, the same border split, the same station grouping. What differs is
    only where those three facts come from, and for the railways that reach
    this class there is nowhere else to get them.

    A line built here is marked ``geometrySource: 'osm'`` unless the FRA
    network could route it — the Alaska Railroad is mainline track and comes
    out of the same official centrelines every other intercity line does, with
    OpenStreetMap supplying only the station list and the corridor.
    """

    SHAPE_SOURCE = 'osm'

    def __init__(self, entry, routes, countries, network, options):
        super().__init__(entry, None, countries, network, options)
        self.routes = routes

    def run(self):
        built = []
        used = set()
        for route in self.routes:
            line = self.build_osm_line(route, used)
            if line:
                built.append(line)
        built = drop_subsets(built)
        built = absorb_duplicate_branches(built)
        built = drop_redundant_branches(built)
        built = unique_ids(built)
        self.report['lines'] = len(built)
        self.report['syntheticConnectors'] = self.synthetic
        return built

    def build_osm_line(self, route, used):
        evidence = ((self.entry.get('officialColorByRelation') or {})
                    .get(str(route['relation'])))
        published_colour = evidence and evidence.get('color')
        colour_source = evidence and evidence.get('source')
        if parse_hex(published_colour) is None or not colour_source:
            self.report['dropped'].append({
                'relation': route['relation'], 'name': route.get('name'),
                'why': 'OSM colour is not an official colour source',
            })
            return None
        stations = list(route['stations'])
        if len(stations) < 2:
            return None
        loop = bool(
            len(stations) > 2
            and normalise_station_name(stations[0]['name'])
                == normalise_station_name(stations[-1]['name'])
            and geo.haversine(stations[0]['point'], stations[-1]['point']) <= 400
        )
        if loop:
            stations = stations[:-1]
        points = [list(s['point']) for s in stations]
        route_points = points + [points[0]] if loop else points
        parts = na_osmlines.merge_parts(route['parts'])
        shape = parts[0] if parts else None
        if shape is None or len(shape) < 2:
            return None
        chords = geo.densify(route_points, 1_000)
        corridors = [c for c in (shape, chords) if c and len(c) > 1]
        # OSM route members are surveyed railway ways, even when a short
        # funicular is represented by only a handful of vertices. The GTFS
        # schematic detector is for diagram-like operator shapes and would
        # otherwise reject real inclines and heritage tramways here.
        schematic = False

        spans = [geo.haversine(route_points[i], route_points[i + 1])
                 for i in range(len(route_points) - 1)]
        kindname = classify.classify(
            OSM_KINDS.get(route['kind'], 'rail'), route['operator'], route['name'],
            profile.median_spacing_m(spans), sum(spans),
            heritage=bool(self.entry.get('heritage')))

        intervals, source = self.geometry_for(
            route_points, shape, corridors, kindname, schematic,
            rid=str(route['relation']))
        if intervals is None or not intervals[0]:
            return None

        groomed, band = groom_with_final_profile(intervals)
        anchors = [list(groomed[0][0])] + [list(p[-1]) for p in groomed]
        if loop:
            anchors = anchors[:len(stations)]

        rank, institution, klass = classify.codes_for(
            kindname, private_operator=bool(self.entry.get('private')))
        colour, colour_dark, reference = display_colours(published_colour)
        base = slugify(route['ref'] or route['name'], str(route['relation']))
        slug, n = base, 1
        while slug in used:
            n += 1
            slug = f'{base}-{n}'
        used.add(slug)
        zone = self.entry.get('timezone') or 'America/New_York'
        return {
            'lineId': f'{self.slug}-{slug}',
            'feed': self.slug,
            'name': route['name'] or route['operator'],
            'shortName': route['ref'],
            'operator': route['operator'] or self.entry['name'],
            'agencyTimezone': zone,
            'kind': kindname,
            'rank': rank,
            'institution': institution,
            'class': klass,
            'color': colour,
            'colorDark': colour_dark,
            'colorReference': reference,
            'colorSource': colour_source,
            'isLoop': loop,
            'geometrySource': source,
            'shapeId': f"osm:relation/{route['relation']}",
            'stationIds': [f"n{s['id']}" for s in stations],
            'stationNames': [title_case_station(s['name']) for s in stations],
            'stationZones': [zone] * len(stations),
            'stationPoints': points,
            'anchors': anchors,
            'intervals': groomed,
            'profile': band.name,
            'lengthKm': round(sum(geo.line_length(p) for p in groomed) / 1000.0, 3),
        }


#: OpenStreetMap's `route` values, in the vocabulary `na_classify` speaks.
OSM_KINDS = {
    'train': 'rail', 'subway': 'metro', 'light_rail': 'tram',
    'tram': 'tram', 'monorail': 'monorail', 'funicular': 'funicular',
}


def drop_subsets(built, preserve_route_ids=False):
    """Remove a line whose stations another line of the SAME service draws.

    Scoped by name on purpose. Acela's fourteen stations are a subset of the
    Northeast Regional's thirty-seven and it is emphatically not the same
    railway — an unscoped subset test deletes every express service in the
    country. What it does delete is the second, shorter publication of one
    train, which is what it is for.
    """
    kept = []
    by_name = defaultdict(list)
    for line in built:
        # A feed that assigns one official route_id per public service has
        # already told us that same-name routes are distinct.  NYC's W was
        # previously deleted here as a subset of N/R after group_routes had
        # correctly preserved it.  Keep subset comparison inside the source
        # route in that mode; branch patterns of one route can still collapse.
        route_scope = line.get('sourceRouteId') if preserve_route_ids else None
        by_name[(line['name'].lower(), route_scope)].append(line)
    for group in by_name.values():
        group.sort(key=lambda b: -len(b['stationIds']))
        seen = []
        for line in group:
            stations = set(line['stationIds'])
            if any(stations <= other for other in seen):
                continue
            seen.append(stations)
            kept.append(line)
    kept.sort(key=lambda b: (b['rank'], b['lineId']))
    return kept


def drop_cross_feed_duplicates(built, feed_metadata, reports,
                               station_tolerance_m=300.0):
    """Drop an explicitly lower-priority publication of the same railway.

    Regional consolidated feeds repeat lines also published by the operating
    agency (Puget Sound), and a renamed agency can leave both its old and new
    feeds in a national catalogue (TEXRail). Geometry alone must not decide:
    different services legitimately share track. A duplicate is removed only
    when operator, public line name, station count and every named station all
    agree spatially, and when the registry gives one source a strictly higher
    ``duplicatePriority``. Equal priority is deliberately a refusal to guess.
    """
    groups = defaultdict(list)
    for line in built:
        metadata = feed_metadata.get(line.get('feed')) or {}
        alias = (metadata.get('duplicateAliases') or {}).get(line.get('name'))
        key = (('explicit', alias)
               if alias else
               ((line.get('operator') or '').strip().casefold(),
                (line.get('name') or '').strip().casefold()))
        groups[key].append(line)

    def same_stations(a, b):
        if len(a['stationNames']) != len(b['stationNames']):
            return False
        unmatched = list(range(len(b['stationNames'])))
        for point in a['stationPoints']:
            # The same official station may be published as "Burlington" in
            # one feed and "Burlington, VT - Union Station" in another. Once
            # operator/public-line identity and explicit source priority have
            # matched, one-to-one spatial identity is the stronger test. It
            # also works in reverse direction and never uses fuzzy names.
            candidates = [(geo.haversine(point, b['stationPoints'][j]), j)
                          for j in unmatched]
            distance, hit = min(candidates, default=(float('inf'), None))
            if distance > station_tolerance_m:
                hit = None
            if hit is None:
                return False
            unmatched.remove(hit)
        return not unmatched

    dropped = set()
    detail = []
    for group in groups.values():
        if len(group) < 2:
            continue
        ranked = sorted(
            group,
            key=lambda line: int((feed_metadata.get(line.get('feed')) or {})
                                 .get('duplicatePriority', 0)),
            reverse=True)
        for winner in ranked:
            winner_priority = int((feed_metadata.get(winner.get('feed')) or {})
                                  .get('duplicatePriority', 0))
            for loser in ranked:
                if loser is winner or id(loser) in dropped:
                    continue
                loser_priority = int((feed_metadata.get(loser.get('feed')) or {})
                                     .get('duplicatePriority', 0))
                if winner_priority <= loser_priority:
                    continue
                if not same_stations(winner, loser):
                    continue
                dropped.add(id(loser))
                detail.append({
                    'line': loser['lineId'], 'feed': loser.get('feed'),
                    'kept': winner['lineId'], 'keptFeed': winner.get('feed'),
                    'why': 'same operator, line name and spatial station set; '
                           'registry duplicatePriority selects the source',
                })
    if detail:
        reports.append({
            'slug': 'cross-feed-duplicates', 'lines': 0,
            'dropped': detail, 'notes': [], 'syntheticConnectors': 0,
        })
        print(f'  dropped {len(detail)} explicitly lower-priority cross-feed '
              'duplicates', file=sys.stderr)
    return [line for line in built if id(line) not in dropped]


def unique_ids(built):
    used = set()
    for line in built:
        base = line['lineId']
        line_id, n = base, 1
        while line_id in used:
            n += 1
            line_id = f'{base}-{n}'
        used.add(line_id)
        line['lineId'] = line_id
    return built


def absorb_duplicate_branches(built, tolerance_m=250.0, share=0.85):
    """Fold a "branch" that runs on the trunk's own track back into the trunk.

    A route whose flag stops only some trips call at produces a pattern with
    stations the fullest pattern does not have — the *Empire Builder* calls at
    Essex, East Glacier Park and Cut Bank on some days and not others — and
    the graph merge cannot tell that apart from a real branch, because in the
    station graph it is exactly the same shape.

    Geometry can. A branch drawn within ``tolerance_m`` of the trunk for
    ``share`` of its length is the trunk, so its stations are projected onto
    the trunk's own geometry and spliced into the trunk's station list at the
    place they actually stand — which is where they belong, and where drawing
    them as a second stroke would have hidden them.
    """
    by_root = defaultdict(list)
    for line in built:
        root = re.sub(r'-b\d+$', '', line['lineId'])
        by_root[root].append(line)
    out = []
    for root, group in by_root.items():
        group.sort(key=lambda b: (0 if not re.search(r'-b\d+$', b['lineId']) else 1,
                                  -len(b['stationIds'])))
        trunk = group[0]
        out.append(trunk)
        for branch in group[1:]:
            if not absorb(trunk, branch, tolerance_m, share):
                out.append(branch)
    out.sort(key=lambda b: (b['rank'], b['lineId']))
    return out


def drop_redundant_branches(built):
    """Keep one branch per piece of new railway, not one per pattern that runs it.

    The Long Island Rail Road reaches Grand Central through one tunnel and
    publishes a pattern for it on every branch that uses it, each diverging
    from the trunk at a different station. Emitted as they come, that is three
    strokes down one tunnel to add one station.

    Two branches of a line that add exactly the same set of stations are
    therefore the same piece of railway, and the SHORTEST is kept: it is the
    one that diverges latest, so it is the one that repeats the least track
    the trunk already draws. Branches that add different stations are
    different railways and all of them stay.
    """
    kept = []
    by_root = defaultdict(list)
    for line in built:
        root = re.sub(r'-b\d+$', '', line['lineId'])
        by_root[root].append(line)
    for root, group in by_root.items():
        trunk = next((b for b in group if not re.search(r'-b\d+$', b['lineId'])),
                     None)
        trunk_stations = set(trunk['stationIds']) if trunk else set()
        seen = {}
        for line in group:
            if line is trunk:
                kept.append(line)
                continue
            fresh = frozenset(s for s in line['stationIds']
                              if s not in trunk_stations)
            if not fresh:
                # Adds no station the trunk lacks; `absorb` already declined it
                # on geometry, so it is a genuinely different alignment between
                # two stations the trunk has. Keep it.
                kept.append(line)
                continue
            best = seen.get(fresh)
            if best is None:
                seen[fresh] = line
                kept.append(line)
                continue
            same_order = (fresh_station_order(line, trunk_stations)
                          == fresh_station_order(best, trunk_stations))
            equivalent = same_order and branch_geometries_equivalent(best, line)
            if equivalent and line['lengthKm'] < best['lengthKm']:
                kept.remove(best)
                seen[fresh] = line
                kept.append(line)
            elif not equivalent:
                # Same destinations over a measurably different official
                # alignment are two branches, not a redundant publication.
                kept.append(line)
    kept.sort(key=lambda b: (b['rank'], b['lineId']))
    return kept


def absorb(trunk, branch, tolerance_m, share):
    tolerance_m = min(tolerance_m, branch_geometry_tolerance(trunk, branch))
    whole = []
    bounds = []
    for piece in trunk['intervals']:
        if not piece or len(piece) < 2:
            return False
        if whole:
            whole.extend(piece[1:])
        else:
            whole.extend(piece)
        bounds.append(len(whole) - 1)
    if len(whole) < 2:
        return False
    index = geo.ReferenceIndex(cell_deg=0.02)
    index.add_line(whole)
    checked = close = 0
    for piece in branch['intervals']:
        for point in (piece or ()):
            checked += 1
            d, _ = index.nearest(point, search_cells=2)
            if d <= tolerance_m:
                close += 1
    if not checked or close / checked < share:
        return False

    cumul = geo.cumulative(whole)
    edges = [cumul[b] for b in bounds]
    # A branch is the trunk only if the trunk can carry all of it. The splice
    # below can only place a station that projects onto the trunk's own track,
    # and it used to pass silently over one that did not — absorbing the
    # branch and taking the station out of the package with it. SEPTA's
    # Broad–Ridge Spur runs Fern Rock to Fairmount on the Broad Street Line
    # and then down Ridge Avenue, so Chinatown and 8th-Market stand a
    # kilometre off the trunk: the spur was folded in and those two stations
    # stopped being anywhere. A branch with a station the trunk cannot hold is
    # a different railway, and stays one.
    changed = False
    for i, sid in enumerate(branch['stationIds']):
        if sid in trunk['stationIds']:
            continue
        if geo.project_to_line(branch['anchors'][i], whole, cumul)[0] > tolerance_m:
            return False
    for i, sid in enumerate(branch['stationIds']):
        if sid in trunk['stationIds']:
            continue
        point = branch['anchors'][i]
        d, _, _, coord, measure = geo.project_to_line(point, whole, cumul)
        if d > tolerance_m:
            continue
        slot = next((j for j, edge in enumerate(edges) if measure < edge), None)
        if slot is None:
            continue
        piece = trunk['intervals'][slot]
        piece_cumul = geo.cumulative(piece)
        pd, _, _, pcoord, pmeasure = geo.project_to_line(coord, piece, piece_cumul)
        if pmeasure <= 1.0 or pmeasure >= piece_cumul[-1] - 1.0:
            continue
        head = geo.slice_between(piece, piece_cumul, 0.0, pmeasure)
        tail = geo.slice_between(piece, piece_cumul, pmeasure, piece_cumul[-1])
        if len(head) < 2 or len(tail) < 2:
            continue
        trunk['intervals'][slot:slot + 1] = [head, tail]
        for key, value in (('stationIds', sid),
                           ('stationNames', branch['stationNames'][i]),
                           ('stationZones', branch['stationZones'][i]),
                           ('stationPoints', branch['stationPoints'][i]),
                           ('anchors', list(pcoord))):
            trunk[key].insert(slot + 1, value)
        changed = True
        whole = []
        bounds = []
        for p in trunk['intervals']:
            if whole:
                whole.extend(p[1:])
            else:
                whole.extend(p)
            bounds.append(len(whole) - 1)
        cumul = geo.cumulative(whole)
        edges = [cumul[b] for b in bounds]
    trunk['lengthKm'] = round(
        sum(geo.line_length(p) for p in trunk['intervals']) / 1000.0, 3)
    if changed:
        trunk['needsRegroom'] = True
    return True


def branch_geometry_tolerance(*rail_lines):
    profiles = {line.get('profile') for line in rail_lines}
    if profiles & {'street', 'metro'}:
        return 60.0
    if profiles & {'commuter', 'regional'}:
        return 150.0
    return 200.0


def fresh_station_order(line, trunk_stations):
    return tuple(station for station in line['stationIds']
                 if station not in trunk_stations)


def branch_geometries_equivalent(a, b, share=0.9):
    tolerance = branch_geometry_tolerance(a, b)

    def coverage(source, reference):
        index = geo.ReferenceIndex(cell_deg=0.02)
        for piece in reference['intervals']:
            if piece and len(piece) > 1:
                index.add_line(piece)
        checked = close = 0
        for piece in source['intervals']:
            for point in piece or ():
                checked += 1
                distance, _ = index.nearest(point, search_cells=2)
                if distance <= tolerance:
                    close += 1
        return checked > 0 and close / checked >= share

    return coverage(a, b) and coverage(b, a)


# ------------------------------------------------------------ station grouping

#: The words a feed adds to say which side of the track a platform is on.
#: They are not part of the station's name — a passenger arriving at "Bathurst
#: Station Eastbound Platform" has arrived at Bathurst — and a station group
#: that keeps one of them ends up named for whichever of its platforms the
#: builder happened to read first. `ca-official-aga-khan-park-museum-eastbound`
#: was the westbound platform too.
DIRECTION_WORDS = (r'north|south|east|west|northbound|southbound|eastbound|'
                   r'westbound|inbound|outbound|nb|sb|eb|wb|in|out|n|s|e|w')

DIRECTIONAL_TAIL = re.compile(
    r'[\s,\-–(/]+(?:%s)\b[\s\-–]*(?:bound\s*)?(?:platform|side|track|'
    r'stop|pl)?\s*\)?\s*$' % DIRECTION_WORDS, re.I)


def strip_directional(name):
    """A platform's name without the side of the track it names.

    Applied repeatedly because feeds stack the decorations — "Bloor Station -
    Northbound Platform" carries two — and only from the END, because a
    direction that leads is part of the name a passenger uses: North Station,
    West Bank, Southbound is a platform but South Station is a station.
    """
    text = (name or '').strip()
    for _ in range(3):
        stripped = DIRECTIONAL_TAIL.sub('', text).strip(' -–,(/')
        if stripped == text or not stripped:
            break
        text = stripped
    return text or (name or '').strip()


def normalise_station_name(name):
    text = strip_directional(name).lower()
    text = re.sub(r'\b(amtrak|via rail|via|station|stn|gare|depot|transit center|'
                  r'transit centre|rail|metro|subway|light rail|lrt|platform|'
                  r'terminal|departure|arrival)\b', ' ', text)
    text = re.sub(r'[^a-z0-9]+', ' ', text)
    return ' '.join(text.split())


def canonical_feed_parents(stops, identity_groups=(), near_m=200.0,
                           coordinate_near_m=0.0, identity_field=None):
    """Fold unparented directional platforms before pattern selection.

    Many North American feeds publish the two sides of one station as two
    stops with no ``parent_station``. If those platform ids survive into the
    stop sequence, an ordinary outbound/inbound pair looks like a single
    100-stop loop and the map draws every station twice. Equal normalized
    names within one platform-scale radius are one timing point; equal names
    farther apart remain distinct stations.
    """
    result = {}
    for group in identity_groups:
        members = [str(stop_id) for stop_id in group if str(stop_id) in stops]
        if members:
            canonical = members[0]
            for stop_id in members:
                result[stop_id] = canonical
    field_canonicals = {}
    if identity_field:
        published = sorted(
            (str(row.get(identity_field) or '').strip(),
             gtfs.parent_of(row, stops))
            for stop_id, row in stops.items()
            if str(row.get(identity_field) or '').strip())
        if not published:
            raise ValueError(
                f'official station identity field {identity_field!r} '
                'is absent or empty')
        for value, stop_id in published:
            field_canonicals.setdefault(value, stop_id)

    clusters = defaultdict(list)
    coordinate_clusters = []
    for stop_id, row in stops.items():
        if stop_id in result:
            continue
        explicit = gtfs.parent_of(row, stops)
        if explicit != stop_id:
            result[stop_id] = explicit
            continue
        field_value = (str(row.get(identity_field) or '').strip()
                       if identity_field else '')
        if field_value:
            result[stop_id] = field_canonicals[field_value]
            continue
        # A location_type=1 row is the operator's declared station identity,
        # not an unparented directional platform.  Two MTA station parents
        # called "14 St" are only 367 m apart but are different complexes;
        # name/proximity must never override those distinct official ids.
        if (row.get('location_type') or '').strip() == '1':
            result[stop_id] = stop_id
            continue
        try:
            point = [float(row['stop_lon']), float(row['stop_lat'])]
        except (KeyError, TypeError, ValueError):
            result[stop_id] = stop_id
            continue
        if coordinate_near_m > 0:
            nearest = min(
                ((geo.haversine(point, member_point), canonical)
                 for canonical, member_point in coordinate_clusters),
                default=None)
            if nearest is not None and nearest[0] <= coordinate_near_m:
                result[stop_id] = nearest[1]
                continue
        key = normalise_station_name(row.get('stop_name'))
        match = None
        for canonical, member_points in clusters[key]:
            # Name-only grouping is an intentionally conservative fallback,
            # not an identity graph.  Requiring the new stop to be close to
            # every existing member prevents a chain (or a star around the
            # first member) from growing a station whose opposite platforms
            # are farther apart than the reviewed platform-scale radius.
            if all(geo.haversine(point, member_point) <= near_m
                   for member_point in member_points):
                match = canonical
                member_points.append(point)
                break
        if match is None:
            match = stop_id
            clusters[key].append((match, [point]))
            coordinate_clusters.append((match, point))
        result[stop_id] = match
    return result


def official_transfer_complexes(stops, transfers):
    """Return station-parent -> complex id from an official GTFS transfer graph.

    This is deliberately opt-in at feed level.  ``transfers.txt`` can mean a
    walking interchange in a general GTFS feed, while operators such as MTA
    publish it as the authoritative graph of station complexes.  Prohibited
    transfers (type 3), missing stops and self edges provide no identity edge.

    Endpoints are first resolved through ``parent_station``.  The deterministic
    lexicographically smallest parent id names each connected component; that
    id is internal and never moves or replaces a line's physical station row.
    """
    edges = defaultdict(set)
    nodes = set()
    for row in transfers or ():
        if (row.get('transfer_type') or '').strip() == '3':
            continue
        source_id = (row.get('from_stop_id') or '').strip()
        target_id = (row.get('to_stop_id') or '').strip()
        source = stops.get(source_id)
        target = stops.get(target_id)
        if source is None or target is None:
            continue
        source_parent = gtfs.parent_of(source, stops)
        target_parent = gtfs.parent_of(target, stops)
        if not source_parent or not target_parent or source_parent == target_parent:
            continue
        nodes.update((source_parent, target_parent))
        edges[source_parent].add(target_parent)
        edges[target_parent].add(source_parent)

    result = {}
    unseen = set(nodes)
    while unseen:
        seed = min(unseen)
        stack = [seed]
        members = set()
        while stack:
            station = stack.pop()
            if station in members:
                continue
            members.add(station)
            stack.extend(edges.get(station, ()))
        unseen.difference_update(members)
        canonical = min(members)
        for station in members:
            result[station] = canonical
    return result


def canonical_group_name(members):
    """The one name a station group is called by, on every line that calls there.

    A group is assembled from as many names as it has platforms, and the
    package used to ship whichever one each line happened to carry: 658 of the
    two countries' 4,918 groups went out under two names or more, so the same
    station read differently depending on which train you had taken to it.
    Japan's package has nineteen such groups, and they are genuine
    alternates rather than one station described twice.

    The name that wins is the one the most platforms agree on, once the side
    of the track is taken off; ties go to the shortest, which is the one
    without the qualifier, and then to alphabetical order so the answer does
    not depend on the order the feeds were read in.
    """
    counts = Counter()
    for member in members:
        name = strip_directional(member['name'])
        if name:
            counts[name] += 1
    if not counts:
        return (members[0]['name'] if members else '')
    best = max(counts.items(), key=lambda kv: (kv[1], -len(kv[0]),
                                               [-ord(c) for c in kv[0]]))
    return best[0]


def group_stations(entries, near_m=140.0, name_near_m=400.0):
    """One dot per place, across operators — the packages' station groups.

    Within one feed the operator's own ``parent_station`` has already decided
    what a station is, and that decision is never second-guessed. Across feeds
    there is no shared identifier at all — Toronto Union is ``TWO`` to Amtrak,
    ``TRTO`` to VIA, ``UN`` to GO and ``14000`` to the TTC — so two rules
    stand in for one, and both must hold before two platforms become one
    station:

    * within ``near_m`` they are the same place whatever they are called, which
      is what merges an Amtrak platform and the subway box under it;
    * out to ``name_near_m`` they must ALSO carry the same name once the
      operator's decorations (“Amtrak”, “Station”, “Transit Center”) are
      removed.

    Beyond that nothing merges. Two stations of the same name a kilometre
    apart are two stations, and a group that swallowed both would put a train
    on the wrong side of the city.

    ## Why the name-blind rule is for OTHER operators only

    The first rule is written for the case where one place is described twice
    by two authorities that share no vocabulary, and it has to be name-blind
    because the two names genuinely differ: Amtrak's "Baltimore Penn Station"
    over MTA's "Penn-North". Applied *inside* one feed it says something quite
    different and quite wrong — that the operator does not know its own
    railway. A streetcar's stops are 100–150 m apart by design, so a name-blind
    140 m merge inside one feed collapses them: the Tampa Historic Streetcar
    shipped with stops #7, #8, #9 and #10 as a single dot named #10, and the
    McKinney Avenue Trolley lost fourteen of its thirty-five.

    So within one feed only the same official GTFS ``parent_station`` (or an
    explicitly enabled official transfer complex) merges. Equal names and
    proximity never override two different parent ids. Unparented directional
    platforms are folded earlier, before their parent identity reaches here.
    """
    cell = 0.006
    grid = defaultdict(list)
    groups = []
    official_identities = {}
    for entry in entries:
        lon, lat = entry['point']
        key = (int(lon / cell), int(lat / cell))
        best = None
        norm = normalise_station_name(entry['name'])
        feed = entry['line']['feed']
        identity = entry.get('identity') or entry.get('feedStop')
        exact = official_identities.get((feed, identity))
        if exact is not None:
            # The official parent/complex wins even when its several lines use
            # different names or anchors.  Anchors remain member properties;
            # this operation only assigns one package station code.
            best = (0.0, exact)
        else:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for gi in grid.get((key[0] + dx, key[1] + dy), ()):
                        group = groups[gi]
                        d = geo.haversine(entry['point'], group['point'])
                        if d > name_near_m:
                            continue
                        names_agree = bool(norm) and norm in group['norms']
                        # Within one feed only the same official GTFS parent or
                        # opted-in transfer complex is one station. Equal names
                        # and proximity cannot override distinct parent ids.
                        same_feed = [member for member in group['members']
                                     if member['line']['feed'] == feed]
                        if same_feed and all(
                                (member.get('identity') or member.get('feedStop'))
                                != identity for member in same_feed):
                            continue
                        if d > near_m and not names_agree:
                            continue
                        if best is None or d < best[0]:
                            best = (d, gi)
        if best is None:
            groups.append({'point': list(entry['point']), 'norm': norm,
                           'norms': {norm} if norm else set(),
                           'feeds': {feed},
                           'members': [entry], 'name': entry['name']})
            group_index = len(groups) - 1
            grid[key].append(group_index)
        else:
            group_index = best[1]
            group = groups[group_index]
            group['members'].append(entry)
            group['feeds'].add(feed)
            if norm:
                group['norms'].add(norm)
        official_identities[(feed, identity)] = group_index
    return groups


# ------------------------------------------------------------- border splitting

def split_line_by_country(line, countries, fallback):
    """One display line per country the railway runs through.

    Returns ``[(region, first_index, last_index), …]`` over the station list.
    Each station belongs only to its own country. The former one-station
    overlap put Canada's Niagara Falls in the US package and the US Niagara
    Falls in Canada's; it also duplicated Saint-Lambert under unrelated
    country-prefixed ids. Cross-border journeys join the two regional route
    sections explicitly and do not require either package to claim a foreign
    station.
    """
    codes = [countries.code_for(p[0], p[1], fallback) or fallback
             for p in line['anchors']]
    runs = split_runs(codes)
    if len(runs) <= 1:
        return [(codes[0] if codes else fallback, 0, len(line['anchors']) - 1)]
    out = []
    for code, first, last in runs:
        out.append((code, first, last))
    return out


def slice_line(line, first, last, region, suffix):
    piece = dict(line)
    piece['lineId'] = f"{line['lineId']}{suffix}"
    if line.get('branchOf'):
        piece['branchOf'] = f"{line['branchOf']}{suffix}"
    piece['stationIds'] = line['stationIds'][first:last + 1]
    piece['stationNames'] = line['stationNames'][first:last + 1]
    piece['stationZones'] = line['stationZones'][first:last + 1]
    piece['stationPoints'] = line['stationPoints'][first:last + 1]
    piece['anchors'] = line['anchors'][first:last + 1]
    piece['intervals'] = line['intervals'][first:last]
    piece['region'] = region
    piece['isLoop'] = line['isLoop'] and first == 0 and last == len(line['anchors']) - 1
    piece['lengthKm'] = round(
        sum(geo.line_length(p) for p in piece['intervals']) / 1000.0, 3)
    # A country slice can move the line into a different station-spacing band.
    # Recompute the compact geometry profile before serialization instead of
    # retaining the whole international service's profile.
    piece['needsRegroom'] = True
    return piece


# ------------------------------------------------------------------- assembly

def assemble(built, countries, options):
    """Split every line at the border, group the stations, and index the zones."""
    per_region = {'us': [], 'ca': []}
    for line in built:
        fallback = line.get('region') or 'us'
        runs = split_line_by_country(line, countries, fallback)
        if len(runs) == 1:
            code = runs[0][0]
            line['region'] = code
            per_region.setdefault(code, []).append(line)
            continue
        seen = Counter()
        for code, first, last in runs:
            if last - first < 1:
                continue
            seen[code] += 1
            suffix = f'-{code}' if seen[code] == 1 else f'-{code}{seen[code]}'
            per_region.setdefault(code, []).append(
                slice_line(line, first, last, code, suffix))
    return per_region


#: The same wall clock, named for the country it is being read in.
#:
#: A cross-border operator publishes one zone for its whole network: Amtrak
#: says ``America/New_York`` for Montréal Central and ``America/Los_Angeles``
#: for Vancouver's Pacific Central. The offsets and the daylight-saving rules
#: are identical either side of the border in each of these pairs, so nothing
#: about *when* a train runs changes — but a Canadian station's clock should
#: be named in Canada, because that is the name the interface prints and a
#: reader in Montréal should not be told they are on New York time.
ZONE_BY_COUNTRY = {
    'ca': {
        'America/New_York': 'America/Toronto',
        'America/Detroit': 'America/Toronto',
        'America/Chicago': 'America/Winnipeg',
        'America/Denver': 'America/Edmonton',
        'America/Los_Angeles': 'America/Vancouver',
    },
    'us': {
        'America/Toronto': 'America/New_York',
        'America/Montreal': 'America/New_York',
        'America/Winnipeg': 'America/Chicago',
        'America/Edmonton': 'America/Denver',
        'America/Vancouver': 'America/Los_Angeles',
    },
}


#: Time-zone identifiers a feed may still publish that the database keeps only
#: as links to their modern spelling. `TimeZone(identifier:)` resolves them, so
#: nothing would break — but the package carries the identifier a station is
#: LABELLED with, and a station labelled `Canada/Eastern` reads as a different
#: clock from the one next to it labelled `America/Toronto` when they are the
#: same clock. Canonicalised here so the package's zone table has one row per
#: clock.
ZONE_ALIASES = {
    'Canada/Eastern': 'America/Toronto',
    'Canada/Central': 'America/Winnipeg',
    'Canada/Saskatchewan': 'America/Regina',
    'Canada/Mountain': 'America/Edmonton',
    'Canada/Pacific': 'America/Vancouver',
    'Canada/Atlantic': 'America/Halifax',
    'Canada/Newfoundland': 'America/St_Johns',
    'America/Montreal': 'America/Toronto',
    'America/Indianapolis': 'America/Indiana/Indianapolis',
    'US/Eastern': 'America/New_York',
    'US/Central': 'America/Chicago',
    'US/Mountain': 'America/Denver',
    'US/Pacific': 'America/Los_Angeles',
    'US/Alaska': 'America/Anchorage',
    'US/Hawaii': 'Pacific/Honolulu',
    'US/Arizona': 'America/Phoenix',
}


def localise_zone(zone, region):
    zone = ZONE_ALIASES.get(zone, zone)
    zone = ZONE_BY_COUNTRY.get(region, {}).get(zone, zone)
    return ZONE_ALIASES.get(zone, zone) or 'America/New_York'


def station_entries(region_lines, region):
    out = []
    for line in region_lines:
        for i, sid in enumerate(line['stationIds']):
            identity = (line.get('stationComplexByStop') or {}).get(sid, sid)
            out.append({
                'feedStop': sid,
                'identity': identity,
                'name': line['stationNames'][i],
                'point': line['anchors'][i],
                'published': line['stationPoints'][i],
                'zone': localise_zone(
                    line['stationZones'][i] or line['agencyTimezone'], region),
                'line': line,
                'index': i,
            })
    return out


def collapse_repeats(line, station_codes, station_names):
    """Fold a station this line calls at twice running into one call.

    Two platforms of one station are one station group — that is what the
    grouping is for — and a line that calls at both then carries the group's
    code twice in a row: SEPTA's Norristown High Speed Line lists Gulph Mills
    at index 17 and again at 18. The merge is right and the repeat is its
    consequence, so it is undone here, once the group codes are known and
    before the package is written.

    Two rows become one station and the two intervals they separated become
    one — the few metres between the two platforms welded to the hop beyond —
    which leaves the interval count the invariant expects for an open line and
    for a loop alike.
    """
    folded = 0
    i = 1
    while i < len(station_codes):
        if station_codes[i] != station_codes[i - 1]:
            i += 1
            continue
        intervals = line['intervals']
        if i < len(intervals):
            joined = ([list(p) for p in intervals[i - 1]]
                      + [list(p) for p in intervals[i][1:]])
            intervals[i - 1] = geo.dedupe(joined, 0.05)
            del intervals[i]
        elif intervals:
            del intervals[i - 1]
        for row in (station_codes, station_names, line['stationIds'],
                    line['stationNames'], line['stationZones'],
                    line['stationPoints'], line['anchors']):
            del row[i]
        folded += 1
    if folded:
        line['needsRegroom'] = True
        line['lengthKm'] = round(
            sum(geo.line_length(p) for p in line['intervals']) / 1000.0, 3)
    return folded


def groom_with_final_profile(intervals, max_passes=3):
    """Groom from the source geometry using the band the output itself needs.

    Grooming can shorten a median interval just across a band boundary (WMATA
    Red crossed 1,800 m), leaving the stored profile and chord cap coarser than
    the final line. Re-evaluate after each pass, but always groom the original
    geometry so the operation never compounds smoothing.
    """
    original = intervals
    band, _ = build.profile_for_line(original)
    groomed = build.groom(original, band)
    for _ in range(max_passes - 1):
        final_band, _ = build.profile_for_line(groomed)
        if final_band == band:
            break
        band = final_band
        groomed = build.groom(original, band)
    return groomed, band


def regroom_after_station_edits(line):
    """Recompute the geometry band after branch/station topology changed.

    Branch absorption can insert enough stops to turn a commuter-scale trunk
    into a metro-scale display line. Keeping the old band leaves 220 m chords
    on a line whose final station spacing requires 160 m. Lines whose station
    topology did not change are left byte-for-byte alone.
    """
    if not line.pop('needsRegroom', False):
        return False
    line['intervals'], band = groom_with_final_profile(line['intervals'])
    line['anchors'] = ([list(line['intervals'][0][0])]
                       + [list(piece[-1]) for piece in line['intervals']])
    if line.get('isLoop'):
        line['anchors'] = line['anchors'][:len(line['stationIds'])]
    line['profile'] = band.name
    line['lengthKm'] = round(
        sum(geo.line_length(piece) for piece in line['intervals']) / 1000.0, 3)
    return True


def validate_line_chain(line, tolerance_m=1.0):
    """Return structural geometry faults that compact-v1 cannot represent.

    A continuation row omits its first vertex; both clients restore that
    vertex from the station anchor.  If an internal interval starts somewhere
    else, serialization turns the gap into a direct chord and the solver's
    raw section geometry disagrees with the displayed package.  Refuse that
    state before either artifact is written.
    """
    intervals = line.get('intervals') or []
    anchors = line.get('anchors') or []
    expected = len(anchors) if line.get('isLoop') else max(0, len(anchors) - 1)
    faults = []
    if len(intervals) != expected:
        faults.append(f'interval count {len(intervals)} != {expected}')
        return faults
    for index, piece in enumerate(intervals):
        if not piece or len(piece) < 2:
            faults.append(f'interval {index} has fewer than two vertices')
            continue
        start = anchors[index]
        end = anchors[(index + 1) % len(anchors)]
        start_gap = geo.haversine(start, piece[0])
        end_gap = geo.haversine(end, piece[-1])
        if start_gap > tolerance_m or end_gap > tolerance_m:
            faults.append(
                f'interval {index} endpoint gap {start_gap:.1f}/{end_gap:.1f} m')
        length = geo.line_length(piece)
        if length <= tolerance_m:
            faults.append(f'interval {index} is only {length:.2f} m')
    return faults


def snap_tiny_chain_gaps(line, maximum_m=3.0):
    """Close rounding-scale seams without concealing a routing error.

    A compact-v1 interval is anchored to the published station at both ends.
    Grooming and branch edits can leave the final source vertex a metre or two
    away from that already-known anchor.  Moving only that endpoint is exact,
    deterministic, and smaller than the coordinate precision visible on the
    map.  Anything larger remains a release blocker: it may be the wrong rail,
    a missing branch, or a station projected onto another track.
    """
    repaired = []
    anchors = line.get('anchors') or ()
    for index, piece in enumerate(line.get('intervals') or ()):
        if not piece or len(piece) < 2 or not anchors:
            continue
        start = anchors[index]
        end = anchors[(index + 1) % len(anchors)]
        start_gap = geo.haversine(start, piece[0])
        end_gap = geo.haversine(end, piece[-1])
        if 1.0 < start_gap <= maximum_m:
            piece[0] = list(start)
            repaired.append((index, 'start', start_gap))
        if 1.0 < end_gap <= maximum_m:
            piece[-1] = list(end)
            repaired.append((index, 'end', end_gap))
    return repaired


def serialized_intervals(line):
    """The exact six-decimal polylines decoded by compact-v1 clients."""
    anchors = line['anchors']
    out = []
    for index, piece in enumerate(line['intervals']):
        rounded = [[round(point[0], 6), round(point[1], 6)] for point in piece]
        rounded[0] = [round(anchors[index][0], 6),
                      round(anchors[index][1], 6)]
        end = anchors[(index + 1) % len(anchors)]
        rounded[-1] = [round(end[0], 6), round(end[1], 6)]
        out.append(rounded)
    return out


def max_endpoint_chord_deviation(points):
    """Largest distance from a polyline to its endpoint chord."""
    if len(points) < 3:
        return 0.0
    a, b = points[0], points[-1]
    return max(geo.point_segment_distance(point, a, b)[0]
               for point in points[1:-1])


def piece_is_station_chord(piece, start, end, minimum_m=450.0,
                           maximum_deviation_m=2.0):
    """Whether densification is the only detail between two station points."""
    if not piece or len(piece) < 2:
        return False
    drawn = geo.line_length(piece)
    direct = geo.haversine(start, end)
    # The public package rounds coordinates to six decimals.  Keep a small
    # margin above its 1.5 m audit threshold because rounding can reduce a raw
    # 1.50–2.00 m deviation enough to turn the shipped interval into a chord.
    return (drawn > minimum_m and direct > 0
            and drawn <= direct * 1.005
            and max_endpoint_chord_deviation(piece) <= maximum_deviation_m)


def suspicious_straight_intervals(line):
    """Station pairs whose 'alignment' is only a densified endpoint chord.

    Densification caps renderer edge length; it does not add geographic
    information. A 64 km chord with 108 collinear points is still one guessed
    line between stations and must fail the same way as a two-point chord.
    """
    band = next((row for row in profile.BANDS
                 if row.name == line.get('profile')), profile.BANDS[2])
    anchors = line.get('anchors') or ()
    found = []
    for index, piece in enumerate(line.get('intervals') or ()):
        if len(piece) < 2 or index + 1 >= len(anchors):
            continue
        drawn = geo.line_length(piece)
        # Leave headroom for six-decimal package serialization: an interval
        # just below 500 m here can round to just above the public audit's
        # 500 m threshold.  The profile factor gets the same 10% safety margin.
        if (drawn > max(450.0, band.max_edge_m * 1.8)
                and piece_is_station_chord(piece, anchors[index],
                                            anchors[index + 1])):
            found.append(index)
    return found


def filter_unresolved_geometry(region_lines, options):
    """Fail closed on direct chords and on branches orphaned by that refusal."""
    blocked = set()
    blocked_roots = set()
    for line in region_lines:
        # A straight segment in a government/operator surveyed centreline is
        # physical evidence, not an interpolated station chord.  The source
        # earns this exception only after endpoint identity and both raw and
        # normalized hashes have been verified from the official manifest.
        verified = getattr(options, 'verified_official_sources', {})
        intervals = ([] if line.get('geometrySource') in verified
                     else suspicious_straight_intervals(line))
        if not intervals:
            continue
        blocked.add(id(line))
        key = (line.get('feed'), line.get('sourceRouteId'))
        if not line.get('branchOf'):
            blocked_roots.add(key)
        options.geometry_blockers.append({
            'line': line['lineId'], 'feed': line.get('feed'),
            'why': 'densified station-to-station chord is not an alignment',
            'intervals': intervals,
            'geometrySource': line.get('geometrySource'),
        })
        print(f"  refused {line['lineId']}: {len(intervals)} direct station "
              f"chord{'s' if len(intervals) != 1 else ''}", file=sys.stderr)

    kept = []
    for line in region_lines:
        if id(line) in blocked:
            continue
        key = (line.get('feed'), line.get('sourceRouteId'))
        if line.get('branchOf') and key in blocked_roots:
            options.geometry_blockers.append({
                'line': line['lineId'], 'feed': line.get('feed'),
                'why': 'branch suppressed because its trunk failed geometry review',
            })
            continue
        kept.append(line)
    return kept


def build_region(region, region_lines, options, reference):
    # Border slicing changes station spacing and therefore the grooming band.
    # Do that before the station-chord release gate: grooming can expose that
    # an apparently detailed short interval contains no information beyond its
    # endpoints.
    for line in region_lines:
        if regroom_after_station_edits(line):
            print(f"  {line['lineId']}: recomputed {line['profile']} grooming "
                  'after regional slicing', file=sys.stderr)
    region_lines = filter_unresolved_geometry(region_lines, options)
    entries = station_entries(region_lines, region)
    groups = group_stations(entries)
    codes = {}
    group_meta = []
    used = set()
    names = {}
    for group in groups:
        group['name'] = canonical_group_name(group['members'])
        base = slugify(normalise_station_name(group['name']) or group['name'], 'stn')
        code = f'{region}-official-{base}'
        n = 1
        while code in used:
            n += 1
            code = f'{region}-official-{base}-{n}'
        used.add(code)
        group_meta.append({'code': code, 'name': group['name'],
                           'point': group['point'], 'members': group['members']})
        for member in group['members']:
            codes[(id(member['line']), member['index'])] = code
            # Every line that calls here calls it by the group's name. The
            # coordinate stays each line's own — a station is anchored onto
            # the alignment of the railway that serves it — but the NAME is a
            # property of the place, not of the train you arrived on.
            names[(id(member['line']), member['index'])] = group['name']

    zones = []
    zone_index = {}

    def zone_of(name):
        name = name or 'America/New_York'
        if name not in zone_index:
            zone_index[name] = len(zones)
            zones.append(name)
        return zone_index[name]

    package_lines = []
    sections = []
    station_features = []
    checks = {}
    for line in region_lines:
        n = len(line['stationIds'])
        station_codes = [codes[(id(line), i)] for i in range(n)]
        station_names = [names[(id(line), i)] for i in range(n)]
        folded = collapse_repeats(line, station_codes, station_names)
        if folded:
            print(f"  {line['lineId']}: folded {folded} repeated station call"
                  f"{'s' if folded > 1 else ''}", file=sys.stderr)
            n = len(station_codes)
        if regroom_after_station_edits(line):
            print(f"  {line['lineId']}: recomputed {line['profile']} grooming "
                  'after station topology changed', file=sys.stderr)
        verified = getattr(options, 'verified_official_sources', {})
        late_chords = ([] if line.get('geometrySource') in verified
                       else suspicious_straight_intervals(line))
        if late_chords:
            options.geometry_blockers.append({
                'line': line['lineId'], 'feed': line.get('feed'),
                'why': ('station grouping exposed a densified '
                        'station-to-station chord'),
                'intervals': late_chords,
                'geometrySource': line.get('geometrySource'),
            })
            print(f"  refused {line['lineId']}: {len(late_chords)} direct "
                  'station chord after station grouping', file=sys.stderr)
            continue
        tiny_repairs = snap_tiny_chain_gaps(line)
        if tiny_repairs:
            largest = max(row[2] for row in tiny_repairs)
            print(f"  {line['lineId']}: snapped {len(tiny_repairs)} compact-v1 "
                  f"endpoint seam{'s' if len(tiny_repairs) > 1 else ''} "
                  f"(max {largest:.1f} m)", file=sys.stderr)
        chain_faults = validate_line_chain(line)
        if chain_faults:
            blocker = {
                'line': line['lineId'], 'feed': line.get('feed'),
                'why': 'compact-v1 geometry invariant failed',
                'faults': chain_faults,
            }
            options.geometry_blockers.append(blocker)
            print(f"  refused {line['lineId']}: " + '; '.join(chain_faults),
                  file=sys.stderr)
            continue
        encoded_intervals = serialized_intervals(line)
        rows = []
        for i in range(n):
            rows.append([station_codes[i], station_names[i],
                         round(line['anchors'][i][0], 6),
                         round(line['anchors'][i][1], 6),
                         station_names[i], 3,
                         zone_of(localise_zone(
                             line['stationZones'][i] or line['agencyTimezone'],
                             region))])
        entry = {
            'id': line['lineId'],
            'name': line['name'],
            'nameNorm': line['name'],
            'operator': line['operator'],
            'sourceFeed': line.get('feed'),
            'branchOf': line.get('branchOf'),
            'operatorShort': line.get('operatorShort'),
            'operatorLogo': line.get('operatorLogo'),
            'brandStatus': line.get('brandStatus'),
            'kind': line['kind'],
            'geometrySource': line['geometrySource'],
            'smoothingProfile': line['profile'],
            'lengthKm': line['lengthKm'],
            'rank': line['rank'],
            'color': line['color'],
            'nameRoma': line['name'],
            'stations': rows,
            'segments': build.segments_for(encoded_intervals, line['anchors']),
            'colorReference': line['colorReference'],
            'colorSource': line['colorSource'],
            'colorDark': line['colorDark'],
        }
        # Keep compact-v1 sparse: an absent audited mark is different from an
        # empty path, and optional display metadata should cost no bytes when
        # it is unavailable.
        if not entry['operatorShort']:
            entry.pop('operatorShort')
        if not entry['branchOf']:
            entry.pop('branchOf')
        if not entry['operatorLogo']:
            entry.pop('operatorLogo')
        if not entry['brandStatus']:
            entry.pop('brandStatus')
        if line['isLoop']:
            entry['isLoop'] = 1
        if line['kind'] == 'highspeed':
            entry['isHSR'] = 1
        package_lines.append(entry)

        if reference is not None:
            checks[line['lineId']] = reference.measure(
                line['intervals'], line['geometrySource'])

        # Solver sections are generated from the exact rounded geometry the
        # clients decode, not from a higher-precision pre-serialization copy.
        # That makes package display and route solving byte-for-byte congruent.
        for i, piece in enumerate(encoded_intervals):
            if not piece or len(piece) < 2:
                continue
            sections.append({
                'type': 'Feature',
                'properties': {
                    'railway_class_code': line['class'],
                    'institution_type_code': line['institution'],
                    'line_name': line['name'],
                    'operator': line['operator'],
                },
                'geometry': {'type': 'LineString',
                             'coordinates': [[round(x, 6), round(y, 6)]
                                             for x, y in piece]},
            })
        for i in range(n):
            anchor = line['anchors'][i]
            # A station's own geometry is the metre or two of track it stands
            # on, which is what Japan's N02 supplies for every station and what
            # the solver's station index measures against. Taken from the
            # interval leaving the station, or — at a terminus — from the one
            # arriving at it.
            neighbour = anchor
            if i < len(line['intervals']) and len(line['intervals'][i]) > 1:
                neighbour = line['intervals'][i][1]
            elif i > 0 and len(line['intervals'][i - 1]) > 1:
                neighbour = line['intervals'][i - 1][-2]
            station_features.append({
                'type': 'Feature',
                'properties': {
                    'railway_class_code': line['class'],
                    'institution_type_code': line['institution'],
                    'line_name': line['name'],
                    'operator': line['operator'],
                    'station_name': station_names[i],
                    # Per OPERATOR, not per line: the same platform serves
                    # several of an operator's routes and is one platform, so
                    # a code that carried the line would give it as many
                    # identities as there are services calling at it. This is
                    # the shape Taiwan's TDX StationUID already has, and the
                    # region prefix is what lets `Region.fromStationCode` place
                    # a journey without opening a dataset.
                    'n02_station_code':
                        f"{region.upper()}-{line['feed'].upper()}"
                        f"-{slugify(line['operator']).upper()}"
                        f"-{line['stationIds'][i]}-{station_codes[i].upper()}",
                    'n02_group_code': station_codes[i],
                    'display_point': [round(anchor[0], 6), round(anchor[1], 6)],
                    'time_zone': localise_zone(
                        line['stationZones'][i] or line['agencyTimezone'], region),
                },
                'geometry': {'type': 'LineString',
                             'coordinates': [[round(anchor[0], 6), round(anchor[1], 6)],
                                             [round(neighbour[0], 6),
                                              round(neighbour[1], 6)]]},
            })
    return {
        'lines': package_lines,
        'zones': zones,
        'sections': sections,
        'stationFeatures': station_features,
        'groups': group_meta,
        'checks': checks,
    }


def readings_for(station_features, region):
    by_code = {}
    by_name = {}
    for feature in station_features:
        props = feature['properties']
        name = props['station_name']
        row = {'name': name, 'zh_Hant': '', 'zh_Hans': '', 'ja': '', 'en': name}
        existing = by_code.get(props['n02_station_code'])
        if existing is not None and existing['name'] != name:
            raise RuntimeError(
                f"source station identity {props['n02_station_code']} maps to "
                f"both {existing['name']!r} and {name!r}")
        by_code[props['n02_station_code']] = row
        by_code.setdefault(props['n02_group_code'], row)
        by_name.setdefault(name, row)
    return {
        'note': ('United States and Canada station names as their operators publish '
                 'them, for the four interface languages. English is the official '
                 'name; no Chinese or Japanese name is invented where an operator '
                 'publishes none, so those stay empty and the interface falls back '
                 'to the official name.'),
        'country': region.upper(),
        'languages': ['zh-Hant', 'zh-Hans', 'ja', 'en'],
        'packageVersion': PACKAGE_VERSION,
        'sources': ['operator GTFS (stops.txt stop_name)'],
        'stats': {'byCode': len(by_code), 'byName': len(by_name)},
        'byCode': by_code,
        'byName': by_name,
    }


# ------------------------------------------------------------------ reference

class CrossCheck:
    """The two independent opinions a built line is measured against.

    The FRA network for anything on mainline track, OpenStreetMap for the
    street and transit track the FRA does not survey. A source is never allowed
    to verify geometry built from itself: NARN-routed lines are checked only
    against OSM, and OSM fallback lines only against NARN. Operator GTFS shapes
    may be checked against either because both are independent of the feed.

    Reported per line: the worst disagreement, how many vertices found no
    reference at all, and which source answered. A line where nothing answers
    is not rejected — a brand-new light-rail extension is genuinely absent from
    both — but it is counted, and the count is in the package.
    """

    def __init__(self, network, osm, official=None):
        self.network = network
        self.osm = osm
        self.official = official

    def measure(self, intervals, geometry_source, sample_every=3,
                unmatched_m=400.0):
        worst = 0.0
        worst_at = None
        checked = unmatched = 0
        sources = Counter()
        for piece in intervals:
            if not piece:
                continue
            for i in range(0, len(piece), sample_every):
                point = piece[i]
                checked += 1
                best = float('inf')
                source = None
                if self.network is not None and geometry_source != 'narn':
                    for edge in self.network.edges_near(point, 1):
                        pts = self.network.edges[edge][2]
                        d, _, _, _, _ = geo.project_to_line(point, pts)
                        if d < best:
                            best, source = d, 'narn'
                if (self.osm is not None and self.osm.way_count
                        and geometry_source != 'osm'):
                    d, _ = self.osm.nearest(point, 1)
                    if d < best:
                        best, source = d, 'osm'
                if self.official is not None:
                    d, tag = self.official.nearest(point, 2)
                    if d < best:
                        best, source = d, tag
                if best > unmatched_m or source is None:
                    unmatched += 1
                    continue
                sources[source] += 1
                if best > worst:
                    worst, worst_at = best, [round(point[0], 6), round(point[1], 6)]
        return {
            'vertices': checked,
            'unmatched': unmatched,
            'maxDeviationMeters': round(worst, 2),
            'worstAt': worst_at,
            'agreedWith': dict(sources),
            'builtFrom': geometry_source,
            'independent': True,
        }


OSM_OPERATOR_EQUIVALENTS = {
    'alstom': 'go transit',
    'pittsburgh regional transit': 'pittsburgh regional transit',
    'prt': 'pittsburgh regional transit',
    'société de transport de montréal': 'société de transport de montréal',
    'denver transit partners': 'regional transportation district',
    'regional transportation district': 'regional transportation district',
    'city and county of honolulu': 'dts',
    'bombardier technology': 'florida department of transportation',
    'regional transportation authority of middle tennessee': 'wego public transit',
    'staten island rapid transit operating authority': 'mta',
    'metropolitan transit system': 'mts',
    'kenosha area transit': 'city of kenosha',
    'the loop trolley company': 'loop trolley',
    'm-1 rail': 'qline detroit',
    'mata': 'memphis area transit authority',
    'rtd': 'regional transportation district',
    'rta': 'new orleans regional transit authority',
}
OSM_ROUTE_EQUIVALENTS = {
    ('transdev', 'the hop'): 'city of milwaukee',
    ('transdev', 'connector'): 'metro',
    ('transdev', 'l-line'): 'sound transit',
}


#: How close two OpenStreetMap stop nodes have to be to be the same platform.
#: Generous, because one relation's stop node is on the track and another's is
#: on the platform beside it, and because a large interchange is a hundred
#: metres end to end.
OSM_SHARED_STOP_M = 150.0

#: How close an OpenStreetMap stop has to be to a station an operator's own
#: feed publishes for the two to be the same station, and how much of a
#: relation has to coincide that way before it is the railway a feed already
#: built. Measured rather than chosen: at 250 m every one of the twelve PATH
#: relations in the extract coincides with a PATH feed line at 1.00, and the
#: highest score any railway that IS a genuine gap reaches is 0.50 — Orlando's
#: Terminal Link against Brightline's station under the same terminal. The
#: margin between those two numbers is the whole safety of the rule.
OSM_ALREADY_BUILT_M = 250.0
OSM_ALREADY_BUILT_SHARE = 0.75

#: How far a station may be from every station of the line an OpenStreetMap
#: line is accused of restating before that accusation is refused. Deliberately
#: an order of magnitude looser than `OSM_ALREADY_BUILT_M`: it is not matching
#: stations, it is asking whether the two lines contradict each other outright
#: about where the railway goes. See `reaches_beyond`.
OSM_DUPLICATE_REACH_M = 1_000.0


def adopt_unattributed(routes):
    """Give a route relation that names no operator the one that runs it.

    A ``route=subway`` relation is not obliged to carry an ``operator`` or a
    ``network`` tag, and five of the Montréal métro's eight do not: the green
    line in both directions, the orange line to Montmorency and the yellow
    line in both directions. Grouped by operator name alone they were not
    merely unattributed, they were invisible — three métro lines shipped and
    half the network did not.

    A relation that calls at the same platforms as one that does name its
    operator is that operator's railway; sharing a platform is most of what a
    station is. Only from relations that name an operator, so the attribution
    always traces back to a tag somebody wrote.

    There are two ways to be sure enough, and the second exists because the
    first was not enough for the very network this function was written for.

    1. **A majority of its stops are that operator's.** The safe case, and the
       one a line passing through somebody else's interchange cannot reach.
       It carries the orange line to Montmorency, which shares all thirty-one
       of its stops with the orange line to Côte-Vertu.

    2. **Every operator it touches at all is the same one, and it is the same
       kind of railway.** A métro line meets its own siblings only where they
       interchange: the green line shares two of its twenty-seven stops with
       STM's tagged blue and orange relations, and the yellow line one of its
       three. Under the majority rule alone those four relations — the green
       line in both directions and the yellow line in both directions — were
       adopted by nobody, stayed unattributed, and were dropped, so
       `ca-2025.json` had the orange and blue lines and no others.

       Unanimity is what makes the weaker evidence safe: an unattributed
       relation that runs through another operator's territory touches that
       other operator too, and a split vote is refused. Over the whole
       continent's extract — 242 relations — exactly five unattributed
       relations share a platform with any attributed one, all five vote
       only for the Société de transport de Montréal, and all five are
       ``route=subway`` as STM's own three are. Nothing else on the continent
       is adopted by either rule.

    Adoption never cascades: the platforms are collected from the relations
    that were tagged before any of this ran, so an adopted operator cannot
    become evidence for adopting something else.
    """
    cell = 0.002
    buckets = defaultdict(set)
    kinds = defaultdict(set)
    for route in routes:
        operator = (route['operator'] or '').strip()
        if not operator:
            continue
        kinds[operator].add(route['kind'])
        for station in route['stations']:
            lon, lat = station['point']
            buckets[(int(lon / cell), int(lat / cell))].add((operator, lon, lat))
    if not buckets:
        return
    for route in routes:
        if (route['operator'] or '').strip():
            continue
        votes = Counter()
        for station in route['stations']:
            lon, lat = station['point']
            kx, ky = int(lon / cell), int(lat / cell)
            near = set()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for operator, olon, olat in buckets.get((kx + dx, ky + dy), ()):
                        if geo.haversine([lon, lat], [olon, olat]) <= OSM_SHARED_STOP_M:
                            near.add(operator)
            votes.update(near)
        if not votes:
            continue
        operator, shared = votes.most_common(1)[0]
        majority = shared * 2 > len(route['stations'])
        unanimous = len(votes) == 1 and route['kind'] in kinds[operator]
        if majority or unanimous:
            route['operator'] = operator


def drop_osm_duplicates(built, reports=None, tolerance_m=150.0, share=0.85):
    """Remove an OpenStreetMap line that runs where an operator's own line does.

    The last of the three tests that ask this question, and the only one that
    asks it of drawn geometry. `build_osm_systems` declines a route whose
    OPERATOR is one of a built line's, `refuse_already_built` declines one
    whose STOPS are a built line's, and both of those run before anything is
    routed; this one runs on the finished lines, where a railway that neither
    of them recognised has nowhere left to hide.

    ``build_osm_systems`` already declines a route whose OPERATOR is one of a
    built line's, and that test is the right one — but it is a test on a name,
    and names are where this fails. A system is very often published by one
    body and operated under contract by another: Cleveland's Red Line is
    "Greater Cleveland Regional Transit Authority" in its own feed and "GCRTA"
    in OpenStreetMap, the Canada Line is TransLink's and "InTransitBC"'s, the
    REM is "Réseau express métropolitain" and "Pulsar", Virginia Railway
    Express is "Keolis", Edmonton's Valley Line is "TransEd Partners". Each
    needs its own hand-written alias, none of them announces itself, and the
    day a feed is added for a system already taken from OpenStreetMap the
    package quietly draws that railway twice.

    So the last word is geometry, which needs no table and cannot go stale: an
    OpenStreetMap line ``share`` of whose vertices lie within ``tolerance_m``
    of a single operator-published line is that line, whatever the two call
    themselves, and the operator's own is the one that is kept.

    Deliberately NOT symmetric, and deliberately measured on the OSM line's own
    vertices. A short line inside a long one — the O'Hare people mover ends at
    a station on the Blue Line, the Denver Trolley shares two stops with the E
    Line — is not a duplicate of it, and testing "how much of the SHORT line is
    covered" is what tells those apart from a genuine restatement.

    That is not quite enough on its own, so `reaches_beyond` has a veto: a
    line that stops somewhere the other never goes is not a restatement of it
    however much track they share. Orlando's Terminal Link is the case that
    needed it.
    """
    survivors = []
    others = [line for line in built if not line['lineId'].startswith('osm-')]
    indexes = {}
    dropped = 0
    for line in built:
        if not line['lineId'].startswith('osm-'):
            survivors.append(line)
            continue
        points = [p for piece in line['intervals'] if piece for p in piece]
        if len(points) < 2:
            survivors.append(line)
            continue
        box = (min(p[0] for p in points), min(p[1] for p in points),
               max(p[0] for p in points), max(p[1] for p in points))
        duplicate = None
        for other in others:
            if other['region'] != line['region']:
                continue
            anchors = other['anchors']
            if (max(a[0] for a in anchors) < box[0] - 0.05
                    or min(a[0] for a in anchors) > box[2] + 0.05
                    or max(a[1] for a in anchors) < box[1] - 0.05
                    or min(a[1] for a in anchors) > box[3] + 0.05):
                continue
            index = indexes.get(other['lineId'])
            if index is None:
                index = geo.ReferenceIndex(cell_deg=0.02)
                for piece in other['intervals']:
                    if piece and len(piece) > 1:
                        index.add_line(piece)
                indexes[other['lineId']] = index
            close = sum(1 for p in points
                        if index.nearest(p, search_cells=2)[0] <= tolerance_m)
            if close >= share * len(points) and not reaches_beyond(line, other):
                duplicate = other
                break
        if duplicate is None:
            survivors.append(line)
            continue
        dropped += 1
        if reports is not None:
            osm_report(reports)['dropped'].append({
                'lineId': line['lineId'], 'name': line['name'],
                'operator': line.get('operator'),
                'why': f"drawn where {duplicate['lineId']} is, which its "
                       f"operator publishes"})
        print(f"  dropped {line['lineId']}: drawn where "
              f"{duplicate['lineId']} is", file=sys.stderr)
    if dropped:
        print(f'  dropped {dropped} OpenStreetMap lines an operator also publishes',
              file=sys.stderr)
    return survivors


def osm_report(reports):
    """The one report entry the OpenStreetMap path writes its refusals into.

    Every other system in this build has a report of its own because it has a
    feed of its own. The refusals below happen before a route has been grouped
    into a system at all — an attraction and a railway an operator already
    published are refused as ROUTES — so they need somewhere to be written
    down that is not any one system, and this is it. They are written down
    because a package that quietly contains fewer railways than its input is
    indistinguishable from one that lost them.
    """
    for report in reports:
        if report.get('slug') == 'osm-routes':
            return report
    report = {'slug': 'osm-routes', 'lines': 0, 'dropped': [], 'notes': [],
              'syntheticConnectors': 0}
    reports.append(report)
    return report


def refuse_already_built(routes, already, report):
    """Refuse an OpenStreetMap route for a railway a feed has already built.

    `build_osm_systems` decides what to build from the OPERATOR — a relation
    whose operator already appears on a built line is skipped — and that test
    can never be sufficient, for a reason that has nothing to do with stale
    inputs. The operator is a body, not a railway, and a body can be partly in
    the packages: the Port Authority of New York and New Jersey runs PATH,
    which publishes a GTFS feed and is built from it, AND AirTrain Newark,
    which publishes nothing and is exactly what this path is for. Refuse the
    operator and AirTrain Newark disappears; admit the operator and PATH is
    drawn twice, once from its own timetable and once from OpenStreetMap,
    under two names for one authority ("Port Authority of New York and New
    Jersey" against "Port Authority Trans-Hudson Corporation") that no alias
    table would have connected either.

    So the question is asked of the railway instead: a relation
    `OSM_ALREADY_BUILT_SHARE` of whose stops stand within
    `OSM_ALREADY_BUILT_M` of the stations of ONE already-built line is that
    line. The feed-built one wins, because it is the operator's own statement
    of where its trains stop and this is a photograph of the track.

    Against one line rather than against all of them, and measured on the
    OpenStreetMap relation's own stops, for the reason `drop_osm_duplicates`
    gives: a short railway that touches several long ones — AirTrain JFK calls
    at Jamaica and Howard Beach, both of which are subway stations — is not a
    restatement of any of them.

    Note what this deliberately does NOT do: it does not refuse a route
    because the registry contains a feed for its operator. When a feed is
    listed but its download failed, nothing was built from it, and refusing
    the OpenStreetMap relation as well would drop the railway out of the
    package altogether rather than draw it twice.
    """
    if not routes:
        return routes
    cell = OSM_ALREADY_BUILT_M / 111_000.0 * 2
    buckets = defaultdict(list)
    for line in already:
        for point in line.get('stationPoints') or ():
            buckets[(int(point[0] / cell), int(point[1] / cell))].append(
                (line['lineId'], point))
    kept = []
    for route in routes:
        votes = Counter()
        for station in route['stations']:
            lon, lat = station['point']
            kx, ky = int(lon / cell), int(lat / cell)
            near = set()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for line_id, point in buckets.get((kx + dx, ky + dy), ()):
                        if geo.haversine([lon, lat], point) <= OSM_ALREADY_BUILT_M:
                            near.add(line_id)
            votes.update(near)
        line_id, shared = votes.most_common(1)[0] if votes else (None, 0)
        if line_id and shared >= OSM_ALREADY_BUILT_SHARE * len(route['stations']):
            report['dropped'].append({
                'relation': route['relation'], 'name': route['name'],
                'operator': route['operator'],
                'why': f'already built from a feed as {line_id} '
                       f'({shared} of {len(route["stations"])} stops within '
                       f'{OSM_ALREADY_BUILT_M:.0f} m)'})
            print(f"  refused OSM relation {route['relation']} "
                  f"({route['name']}): already built as {line_id}",
                  file=sys.stderr)
            continue
        kept.append(route)
    return kept


def refuse_attractions(routes, report):
    """Refuse a route that runs inside a paid attraction.

    The rule is `na_attractions`', and the OpenStreetMap path is the third of
    the three callers that needed it — the first two were the feed registry
    and the coverage report, and this one had no such filter at all, which is
    how `ca-2025.json` came to ship the Fort Edmonton Park streetcar.

    Asked of the relation's operator AND its own name, which is what makes it
    a decision about a line rather than about a body. The Edmonton Radial
    Railway Society runs two tramways: one inside Fort Edmonton Park, one
    across the High Level Bridge between Whyte Avenue and Jasper Plaza, which
    is a public way of crossing Edmonton and stays.
    """
    kept = []
    for route in routes:
        term = na_attractions.matched_term(route['operator'], route['name'])
        if term:
            report['dropped'].append({
                'relation': route['relation'], 'name': route['name'],
                'operator': route['operator'],
                'why': f'inside a paid attraction: matched {term!r}'})
            print(f"  refused OSM relation {route['relation']} "
                  f"({route['name']}): attraction, matched {term!r}",
                  file=sys.stderr)
            continue
        kept.append(route)
    return kept


# A relation in this table has been checked against the named operator source
# and is known to encode a passenger service incorrectly. It is refused rather
# than "fixed" by guessing a station order. The audit report beside the package
# records the official evidence and the exact work required to admit it again.
OSM_KNOWN_INVALID_RELATIONS = {
    9599901: (
        'Rocky Mountaineer Rainforest to Gold Rush: OSM stop members are not '
        'in the operator-published journey order; see ca-2025.audit.md'),
}


def refuse_known_invalid(routes, report):
    kept = []
    for route in routes:
        why = OSM_KNOWN_INVALID_RELATIONS.get(route['relation'])
        if why is None:
            kept.append(route)
            continue
        report['dropped'].append({
            'relation': route['relation'], 'name': route['name'],
            'operator': route['operator'], 'why': why})
        print(f"  refused OSM relation {route['relation']} "
              f"({route['name']}): {why}", file=sys.stderr)
    return kept


def reaches_beyond(line, other, tolerance_m=OSM_DUPLICATE_REACH_M):
    """Whether ``line`` calls somewhere ``other`` never goes.

    The geometry test above is necessary and not sufficient, and Orlando is
    where that shows. The Terminal Link people mover runs from the main
    terminal to Terminal C along the same airport viaduct corridor that
    Brightline's tracks use to reach its Orlando platform, so every vertex of
    the two-kilometre people mover lies within a hundred and fifty metres of a
    line that runs to Miami. On geometry alone it is a restatement of
    Brightline. It is not: it stops at Terminal A/B, which is two kilometres
    from the nearest station Brightline has, and no amount of shared corridor
    makes a railway that goes somewhere else the same railway.

    So a station of ``line`` further than ``tolerance_m`` from every station of
    ``other`` is a veto. Generously far on purpose — this is not a station
    matcher and must not become one. It is asked only whether the two lines
    flatly contradict each other about where the railway goes, so the distance
    has to be one that no pair of names for one station could ever reach.
    """
    theirs = other.get('stationPoints') or ()
    if not theirs:
        return False
    return any(all(geo.haversine(mine, point) > tolerance_m for point in theirs)
               for mine in line.get('stationPoints') or ())


def build_osm_systems(options, countries, network, already, reports):
    """Build the railways that reach the packages only through OpenStreetMap.

    Which ones is decided here rather than listed: every route relation in the
    extracts whose operator is not already an operator of a built line. That
    is the same test `report-na-coverage.py` applies, so a railway leaves this
    path the day its operator publishes a feed — nobody has to remember to
    take it out.

    Three refusals stand between the extracts and a display line, and each is
    here because the extracts contain things the packages must not:

    * `refuse_attractions` — a ride inside a paid attraction is not transport;
    * `refuse_already_built` — a railway an operator's own feed already built
      must not be drawn a second time from a photograph of its track;
    * `na_osmlines.fold_directions` — a railway published as one relation per
      direction is one line, not two.

    Grouped by operator so that one system is one builder, which is what makes
    the ids, the station codes and the duplicate-branch folding behave the way
    they do for a feed. The fold is per operator group for the same reason:
    the question it asks — "is this the other direction of that?" — is only
    ever meaningful between two relations of one system.
    """
    routes = na_osmlines.load_dir(options.osm_routes)
    if not routes:
        return []
    report = osm_report(reports)
    covered = {line['operator'].lower() for line in already if line.get('operator')}
    adopt_unattributed(routes)
    routes = refuse_known_invalid(routes, report)
    routes = refuse_attractions(routes, report)
    routes = refuse_already_built(routes, already, report)
    systems = defaultdict(list)
    for route in routes:
        operator = (route['operator'] or '').strip()
        equivalent = OSM_OPERATOR_EQUIVALENTS.get(operator.lower(),
                                                   operator.lower())
        route_name = (route.get('name') or '').lower()
        for (candidate, fragment), owner in OSM_ROUTE_EQUIVALENTS.items():
            if operator.lower() == candidate and fragment in route_name:
                equivalent = owner
                break
        if not operator or equivalent in covered:
            continue
        systems[operator].append(route)

    for operator, group in systems.items():
        kept, folded = na_osmlines.fold_directions(group)
        systems[operator] = kept
        for loser, winner in folded:
            report['dropped'].append({
                'relation': loser['relation'], 'name': loser['name'],
                'operator': operator,
                'why': f"the other direction of relation {winner['relation']} "
                       f"({winner['name']})"})
        if folded:
            print(f'  {operator}: folded {len(folded)} direction relations '
                  f'into {len(kept)} railways', file=sys.stderr)

    out = []
    for operator, group in sorted(systems.items(), key=lambda kv: -len(kv[1])):
        slug = 'osm-' + slugify(operator, 'system')[:26]
        region = country_of(group, countries)
        entry = {'slug': slug, 'name': operator, 'region': region, 'mdb': None,
                 'timezone': None}
        builder = OsmBuild(entry, group, countries, network, options)
        try:
            produced = builder.run()
        except Exception as exc:                            # noqa: BLE001
            builder.report['notes'].append(f'{type(exc).__name__}: {exc}')
            produced = []
        for line in produced:
            line['region'] = region
        out += produced
        reports.append(builder.report)
        print(f'  {slug}: {len(produced)} lines from OpenStreetMap',
              file=sys.stderr)
    return out


def country_of(routes, countries):
    """Which package an OpenStreetMap-only system belongs to.

    Its first stop's country, taken from the FRA network's own attribution the
    same way every other station's is. A system with no track near it — a
    people mover inside an airport — falls back to the United States, which is
    where all but a handful of them are; the border split corrects any that
    are not, because it asks the same question per station afterwards.
    """
    for route in routes:
        for station in route['stations']:
            code = countries.code_for(station['point'][0], station['point'][1], None)
            if code:
                return code
    return 'us'


def synthetic_total(lines):
    """How many intervals in one country are straight lines between stations.

    Nought is what every other package family in this app reports, and it is
    what these two should converge on; anything above it is the number of
    station pairs for which neither the FRA network nor the operator's own
    alignment could say where the railway goes. It is in the package rather
    than in a build log because a reader of the data is entitled to know how
    much of it is drawn rather than surveyed.

    Count the assembled regional lines, not feed reports: the latter describe
    the whole two-country build and previously wrote Pittsburgh's two incline
    chords into both the US and Canadian package metadata even though neither
    incline is in Canada.
    """
    return sum(len(line.get('intervals') or ())
               for line in lines
               if line.get('geometrySource') == 'station-chord')


def load_osm(sources):
    track = na_osm.Track()
    for name in ('osm', 'osm-geom', 'osm-routes'):
        track.load_dir(os.path.join(sources, name))
    return track


def load_osm_relation_shapes(path):
    """Surveyed route-member geometry keyed by explicitly audited relation id.

    Unlike ``na_osmlines.load_dir``, this loader does not require stop members:
    the Pittsburgh incline relations contain precise track ways but no stop
    nodes. Their station identity and order come from PRT's official GTFS; the
    registry pins only those two route IDs to the corresponding OSM relation.
    """
    out = {}
    if not path or not os.path.isdir(path):
        return out
    for name in sorted(os.listdir(path)):
        if not name.endswith(('.json', '.json.gz')):
            continue
        full = os.path.join(path, name)
        opener = gzip.open if name.endswith('.gz') else open
        try:
            with opener(full, 'rt', encoding='utf-8') as source:
                elements = json.load(source).get('elements') or []
        except (OSError, ValueError):
            continue
        ways = {}
        for element in elements:
            if element.get('type') != 'way':
                continue
            points = [[p['lon'], p['lat']]
                      for p in (element.get('geometry') or ())]
            if len(points) > 1:
                ways[element['id']] = points
        for relation in elements:
            if (relation.get('type') != 'relation'
                    or (relation.get('tags') or {}).get('type') != 'route'):
                continue
            parts = na_osmlines.merge_parts(
                na_osmlines.chain_ways(relation, ways))
            if parts:
                out[relation['id']] = max(parts, key=geo.line_length)
    return out


def load_official_geometry(sources):
    """Independent operator/government geometry not represented by NARN.

    Files are normalized extracts written by source-specific downloaders
    (currently ATI Puerto Rico). Keeping them separate from OSM preserves both
    provenance and the rule that a source never verifies itself.
    """
    index = geo.ReferenceIndex(cell_deg=0.02)
    directory = os.path.join(sources, 'official-geom')
    files = lines_count = 0
    if not os.path.isdir(directory):
        return index, files, lines_count
    for name in sorted(os.listdir(directory)):
        if not name.endswith(('.json', '.json.gz')):
            continue
        path = os.path.join(directory, name)
        opener = gzip.open if name.endswith('.gz') else open
        try:
            with opener(path, 'rt', encoding='utf-8') as source:
                payload = json.load(source)
        except (OSError, ValueError):
            continue
        tag = payload.get('sourceId') or os.path.splitext(name)[0]
        for points in payload.get('lines') or ():
            if len(points) > 1:
                index.add_line(points, tag=tag)
                lines_count += 1
        files += 1
    return index, files, lines_count


# ----------------------------------------------------------------------- main

def load_registry(path):
    with open(path) as fh:
        return json.load(fh)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def write_json(path, payload):
    tmp = path + '.tmp'
    with open(tmp, 'w') as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(', ', ': '))
    os.replace(tmp, path)
    return os.path.getsize(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source-dir', required=True)
    ap.add_argument('--registry', default=os.path.join(HERE, 'na-feeds.json'))
    ap.add_argument('--output-dir', default=os.path.join(HERE, '..', '..', 'public', 'rail'))
    ap.add_argument('--data-dir', default=os.path.join(HERE, '..', '..', 'data'))
    ap.add_argument('--cache-dir', default=None)
    ap.add_argument('--only', action='append', default=None)
    ap.add_argument('--corridor-m', type=float, default=1_500.0)
    ap.add_argument('--snap-m', type=float, default=3_000.0)
    ap.add_argument('--anchor-m', type=float, default=600.0)
    ap.add_argument('--max-trips-per-route', type=int, default=1500)
    ap.add_argument('--osm-routes', default=None,
                    help='directory of OpenStreetMap route extracts for the '
                         'railways no operator publishes a feed for')
    ap.add_argument('--skip-crosscheck', action='store_true')
    ap.add_argument('--report', default=None)
    options = ap.parse_args()

    registry = load_registry(options.registry)
    feeds = registry['feeds']
    feed_metadata = {entry['slug']: entry for entry in registry['feeds']}
    brand_audit_path = os.path.join(HERE, 'na-operator-brands.json')
    brand_audit = (load_registry(brand_audit_path)
                   if os.path.exists(brand_audit_path) else {})
    audited_unbranded = set((brand_audit.get('unbranded') or {}).keys())
    if options.only:
        wanted = set(options.only)
        feeds = [f for f in feeds if f['slug'] in wanted]

    started = time.time()
    features = list(iter_narn(options.source_dir))
    countries = NetworkCountries(features)
    network = narn.Network(features)
    del features
    print(f'FRA network: {len(network.edges)} edges, '
          f'{len(countries.buckets)} border cells ({time.time() - started:.1f}s)',
          file=sys.stderr)
    options.osm_relation_shapes = load_osm_relation_shapes(options.osm_routes)
    options.official_networks = {}
    options.verified_official_sources = {}
    requested_official = {entry.get('officialNetwork') for entry in feeds}
    official_endpoint_join_m = {}
    for entry in feeds:
        requested_official.update(
            (entry.get('officialNetworkByRouteId') or {}).values())
        join_m = float(entry.get('officialNetworkEndpointJoinMeters') or 0.0)
        if join_m:
            keys = set((entry.get('officialNetworkByRouteId') or {}).values())
            if entry.get('officialNetwork'):
                keys.add(entry['officialNetwork'])
            for key in keys:
                official_endpoint_join_m[key] = max(
                    official_endpoint_join_m.get(key, 0.0), join_m)
    requested_official.discard(None)
    if 'quebec-mtq-via' in requested_official:
        path = os.path.join(options.source_dir, 'quebec-rail.geojson')
        if os.path.exists(path):
            t = time.time()
            options.official_networks['quebec-mtq-via'] = \
                na_official.load_geojson(path, ('VIA', 'VIA/Amtrak'))
            official = options.official_networks['quebec-mtq-via']
            print(f'Québec MTQ VIA network: {len(official.points)} vertices '
                  f'({time.time() - t:.1f}s)', file=sys.stderr)
        else:
            print('Québec MTQ VIA network unavailable; VIA lines that NARN '
                  'cannot route safely will remain blocked', file=sys.stderr)
    official_directory = os.path.join(options.source_dir, 'official-networks')
    route_specific = requested_official - {'quebec-mtq-via'}
    verified, provenance_diagnostics = na_provenance.verify_route_networks(
        official_directory, route_specific)
    for diagnostic in provenance_diagnostics:
        print(diagnostic, file=sys.stderr)
    for key in sorted(requested_official - {'quebec-mtq-via'}):
        if key not in verified:
            print(f'{key}: official route network failed provenance review; '
                  'affected lines will remain blocked unless another audited '
                  'source can route them', file=sys.stderr)
            continue
        path = os.path.join(official_directory, f'{key}.geojson')
        if not os.path.exists(path):
            print(f'{key}: official route network unavailable; affected '
                  'lines will remain blocked unless another audited source '
                  'can route them', file=sys.stderr)
            continue
        t = time.time()
        network_for_route = na_official.load_geojson(
            path, None, endpoint_join_m=official_endpoint_join_m.get(key, 0.0))
        if not network_for_route.points:
            print(f'{key}: official route network is empty; affected lines '
                  'will remain blocked', file=sys.stderr)
            continue
        options.official_networks[key] = network_for_route
        options.verified_official_sources[key] = verified[key]
        print(f'{key}: {len(network_for_route.points)} official vertices '
              f'({len(network_for_route.joined_endpoints)} endpoint joins, '
              f'{time.time() - t:.1f}s)', file=sys.stderr)

    cache = options.cache_dir
    if cache:
        os.makedirs(cache, exist_ok=True)

    built = []
    reports = []
    for entry in feeds:
        path = cache and os.path.join(cache, f"{entry['slug']}.json")
        fingerprint = feed_cache_fingerprint(entry, options.source_dir)
        if path and os.path.exists(path):
            with open(path) as fh:
                payload = json.load(fh)
            if payload.get('fingerprint') == fingerprint:
                built.extend(payload['lines'])
                reports.append(payload['report'])
                print(f"  {entry['slug']}: {len(payload['lines'])} lines (cached)",
                      file=sys.stderr)
                continue
        t = time.time()
        builder = FeedBuild(entry, options.source_dir, countries, network, options)
        try:
            produced = builder.run()
        except Exception as exc:                       # noqa: BLE001
            builder.report['notes'].append(f'{type(exc).__name__}: {exc}')
            produced = []
        for line in produced:
            line['region'] = entry.get('region', 'us')
        built.extend(produced)
        reports.append(builder.report)
        if path:
            write_json(path, {'fingerprint': fingerprint, 'lines': produced,
                              'report': builder.report})
        print(f"  {entry['slug']}: {len(produced)} lines "
              f"({time.time() - t:.1f}s)", file=sys.stderr)

    built = drop_cross_feed_duplicates(built, feed_metadata, reports)

    if options.osm_routes:
        built += build_osm_systems(options, countries, network, built, reports)
        built = drop_osm_duplicates(built, reports)

    # Branding is release metadata rather than geometry. Refresh it after the
    # expensive per-feed cache has been read so a corrected logo association
    # never requires re-routing a continent merely to reach the package.
    operator_brand = {}
    operator_brand_status = {}
    for slug, metadata in feed_metadata.items():
        aliases = [metadata.get('name'), metadata.get('operatorOverride')]
        aliases += metadata.get('agencies') or []
        status = ('audited-logo' if metadata.get('operatorLogo')
                  else 'restricted' if metadata.get('logoRestricted')
                  else 'audited-unbranded' if slug in audited_unbranded
                  else None)
        for alias in aliases:
            if alias:
                key = alias.strip().casefold()
                if metadata.get('operatorLogo'):
                    operator_brand[key] = metadata['operatorLogo']
                if status:
                    operator_brand_status[key] = status

    for line in built:
        metadata = feed_metadata.get(line.get('feed')) or {}
        per_operator = metadata.get('operatorLogos') or {}
        logo = per_operator.get(line.get('operator'))
        # A feed-wide mark is safe only when the registry identifies one
        # agency (or deliberately overrides it). Consolidated regional feeds
        # contain several unrelated operators; assigning the aggregator's
        # mark to every line is worse than omitting a mark.
        if logo is None and (metadata.get('operatorOverride')
                             or len(metadata.get('agencies') or ()) == 1):
            logo = metadata.get('operatorLogo')
        operator_key = (line.get('operator') or '').strip().casefold()
        if logo is None:
            logo = operator_brand.get(operator_key)
        line['operatorLogo'] = logo
        line['operatorShort'] = metadata.get('operatorShort')
        line['brandStatus'] = (
            'audited-logo' if logo
            else 'restricted' if metadata.get('logoRestricted')
            else 'audited-unbranded' if line.get('feed') in audited_unbranded
            else (operator_brand_status.get(operator_key) or 'unverified'))

    per_region = assemble(built, countries, options)
    reference = None
    if not options.skip_crosscheck:
        osm = load_osm(options.source_dir)
        official, official_files, official_lines = load_official_geometry(
            options.source_dir)
        reference = CrossCheck(network, osm, official)
        print(f'cross-check: {len(network.edges)} FRA edges, '
              f'{osm.way_count} OSM ways from {osm.tiles} tiles, '
              f'{official_lines} official alignments from '
              f'{official_files} supplemental files', file=sys.stderr)

    options.geometry_blockers = []
    summary = {'generatedAt': GENERATED_AT, 'feeds': reports, 'regions': {}}
    for region in ('us', 'ca'):
        region_lines = per_region.get(region) or []
        if not region_lines:
            continue
        result = build_region(region, region_lines, options, reference)
        worst = max((v['maxDeviationMeters'] for v in result['checks'].values()),
                    default=0.0)
        package = {
            'format': 'compact-v1',
            'version': PACKAGE_VERSION,
            'generatedAt': GENERATED_AT,
            'crs': 'WGS84',
            'country': region.upper(),
            'timeZones': result['zones'],
            'lines': result['lines'],
            'geometrySource': {
                'officialOnly': 1 if reference is None else 0,
                'providers': registry['providers'],
                'license': registry['license'],
                'syntheticConnectors': synthetic_total(region_lines),
                'osmSources': 1,
                'verifiedOfficialNetworks': {
                    key: value for key, value in
                    sorted(options.verified_official_sources.items())
                    if any(line.get('geometrySource') == key
                           for line in region_lines)
                },
                'officialGeometryComparison': {
                    'scope': 'FRA/BTS North American Rail Network and OpenStreetMap track',
                    'lines': len(result['lines']),
                    'maxDeviationMeters': round(worst, 2),
                    'byLine': result['checks'],
                },
            },
            'attributeSources': {
                'colours': ('operator-published GTFS route_color, or a registry '
                            'colour carrying its official source URL; lines '
                            'without either are release-blocked; '
                            'colorReference preserves the published value and '
                            'the two display values only adjust contrast'),
                'names': 'operator-published GTFS route_long_name and stop_name',
                'order': 'operator-published GTFS stop sequences',
                'quebecGeometry': ('Québec Ministère des Transports et de '
                                    'la Mobilité durable Réseau ferroviaire '
                                    '(CC-BY 4.0), only for lines whose segments '
                                    'explicitly identify VIA as passenger user'),
                'branding': ('operator identity cross-checked through Wikidata; '
                             'artwork is the item\'s explicit P154 logo image, '
                             'with Q-id and Commons source recorded in '
                             'rail/operator-logos/na/manifest.json'),
            },
        }
        out = os.path.join(options.output_dir, f'{region}-2025.json')
        size = write_json(out, package)
        stations = write_json(os.path.join(options.data_dir, f'stations-{region}.json'),
                              {'type': 'FeatureCollection',
                               'features': result['stationFeatures']})
        sect = write_json(os.path.join(options.data_dir, f'rail-sections-{region}.json'),
                          {'type': 'FeatureCollection', 'features': result['sections']})
        read = write_json(os.path.join(options.data_dir,
                                       f'station-readings-{region}.json'),
                          readings_for(result['stationFeatures'], region))
        summary['regions'][region] = {
            'lines': len(result['lines']),
            'stationGroups': len(result['groups']),
            'sections': len(result['sections']),
            'zones': result['zones'],
            'maxDeviationMeters': round(worst, 2),
            'bytes': {'package': size, 'stations': stations,
                      'sections': sect, 'readings': read},
        }
        print(f'{region}: {len(result["lines"])} lines, '
              f'{len(result["groups"])} station groups, {size / 1e6:.1f} MB',
              file=sys.stderr)

    if options.geometry_blockers:
        reports.append({
            'slug': 'geometry-release-blockers', 'lines': 0,
            'dropped': options.geometry_blockers, 'notes': [],
            'syntheticConnectors': 0,
        })

    if options.report:
        write_json(options.report, summary)
    print(json.dumps(summary['regions'], indent=1), file=sys.stderr)


def iter_narn(sources):
    narn_dir = os.path.join(sources, 'narn')
    if os.path.isdir(narn_dir):
        for name in sorted(os.listdir(narn_dir)):
            if not name.endswith('.json.gz'):
                continue
            with gzip.open(os.path.join(narn_dir, name)) as fh:
                for row in json.loads(fh.read()):
                    yield {'properties': row['p'],
                           'geometry': {'type': 'LineString', 'coordinates': row['c']}}
        return
    path = os.path.join(sources, 'narn-passenger.geojson')
    if os.path.exists(path):
        with open(path) as fh:
            for feature in json.load(fh)['features']:
                yield feature


if __name__ == '__main__':
    main()
