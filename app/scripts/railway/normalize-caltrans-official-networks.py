#!/usr/bin/env python3
"""Extract route-isolated Caltrain and San Diego networks from Caltrans CRN.

The California Rail Network is an independent state railway alignment. GTFS
is not used here: route ownership and network fields in CRN select the
features, and every published coordinate remains a Caltrans coordinate.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os


SOURCE = {
    'publisher': 'California Department of Transportation (Caltrans)',
    'url': ('https://hub.arcgis.com/api/v3/datasets/'
            '2ac93358aca84aa7b547b29a42d5ff52_0/downloads/data?'
            'format=geojson&spatialRefId=4326&where=1%3D1'),
    'catalogUrl': 'https://lab.data.ca.gov/dataset/california-rail-network',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


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


def route_groups(document):
    features = document.get('features') or []
    if len(features) < 2_000:
        raise SystemExit('California Rail Network is unexpectedly incomplete')
    groups = {
        'caltrans-caltrain': [],
        'caltrans-sd-blue': [],
        'caltrans-sd-orange': [],
    }
    for feature in features:
        properties = feature.get('properties') or {}
        geometry = feature.get('geometry') or {}
        if str(properties.get('STATUS')) != '1':
            continue
        if geometry.get('type') not in {'LineString', 'MultiLineString'}:
            continue
        network = str(properties.get('COMM_NETWO') or '')
        operator = str(properties.get('COMM_OP') or '')
        key = None
        if 'Caltrain' in network and 'PCJPB' in operator:
            key = 'caltrans-caltrain'
        elif (operator == 'SDTI'
              and network == 'San Diego Light Rail Trolley (Blue Line)'):
            key = 'caltrans-sd-blue'
        elif (operator == 'SDTI'
              and network == 'San Diego Light Rail Trolley (Orange Line)'):
            key = 'caltrans-sd-orange'
        if key:
            groups[key].append(feature)
    for key, selected in groups.items():
        if not selected:
            raise SystemExit(f'{key}: no exact Caltrans route features')
    return groups


def normalize(input_path, output_dir):
    with open(input_path, 'rb') as source:
        raw = source.read()
    try:
        document = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'California Rail Network is invalid: {exc}')
    groups = route_groups(document)
    raw_sha = digest(raw)
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['sources']['caltrans-crn'] = {
        **SOURCE, 'rawSha256': raw_sha,
        'featureCount': len(document['features']),
    }
    manifest['files'] = {
        key: value for key, value in manifest['files'].items()
        if not key.startswith('caltrans-')
    }
    for key, features in sorted(groups.items()):
        output_document = {
            'type': 'FeatureCollection', 'sourceId': key,
            'source': {**SOURCE, 'rawSha256': raw_sha},
            'features': features,
        }
        encoded = json.dumps(output_document, ensure_ascii=False,
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
    manifest = normalize(args.input, args.output_dir)
    count = sum(key.startswith('caltrans-') for key in manifest['files'])
    print(f'wrote {count} route-isolated Caltrans networks')


if __name__ == '__main__':
    main()
