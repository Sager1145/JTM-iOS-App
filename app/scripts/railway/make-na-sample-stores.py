#!/usr/bin/env python3
"""Write the sample itineraries the two North American packages ship with.

    python3 scripts/railway/make-na-sample-stores.py \
        --package public/rail/us-2025.json --stations data/stations-us.json \
        --region us --out data/train-store-us.json

Every other country ships one, and they are not decoration: they are the only
journeys a reader has before they record their own, and they are what the route
solver, the statistics screen and the passport are first exercised against on a
device. Each is generated from the shipped package rather than typed, so a
sample can never name a station the package does not have.

**Two of them cross a border on purpose.** The United States store carries the
*Adirondack* from New York to Montréal and the Canadian store carries the
*Maple Leaf* from Toronto to New York, because a cross-border journey is the
one case the seven-package app could not hold until now, and a feature with no
sample is a feature nobody looks at.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from collections import defaultdict


def load(package_paths, stations_paths):
    """Every package the samples may name, merged into one lookup.

    More than one, because a cross-border sample names a line in each: the
    *Adirondack* is `amtrak-adirondack-us` as far as the border and
    `amtrak-adirondack-ca` beyond it, and a generator holding one package could
    only write the half of the journey that ends at Rouses Point. The merge is
    safe because the two packages share no line id — the build prefixes them
    with the region — and because a station group code carries its region too.
    """
    package = {'lines': []}
    for path in package_paths:
        with open(path) as fh:
            package['lines'] += json.load(fh)['lines']
    codes = defaultdict(dict)          # line name -> group code -> station code
    for path in stations_paths:
        with open(path) as fh:
            for feature in json.load(fh)['features']:
                props = feature['properties']
                codes[props['line_name']][props['n02_group_code']] = (
                    props['n02_station_code'])
    return package, codes


def line_by_id(package, line_id):
    for line in package['lines']:
        if line['id'] == line_id:
            return line
    return None


def journey(package, codes, spec, region):
    """One itinerary along one or two of the package's own lines."""
    stops = []
    sections = []
    line_names = []
    operators = []
    last_point = None
    for part in spec['lines']:
        line = line_by_id(package, part['id'])
        if line is None:
            return None
        table = codes.get(line['name'], {})
        rows = line['stations']
        first = index_of(rows, part.get('from'))
        last = index_of(rows, part.get('to'))
        if first is None or last is None:
            return None
        step = 1 if last >= first else -1
        chosen = [rows[i] for i in range(first, last + step, step)]
        if line['name'] not in line_names:
            line_names.append(line['name'])
        if line['operator'] not in operators:
            operators.append(line['operator'])
        for row in chosen:
            code = table.get(row[0]) or row[0]
            point = (row[2], row[3])
            # Border-split display lines deliberately overlap one physical
            # station so their geometries meet. Each country gives that row a
            # country-prefixed code, so code-only deduplication wrote the same
            # stop twice and created a zero-length cross-border journey leg.
            if (stops and (stops[-1]['n02_station_code'] == code
                           or (last_point is not None
                               and distance_metres(last_point, point) <= 20.0))):
                continue
            stops.append({
                'name': row[1],
                'n02_station_code': code,
                'arrival': None,
                'departure': None,
                'stop_type': 'passenger_stop',
                'ride_segment': True,
            })
            if len(stops) > 1:
                sections.append({
                    'from_n02_station_code': stops[-2]['n02_station_code'],
                    'to_n02_station_code': code,
                    'line_names': [line['name']],
                    'operator_names': [line['operator']],
                })
            last_point = point
    if len(stops) < 2:
        return None
    stops[0]['stop_type'] = 'origin'
    stops[-1]['stop_type'] = 'destination'
    colour = line_by_id(package, spec['lines'][0]['id'])['color']
    return {
        'id': spec['id'],
        'date': spec['date'],
        'number': spec['number'],
        'train_type': spec['trainType'],
        'company': operators[0],
        'origin': stops[0]['name'],
        'destination': stops[-1]['name'],
        'direction': 'down',
        'visible': True,
        'region': region,
        'style': {'color': colour},
        'route_policy': {
            'mode': 'single_primary_route',
            'jr_only': False,
            'allow_alternatives': False,
            'allow_browser_straight_line_fallback': False,
            'preferred_line_names': line_names,
            'preferred_operator_names': operators,
            'institution_filter_mode': 'soft',
        },
        'route_sections': sections,
        'stops': stops,
    }


def distance_metres(a, b):
    lon1, lat1 = map(math.radians, a)
    lon2, lat2 = map(math.radians, b)
    dlon, dlat = lon2 - lon1, lat2 - lat1
    h = (math.sin(dlat / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 2 * 6_371_008.8 * math.asin(min(1.0, math.sqrt(h)))


def index_of(rows, name):
    if name is None:
        return None
    for i, row in enumerate(rows):
        if row[1] == name or row[0] == name:
            return i
    # A prefix match, so a spec can name "Chicago" for "Chicago Union Station".
    for i, row in enumerate(rows):
        if row[1].lower().startswith(name.lower()):
            return i
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--package', action='append', required=True)
    ap.add_argument('--stations', action='append', required=True)
    ap.add_argument('--region', required=True)
    ap.add_argument('--specs', required=True,
                    help='JSON list of itinerary specifications')
    ap.add_argument('--out', required=True)
    options = ap.parse_args()

    package, codes = load(options.package, options.stations)
    with open(options.specs) as fh:
        specs = json.load(fh)

    trains = []
    for spec in specs:
        built = journey(package, codes, spec, options.region)
        if built is None:
            sys.stderr.write(f"  skipped {spec['id']}: the package does not "
                             f"carry that line or those stations\n")
            continue
        trains.append(built)
    payload = {'schema_version': '1.3', 'trains': trains}
    with open(options.out, 'w') as fh:
        json.dump(payload, fh, ensure_ascii=False)
    sys.stderr.write(f'{len(trains)} journeys -> {options.out} '
                     f'({os.path.getsize(options.out)} bytes)\n')


if __name__ == '__main__':
    main()
