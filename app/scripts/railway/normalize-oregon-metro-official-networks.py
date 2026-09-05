#!/usr/bin/env python3
"""Normalize Portland Streetcar A Loop from Oregon Metro RLIS.

Only GTFS route 194 is in scope here.  RLIS publishes physical rail assets,
including planned lines, so the extract is limited to the reviewed A Loop
``LINE`` values whose ``STATUS`` is ``Existing``.  The coordinates are copied
from the government layer without GTFS shape substitution or OSM repair.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os


SOURCE_ID = 'oregonmetro-rlis-rail-transit'
SOURCE = {
    'publisher': 'Oregon Metro Data Resource Center (RLIS)',
    'url': ('https://services2.arcgis.com/McQ0OlIABe29rJJy/arcgis/rest/'
            'services/Light_rail/FeatureServer/0/query?where=1%3D1&'
            'outFields=*&returnGeometry=true&outSR=4326&f=geojson'),
    'licenseUrl': ('https://rlisdiscovery.oregonmetro.gov/pages/'
                   'open-database-license'),
}
ROUTE_KEY = 'oregonmetro-rlis-portland-streetcar-a'
A_LOOP_LINES = {
    'Auxiliary Portland Streetcar',
    'Orange MAX and Portland Street Car A and B Loops',
    'Portland Street Car A Loop',
    'Portland Street Car A and B Loops',
    'Portland Street Car NS Line and A Loop',
    'Portland Street Car NS Line and A and B Loops',
}
A_LOOP_TYPES = {'Street Car', 'MAX/Street Car'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_source(path):
    with open(path, 'rb') as source:
        raw = source.read()
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{SOURCE_ID}: invalid GeoJSON: {exc}')
    features = payload.get('features') or []
    if payload.get('type') != 'FeatureCollection' or not features:
        raise SystemExit(f'{SOURCE_ID}: empty/non-FeatureCollection source')
    return raw, features


def a_loop_group(features):
    selected = []
    observed = set()
    for feature in features:
        properties = feature.get('properties') or {}
        line = str(properties.get('LINE') or '')
        if (str(properties.get('STATUS') or '') != 'Existing'
                or line not in A_LOOP_LINES):
            continue
        route_type = str(properties.get('TYPE') or '')
        if route_type not in A_LOOP_TYPES:
            raise SystemExit(
                f'{ROUTE_KEY}: RLIS LINE changed TYPE: {line!r}/{route_type!r}')
        geometry = feature.get('geometry') or {}
        if geometry.get('type') not in ('LineString', 'MultiLineString'):
            raise SystemExit(f'{ROUTE_KEY}: RLIS feature is not line geometry')
        coordinates = geometry.get('coordinates') or []
        if not coordinates:
            raise SystemExit(f'{ROUTE_KEY}: RLIS feature has empty geometry')
        observed.add(line)
        selected.append(feature)
    missing = A_LOOP_LINES - observed
    if missing:
        raise SystemExit(
            f'{ROUTE_KEY}: RLIS source is missing reviewed LINE values: '
            f'{sorted(missing)}')
    # FID is the source's stable asset identifier.  Sorting makes the output
    # byte-for-byte deterministic even if ArcGIS changes response row order.
    return sorted(selected,
                  key=lambda row: (str((row.get('properties') or {}).get('FID')),
                                   str((row.get('properties') or {}).get('LINE'))))


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
    raw, features = read_source(input_path)
    selected = a_loop_group(features)
    raw_sha = digest(raw)
    source = {**SOURCE, 'rawSha256': raw_sha}
    payload = {
        'type': 'FeatureCollection',
        'sourceId': ROUTE_KEY,
        'source': source,
        'features': selected,
    }
    encoded = json.dumps(payload, ensure_ascii=False, separators=(',', ':'),
                         sort_keys=True).encode()

    os.makedirs(output_dir, exist_ok=True)
    filename = ROUTE_KEY + '.geojson'
    path = os.path.join(output_dir, filename)
    with open(path + '.tmp', 'wb') as output:
        output.write(encoded)
    os.replace(path + '.tmp', path)

    manifest = load_manifest(output_dir)
    manifest['sources'][SOURCE_ID] = {
        **SOURCE,
        'rawSha256': raw_sha,
        'featureCount': len(features),
    }
    manifest['files'][ROUTE_KEY] = {
        'file': filename,
        'features': len(selected),
        'sha256': digest(encoded),
    }
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    manifest_path = os.path.join(output_dir, 'manifest.json')
    with open(manifest_path + '.tmp', 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2,
                  sort_keys=True)
        output.write('\n')
    os.replace(manifest_path + '.tmp', manifest_path)
    return manifest, selected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--input', required=True)
    args = parser.parse_args()
    manifest, selected = normalize(args.output_dir, args.input)
    print(f'wrote {ROUTE_KEY} ({len(selected)} RLIS features); manifest now '
          f'contains {len(manifest["files"])} files')


if __name__ == '__main__':
    main()
