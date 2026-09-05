#!/usr/bin/env python3
"""Normalize City of Ottawa engineering alignments for O-Train Lines 2/4.

The Rail Implementation Office layer contains both the Trillium main line and
Airport branch, plus unrelated CAD linework.  This normalizer accepts only the
three published track-alignment layers, then uses OC Transpo's official GTFS
station order to emit one route-isolated network per passenger service.  GTFS
selects the path; every output coordinate comes from the City engineering GIS.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import io
import json
import os
import sys
import zipfile
from collections import defaultdict


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))
import na_official


SOURCE = {
    'publisher': 'City of Ottawa / Rail Implementation Office',
    'catalogUrl': ('https://maps.ottawa.ca/arcgis/rest/services/'
                   'Rail_Implementation_Office/MapServer/33'),
    'url': ('https://maps.ottawa.ca/arcgis/rest/services/'
            'Rail_Implementation_Office/MapServer/33/query?'
            "where=REFNAME%3D%27Trillium%27%20AND%20LAYER%20LIKE%20"
            "%27T-ALIGN%25%27&outFields=OBJECTID%2CLAYER%2CREFNAME&"
            'returnGeometry=true&outSR=4326&f=geojson'),
    'license': 'Open Government Licence – City of Ottawa',
}
ALIGNMENT_LAYERS = {
    'T-ALIGN-NB ALIGN',
    'T-ALIGN-SB ALIGN',
    'T-ALIGN-MISC ALIGN',
}
TARGETS = {
    '2': 'ottawa-trillium-2',
    '4': 'ottawa-trillium-4',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def official_features(raw):
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'Ottawa alignment is not valid GeoJSON: {exc}')
    if payload.get('type') != 'FeatureCollection':
        raise SystemExit('Ottawa alignment is not a FeatureCollection')
    result = []
    for feature in payload.get('features') or ():
        properties = feature.get('properties') or {}
        geometry = feature.get('geometry') or {}
        if (properties.get('REFNAME') != 'Trillium'
                or properties.get('LAYER') not in ALIGNMENT_LAYERS):
            continue
        if geometry.get('type') not in ('LineString', 'MultiLineString'):
            raise SystemExit('Ottawa track alignment contains non-line geometry')
        result.append(feature)
    if not result:
        raise SystemExit('Ottawa layer contains no audited Trillium alignment')
    return result


def gtfs_patterns(path):
    with zipfile.ZipFile(path) as archive:
        def rows(name):
            return list(csv.DictReader(io.TextIOWrapper(
                archive.open(name), encoding='utf-8-sig', newline='')))

        routes = {row['route_id']: row for row in rows('routes.txt')
                  if row.get('route_short_name') in TARGETS}
        trips = {row['trip_id']: row for row in rows('trips.txt')
                 if row.get('route_id') in routes}
        stops = {row['stop_id']: row for row in rows('stops.txt')}
        times = defaultdict(list)
        for row in rows('stop_times.txt'):
            if row.get('trip_id') in trips and row.get('stop_id') in stops:
                times[row['trip_id']].append(
                    (int(row['stop_sequence']), row['stop_id']))

    patterns = {route: {} for route in TARGETS}
    for trip_id, sequence in times.items():
        route_id = trips[trip_id]['route_id']
        route = routes[route_id]['route_short_name']
        stop_ids = []
        points = []
        for _, stop_id in sorted(sequence):
            if stop_ids and stop_ids[-1] == stop_id:
                continue
            stop = stops[stop_id]
            try:
                point = [float(stop['stop_lon']), float(stop['stop_lat'])]
            except (KeyError, TypeError, ValueError):
                continue
            stop_ids.append(stop_id)
            points.append(point)
        if len(points) < 2:
            continue
        sequence_key = tuple(stop_ids)
        if tuple(reversed(sequence_key)) < sequence_key:
            sequence_key = tuple(reversed(sequence_key))
            points.reverse()
        patterns[route].setdefault(sequence_key, {
            'tripId': trip_id,
            'stationPoints': points,
        })

    def subsequence(small, large):
        iterator = iter(large)
        return all(any(value == candidate for candidate in iterator)
                   for value in small)

    for route, by_sequence in patterns.items():
        patterns[route] = [
            pattern for sequence, pattern in by_sequence.items()
            if not any(len(other) > len(sequence)
                       and subsequence(sequence, other)
                       for other in by_sequence)
        ]
        if not patterns[route]:
            raise SystemExit(f'OC Transpo GTFS has no Line {route} pattern')
    return patterns


def route_groups(features, patterns):
    # Bayview's short double-track section is digitized as separate
    # T-ALIGN-NB / T-ALIGN-SB layers. The southbound layer's free end lands
    # 0.0017 m from a vertex-free point on the northbound polyline's
    # interior at the merge south of Corso Italia (measured against the
    # 2026-09 Rail Implementation Office extract) -- sub-millimetre
    # agreement that is the same physical point recorded twice, not a gap.
    # 2.0 m stays far below any real distance between parallel tracks.
    network = na_official.PassengerNetwork(features, endpoint_line_join_m=2.0)
    groups = {}
    for route, key in TARGETS.items():
        output = []
        seen = set()
        for pattern_index, pattern in enumerate(patterns[route]):
            intervals, diagnostic = network.route_stations(
                pattern['stationPoints'], max_snap_m=300.0)
            if not intervals:
                raise SystemExit(
                    f'{key}: City alignment cannot route official GTFS '
                    f'pattern {pattern["tripId"]}: {diagnostic}')
            for interval_index, interval in enumerate(intervals):
                signature = min(
                    tuple((round(point[0], 7), round(point[1], 7))
                          for point in interval),
                    tuple((round(point[0], 7), round(point[1], 7))
                          for point in reversed(interval)))
                if signature in seen:
                    continue
                seen.add(signature)
                output.append({
                    'type': 'Feature',
                    'properties': {
                        'routeKey': key,
                        'sourceDataset': 'Stage 2 Alignment',
                        'gtfsSelectionTrip': pattern['tripId'],
                        'patternIndex': pattern_index,
                        'intervalIndex': interval_index,
                    },
                    'geometry': {
                        'type': 'LineString',
                        'coordinates': interval,
                    },
                })
        if not output:
            raise SystemExit(f'{key}: official route extract is empty')
        groups[key] = output
    return groups


def load_manifest(output_dir):
    path = os.path.join(output_dir, 'manifest.json')
    try:
        with open(path, encoding='utf-8') as source:
            manifest = json.load(source)
    except FileNotFoundError:
        manifest = {'schemaVersion': 1, 'sources': {}, 'files': {}}
    if manifest.get('schemaVersion') != 1:
        raise SystemExit('official-network manifest schema is unsupported')
    manifest.setdefault('sources', {})
    manifest.setdefault('files', {})
    return manifest


def normalize(output_dir, alignment_input, gtfs_input, generated_at=None):
    with open(alignment_input, 'rb') as source:
        raw = source.read()
    raw_sha = digest(raw)
    groups = route_groups(official_features(raw), gtfs_patterns(gtfs_input))
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['sources']['ottawa-trillium'] = {
        **SOURCE, 'rawSha256': raw_sha,
    }
    manifest['files'] = {
        key: value for key, value in manifest['files'].items()
        if not key.startswith('ottawa-trillium-')
    }
    for key, features in sorted(groups.items()):
        payload = {
            'type': 'FeatureCollection',
            'sourceId': key,
            'source': {**SOURCE, 'rawSha256': raw_sha},
            'features': features,
        }
        encoded = json.dumps(payload, ensure_ascii=False,
                             separators=(',', ':')).encode()
        filename = f'{key}.geojson'
        path = os.path.join(output_dir, filename)
        with open(path + '.tmp', 'wb') as output:
            output.write(encoded)
        os.replace(path + '.tmp', path)
        manifest['files'][key] = {
            'file': filename,
            'features': len(features),
            'sha256': digest(encoded),
        }
    manifest['generatedAt'] = (generated_at
                               or dt.datetime.now(dt.timezone.utc).isoformat())
    path = os.path.join(output_dir, 'manifest.json')
    with open(path + '.tmp', 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2)
        output.write('\n')
    os.replace(path + '.tmp', path)
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--alignment-input', required=True)
    parser.add_argument('--gtfs-input', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, args.alignment_input,
                         args.gtfs_input)
    print(f'wrote {sum(key.startswith("ottawa-trillium-") for key in manifest["files"])} Ottawa route networks')


if __name__ == '__main__':
    main()
