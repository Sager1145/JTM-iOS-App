#!/usr/bin/env python3
"""Normalize SEPTA's reviewed Regional Rail linework into route-only graphs.

GTFS supplies service identity, station order, and the operator's display
colour.  OpenDataPhilly's "Regional Rail Lines" layer (SEPTA Planning
Division) supplies only the physical alignment, one feature per branch, each
already isolated to its own service -- unlike ``normalize-east-official-
networks.py``'s septa-high-speed/septa-trolley inputs, this layer needs no
route-token grouping: `Route_Name` names the branch outright.

SEPTA publishes Regional Rail as a separate GTFS feed (mdb-503,
``google_rail.zip``) from its bus/trolley/high-speed feed (mdb-502,
``google_bus.zip``); the two are registered as separate ``na-feeds.json``
entries (`septa` and `septa-regional-rail`) for that reason, the same way
NJ Transit's rail/light-rail/PATH feeds are three separate entries.  This
normalizer only produces geometry; it does not touch either feed record.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import urllib.request


SOURCES = {
    'septa-regional-rail': {
        'publisher': 'SEPTA Planning Division',
        'url': ('https://opendata.arcgis.com/api/v3/datasets/'
                '7ebff6bc356d4fa28d4a7e4147d03b32_0/downloads/data?'
                'format=geojson&spatialRefId=4326'),
        'metadataUrl': ('https://opendataphilly.org/datasets/'
                        'septa-regional-rail-lines/'),
    },
}

# `Route_Name` -> na-feeds.json officialNetworkByRouteId key. GTFS feed
# mdb-503 (google_rail.zip) publishes these thirteen route_ids with
# route_long_name values that match the layer's Route_Name one-for-one
# (route_type 2 in every case).
SEPTA_REGIONAL_RAIL_KEYS = {
    'Airport': 'septa-rail-air',
    'Chestnut Hill East': 'septa-rail-che',
    'Chestnut Hill West': 'septa-rail-chw',
    'Cynwyd': 'septa-rail-cyn',
    'Fox Chase': 'septa-rail-fox',
    'Lansdale/Doylestown': 'septa-rail-lan',
    'Manayunk/Norristown': 'septa-rail-nor',
    'Media/Wawa': 'septa-rail-med',
    'Paoli/Thorndale': 'septa-rail-pao',
    'Trenton': 'septa-rail-tre',
    'Warminster': 'septa-rail-war',
    'West Trenton': 'septa-rail-wtr',
    'Wilmington/Newark': 'septa-rail-wil',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fetch(url):
    request = urllib.request.Request(
        url, headers={'User-Agent': 'JTM railway data builder/1.0'})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def read_source(path, source_id):
    if path:
        with open(path, 'rb') as source:
            return source.read()
    return fetch(SOURCES[source_id]['url'])


def parse_geojson(raw, source_id):
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{source_id}: response is not valid GeoJSON: {exc}')
    if payload.get('type') != 'FeatureCollection':
        raise SystemExit(f'{source_id}: expected a GeoJSON FeatureCollection')
    features = payload.get('features') or []
    if not features:
        raise SystemExit(f'{source_id}: official dataset is empty')
    for feature in features:
        geometry_type = (feature.get('geometry') or {}).get('type')
        if geometry_type not in ('LineString', 'MultiLineString'):
            raise SystemExit(
                f'{source_id}: official dataset contains non-line geometry')
    return features


def septa_regional_rail_groups(features):
    groups = {key: [] for key in SEPTA_REGIONAL_RAIL_KEYS.values()}
    seen = set()
    for feature in features:
        route = str((feature.get('properties') or {}).get('Route_Name') or '')
        seen.add(route)
        key = SEPTA_REGIONAL_RAIL_KEYS.get(route)
        if key is None:
            raise SystemExit(
                f'SEPTA Regional Rail layer has unknown Route_Name {route!r}')
        groups[key].append(feature)
    if seen != set(SEPTA_REGIONAL_RAIL_KEYS):
        missing = set(SEPTA_REGIONAL_RAIL_KEYS) - seen
        raise SystemExit(
            f'SEPTA Regional Rail layer is missing branches: {sorted(missing)}')
    return groups


def _load_manifest(output_dir):
    path = os.path.join(output_dir, 'manifest.json')
    if not os.path.exists(path):
        return {'schemaVersion': 1, 'sources': {}, 'files': {}}
    try:
        with open(path, encoding='utf-8') as source:
            manifest = json.load(source)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'existing official-network manifest is invalid: {exc}')
    if manifest.get('schemaVersion') != 1:
        raise SystemExit('existing official-network manifest schema is unsupported')
    if not isinstance(manifest.get('sources'), dict) \
            or not isinstance(manifest.get('files'), dict):
        raise SystemExit('existing official-network manifest has invalid sections')
    return manifest


def _write_group(output_dir, key, features, source_id, raw_sha):
    if not features:
        raise SystemExit(f'{key}: official source has no matching features')
    source = SOURCES[source_id]
    payload = {
        'type': 'FeatureCollection',
        'sourceId': key,
        'source': {**source, 'rawSha256': raw_sha},
        'features': features,
    }
    encoded = json.dumps(
        payload, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    path = os.path.join(output_dir, f'{key}.geojson')
    with open(path + '.tmp', 'wb') as output:
        output.write(encoded)
    os.replace(path + '.tmp', path)
    return {
        'file': os.path.basename(path),
        'features': len(features),
        'sha256': digest(encoded),
    }


def normalize(output_dir, inputs):
    os.makedirs(output_dir, exist_ok=True)
    manifest = _load_manifest(output_dir)
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    jobs = (
        ('septa-regional-rail', inputs.get('septa_regional_rail_input'),
         septa_regional_rail_groups),
    )
    written = 0
    for source_id, supplied, grouper in jobs:
        raw = read_source(supplied, source_id)
        raw_sha = digest(raw)
        features = parse_geojson(raw, source_id)
        manifest['sources'][source_id] = {
            **SOURCES[source_id],
            'rawSha256': raw_sha,
            'featureCount': len(features),
        }
        for key, selected in sorted(grouper(features).items()):
            manifest['files'][key] = _write_group(
                output_dir, key, selected, source_id, raw_sha)
            written += 1

    manifest_path = os.path.join(output_dir, 'manifest.json')
    with open(manifest_path + '.tmp', 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2)
        output.write('\n')
    os.replace(manifest_path + '.tmp', manifest_path)
    return written


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--septa-regional-rail-input')
    args = parser.parse_args()
    written = normalize(args.output_dir, vars(args))
    print(f'wrote {written} SEPTA Regional Rail route-specific official networks')


if __name__ == '__main__':
    main()
