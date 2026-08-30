#!/usr/bin/env python3
"""Normalize LA County/Metro and DataSF/SFMTA route-specific GIS lines."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import sys


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))
import na_geo as geo


SOURCES = {
    'la-metro': {
        'publisher': 'Los Angeles County / LA Metro',
        'url': ('https://services.arcgis.com/RmCCgQtiZLDCtblq/ArcGIS/rest/'
                'services/MTA_Metro_Lines/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&returnGeometry=true&outSR=4326&f=geojson'),
    },
    'sfmta': {
        'publisher': 'DataSF / San Francisco Municipal Transportation Agency',
        'url': ('https://data.sfgov.org/api/v3/views/9exe-acju/'
                'query.geojson?accessType=DOWNLOAD'),
    },
}

LA_ROUTES = {
    '801': ('Metro A Line', 'Metro A & E Line'),
    '802': ('Metro B Line', 'Metro B & D Line'),
    '803': ('Metro C Line',),
    '804': ('Metro E Line', 'Metro A & E Line'),
    '805': ('Metro D Line', 'Metro B & D Line'),
    '807': ('Metro K Line',),
}
SFMTA_ROUTES = {'C': 'CA', 'F': 'F', 'J': 'J', 'K': 'K', 'L': 'L',
                'M': 'M', 'N': 'N', 'PH': 'PH', 'PM': 'PM', 'T': 'T'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def parse_geojson(raw, source):
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{source}: invalid GeoJSON: {exc}')
    if payload.get('type') != 'FeatureCollection' or not payload.get('features'):
        raise SystemExit(f'{source}: empty or invalid FeatureCollection')
    return payload['features']


def feature_lines(feature):
    geometry = feature.get('geometry') or {}
    coordinates = geometry.get('coordinates') or []
    if geometry.get('type') == 'LineString':
        return [coordinates]
    if geometry.get('type') == 'MultiLineString':
        return coordinates
    raise SystemExit('official route feature is not line geometry')


def normalized_feature(feature, properties=None):
    lines = [geo.densify(line, 25.0) for line in feature_lines(feature)]
    geometry = ({'type': 'LineString', 'coordinates': lines[0]}
                if len(lines) == 1 else
                {'type': 'MultiLineString', 'coordinates': lines})
    return {'type': 'Feature',
            'properties': properties or dict(feature.get('properties') or {}),
            'geometry': geometry}


def la_groups(features):
    groups = {f'la-metro-{route}': [] for route in LA_ROUTES}
    seen_labels = set()
    for feature in features:
        props = feature.get('properties') or {}
        label = str(props.get('LABEL') or '')
        seen_labels.add(label)
        if props.get('STATUS') != 'Existing' or props.get('TYPE') != 'Rail':
            continue
        selected = False
        for route, labels in LA_ROUTES.items():
            if label in labels:
                groups[f'la-metro-{route}'].append(normalized_feature(feature))
                selected = True
        if not selected:
            raise SystemExit(f'LA Metro has unmapped existing rail label {label!r}')
    for route, labels in LA_ROUTES.items():
        if not any(label in seen_labels for label in labels):
            raise SystemExit(f'LA Metro source is missing route {route}')
    return groups


def sfmta_groups(features):
    groups = {f'sfmta-{route.lower()}-{direction.lower()}': []
              for route in SFMTA_ROUTES.values()
              for direction in ('I', 'O')}
    seen = set()
    for feature in features:
        props = feature.get('properties') or {}
        public_name = str(props.get('route_name') or '')
        route = SFMTA_ROUTES.get(public_name)
        if route is None or props.get('pattern_type') != 'F':
            continue
        direction = str(props.get('direction') or '').upper()
        if direction not in ('I', 'O'):
            raise SystemExit(f'SFMTA {route}: invalid direction {direction!r}')
        key = f'sfmta-{route.lower()}-{direction.lower()}'
        groups[key].append(normalized_feature(feature))
        seen.add((route, direction))
    expected = {(route, direction) for route in SFMTA_ROUTES.values()
                for direction in ('I', 'O')}
    missing = expected - seen
    if missing:
        raise SystemExit('SFMTA source lacks full route directions: '
                         + ', '.join(f'{r}-{d}' for r, d in sorted(missing)))
    for key, rows in groups.items():
        if len(rows) != 1:
            raise SystemExit(f'{key}: expected exactly one full-length pattern')
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


def write_group(output_dir, key, features, source_id, raw_sha):
    if not features:
        raise SystemExit(f'{key}: no official route features')
    source = SOURCES[source_id]
    payload = {'type': 'FeatureCollection', 'sourceId': key,
               'source': {**source, 'rawSha256': raw_sha},
               'features': features}
    encoded = json.dumps(payload, ensure_ascii=False,
                         separators=(',', ':')).encode()
    path = os.path.join(output_dir, f'{key}.geojson')
    with open(path + '.tmp', 'wb') as output:
        output.write(encoded)
    os.replace(path + '.tmp', path)
    return {'file': os.path.basename(path), 'features': len(features),
            'sha256': digest(encoded)}


def normalize(output_dir, la_input, sfmta_input):
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    for source_id, path, grouper, prefixes in (
            ('la-metro', la_input, la_groups, ('la-metro-',)),
            ('sfmta', sfmta_input, sfmta_groups, ('sfmta-',))):
        with open(path, 'rb') as source:
            raw = source.read()
        raw_sha = digest(raw)
        groups = grouper(parse_geojson(raw, source_id))
        manifest['files'] = {key: value
                             for key, value in manifest['files'].items()
                             if not key.startswith(prefixes)}
        manifest['sources'][source_id] = {
            **SOURCES[source_id], 'rawSha256': raw_sha,
            'featureCount': sum(len(rows) for rows in groups.values()),
        }
        for key, rows in sorted(groups.items()):
            manifest['files'][key] = write_group(
                output_dir, key, rows, source_id, raw_sha)
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
    parser.add_argument('--la-input', required=True)
    parser.add_argument('--sfmta-input', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, args.la_input, args.sfmta_input)
    print(f'wrote {len(LA_ROUTES) + 2 * len(SFMTA_ROUTES)} route networks; '
          f'manifest now contains {len(manifest["files"])} files')


if __name__ == '__main__':
    main()
