#!/usr/bin/env python3
"""Download and normalize route-specific official metro centrelines.

GTFS remains authoritative for service identity and station order.  These
government/operator spatial datasets are authoritative for the physical
alignment.  Each output file contains one service only: routing over a whole
city network could otherwise jump between adjacent or shared tracks.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import urllib.request

from lib.na_provenance import SOURCES

MTA_SERVICE_KEYS = {
    '1': 'mta-subway-1',
    '2': 'mta-subway-2',
    '3': 'mta-subway-3',
    '4': 'mta-subway-4',
    '5': 'mta-subway-5',
    '5 Peak': 'mta-subway-5',
    '6': 'mta-subway-6',
    '7': 'mta-subway-7',
    'A': 'mta-subway-a',
    'B': 'mta-subway-b',
    'C': 'mta-subway-c',
    'D': 'mta-subway-d',
    'E': 'mta-subway-e',
    'F': 'mta-subway-f',
    'SF': 'mta-subway-fs',
    'G': 'mta-subway-g',
    'ST': 'mta-subway-gs',
    'SR': 'mta-subway-h',
    'J': 'mta-subway-j',
    'L': 'mta-subway-l',
    'M': 'mta-subway-m',
    'N': 'mta-subway-n',
    'Q': 'mta-subway-q',
    'R': 'mta-subway-r',
    'SIR': 'mta-subway-si',
    'W': 'mta-subway-w',
    'Z': 'mta-subway-z',
}

CTA_ROUTE_KEYS = {
    'blue': 'cta-blue',
    'brown': 'cta-brown',
    'green': 'cta-green',
    'orange': 'cta-orange',
    'pink': 'cta-pink',
    'purple': 'cta-purple',
    'red': 'cta-red',
    'yellow': 'cta-yellow',
}

NORTA_ROUTE_KEYS = {
    '12': 'norta-12',
    '47': 'norta-47',
    '48': 'norta-48',
}

# The 2022 City layer contains short-turns and both directions as independent
# features.  Mixing them into one graph creates false cycles at Canal Street.
# These are the complete, single-direction city-published alignments whose
# endpoints cover the current operator GTFS station sequence.
NORTA_PRIMARY_SHAPES = {
    '12': 'shp-12-01',
    '47': 'shp-47-01',
    '48': 'shp-48-08',
}

SOURCE_FILE_PREFIXES = {
    'mta': ('mta-subway-',),
    'cta': ('cta-',),
    'norta': ('norta-',),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fetch(url):
    request = urllib.request.Request(
        url, headers={'User-Agent': 'JTM railway data builder/1.0'})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def read_source(path, source):
    if path:
        with open(path, 'rb') as fh:
            return fh.read()
    return fetch(SOURCES[source]['url'])


def parse_geojson(raw, source):
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{source}: response is not valid GeoJSON: {exc}')
    if payload.get('type') != 'FeatureCollection':
        raise SystemExit(f'{source}: expected a GeoJSON FeatureCollection')
    features = payload.get('features') or []
    if not features:
        raise SystemExit(f'{source}: official dataset is empty')
    for feature in features:
        geometry = feature.get('geometry') or {}
        if geometry.get('type') not in ('LineString', 'MultiLineString'):
            raise SystemExit(f'{source}: non-line geometry in official dataset')
    return features


def mta_groups(features):
    groups = {key: [] for key in set(MTA_SERVICE_KEYS.values())}
    unknown = set()
    for feature in features:
        service = str((feature.get('properties') or {}).get('service') or '')
        key = MTA_SERVICE_KEYS.get(service)
        if key is None:
            unknown.add(service)
            continue
        groups[key].append(feature)
    if unknown:
        raise SystemExit('MTA dataset contains unmapped services: '
                         + ', '.join(sorted(unknown)))
    return groups


def cta_groups(features):
    groups = {key: [] for key in CTA_ROUTE_KEYS.values()}
    for feature in features:
        lines = str((feature.get('properties') or {}).get('lines') or '').lower()
        for route, key in CTA_ROUTE_KEYS.items():
            if route in lines:
                groups[key].append(feature)
    return groups


def norta_groups(features):
    groups = {key: [] for key in NORTA_ROUTE_KEYS.values()}
    for feature in features:
        properties = feature.get('properties') or {}
        route_id = str(properties.get('route_id') or '')
        key = NORTA_ROUTE_KEYS.get(route_id)
        if key and properties.get('shape_id') == NORTA_PRIMARY_SHAPES[route_id]:
            groups[key].append(feature)
    return groups


def write_group(output_dir, key, features, source, raw_sha):
    if not features:
        raise SystemExit(f'{key}: no matching features in official dataset')
    payload = {
        'type': 'FeatureCollection',
        'sourceId': key,
        'source': {
            'publisher': SOURCES[source]['publisher'],
            'url': SOURCES[source]['url'],
            'rawSha256': raw_sha,
        },
        'features': features,
    }
    path = os.path.join(output_dir, f'{key}.geojson')
    with open(path + '.tmp', 'w', encoding='utf-8') as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(',', ':'))
    os.replace(path + '.tmp', path)
    with open(path, 'rb') as source_file:
        normalized_sha = digest(source_file.read())
    return {'file': os.path.basename(path), 'features': len(features),
            'sha256': normalized_sha}


def load_manifest(output_dir):
    """Load the shared manifest without erasing other authorities' entries."""
    manifest_path = os.path.join(output_dir, 'manifest.json')
    try:
        with open(manifest_path, encoding='utf-8') as source:
            manifest = json.load(source)
    except FileNotFoundError:
        manifest = {'schemaVersion': 1, 'sources': {}, 'files': {}}
    if manifest.get('schemaVersion') != 1:
        raise SystemExit('official network manifest has unsupported schemaVersion')
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    manifest.setdefault('sources', {})
    manifest.setdefault('files', {})
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--mta-input', help='use an already downloaded MTA GeoJSON')
    parser.add_argument('--cta-input', help='use an already downloaded CTA GeoJSON')
    parser.add_argument('--norta-input',
                        help='use an already downloaded New Orleans GeoJSON')
    args = parser.parse_args()
    os.makedirs(args.output_dir, exist_ok=True)

    manifest_path = os.path.join(args.output_dir, 'manifest.json')
    manifest = load_manifest(args.output_dir)
    for source, supplied, grouper in (
            ('mta', args.mta_input, mta_groups),
            ('cta', args.cta_input, cta_groups),
            ('norta', args.norta_input, norta_groups)):
        raw = read_source(supplied, source)
        raw_sha = digest(raw)
        features = parse_geojson(raw, source)
        prefixes = SOURCE_FILE_PREFIXES[source]
        manifest['files'] = {
            key: value for key, value in manifest['files'].items()
            if not key.startswith(prefixes)
        }
        manifest['sources'][source] = {
            **SOURCES[source], 'rawSha256': raw_sha,
            'featureCount': len(features),
        }
        for key, selected in sorted(grouper(features).items()):
            manifest['files'][key] = write_group(
                args.output_dir, key, selected, source, raw_sha)

    with open(manifest_path + '.tmp', 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    os.replace(manifest_path + '.tmp', manifest_path)
    print(f'wrote {len(manifest["files"])} route-specific official networks')


if __name__ == '__main__':
    main()
