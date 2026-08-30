#!/usr/bin/env python3
"""Normalize official Calgary, Edmonton, and TransLink rail GIS by route."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os


SOURCES = {
    'calgary-lrt': {
        'publisher': 'The City of Calgary / Calgary Transit',
        'url': ('https://data.calgary.ca/resource/avbp-2r3h.geojson?'
                '$limit=50000'),
        'metadataUrl': ('https://data.calgary.ca/Transportation-Transit/'
                        'Tracks-LRT-Centre-Line/kmts-cfkc/about'),
    },
    'edmonton-lrt': {
        'publisher': 'The City of Edmonton / Edmonton Transit Service',
        'url': ('https://data.edmonton.ca/resource/8r95-rjy4.geojson?'
                '$limit=50000'),
        'metadataUrl': 'https://data.edmonton.ca/d/8r95-rjy4',
    },
    'translink-system-map': {
        'publisher': 'TransLink',
        'url': ('https://services7.arcgis.com/WpS8F3vcmrEQUG8m/arcgis/rest/'
                'services/Translink_System_App_2/FeatureServer/5/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
        'metadataUrl': ('https://www.translink.ca/schedules-and-maps/'
                        'interactive-system-map'),
    },
}

CALGARY_KEYS = {'RED LINE': 'calgary-red', 'BLUE LINE': 'calgary-blue'}
EDMONTON_KEYS = {
    '021R': 'edmonton-capital', '022R': 'edmonton-metro',
    '023R': 'edmonton-valley',
}
TRANSLINK_KEYS = {
    'CL': 'translink-canada', 'EL': 'translink-expo',
    'ML': 'translink-millennium', 'WCE': 'translink-wce',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    with open(path, 'rb') as source:
        return source.read()


def parse(raw, source_id):
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{source_id}: invalid GeoJSON: {exc}')
    features = payload.get('features') or []
    if payload.get('type') != 'FeatureCollection' or not features:
        raise SystemExit(f'{source_id}: empty/non-FeatureCollection source')
    if any((row.get('geometry') or {}).get('type')
           not in ('LineString', 'MultiLineString') for row in features):
        raise SystemExit(f'{source_id}: non-line geometry')
    return features


def distance_m(first, second):
    """Haversine distance used only to choose a subdivision count."""
    lon1, lat1 = map(math.radians, first)
    lon2, lat2 = map(math.radians, second)
    dlon, dlat = lon2 - lon1, lat2 - lat1
    value = (math.sin(dlat / 2) ** 2
             + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 12_742_000 * math.asin(math.sqrt(value))


def densify_line(line, max_segment_m=100.0):
    """Add vertices on the authority's own straight segments.

    The official TransLink layer generalizes long tunnel sections to segments
    whose endpoints can be over a kilometre from an intermediate station.
    Routing snaps to vertices, so subdivide those exact segments without
    moving an endpoint or bending/interpreting the published linework.
    """
    if len(line) < 2:
        return line
    output = [line[0]]
    for first, second in zip(line, line[1:]):
        steps = max(1, int(math.ceil(distance_m(first, second)
                                     / max_segment_m)))
        for index in range(1, steps + 1):
            fraction = index / steps
            output.append([
                first[0] + (second[0] - first[0]) * fraction,
                first[1] + (second[1] - first[1]) * fraction,
            ])
    return output


def densify_feature(feature, max_segment_m=100.0):
    copied = {**feature, 'properties': dict(feature.get('properties') or {})}
    geometry = feature.get('geometry') or {}
    coordinates = geometry.get('coordinates') or []
    if geometry.get('type') == 'LineString':
        dense = densify_line(coordinates, max_segment_m)
    elif geometry.get('type') == 'MultiLineString':
        dense = [densify_line(line, max_segment_m) for line in coordinates]
    else:
        raise SystemExit('cannot densify non-line official geometry')
    copied['geometry'] = {**geometry, 'coordinates': dense}
    return copied


def calgary_groups(features):
    groups = {key: [] for key in CALGARY_KEYS.values()}
    for feature in features:
        name = str((feature.get('properties') or {}).get('full_name') or '')
        if name in ('FREE FARE ZONE', 'BLUE LINE - RED LINE'):
            for selected in groups.values():
                selected.append(feature)
        elif name in CALGARY_KEYS:
            groups[CALGARY_KEYS[name]].append(feature)
        else:
            raise SystemExit(f'Calgary has unknown full_name {name!r}')
    return groups


def edmonton_groups(features):
    groups = {key: [] for key in EDMONTON_KEYS.values()}
    for feature in features:
        route = str((feature.get('properties') or {}).get('lrt_route_') or '')
        if route not in EDMONTON_KEYS:
            raise SystemExit(f'Edmonton has unknown route {route!r}')
        groups[EDMONTON_KEYS[route]].append(feature)
        # ETS publishes Metro service from Century Park over the shared
        # Capital corridor before it diverges to NAIT-Blatchford Market.
        if route == '021R':
            groups['edmonton-metro'].append(feature)
    return groups


def translink_groups(features):
    groups = {key: [] for key in TRANSLINK_KEYS.values()}
    for feature in features:
        code = str((feature.get('properties') or {}).get('line_no') or '')
        if code in TRANSLINK_KEYS:
            groups[TRANSLINK_KEYS[code]].append(densify_feature(feature))
    return groups


def load_manifest(output_dir):
    path = os.path.join(output_dir, 'manifest.json')
    if not os.path.exists(path):
        return {'schemaVersion': 1, 'sources': {}, 'files': {}}
    with open(path, encoding='utf-8') as source:
        payload = json.load(source)
    if payload.get('schemaVersion') != 1:
        raise SystemExit('unsupported official manifest')
    return payload


def write_group(output_dir, key, features, source_id, raw_sha):
    if not features:
        raise SystemExit(f'{key}: official source has no features')
    payload = {'type': 'FeatureCollection', 'sourceId': key,
               'source': {**SOURCES[source_id], 'rawSha256': raw_sha},
               'features': features}
    encoded = json.dumps(payload, ensure_ascii=False,
                         separators=(',', ':')).encode()
    path = os.path.join(output_dir, f'{key}.geojson')
    with open(path + '.tmp', 'wb') as output:
        output.write(encoded)
    os.replace(path + '.tmp', path)
    return {'file': os.path.basename(path), 'features': len(features),
            'sha256': digest(encoded)}


def normalize(output_dir, calgary_input, edmonton_input, translink_input):
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    jobs = (
        ('calgary-lrt', calgary_input, calgary_groups),
        ('edmonton-lrt', edmonton_input, edmonton_groups),
        ('translink-system-map', translink_input, translink_groups),
    )
    count = 0
    for source_id, path, grouper in jobs:
        raw = read(path)
        features = parse(raw, source_id)
        raw_sha = digest(raw)
        manifest['sources'][source_id] = {
            **SOURCES[source_id], 'rawSha256': raw_sha,
            'featureCount': len(features)}
        for key, selected in sorted(grouper(features).items()):
            manifest['files'][key] = write_group(
                output_dir, key, selected, source_id, raw_sha)
            count += 1
    path = os.path.join(output_dir, 'manifest.json')
    with open(path + '.tmp', 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2)
        output.write('\n')
    os.replace(path + '.tmp', path)
    return count


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--calgary-input', required=True)
    parser.add_argument('--edmonton-input', required=True)
    parser.add_argument('--translink-input', required=True)
    args = parser.parse_args()
    print(f'wrote {normalize(args.output_dir, args.calgary_input, args.edmonton_input, args.translink_input)} Canada-west route networks')


if __name__ == '__main__':
    main()
