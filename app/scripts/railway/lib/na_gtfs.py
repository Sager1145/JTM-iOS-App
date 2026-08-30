"""Reading a GTFS feed as an operator's own statement about its railway.

GTFS is the official record for North American passenger rail in the way TDX
is for Taiwan: the operator publishes it, it is what its own passenger
information is generated from, and it carries the four things a display line
needs — which stations, in what order, under what name and colour, along which
alignment. Nothing here invents any of those.

What this module does NOT do is decide anything. It reads a feed, groups trips
into the distinct stopping patterns the operator actually runs, and hands them
over. Which pattern becomes a display line, and which becomes a branch of one,
is the builder's decision and is argued there.
"""
from __future__ import annotations

import csv
import io
import os
import sys
import zipfile
from collections import Counter, defaultdict

#: The ``route_type`` values that are a railway. GTFS's basic set plus the
#: extended ranges, which several North American feeds use: 1xx rail services,
#: 4xx urban rail, 9xx tram, 1400 funicular. Aerial lifts (13xx) are not a
#: railway and buses of every kind are excluded by construction.
BASIC_RAIL_TYPES = {0, 1, 2, 5, 7, 12}


def is_rail_type(value) -> bool:
    try:
        n = int(str(value).strip())
    except (TypeError, ValueError):
        return False
    if n in BASIC_RAIL_TYPES:
        return True
    return (100 <= n <= 117) or (400 <= n <= 405) or (900 <= n <= 906) or n == 1400


def route_type_kind(value) -> str:
    """The coarse kind a ``route_type`` names — used only for ranking and ids."""
    try:
        n = int(str(value).strip())
    except (TypeError, ValueError):
        return 'rail'
    if n == 0 or 900 <= n <= 906:
        return 'tram'
    if n == 1 or 400 <= n <= 405:
        return 'metro'
    if n == 2 or 100 <= n <= 117:
        return 'rail'
    if n == 5:
        return 'cable'
    if n == 7 or n == 1400:
        return 'funicular'
    if n == 12:
        return 'monorail'
    return 'rail'


class Feed:
    """One GTFS feed, opened from a local zip."""

    def __init__(self, path):
        self.path = path
        self.zip = zipfile.ZipFile(path)
        self._names = {n.rsplit('/', 1)[-1]: n for n in self.zip.namelist()}

    def has(self, name):
        return name in self._names

    def rows(self, name):
        """Stream one table as dicts. Absent tables yield nothing.

        Header and value whitespace is stripped, and that is not tidiness: at
        least one major operator publishes ``route_id, route_short_name,
        route_type, …`` with a space after each comma, so a plain
        ``DictReader`` names the columns `" route_type"` and every one of them
        reads back as absent. The failure is silent and total — a commuter
        railroad with eleven lines is read as an operator with no railway at
        all — which is exactly the kind of thing a build must not do quietly.
        """
        member = self._names.get(name)
        if member is None:
            return
        with self.zip.open(member) as raw:
            text = io.TextIOWrapper(raw, encoding='utf-8-sig', errors='replace',
                                    newline='')
            reader = csv.reader(text)
            try:
                header = [h.strip() for h in next(reader)]
            except StopIteration:
                return
            width = len(header)
            for values in reader:
                if not values:
                    continue
                row = {header[i]: values[i].strip()
                       for i in range(min(width, len(values)))}
                for i in range(len(values), width):
                    row[header[i]] = ''
                yield row

    def table(self, name, key=None):
        if key is None:
            return list(self.rows(name))
        return {r[key]: r for r in self.rows(name) if r.get(key)}

    # ------------------------------------------------------------------ parts

    def agencies(self):
        out = {}
        for row in self.rows('agency.txt'):
            out[(row.get('agency_id') or '').strip()] = row
        return out

    def rail_routes(self):
        return [r for r in self.rows('routes.txt') if is_rail_type(r.get('route_type'))]

    def stops(self):
        return self.table('stops.txt', 'stop_id')

    def shapes(self):
        """``shape_id -> [[lon, lat], …]`` in ``shape_pt_sequence`` order."""
        acc = defaultdict(list)
        for row in self.rows('shapes.txt'):
            try:
                seq = float(row['shape_pt_sequence'])
                lat = float(row['shape_pt_lat'])
                lon = float(row['shape_pt_lon'])
            except (KeyError, TypeError, ValueError):
                continue
            acc[row['shape_id']].append((seq, lon, lat))
        return {k: [[lon, lat] for _, lon, lat in sorted(v)] for k, v in acc.items()}

    def trips_by_route(self, route_ids):
        out = defaultdict(list)
        wanted = set(route_ids)
        for row in self.rows('trips.txt'):
            if row.get('route_id') in wanted:
                out[row['route_id']].append(row)
        return out

    def stop_sequences(self, trip_ids):
        """``trip_id -> [stop_id, …]`` for the trips asked for.

        Streamed rather than loaded: ``stop_times.txt`` is the largest table in
        every feed and is hundreds of megabytes for the big agencies, of which
        the rail routes are often a small part.
        """
        wanted = set(trip_ids)
        acc = defaultdict(list)
        for row in self.rows('stop_times.txt'):
            trip = row.get('trip_id')
            if trip not in wanted:
                continue
            # GTFS explicitly defines this pair as a non-passenger timing
            # point. Depot platforms and tail tracks occur in rail trips but
            # are not stations a passenger can board or leave at.
            if ((row.get('pickup_type') or '0').strip() == '1'
                    and (row.get('drop_off_type') or '0').strip() == '1'):
                continue
            try:
                seq = int(float(row['stop_sequence']))
            except (KeyError, TypeError, ValueError):
                continue
            acc[trip].append((seq, row.get('stop_id'),
                              row.get('shape_dist_traveled') or ''))
        return {t: [s for _, s, _ in sorted(v)] for t, v in acc.items()}

    def service_weights(self):
        """How many calendar days each ``service_id`` runs on, roughly.

        Used only to rank stopping patterns: a pattern run by one Sunday-only
        trip should not out-vote the weekday service just because the feed
        happens to list it first. A feed with no ``calendar.txt`` weights every
        service equally, which is the same ranking as counting trips.
        """
        weights = {}
        for row in self.rows('calendar.txt'):
            days = sum(1 for d in ('monday', 'tuesday', 'wednesday', 'thursday',
                                   'friday', 'saturday', 'sunday')
                       if (row.get(d) or '0').strip() == '1')
            weights[row.get('service_id')] = max(1, days)
        extra = Counter()
        for row in self.rows('calendar_dates.txt'):
            if (row.get('exception_type') or '').strip() == '1':
                extra[row.get('service_id')] += 1
        for service, n in extra.items():
            weights.setdefault(service, max(1, min(7, n)))
        return weights


def parent_of(stop_row, stops):
    """The station a platform belongs to — a feed's own grouping, never ours.

    ``location_type=1`` is GTFS's word for a station, and ``parent_station``
    is how a platform names one. Where a feed publishes neither, the stop is
    its own station: inventing a grouping from name or proximity would merge
    two genuinely separate stations that share a street name, which is the
    error that puts a train on the wrong track.
    """
    parent = (stop_row.get('parent_station') or '').strip()
    while parent and parent in stops:
        row = stops[parent]
        nxt = (row.get('parent_station') or '').strip()
        if not nxt or nxt == parent:
            return parent
        parent = nxt
    return stop_row.get('stop_id')


def pattern_key(stop_ids):
    return tuple(stop_ids)


def collapse_repeats(stop_ids):
    """Drop an immediately repeated stop, keeping every genuine revisit.

    A feed that lists the same platform twice in a row is describing a dwell,
    not a movement. A loop service that returns to a station later in the trip
    is describing a movement, and collapsing that would cut the loop.
    """
    out = []
    for s in stop_ids:
        if not out or out[-1] != s:
            out.append(s)
    return out
