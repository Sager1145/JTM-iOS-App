#!/usr/bin/env python3
"""Normalize Houston METRO's operator-published METRORail GIS by route."""
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


SOURCE = {
    'publisher': 'Metropolitan Transit Authority of Harris County (METRO)',
    'url': ('https://services5.arcgis.com/p8QKnlioaN3sruqA/arcgis/rest/'
            'services/METRO_transit_layers/FeatureServer/4/query?'
            'where=1%3D1&outFields=*&returnGeometry=true&'
            'outSR=4326&f=geojson'),
}
ROUTES = {'Red': '700', 'Green': '800', 'Purple': '900'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def geometry_lines(feature):
    geometry = feature.get('geometry') or {}
    if geometry.get('type') == 'LineString':
        return [geometry.get('coordinates') or []]
    if geometry.get('type') == 'MultiLineString':
        return geometry.get('coordinates') or []
    raise SystemExit('METRO official route feature is not line geometry')


def normalized_feature(feature):
    lines = [geo.densify(line, 25.0) for line in geometry_lines(feature)
             if len(line) >= 2]
    if not lines:
        raise SystemExit('METRO official route feature has no coordinates')
    geometry = ({'type': 'LineString', 'coordinates': lines[0]}
                if len(lines) == 1 else
                {'type': 'MultiLineString', 'coordinates': lines})
    return {'type': 'Feature',
            'properties': dict(feature.get('properties') or {}),
            'geometry': geometry}


def route_groups(features):
    groups = {f'houston-metro-{route}': [] for route in ROUTES.values()}
    for feature in features:
        props = feature.get('properties') or {}
        if props.get('TYPE') != 'RAIL' or props.get('Status') != 'Operational':
            continue
        colour = str(props.get('LineColor') or '')
        route = ROUTES.get(colour)
        if route is None:
            raise SystemExit(f'unmapped operational METRORail color {colour!r}')
        groups[f'houston-metro-{route}'].append(normalized_feature(feature))
    for key, rows in groups.items():
        if not rows:
            raise SystemExit(f'{key}: official GIS has no operational geometry')
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


def normalize(output_dir, input_path):
    with open(input_path, 'rb') as source:
        raw = source.read()
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'Houston METRO GIS is invalid: {exc}')
    if payload.get('type') != 'FeatureCollection' or not payload.get('features'):
        raise SystemExit('Houston METRO GIS is empty')

    groups = route_groups(payload['features'])
    raw_sha = digest(raw)
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['sources']['houston-metro'] = {
        **SOURCE, 'rawSha256': raw_sha,
        'featureCount': len(payload['features']),
    }
    manifest['files'] = {
        key: value for key, value in manifest['files'].items()
        if not key.startswith('houston-metro-')}
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
    parser.add_argument('--input', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, args.input)
    print('wrote 3 route-isolated Houston METRORail networks; manifest now '
          f'contains {len(manifest["files"])} files')


if __name__ == '__main__':
    main()
