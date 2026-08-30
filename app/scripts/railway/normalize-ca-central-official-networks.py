#!/usr/bin/env python3
"""Build GO Transit and UP Express networks from Ontario's ORWN tracks.

ORWN is an independent provincial railway centreline, not a repackaged GTFS
shape.  Its records carry acquisition method, positional accuracy, operator,
track class, and status.  Operator GTFS geometry is used only as a broad
1.5-km corridor selector; every coordinate written here comes from ORWN.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import io
import json
import math
import os
import sys
import zipfile
from collections import defaultdict

import shapefile


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))
import na_geo as geo
import na_narn


SOURCE = {
    'publisher': ('Ontario Ministry of Natural Resources - '
                  'Geospatial Ontario'),
    'url': ('https://ws.gisetl.lrc.gov.on.ca/fmedatadownload/Packages/'
            'ORWNTRK.zip'),
    'catalogUrl': ('https://www.arcgis.com/home/item.html?'
                   'id=b08674e0c4ce45e78e1225092a4f2afd'),
}
CORRIDOR_METERS = 1_500.0
ALLOWED_TRACK_CLASSES = {
    'Main', 'Siding', 'Crossover', 'Spur', 'Connecting', 'Wye',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def point_segment_distance(point, start, end):
    latitude = math.radians((point[1] + start[1] + end[1]) / 3.0)
    scale_x = 111_195.0 * math.cos(latitude)
    scale_y = 111_195.0
    px, py = point[0] * scale_x, point[1] * scale_y
    ax, ay = start[0] * scale_x, start[1] * scale_y
    bx, by = end[0] * scale_x, end[1] * scale_y
    vx, vy = bx - ax, by - ay
    denominator = vx * vx + vy * vy
    fraction = (max(0.0, min(1.0,
                    ((px - ax) * vx + (py - ay) * vy) / denominator))
                if denominator else 0.0)
    return math.hypot(px - ax - fraction * vx,
                      py - ay - fraction * vy)


def zip_member(archive, suffix):
    names = [name for name in archive.namelist()
             if name.lower().endswith(suffix.lower())]
    if len(names) != 1:
        raise SystemExit(f'ORWN archive must contain exactly one {suffix}')
    return archive.read(names[0])


def read_orwn(raw):
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            reader = shapefile.Reader(
                shp=io.BytesIO(zip_member(archive, '.shp')),
                shx=io.BytesIO(zip_member(archive, '.shx')),
                dbf=io.BytesIO(zip_member(archive, '.dbf')),
                encoding='cp1252')
            fields = [field[0] for field in reader.fields[1:]]
            required = {'STATUS', 'TRACKCLASS', 'GEOACQTECH',
                        'GEOACCURA', 'GEOPROVIDE', 'ADMINAREA'}
            if not required.issubset(fields):
                raise SystemExit('ORWN track schema is missing audited fields')
            features = []
            for shape_record in reader.iterShapeRecords():
                properties = dict(zip(fields, shape_record.record))
                points = [list(point) for point in shape_record.shape.points]
                parts = list(shape_record.shape.parts) + [len(points)]
                lines = [points[start:end]
                         for start, end in zip(parts, parts[1:])
                         if end - start >= 2]
                if lines:
                    features.append((properties, lines))
    except (OSError, zipfile.BadZipFile, shapefile.ShapefileException) as exc:
        raise SystemExit(f'ORWN track archive is invalid: {exc}')
    if len(features) < 10_000:
        raise SystemExit('ORWN track archive is unexpectedly incomplete')
    return features


def gtfs_route_data(path, operator):
    with zipfile.ZipFile(path) as archive:
        def rows(name):
            return list(csv.DictReader(io.TextIOWrapper(
                archive.open(name), encoding='utf-8-sig', newline='')))

        routes = rows('routes.txt')
        trips = rows('trips.txt')
        shape_rows = rows('shapes.txt')
        stop_times = rows('stop_times.txt')
        stops = {row['stop_id']: row for row in rows('stops.txt')}

    rail_routes = {
        row['route_id']: (row.get('route_short_name') or row['route_id'])
        for row in routes if row.get('route_type') == '2'
    }
    shape_routes = defaultdict(set)
    for row in trips:
        if row.get('route_id') in rail_routes and row.get('shape_id'):
            shape_routes[row['shape_id']].add(rail_routes[row['route_id']])
    points = defaultdict(list)
    for row in shape_rows:
        if row.get('shape_id') in shape_routes:
            points[row['shape_id']].append((
                int(row['shape_pt_sequence']),
                [float(row['shape_pt_lon']), float(row['shape_pt_lat'])]))

    result = defaultdict(lambda: {'shapes': [], 'patterns': {}})
    for shape_id, route_names in shape_routes.items():
        shape = [point for _, point in sorted(points[shape_id])]
        if len(shape) < 2:
            continue
        for route_name in route_names:
            result[route_name]['shapes'].append(shape)

    times = defaultdict(list)
    for row in stop_times:
        if row.get('trip_id') and row.get('stop_id') in stops:
            times[row['trip_id']].append((int(row['stop_sequence']),
                                          row['stop_id']))
    trips_by_id = {row['trip_id']: row for row in trips}
    for trip_id, sequence in times.items():
        trip = trips_by_id.get(trip_id) or {}
        route_name = rail_routes.get(trip.get('route_id'))
        if route_name is None:
            continue
        stop_ids = []
        station_points = []
        for _, stop_id in sorted(sequence):
            if stop_ids and stop_ids[-1] == stop_id:
                continue
            row = stops[stop_id]
            try:
                point = [float(row['stop_lon']), float(row['stop_lat'])]
            except (KeyError, TypeError, ValueError):
                continue
            stop_ids.append(stop_id)
            station_points.append(point)
        if len(stop_ids) < 2:
            continue
        shape_id = trip.get('shape_id')
        shape = [point for _, point in sorted(points.get(shape_id) or ())]
        if len(shape) < 2:
            continue
        # Collapse reverse-direction duplicates and orient the selected shape
        # to the canonical station order.
        forward = tuple(stop_ids)
        reverse = tuple(reversed(stop_ids))
        if reverse < forward:
            forward = reverse
            station_points.reverse()
            shape.reverse()
        previous = result[route_name]['patterns'].get(forward)
        if previous is None or geo.line_length(shape) > geo.line_length(
                previous['shape']):
            result[route_name]['patterns'][forward] = {
                'stationPoints': station_points, 'shape': shape,
                'tripId': trip_id,
            }

    def subsequence(small, large):
        iterator = iter(large)
        return all(any(value == candidate for candidate in iterator)
                   for value in small)

    for route_name, data in result.items():
        patterns = data['patterns']
        maximal = []
        for sequence, pattern in patterns.items():
            if any(len(other) > len(sequence) and subsequence(sequence, other)
                   for other in patterns):
                continue
            maximal.append(pattern)
        data['patterns'] = maximal
    if not result:
        raise SystemExit(f'{operator} GTFS has no rail shapes')
    return dict(result)


def gtfs_route_shapes(path, operator):
    return {name: data['shapes']
            for name, data in gtfs_route_data(path, operator).items()}


def segment_index(shapes, cell=0.02):
    index = defaultdict(list)
    padding = CORRIDOR_METERS / 75_000.0
    for shape in shapes:
        for start, end in zip(shape, shape[1:]):
            left = int((min(start[0], end[0]) - padding) / cell)
            right = int((max(start[0], end[0]) + padding) / cell)
            bottom = int((min(start[1], end[1]) - padding) / cell)
            top = int((max(start[1], end[1]) + padding) / cell)
            for x in range(left, right + 1):
                for y in range(bottom, top + 1):
                    index[(x, y)].append((start, end))
    return index, cell


def within_corridor(lines, index, cell):
    # Test every surveyed vertex.  ORWN linework is already segmented at
    # railway topology changes, so admitting a record by one nearby vertex
    # preserves the connecting record needed at station and junction limits.
    for line in lines:
        for point in line:
            candidates = index.get((int(point[0] / cell),
                                    int(point[1] / cell)), ())
            if any(point_segment_distance(point, start, end)
                   <= CORRIDOR_METERS for start, end in candidates):
                return True
    return False


def normalized_feature(properties, lines):
    dense = [geo.densify(line, 25.0) for line in lines if len(line) >= 2]
    geometry = ({'type': 'LineString', 'coordinates': dense[0]}
                if len(dense) == 1 else
                {'type': 'MultiLineString', 'coordinates': dense})
    return {'type': 'Feature', 'properties': properties,
            'geometry': geometry}


def route_groups(orwn, go_shapes, up_shapes):
    route_shapes = {
        **{f'go-{name.lower()}': shapes
           for name, shapes in go_shapes.items()},
        **{f'up-{name.lower()}': shapes
           for name, shapes in up_shapes.items()},
    }
    groups = {}
    for stable_name, shapes in route_shapes.items():
        index, cell = segment_index(shapes)
        selected = []
        for properties, lines in orwn:
            if (properties.get('ADMINAREA') != 'Ontario'
                    or properties.get('STATUS') != 'Operational'
                    or properties.get('TRACKCLASS')
                    not in ALLOWED_TRACK_CLASSES):
                continue
            if within_corridor(lines, index, cell):
                selected.append(normalized_feature(properties, lines))
        key = f'orwn-{stable_name}'
        if not selected:
            raise SystemExit(f'{key}: no provincial railway selected')
        groups[key] = selected
    return groups


def official_routing_network(features):
    edges = []
    for feature in features:
        geometry = feature['geometry']
        lines = ([geometry['coordinates']]
                 if geometry['type'] == 'LineString'
                 else geometry['coordinates'])
        for line in lines:
            if len(line) < 2:
                continue
            properties = dict(feature['properties'])
            properties['FRFRANODE'] = tuple(round(value, 6)
                                            for value in line[0])
            properties['TOFRANODE'] = tuple(round(value, 6)
                                            for value in line[-1])
            edges.append({
                'type': 'Feature', 'properties': properties,
                'geometry': {'type': 'LineString', 'coordinates': line},
            })
    return na_narn.Network(edges)


def remove_short_return_spikes(points, tolerance_m=5.0):
    """Remove only A-B-A survey branches whose outer points coincide.

    ORWN contains short crossover/spur excursions in the routable topology.
    A route can enter one and immediately return to the same centreline,
    producing an impossible 177-degree train reversal.  Requiring the outer
    official coordinates to agree within five metres makes this a topology
    cleanup, not a geometric simplification.
    """
    def turn(a, b, c):
        latitude = math.radians((a[1] + b[1] + c[1]) / 3.0)
        scale_x = 111_195.0 * math.cos(latitude)
        ux, uy = ((b[0] - a[0]) * scale_x,
                  (b[1] - a[1]) * 111_195.0)
        vx, vy = ((c[0] - b[0]) * scale_x,
                  (c[1] - b[1]) * 111_195.0)
        denominator = math.hypot(ux, uy) * math.hypot(vx, vy)
        if denominator == 0:
            return 0.0
        cosine = max(-1.0, min(1.0, (ux * vx + uy * vy) / denominator))
        return math.degrees(math.acos(cosine))

    cleaned = []
    for point in points:
        cleaned.append(point)
        while (len(cleaned) >= 3
               and geo.haversine(cleaned[-3], cleaned[-1]) <= tolerance_m):
            del cleaned[-2:]
        changed = True
        while changed and len(cleaned) >= 3:
            changed = False
            # A several-hundred-metre excursion returning within 50 metres of
            # the same centreline is a spur selection, not a passenger path.
            for index in range(1, len(cleaned) - 1):
                a, b, c = cleaned[index - 1:index + 2]
                if (turn(a, b, c) >= 170.0
                        and geo.haversine(a, c) <= 50.0):
                    del cleaned[index]
                    changed = True
                    break
            if changed:
                continue
            # Two consecutive reversals enclose one short backwards segment
            # on a parallel rail.  Remove whichever inner vertex leaves the
            # straighter official centreline continuation.
            for index in range(1, len(cleaned) - 2):
                a, b, c, d = cleaned[index - 1:index + 3]
                if (turn(a, b, c) >= 160.0
                        and turn(b, c, d) >= 160.0
                        and geo.haversine(b, c) <= 200.0):
                    remove_b = turn(a, c, d)
                    remove_c = turn(a, b, d)
                    del cleaned[index if remove_b <= remove_c else index + 1]
                    changed = True
                    break
    return cleaned


def routed_groups(orwn, go_data, up_data):
    raw_groups = route_groups(
        orwn,
        {name: data['shapes'] for name, data in go_data.items()},
        {name: data['shapes'] for name, data in up_data.items()})
    all_data = {
        **{f'orwn-go-{name.lower()}': data
           for name, data in go_data.items()},
        **{f'orwn-up-{name.lower()}': data
           for name, data in up_data.items()},
    }
    groups = {}
    for key, candidates in raw_groups.items():
        network = official_routing_network(candidates)
        routed = []
        seen = set()
        for pattern_index, pattern in enumerate(all_data[key]['patterns']):
            stations = pattern['stationPoints']
            # Platform markers can lie beside several tracks at a junction.
            # Projecting them onto the operator's own shape chooses which
            # surveyed ORWN rail to route, without copying any GTFS geometry.
            selectors = [geo.project_to_line(point, pattern['shape'])[3]
                         for point in stations]
            intervals, _ = na_narn.route_stations(
                network, [pattern['shape'], selectors], selectors,
                width_m=300.0, max_snap_m=600.0, pad_cells=1)
            for interval_index, interval in enumerate(intervals):
                if not interval or len(interval) < 2:
                    continue
                interval = remove_short_return_spikes(interval)
                signature = min(
                    tuple((round(point[0], 6), round(point[1], 6))
                          for point in interval),
                    tuple((round(point[0], 6), round(point[1], 6))
                          for point in reversed(interval)))
                if signature in seen:
                    continue
                seen.add(signature)
                routed.append({
                    'type': 'Feature',
                    'properties': {
                        'sourceDataset': 'Ontario Railway Network Track',
                        'routeKey': key,
                        'gtfsSelectionTrip': pattern['tripId'],
                        'patternIndex': pattern_index,
                        'intervalIndex': interval_index,
                    },
                    'geometry': {
                        'type': 'LineString',
                        'coordinates': geo.densify(interval, 25.0),
                    },
                })
        if not routed:
            raise SystemExit(f'{key}: ORWN could not route a GTFS pattern')
        groups[key] = routed
    return groups


def load_manifest(output_dir):
    path = os.path.join(output_dir, 'manifest.json')
    if not os.path.exists(path):
        return {'schemaVersion': 1, 'sources': {}, 'files': {}}
    with open(path, encoding='utf-8') as source:
        manifest = json.load(source)
    if manifest.get('schemaVersion') != 1:
        raise SystemExit('official-network manifest schema is unsupported')
    manifest.setdefault('sources', {})
    manifest.setdefault('files', {})
    return manifest


def normalize(output_dir, orwn_input, go_gtfs, up_gtfs):
    with open(orwn_input, 'rb') as source:
        raw = source.read()
    orwn = read_orwn(raw)
    groups = routed_groups(orwn,
                           gtfs_route_data(go_gtfs, 'GO Transit'),
                           gtfs_route_data(up_gtfs, 'UP Express'))
    raw_sha = digest(raw)
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['sources']['ontario-orwn'] = {
        **SOURCE, 'rawSha256': raw_sha, 'featureCount': len(orwn),
    }
    manifest['files'] = {
        key: value for key, value in manifest['files'].items()
        if not key.startswith('orwn-go-') and not key.startswith('orwn-up-')
    }
    for key, features in sorted(groups.items()):
        document = {'type': 'FeatureCollection', 'sourceId': key,
                    'source': {**SOURCE, 'rawSha256': raw_sha},
                    'features': features}
        encoded = json.dumps(document, ensure_ascii=False,
                             separators=(',', ':')).encode()
        filename = f'{key}.geojson'
        path = os.path.join(output_dir, filename)
        with open(path + '.tmp', 'wb') as output:
            output.write(encoded)
        os.replace(path + '.tmp', path)
        manifest['files'][key] = {
            'file': filename, 'features': len(features),
            'sha256': digest(encoded),
        }
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    path = os.path.join(output_dir, 'manifest.json')
    with open(path + '.tmp', 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2)
        output.write('\n')
    os.replace(path + '.tmp', path)
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--orwn-input', required=True)
    parser.add_argument('--go-gtfs', required=True)
    parser.add_argument('--up-gtfs', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, args.orwn_input,
                         args.go_gtfs, args.up_gtfs)
    count = sum(key.startswith(('orwn-go-', 'orwn-up-'))
                for key in manifest['files'])
    print(f'wrote {count} route-isolated Ontario railway networks')


if __name__ == '__main__':
    main()
