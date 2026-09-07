#!/usr/bin/env python3
"""Normalize Virginia DRPT's independently published VRE line centrelines."""
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


SOURCE_ID = 'virginia-drpt-vre'
SOURCE = {
    'publisher': 'Virginia Department of Rail and Public Transportation',
    'url': ('https://services9.arcgis.com/9oDT7ErWemWCzvY7/arcgis/rest/'
            'services/VRE_Lines/FeatureServer/7/query?where=1%3D1&'
            'outFields=*&returnGeometry=true&outSR=4326&f=geojson'),
    'catalogUrl': ('https://www.arcgis.com/home/item.html?'
                   'id=53bb8f60e9cc48bf8dd12dafab3feec3'),
}
ROUTES = {
    'Fredericksburg Line': 'vre-fredericksburg',
    'Manassas Line': 'vre-manassas',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_source(path):
    with open(path, 'rb') as source:
        raw = source.read()
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'Virginia DRPT VRE layer is invalid: {exc}')
    if payload.get('type') != 'FeatureCollection':
        raise SystemExit('Virginia DRPT VRE layer is not a FeatureCollection')
    by_name = {}
    for feature in payload.get('features') or ():
        name = str((feature.get('properties') or {}).get('NAME') or '')
        if name in by_name:
            raise SystemExit(f'Virginia DRPT VRE layer duplicates {name!r}')
        by_name[name] = feature
    if set(by_name) != set(ROUTES):
        raise SystemExit(
            'Virginia DRPT VRE layer route names changed; exact review required')
    return raw, by_name


def normalized_feature(feature, route_key):
    geometry = feature.get('geometry') or {}
    if geometry.get('type') != 'LineString':
        raise SystemExit(f'{route_key}: official geometry is not a LineString')
    coordinates = geometry.get('coordinates') or []
    if len(coordinates) < 100:
        raise SystemExit(f'{route_key}: official geometry is unexpectedly short')
    properties = dict(feature.get('properties') or {})
    properties['sourceDataset'] = 'Virginia DRPT VRE Lines'
    properties['routeKey'] = route_key
    return {
        'type': 'Feature', 'properties': properties,
        'geometry': {
            'type': 'LineString',
            'coordinates': geo.densify(coordinates, 25.0),
        },
    }


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
    raw, by_name = read_source(input_path)
    raw_sha = digest(raw)
    groups = {
        route_key: [normalized_feature(by_name[name], route_key)]
        for name, route_key in ROUTES.items()
    }
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['sources'][SOURCE_ID] = {
        **SOURCE, 'rawSha256': raw_sha, 'featureCount': len(by_name),
    }
    manifest['files'] = {
        key: value for key, value in manifest['files'].items()
        if key not in set(ROUTES.values())
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
    parser.add_argument('--input', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, args.input)
    count = sum(key in ROUTES.values() for key in manifest['files'])
    print(f'wrote {count} route-isolated Virginia DRPT VRE networks')


if __name__ == '__main__':
    main()
