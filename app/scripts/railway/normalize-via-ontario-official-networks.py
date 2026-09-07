#!/usr/bin/env python3
"""Build route-isolated VIA networks from Ontario's surveyed ORWN tracks.

VIA GTFS is used only to select a broad corridor and the appropriate track at
junctions.  Every output coordinate comes from Ontario's independent Railway
Network Track dataset.  Route ids are explicit so one VIA service cannot leak
into another service's network.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import importlib.util
import io
import json
import os
import sys
import zipfile
from collections import defaultdict


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))
import na_geo as geo
import na_narn


CENTRAL_PATH = os.path.join(
    HERE, 'normalize-ca-central-official-networks.py')
SPEC = importlib.util.spec_from_file_location('ca_central_official',
                                               CENTRAL_PATH)
central = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(central)


SOURCE = central.SOURCE
TARGETS = {
    '119-93': 'orwn-via-119-93',
    '119-341': 'orwn-via-119-341',
    '119-618': 'orwn-via-119-618',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def via_route_data(path):
    with zipfile.ZipFile(path) as archive:
        def rows(name):
            return list(csv.DictReader(io.TextIOWrapper(
                archive.open(name), encoding='utf-8-sig', newline='')))

        routes = rows('routes.txt')
        trips = rows('trips.txt')
        shapes = rows('shapes.txt')
        stop_times = rows('stop_times.txt')
        stops = {row['stop_id']: row for row in rows('stops.txt')}

    route_ids = {row['route_id'] for row in routes
                 if row.get('route_type') == '2'} & set(TARGETS)
    if route_ids != set(TARGETS):
        missing = sorted(set(TARGETS) - route_ids)
        raise SystemExit(f'VIA GTFS is missing audited route ids: {missing}')

    trips_by_id = {row['trip_id']: row for row in trips
                   if row.get('route_id') in route_ids}
    shape_routes = defaultdict(set)
    for trip in trips_by_id.values():
        if trip.get('shape_id'):
            shape_routes[trip['shape_id']].add(trip['route_id'])
    shape_points = defaultdict(list)
    for row in shapes:
        if row.get('shape_id') in shape_routes:
            shape_points[row['shape_id']].append((
                int(row['shape_pt_sequence']),
                [float(row['shape_pt_lon']), float(row['shape_pt_lat'])]))

    result = {route_id: {'shapes': [], 'patterns': {}}
              for route_id in route_ids}
    for shape_id, route_id_values in shape_routes.items():
        shape = [point for _, point in sorted(shape_points[shape_id])]
        if len(shape) < 2:
            continue
        for route_id in route_id_values:
            result[route_id]['shapes'].append(shape)

    times = defaultdict(list)
    for row in stop_times:
        if row.get('trip_id') in trips_by_id and row.get('stop_id') in stops:
            times[row['trip_id']].append((int(row['stop_sequence']),
                                          row['stop_id']))
    for trip_id, sequence in times.items():
        trip = trips_by_id[trip_id]
        stop_ids = []
        station_points = []
        for _, stop_id in sorted(sequence):
            if stop_ids and stop_ids[-1] == stop_id:
                continue
            stop = stops[stop_id]
            try:
                point = [float(stop['stop_lon']), float(stop['stop_lat'])]
            except (KeyError, TypeError, ValueError):
                continue
            stop_ids.append(stop_id)
            station_points.append(point)
        shape = [point for _, point in sorted(
            shape_points.get(trip.get('shape_id')) or ())]
        if len(stop_ids) < 2 or len(shape) < 2:
            continue
        forward = tuple(stop_ids)
        reverse = tuple(reversed(stop_ids))
        if reverse < forward:
            forward = reverse
            station_points.reverse()
            shape.reverse()
        previous = result[trip['route_id']]['patterns'].get(forward)
        if previous is None or geo.line_length(shape) > geo.line_length(
                previous['shape']):
            result[trip['route_id']]['patterns'][forward] = {
                'stationPoints': station_points,
                'shape': shape,
                'tripId': trip_id,
            }

    def subsequence(small, large):
        iterator = iter(large)
        return all(any(value == candidate for candidate in iterator)
                   for value in small)

    for route_id, data in result.items():
        patterns = data['patterns']
        data['patterns'] = [
            pattern for sequence, pattern in patterns.items()
            if not any(len(other) > len(sequence)
                       and subsequence(sequence, other)
                       for other in patterns)
        ]
        if not data['shapes'] or not data['patterns']:
            raise SystemExit(f'{route_id}: VIA GTFS has no usable rail pattern')
    return result


def route_groups(orwn, route_data):
    groups = {}
    for route_id, key in TARGETS.items():
        data = route_data[route_id]
        index, cell = central.segment_index(data['shapes'])
        selected = []
        for properties, lines in orwn:
            if (properties.get('ADMINAREA') != 'Ontario'
                    or properties.get('STATUS') != 'Operational'
                    or properties.get('TRACKCLASS')
                    not in central.ALLOWED_TRACK_CLASSES):
                continue
            if central.within_corridor(lines, index, cell):
                selected.append(central.normalized_feature(properties, lines))
        if not selected:
            raise SystemExit(f'{key}: no provincial railway selected')

        network = central.official_routing_network(selected)
        routed = []
        seen = set()
        for pattern_index, pattern in enumerate(data['patterns']):
            selectors = [geo.project_to_line(point, pattern['shape'])[3]
                         for point in pattern['stationPoints']]
            intervals, _ = na_narn.route_stations(
                network, [pattern['shape'], selectors], selectors,
                width_m=300.0, max_snap_m=600.0, pad_cells=1)
            for interval_index, interval in enumerate(intervals):
                if not interval or len(interval) < 2:
                    continue
                interval = central.remove_short_return_spikes(interval)
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
            raise SystemExit(f'{key}: ORWN could not route a VIA pattern')
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


def normalize(output_dir, orwn_input, via_gtfs):
    with open(orwn_input, 'rb') as source:
        raw = source.read()
    groups = route_groups(central.read_orwn(raw), via_route_data(via_gtfs))
    raw_sha = digest(raw)
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['sources']['ontario-orwn'] = {
        **SOURCE, 'rawSha256': raw_sha,
    }
    manifest['files'] = {
        key: value for key, value in manifest['files'].items()
        if not key.startswith('orwn-via-')
    }
    for key, features in sorted(groups.items()):
        document = {
            'type': 'FeatureCollection', 'sourceId': key,
            'source': {**SOURCE, 'rawSha256': raw_sha},
            'features': features,
        }
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
    parser.add_argument('--via-gtfs', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, args.orwn_input, args.via_gtfs)
    count = sum(key.startswith('orwn-via-') for key in manifest['files'])
    print(f'wrote {count} route-isolated VIA Ontario networks')


if __name__ == '__main__':
    main()
