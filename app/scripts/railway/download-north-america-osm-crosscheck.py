#!/usr/bin/env python3
"""Fetch the OpenStreetMap track that every built line is checked against.

    python3 scripts/railway/download-north-america-osm-crosscheck.py \
        --package public/rail/us-2025.json --package public/rail/ca-2025.json \
        --output-dir /private/tmp/na-rail/osm-geom

## Why this is a separate step, and why it is driven by the packages

The FRA's network is the authority for where mainline track is, and it is used
as one: every intercity and commuter line is routed over it. It does not
survey street track, so a streetcar, a light-rail line on a median, a people
mover and a funicular have no official centreline in the United States or
Canada at all — for those the operator's own GTFS alignment is the only
statement of where the railway is, and a single source that nothing checks is
a source that can be wrong in silence.

OpenStreetMap is that check. It is not used as a source here — no coordinate
in either package comes from it — only as a second opinion, which is the
weakest use a package can make of an open dataset and the one that needs no
licence inheritance.

Driven by the packages because the alternative is downloading the transit
track of two countries to check a few thousand kilometres of it. One bounding
box per built line, merged where they overlap, is a few dozen queries instead
of a continent.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from na_overpass import Overpass                        # noqa: E402

#: The OSM railway values a passenger package can be checked against. Freight
#: spurs and yards are `railway=rail` too, which is why the mainline check uses
#: the FRA network instead of this: here the query is scoped to a built line's
#: own bounding box, so what comes back is the track around that line.
RAILWAY_VALUES = 'rail|light_rail|subway|tram|monorail|funicular|narrow_gauge'


def line_boxes(package_path, pad_deg=0.01, max_line_km=250.0):
    """A bounding box per line that OpenStreetMap is the check for.

    ``max_line_km`` skips the intercity network, and skipping it is the point
    rather than a saving. Those lines are ROUTED over the FRA's own centrelines
    inside a corridor drawn by the operator's published alignment, so they are
    already the agreement of two official sources; asking OpenStreetMap as well
    would mean downloading the freight network of a continent to confirm what
    two governments and an operator already say. What is left — the metros,
    the light rail, the streetcars, the people movers and the funiculars — is
    exactly the track the FRA does not survey, and exactly what needs a second
    opinion.
    """
    with open(package_path) as fh:
        package = json.load(fh)
    boxes = []
    for line in package['lines']:
        lons, lats = [], []
        total_km = 0.0
        for segment in line['segments']:
            total_km += float(segment[0] or 0)
            for lon, lat in segment[2]:
                lons.append(lon)
                lats.append(lat)
        if not lons or total_km > max_line_km:
            continue
        boxes.append((min(lats) - pad_deg, min(lons) - pad_deg,
                      max(lats) + pad_deg, max(lons) + pad_deg))
    return boxes


def merge_boxes(boxes, max_span_deg=1.2):
    """Fold overlapping boxes together, and refuse to build a huge one.

    A transcontinental line's own box is a third of a continent, and asking
    Overpass for every railway inside it would be asking for the whole
    country's freight network. Those are split into tiles instead, which is
    also what keeps any single response small enough to arrive.
    """
    tiles = []
    for south, west, north, east in boxes:
        rows = max(1, int((north - south) / max_span_deg) + 1)
        cols = max(1, int((east - west) / max_span_deg) + 1)
        for r in range(rows):
            for c in range(cols):
                tiles.append((
                    south + (north - south) * r / rows,
                    west + (east - west) * c / cols,
                    south + (north - south) * (r + 1) / rows,
                    west + (east - west) * (c + 1) / cols,
                ))
    # Merge overlapping city boxes while keeping the union below the response
    # size cap. Exact-key deduplication leaves one query per route (Toronto's
    # lines alone produced dozens); a true spatial union asks once for the
    # shared track and is both faster and less load on Overpass.
    merged = []
    for tile in sorted(tiles):
        candidate = tile
        index = 0
        while index < len(merged):
            other = merged[index]
            overlaps = not (
                candidate[2] < other[0] or other[2] < candidate[0]
                or candidate[3] < other[1] or other[3] < candidate[1]
            )
            union = (min(candidate[0], other[0]),
                     min(candidate[1], other[1]),
                     max(candidate[2], other[2]),
                     max(candidate[3], other[3]))
            if (overlaps and union[2] - union[0] <= max_span_deg
                    and union[3] - union[1] <= max_span_deg):
                candidate = union
                merged.pop(index)
                index = 0
                continue
            index += 1
        merged.append(candidate)
    seen = {tuple(round(v, 4) for v in tile): tile for tile in merged}
    return list(seen.values())


def tile_name(tile):
    return 'tile-%+08.3f%+09.3f.json.gz' % (tile[0], tile[1])


def quarters(tile):
    south, west, north, east = tile
    midlat = (south + north) / 2
    midlon = (west + east) / 2
    return [(south, west, midlat, midlon), (south, midlon, midlat, east),
            (midlat, west, north, midlon), (midlat, midlon, north, east)]


def fetch_tile(client, tile, output_dir, depth=0, max_depth=2):
    """One tile, splitting into quarters rather than giving up.

    The response, not the query, is what fails here: a busy Overpass and a
    proxy between it and this machine truncate a large body, and no number of
    retries makes the same large body smaller. Quartering asks the same
    question four times over four smaller areas, and the union of the answers
    is the answer — which is what makes a slow network a matter of waiting
    rather than of coverage this package cannot claim.
    """
    path = os.path.join(output_dir, tile_name(tile))
    if os.path.exists(path) and os.path.getsize(path) > 100:
        return 1
    if fetch(client, tile, path, tries=2):
        return 1
    if depth >= max_depth:
        sys.stderr.write(f'  GAVE UP {tile_name(tile)}\n')
        return 0
    got = 0
    for quarter in quarters(tile):
        got += fetch_tile(client, quarter, output_dir, depth + 1, max_depth)
    return 1 if got else 0


def fetch(client, tile, path, tries=3):
    south, west, north, east = tile
    query = (f'[out:json][timeout:180];'
             f'way["railway"~"^({RAILWAY_VALUES})$"]'
             f'({south:.5f},{west:.5f},{north:.5f},{east:.5f});'
             f'out geom;')
    body = client.get(query, tries=tries, timeout=420)
    if body is None:
        return False
    with open(path, 'wb') as fh:
        fh.write(body)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--package', action='append', required=True)
    ap.add_argument('--output-dir', required=True)
    ap.add_argument('--max-span-deg', type=float, default=1.2)
    ap.add_argument('--max-line-km', type=float, default=250.0)
    options = ap.parse_args()

    os.makedirs(options.output_dir, exist_ok=True)
    boxes = []
    for path in options.package:
        boxes += line_boxes(path, max_line_km=options.max_line_km)
    tiles = merge_boxes(boxes, options.max_span_deg)
    tiles.sort()
    sys.stderr.write(f'{len(boxes)} line boxes -> {len(tiles)} tiles\n')

    client = Overpass()
    done = 0
    for index, tile in enumerate(tiles):
        done += fetch_tile(client, tile, options.output_dir)
        sys.stderr.write(f'{index + 1}/{len(tiles)} ({done} answered)\n')
        sys.stderr.flush()
        time.sleep(1)
    sys.stderr.write(f'done: {done}/{len(tiles)}\n')
    if done < len(tiles):
        # The package reports the fraction of its vertices an independent
        # source could confirm, and an unfetched tile lowers that fraction
        # without a single coordinate being wrong. Saying so here is what
        # keeps "84.5 % confirmed" from being read as "15 % disagrees".
        sys.stderr.write(
            f'INCOMPLETE: {len(tiles) - done} tiles unanswered — the '
            f'cross-check will report their track as unconfirmed rather than '
            f'as disagreeing\n')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main() or 0)
