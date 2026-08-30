#!/usr/bin/env python3
"""Enumerate every passenger railway OpenStreetMap knows about in North America.

    python3 scripts/railway/download-north-america-osm-inventory.py \
        --output /private/tmp/na-rail/osm-inventory.json

This is the list `report-na-coverage.py` measures the packages against, and it
is the whole basis of the claim that the packages contain every passenger
railway. Until now it was made by hand, once, which meant the claim could not
be re-checked without repeating an undocumented set of queries — so a railway
that opened after that afternoon could not be discovered, only stumbled on.

## What is asked for, and why it is only tags

Every relation tagged ``route=train|subway|light_rail|tram|monorail|funicular``
inside the continent. Not their geometry and not their members: the comparison
downstream is on the OPERATOR, so the tags are the whole of the answer and
asking for geometry would turn a few megabytes into a few gigabytes.

``route=railway`` is deliberately absent. It is the tag for a piece of
infrastructure — a named stretch of line — rather than for a service that
carries passengers along it, and including it would fill the inventory with
freight subdivisions the packages are right not to contain.

## Why it is tiled

One query for the continent is one query the instance will refuse. The
continent is cut into bands of longitude and latitude small enough that each
answers inside the query timeout, and a tile that still refuses is quartered
until its pieces do — the same descent `download-north-america-osm-crosscheck`
uses, for the same reason. Tiles already written are not fetched again, so an
interrupted run resumes.
"""
from __future__ import annotations

import argparse
import gzip
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from na_overpass import Overpass                        # noqa: E402

#: The continent, as the coverage report means it: the United States including
#: Alaska and Hawai‘i, Canada to the Arctic islands, and the Mexican border
#: strip that any box drawn around the other two contains. Mexico's systems are
#: in the answer and `report-na-coverage.py` drops them by name — which is the
#: honest way round, because a bounding box that tried to exclude them would
#: also cut San Diego's trolley off at the border it crosses.
CONTINENT = (14.0, -172.0, 72.0, -52.0)

ROUTE_VALUES = 'train|subway|light_rail|tram|monorail|funicular'


def tiles(box, step_lat=6.0, step_lon=8.0):
    south, west, north, east = box
    out = []
    lat = south
    while lat < north:
        lon = west
        while lon < east:
            out.append((lat, lon, min(lat + step_lat, north),
                        min(lon + step_lon, east)))
            lon += step_lon
        lat += step_lat
    return out


def quarters(tile):
    south, west, north, east = tile
    mid_lat, mid_lon = (south + north) / 2, (west + east) / 2
    return [(south, west, mid_lat, mid_lon), (south, mid_lon, mid_lat, east),
            (mid_lat, west, north, mid_lon), (mid_lat, mid_lon, north, east)]


def tile_name(tile):
    return 'inv_%.2f_%.2f_%.2f_%.2f.json.gz' % tile


def fetch_tile(client, tile, output_dir, depth=0, max_depth=3):
    """One tile, or its quarters when the instance will not answer it whole.

    Returns the number of tiles that ended up with a file. A tile that comes
    back empty still counts: most of this box is ocean and tundra, and "there
    is no passenger railway here" is a real answer that must not be retried
    forever.
    """
    path = os.path.join(output_dir, tile_name(tile))
    if os.path.exists(path) and os.path.getsize(path) > 40:
        return 1
    south, west, north, east = tile
    query = ('[out:json][timeout:180];'
             'relation(%.4f,%.4f,%.4f,%.4f)["route"~"^(%s)$"];'
             'out tags;' % (south, west, north, east, ROUTE_VALUES))
    body = client.get(query, tries=2, timeout=420)
    if body is not None:
        with open(path, 'wb') as fh:
            fh.write(body)
        return 1
    if depth >= max_depth:
        sys.stderr.write('  GAVE UP %s\n' % tile_name(tile))
        return 0
    got = 0
    for quarter in quarters(tile):
        got += fetch_tile(client, quarter, output_dir, depth + 1, max_depth)
    return 1 if got else 0


def merge(output_dir):
    """Every tile's relations, de-duplicated by relation id.

    Tiles overlap at their edges and a route relation is returned by every
    tile its bounding box touches, so the id is the identity — not the name,
    which several operators reuse across their own lines.
    """
    seen = {}
    for name in sorted(os.listdir(output_dir)):
        if not name.startswith('inv_') or not name.endswith('.json.gz'):
            continue
        with gzip.open(os.path.join(output_dir, name)) as fh:
            for element in json.load(fh).get('elements', []):
                seen[element.get('id')] = element
    return list(seen.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', required=True)
    ap.add_argument('--tile-dir')
    ap.add_argument('--step-lat', type=float, default=6.0)
    ap.add_argument('--step-lon', type=float, default=8.0)
    options = ap.parse_args()

    tile_dir = options.tile_dir or os.path.join(
        os.path.dirname(os.path.abspath(options.output)), 'osm-inventory-tiles')
    os.makedirs(tile_dir, exist_ok=True)

    client = Overpass()
    boxes = tiles(CONTINENT, options.step_lat, options.step_lon)
    sys.stderr.write('%d tiles over the continent\n' % len(boxes))
    answered = 0
    for index, tile in enumerate(boxes):
        answered += fetch_tile(client, tile, tile_dir)
        sys.stderr.write('%d/%d (%d answered)\n'
                         % (index + 1, len(boxes), answered))
        sys.stderr.flush()
        time.sleep(1.0)

    elements = merge(tile_dir)
    with open(options.output, 'w') as fh:
        json.dump({'generator': 'download-north-america-osm-inventory.py',
                   'tiles': {'asked': len(boxes), 'answered': answered},
                   'elements': elements}, fh)
    operators = {e.get('tags', {}).get('operator') for e in elements}
    sys.stderr.write('%d route relations, %d distinct operator strings -> %s\n'
                     % (len(elements), len(operators - {None}), options.output))
    if answered < len(boxes):
        sys.stderr.write('INCOMPLETE: %d tiles unanswered; the inventory is a '
                         'floor, not the list\n' % (len(boxes) - answered))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
