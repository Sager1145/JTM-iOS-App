#!/usr/bin/env python3
"""Build route-isolated UTA networks from Utah's imagery-surveyed tracks.

The state layer distinguishes FrontRunner, the S-Line, and named TRAX
branches.  Older shared TRAX track has only the generic ``TRAX`` division, so
those records are admitted to a route only when they are within 200 metres of
that route's operator-published GTFS shapes.  Geometry is always copied from
the independent state survey; GTFS is used only to select the serving route.
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


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))
import na_geo as geo


SOURCE = {
    'publisher': 'Utah Geospatial Resource Center (UGRC)',
    'url': ('https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/'
            'services/UtahRailroads/FeatureServer/0/query?where='
            'OPERATOR%3D%27UT%20Transit%20Auth%27&outFields=*&'
            'returnGeometry=true&outSR=4326&f=geojson'),
}

# Stable GTFS route_id -> public service number -> normalized network key.
ROUTES = {
    '5907': ('701', 'uta-701'),
    '8246': ('703', 'uta-703'),
    '39020': ('704', 'uta-704'),
    '45389': ('720', 'uta-720'),
    '41065': ('750', 'uta-750'),
}
def digest(data):
    return hashlib.sha256(data).hexdigest()


def geometry_lines(feature):
    geometry = feature.get('geometry') or {}
    if geometry.get('type') == 'LineString':
        return [geometry.get('coordinates') or []]
    if geometry.get('type') == 'MultiLineString':
        return geometry.get('coordinates') or []
    raise SystemExit('Utah official railroad feature is not line geometry')


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


def feature_endpoints(feature):
    return [endpoint for line in geometry_lines(feature) if len(line) >= 2
            for endpoint in (line[0], line[-1])]


def exact_track_components(features, join_meters=1.0):
    """Separate the two surveyed rails before station snapping.

    UGRC represents each physical TRAX rail independently.  Joining the two
    rails at a 25 m routing tolerance creates a false giant loop: adjacent
    platforms can snap to opposite rails and the path runs to a terminus and
    back.  Survey records on the same rail share endpoints to sub-metre
    accuracy, so a one-metre component split is evidence-based.
    """
    parents = list(range(len(features)))

    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(left, right):
        left, right = root(left), root(right)
        if left != right:
            parents[right] = left

    endpoints = [feature_endpoints(feature) for feature in features]
    for left in range(len(features)):
        for right in range(left + 1, len(features)):
            if any(geo.haversine(a, b) <= join_meters
                   for a in endpoints[left] for b in endpoints[right]):
                union(left, right)
    groups = defaultdict(list)
    for index, feature in enumerate(features):
        groups[root(index)].append(feature)
    return list(groups.values())


def component_shape_score(features, shape):
    segments = [(a, b) for feature in features
                for line in geometry_lines(feature)
                for a, b in zip(line, line[1:])]
    sample = shape[::max(1, len(shape) // 250)]
    return sum(min(point_segment_distance(point, a, b)
                   for a, b in segments) for point in sample) / len(sample)


def primary_surveyed_rail(features, route_shapes):
    components = exact_track_components(features)
    if len(components) == 1:
        return components[0]
    # The longest operator shape identifies one service direction.  It never
    # contributes coordinates; it only chooses between the two independently
    # surveyed parallel rails.
    shape = max(route_shapes, key=lambda row: geo.line_length(row))
    ranked = sorted((component_shape_score(component, shape), component)
                    for component in components)
    if len(ranked) > 1 and ranked[1][0] - ranked[0][0] < 0.25:
        raise SystemExit('parallel surveyed rails are ambiguous for UTA route')
    return ranked[0][1]


def gtfs_route_shapes(path):
    with zipfile.ZipFile(path) as archive:
        def rows(name):
            return list(csv.DictReader(io.TextIOWrapper(
                archive.open(name), encoding='utf-8-sig', newline='')))

        trips = rows('trips.txt')
        shape_rows = rows('shapes.txt')

    shape_ids = defaultdict(set)
    for row in trips:
        if row.get('route_id') in ROUTES and row.get('shape_id'):
            shape_ids[row['route_id']].add(row['shape_id'])

    points = defaultdict(list)
    for row in shape_rows:
        if any(row.get('shape_id') in values for values in shape_ids.values()):
            points[row['shape_id']].append((
                int(row['shape_pt_sequence']),
                [float(row['shape_pt_lon']), float(row['shape_pt_lat'])]))

    result = {}
    for route_id in ROUTES:
        result[route_id] = [
            [point for _, point in sorted(points[shape_id])]
            for shape_id in sorted(shape_ids[route_id])
            if len(points[shape_id]) >= 2
        ]
        if not result[route_id]:
            raise SystemExit(f'UTA GTFS route {route_id} has no usable shapes')
    return result


def normalized_feature(feature):
    lines = [geo.densify(line, 25.0) for line in geometry_lines(feature)
             if len(line) >= 2]
    if not lines:
        raise SystemExit('Utah official railroad feature has no coordinates')
    geometry = ({'type': 'LineString', 'coordinates': lines[0]}
                if len(lines) == 1 else
                {'type': 'MultiLineString', 'coordinates': lines})
    return {'type': 'Feature',
            'properties': dict(feature.get('properties') or {}),
            'geometry': geometry}


def route_groups(features, shapes):
    for feature in features:
        props = feature.get('properties') or {}
        if props.get('OPERATOR') != 'UT Transit Auth':
            raise SystemExit('Utah railroad response contains another operator')

    groups = {}
    for route_id, (public, key) in ROUTES.items():
        candidates = []
        for feature in features:
            division = str((feature.get('properties') or {}).get('DIVISION')
                           or '')
            if public == '750':
                include = division == 'FRONT RUNNER'
            else:
                include = public in division
            if include:
                candidates.append(feature)
        if not candidates:
            raise SystemExit(f'{key}: no state-surveyed track selected')
        if public in ('701', '703', '704'):
            candidates = primary_surveyed_rail(candidates, shapes[route_id])
        groups[key] = [normalized_feature(feature) for feature in candidates]
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


def normalize(output_dir, railroad_input, gtfs_input):
    with open(railroad_input, 'rb') as source:
        raw = source.read()
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'Utah railroad source is invalid: {exc}')
    if payload.get('type') != 'FeatureCollection' or not payload.get('features'):
        raise SystemExit('Utah railroad source is empty')

    groups = route_groups(payload['features'], gtfs_route_shapes(gtfs_input))
    raw_sha = digest(raw)
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['sources']['utah-railroads'] = {
        **SOURCE, 'rawSha256': raw_sha,
        'featureCount': len(payload['features']),
    }
    manifest['files'] = {key: value for key, value in manifest['files'].items()
                         if not key.startswith('uta-')}
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
    parser.add_argument('--railroad-input', required=True)
    parser.add_argument('--gtfs-input', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, args.railroad_input, args.gtfs_input)
    print('wrote 5 route-isolated UTA networks; manifest now contains '
          f'{len(manifest["files"])} files')


if __name__ == '__main__':
    main()
