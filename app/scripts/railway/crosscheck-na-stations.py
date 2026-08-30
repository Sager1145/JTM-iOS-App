#!/usr/bin/env python3
"""Measure every station's published position against OpenStreetMap's.

    python3 scripts/railway/crosscheck-na-stations.py \
        --package public/rail/us-2025.json --package public/rail/ca-2025.json \
        --tile-dir /private/tmp/na-rail/osm-stations \
        --out /private/tmp/na-rail/station-crosscheck.json

## Why this exists separately from the line cross-check

`download-north-america-osm-crosscheck.py` measures the *alignment* — every
vertex of every built line against an independent source. It says nothing at
all about the stations, and a package can have both its track in the right
place and its platforms in the wrong one: the coordinates come from different
fields of different files. A GTFS `stop_lat`/`stop_lon` is whatever the
operator typed, and operators do type a station's street address, the middle of
a car park, or the centroid of a whole complex.

So this asks the second question the first one does not: is the DOT where the
railway says the station is?

## What it compares, and what a disagreement means

Each station group in a package is matched to the nearest OpenStreetMap
railway station within a search radius, preferring one whose name matches once
both are normalised. What comes back is a distance, and a distance is not by
itself a fault:

* **Under the band's tolerance** — the two sources agree about a platform, to
  the accuracy either of them claims.
* **Over it, with a name match** — the two sources agree about WHICH station
  and disagree about where it is. This is the finding worth having, and its
  usual cause is an operator publishing the entrance rather than the platform.
* **Over it, with no name match** — most likely nothing was found rather than
  something wrong. Reported separately, and never counted as a disagreement,
  for the same reason the line cross-check separates absence from conflict: a
  station OpenStreetMap has not mapped is not a station in the wrong place.

The tolerances are the band's, from `na_profile.CROSSCHECK_TOLERANCE_M`,
because the question scales the same way the alignment's does: 40 m between
two statements about a tram stop is a different corner, and between two
statements about a prairie station is the other end of one platform.
"""
from __future__ import annotations

import argparse
import gzip
import json
import math
import os
import re
import sys
import time
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from na_overpass import Overpass                        # noqa: E402
from na_profile import (CROSSCHECK_TOLERANCE_M,          # noqa: E402
                        median_spacing_m, profile_for)

EARTH_R = 6_371_008.8

#: What OpenStreetMap calls a place a passenger train stops. `halt` and
#: `tram_stop` are in because this package family contains the railways that
#: use them; `subway_entrance` is deliberately OUT — an entrance is a door on
#: the street above, which is precisely the disagreement being measured.
STATION_QUERY = (
    'node["railway"~"^(station|halt|tram_stop)$"]({bbox});'
    'way["railway"~"^(station|halt)$"]({bbox});'
    'node["public_transport"="station"]["train"="yes"]({bbox});'
)


def haversine(a, b):
    lon1, lat1 = a
    lon2, lat2 = b
    p1, p2 = math.radians(lat1), math.radians(lat2)
    h = (math.sin((p2 - p1) / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2)
    return 2 * EARTH_R * math.asin(min(1.0, math.sqrt(h)))


def normalise(name):
    """A station name reduced to what two sources could agree on.

    The same reduction `build-north-america-rail-package.py` applies, plus the
    words OpenStreetMap adds and GTFS does not.
    """
    text = (name or '').lower()
    text = re.sub(r'\b(amtrak|via rail|via|station|stn|gare|depot|halt|stop|'
                  r'transit center|transit centre|rail|railway|metro|subway|'
                  r'light rail|lrt|platform|terminal|tram)\b', ' ', text)
    text = re.sub(r'[^a-z0-9]+', ' ', text)
    return ' '.join(text.split())


def package_stations(path):
    """Every station group in a package, once, with the band it is drawn in.

    A group appears on as many lines as call there, and its anchor differs
    slightly per line; the one taken here is the first, because what is being
    measured is where the package puts the station and any of its anchors
    answers that to far better than the tolerances involved.
    """
    with open(path) as fh:
        package = json.load(fh)
    out = {}
    for line in package['lines']:
        stations = line['stations']
        if len(stations) < 2:
            continue
        lengths = []
        previous = None
        for index, row in enumerate(line['segments']):
            points = list(row[2])
            if row[1] and previous is not None:
                points = [previous] + points
            if len(points) < 2:
                continue
            a = stations[index % len(stations)]
            b = stations[(index + 1) % len(stations)]
            points[0] = [a[2], a[3]]
            points[-1] = [b[2], b[3]]
            previous = points[-1]
            lengths.append(sum(haversine(points[j], points[j + 1])
                               for j in range(len(points) - 1)))
        if not lengths:
            continue
        band = profile_for(median_spacing_m(lengths), sum(lengths)).name
        for station in stations:
            code = station[0]
            if code not in out:
                out[code] = {'code': code, 'name': station[1],
                             'point': [station[2], station[3]], 'band': band}
    return package.get('country'), out


def tiles_for(points, span=2.0, pad=0.02):
    """The boxes that cover these stations, on a fixed grid.

    A fixed grid rather than boxes drawn round the stations, so that a rerun
    asks for the same tiles and the cache keeps working.
    """
    wanted = set()
    for lon, lat in points:
        wanted.add((math.floor(lat / span) * span, math.floor(lon / span) * span))
    return sorted((round(lat - pad, 4), round(lon - pad, 4),
                   round(lat + span + pad, 4), round(lon + span + pad, 4))
                  for lat, lon in wanted)


def tile_name(tile):
    return 'stn_%.2f_%.2f_%.2f_%.2f.json.gz' % tile


def fetch_tiles(client, tiles, tile_dir):
    os.makedirs(tile_dir, exist_ok=True)
    answered = 0
    for index, tile in enumerate(tiles):
        path = os.path.join(tile_dir, tile_name(tile))
        if os.path.exists(path) and os.path.getsize(path) > 40:
            answered += 1
            continue
        bbox = '%.4f,%.4f,%.4f,%.4f' % tile
        query = ('[out:json][timeout:180];('
                 + STATION_QUERY.format(bbox=bbox)
                 + ');out center tags;')
        body = client.get(query, tries=2, timeout=300)
        if body is not None:
            with open(path, 'wb') as fh:
                fh.write(body)
            answered += 1
        sys.stderr.write('%d/%d (%d answered)\n' % (index + 1, len(tiles), answered))
        sys.stderr.flush()
        time.sleep(0.5)
    return answered


def load_osm(tile_dir):
    found = {}
    for name in sorted(os.listdir(tile_dir)):
        if not name.startswith('stn_'):
            continue
        with gzip.open(os.path.join(tile_dir, name)) as fh:
            for element in json.load(fh).get('elements', []):
                centre = element.get('center') or element
                lon, lat = centre.get('lon'), centre.get('lat')
                if lon is None or lat is None:
                    continue
                key = (element.get('type'), element.get('id'))
                found[key] = {'point': [lon, lat],
                              'name': (element.get('tags') or {}).get('name', '')}
    return list(found.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--package', action='append', required=True)
    ap.add_argument('--tile-dir', required=True)
    ap.add_argument('--out')
    ap.add_argument('--radius-m', type=float, default=600.0)
    # Station nodes are tags and a coordinate, so a tile can be far larger
    # than the cross-check's — that one asks for way geometry and a 2° box of
    # it is tens of megabytes. At 0.5° the two countries need 635 queries,
    # which is a great deal to ask of one volunteer instance for a
    # measurement; at 2° it is a few dozen and the answers are still small.
    ap.add_argument('--span-deg', type=float, default=2.0)
    ap.add_argument('--skip-download', action='store_true')
    options = ap.parse_args()

    groups = {}
    country_of = {}
    for path in options.package:
        country, found = package_stations(path)
        for code, row in found.items():
            groups[code] = row
            country_of[code] = country
    sys.stderr.write('%d station groups\n' % len(groups))

    if not options.skip_download:
        tiles = tiles_for([g['point'] for g in groups.values()],
                          span=options.span_deg)
        sys.stderr.write('%d tiles\n' % len(tiles))
        answered = fetch_tiles(Overpass(), tiles, options.tile_dir)
        if answered < len(tiles):
            sys.stderr.write('INCOMPLETE: %d tiles unanswered; stations under '
                             'them count as unmatched, not as disagreeing\n'
                             % (len(tiles) - answered))

    osm = load_osm(options.tile_dir)
    sys.stderr.write('%d OpenStreetMap stations\n' % len(osm))

    # A degree grid so each station looks at its own neighbourhood rather than
    # at a continent. 0.01° is about 1.1 km of latitude, comfortably wider than
    # any radius this is asked for.
    cell = 0.01
    grid = defaultdict(list)
    for row in osm:
        lon, lat = row['point']
        grid[(int(lon / cell), int(lat / cell))].append(row)

    findings = []
    stats = defaultdict(lambda: {'matched': 0, 'unmatched': 0, 'over': 0,
                                 'worst': 0.0, 'distances': []})
    reach = int(options.radius_m / (cell * 111_000)) + 1
    for code, group in groups.items():
        lon, lat = group['point']
        key = (int(lon / cell), int(lat / cell))
        norm = normalise(group['name'])
        best_named = best_any = None
        for dx in range(-reach, reach + 1):
            for dy in range(-reach, reach + 1):
                for row in grid.get((key[0] + dx, key[1] + dy), ()):
                    d = haversine(group['point'], row['point'])
                    if d > options.radius_m:
                        continue
                    if best_any is None or d < best_any[0]:
                        best_any = (d, row)
                    if norm and normalise(row['name']) == norm:
                        if best_named is None or d < best_named[0]:
                            best_named = (d, row)
        band = group['band']
        entry = stats[band]
        hit = best_named or best_any
        if hit is None:
            entry['unmatched'] += 1
            continue
        distance, row = hit
        entry['matched'] += 1
        entry['distances'].append(distance)
        entry['worst'] = max(entry['worst'], distance)
        tolerance = CROSSCHECK_TOLERANCE_M.get(band, 90.0)
        if distance > tolerance and best_named is not None:
            entry['over'] += 1
            findings.append({
                'station': code, 'country': country_of[code],
                'name': group['name'], 'osmName': row['name'],
                'band': band, 'metres': round(distance),
                'tolerance': tolerance,
                'package': group['point'], 'osm': row['point']})

    total_matched = sum(v['matched'] for v in stats.values())
    total_over = sum(v['over'] for v in stats.values())
    print('=' * 74)
    print('%d station groups, %d matched to OpenStreetMap, %d beyond tolerance'
          % (len(groups), total_matched, total_over))
    print('=' * 74)
    print('%-10s %8s %8s %8s %9s %9s %9s'
          % ('band', 'matched', 'unmatch', 'over', 'median', 'p90', 'worst'))
    for band in ('street', 'metro', 'commuter', 'regional', 'longhaul'):
        v = stats.get(band)
        if not v or not v['distances']:
            continue
        d = sorted(v['distances'])
        print('%-10s %8d %8d %8d %8.0fm %8.0fm %8.0fm'
              % (band, v['matched'], v['unmatched'], v['over'],
                 d[len(d) // 2], d[int(len(d) * 0.9)], v['worst']))
    print()
    for row in sorted(findings, key=lambda r: -r['metres'])[:25]:
        print('%6dm (%s allows %.0f)  %-34s  osm: %s'
              % (row['metres'], row['band'], row['tolerance'],
                 row['name'][:34], row['osmName'][:30]))

    if options.out:
        with open(options.out, 'w') as fh:
            json.dump({'findings': findings,
                       'byBand': {k: {kk: vv for kk, vv in v.items()
                                      if kk != 'distances'}
                                  for k, v in stats.items()}}, fh, indent=1)
        sys.stderr.write('wrote %s\n' % options.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
