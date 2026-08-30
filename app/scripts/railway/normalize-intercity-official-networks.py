#!/usr/bin/env python3
"""Normalize reviewed official intercity/commuter geometry by public route.

The inputs are downloaded separately so their raw bytes can be hashed before
normalization.  Every output contains only the exact service named in the
registry; a shortest-path search can therefore not jump onto a neighbouring
route merely because the two share a terminal or corridor.
"""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import json
import math
import os

from lib.na_provenance import SOURCES


AMTRAK = {
    'Amtrak Cascades': 'amtrak-ntad-cascades',
    'Capitol Corridor': 'amtrak-ntad-capitol-corridor',
    'Coast Starlight': 'amtrak-ntad-coast-starlight',
    'Illini': 'amtrak-ntad-illini',
    'Maple Leaf': 'amtrak-ntad-maple-leaf',
    'Pacific Surfliner': 'amtrak-ntad-pacific-surfliner',
    'Saluki': 'amtrak-ntad-saluki',
    'Sunset Limited': 'amtrak-ntad-sunset-limited',
    'Texas Eagle': 'amtrak-ntad-texas-eagle',
    'Wolverine': 'amtrak-ntad-wolverine',
}

MNR = {
    'Hudson Line': 'mnr-hudson',
    'Harlem Line': 'mnr-harlem',
    'New Haven Line': 'mnr-new-haven',
    'New Canaan Branch': 'mnr-new-canaan',
    'Danbury Branch': 'mnr-danbury',
    'Waterbury Branch': 'mnr-waterbury',
}

MNR_TRUNKS = {
    # The MTA GIS layer publishes the lines as physical branches: Harlem
    # starts at Mott Haven and New Haven starts at Woodlawn, rather than
    # duplicating their shared approach to Grand Central.  A passenger-route
    # network therefore needs those exact official trunk features too.
    'mnr-harlem': ('Hudson Line', 'Harlem Line'),
    'mnr-new-haven': ('Hudson Line', 'Harlem Line', 'New Haven Line'),
    'mnr-new-canaan': (
        'Hudson Line', 'Harlem Line', 'New Haven Line', 'New Canaan Branch'),
    'mnr-danbury': (
        'Hudson Line', 'Harlem Line', 'New Haven Line', 'Danbury Branch'),
    'mnr-waterbury': ('New Haven Line', 'Waterbury Branch'),
}

METROLINK = {
    'Antelope Valley Line': 'metrolink-scrra-av',
    'Inland Empire-Orange County Line': 'metrolink-scrra-ie-oc',
    'Orange County Line': 'metrolink-scrra-oc',
    'Riverside Line': 'metrolink-scrra-riverside',
    'San Bernardino Line': 'metrolink-scrra-sb',
    'Ventura County Line': 'metrolink-scrra-vc',
    '91/Perris Valley Line': 'metrolink-scrra-91',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_geojson(path, source_id):
    with open(path, 'rb') as source_file:
        raw = source_file.read()
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{source_id}: invalid GeoJSON: {exc}')
    features = payload.get('features') or []
    if payload.get('type') != 'FeatureCollection' or not features:
        raise SystemExit(f'{source_id}: expected non-empty FeatureCollection')
    for feature in features:
        if (feature.get('geometry') or {}).get('type') not in (
                'LineString', 'MultiLineString'):
            raise SystemExit(f'{source_id}: contains non-line geometry')
    return raw, features


def exact_groups(features, property_name, mapping):
    by_name = {}
    for feature in features:
        name = str((feature.get('properties') or {}).get(property_name) or '')
        by_name.setdefault(name, []).append(feature)
    groups = {}
    for name, key in mapping.items():
        selected = by_name.get(name) or []
        if len(selected) != 1:
            raise SystemExit(
                f'{key}: expected exactly one official feature named {name!r}, '
                f'found {len(selected)}')
        groups[key] = selected
    return groups


def distance_m(first, second):
    lat = math.radians((first[1] + second[1]) / 2.0)
    dx = math.radians(second[0] - first[0]) * math.cos(lat)
    dy = math.radians(second[1] - first[1])
    return math.hypot(dx, dy) * 6_371_008.8


def geometry_lines(feature):
    geometry = feature['geometry']
    coordinates = geometry['coordinates']
    return [coordinates] if geometry['type'] == 'LineString' else coordinates


def join_mnr_shared_trunk(features):
    """Close MTA's 9.75 m Woodlawn digitizing gap, and no other gap."""
    features = copy.deepcopy(features)
    by_name = {
        str((feature.get('properties') or {}).get('route_name') or ''): feature
        for feature in features
    }
    new_haven = geometry_lines(by_name['New Haven Line'])[0]
    harlem = geometry_lines(by_name['Harlem Line'])[0]
    junction, gap = min(
        ((point, distance_m(new_haven[0], point)) for point in harlem),
        key=lambda candidate: candidate[1])
    if gap > 15.0:
        raise SystemExit(
            'mnr-new-haven: official Woodlawn junction gap changed; '
            f'expected <=15 m, found {gap:.2f} m')
    new_haven[0] = list(junction)
    return features


def clip_first_line_at(feature, junction):
    """Keep an official line only through an exact published junction."""
    feature = copy.deepcopy(feature)
    line = geometry_lines(feature)[0]
    try:
        index = line.index(junction)
    except ValueError:
        raise SystemExit(
            f"{feature['properties']['route_name']}: shared junction missing")
    clipped = line[:index + 1]
    if len(clipped) < 2:
        raise SystemExit(
            f"{feature['properties']['route_name']}: empty shared trunk")
    if feature['geometry']['type'] == 'LineString':
        feature['geometry']['coordinates'] = clipped
    else:
        feature['geometry']['coordinates'] = [clipped]
    return feature


def mnr_groups(features):
    features = join_mnr_shared_trunk(features)
    singles = exact_groups(features, 'route_name', MNR)
    by_name = {
        str((feature.get('properties') or {}).get('route_name') or ''): feature
        for feature in features
    }
    harlem_start = geometry_lines(by_name['Harlem Line'])[0][0]
    new_haven_start = geometry_lines(by_name['New Haven Line'])[0][0]
    shared_hudson = clip_first_line_at(by_name['Hudson Line'], harlem_start)
    shared_harlem = clip_first_line_at(by_name['Harlem Line'], new_haven_start)
    exact_features = {
        **by_name,
        'Hudson Line': shared_hudson,
        'Harlem Line': shared_harlem,
    }
    for key, names in MNR_TRUNKS.items():
        selected = []
        for index, name in enumerate(names):
            # A line named as a shared predecessor is clipped; the final
            # route/branch feature remains complete.
            selected.append(exact_features[name] if index < len(names) - 1
                            else by_name[name])
        singles[key] = selected
    return singles


def write_group(output_dir, key, features, source_id, raw_sha):
    source = SOURCES[source_id]
    payload = {
        'type': 'FeatureCollection',
        'sourceId': key,
        'source': {
            'publisher': source['publisher'],
            'url': source['url'],
            'rawSha256': raw_sha,
        },
        'features': features,
    }
    path = os.path.join(output_dir, f'{key}.geojson')
    with open(path + '.tmp', 'w', encoding='utf-8') as target:
        json.dump(payload, target, ensure_ascii=False, separators=(',', ':'))
    os.replace(path + '.tmp', path)
    with open(path, 'rb') as source_file:
        normalized_sha = digest(source_file.read())
    return {'file': os.path.basename(path), 'features': len(features),
            'sha256': normalized_sha}


def load_manifest(output_dir):
    path = os.path.join(output_dir, 'manifest.json')
    try:
        with open(path, encoding='utf-8') as source_file:
            manifest = json.load(source_file)
    except FileNotFoundError:
        manifest = {'schemaVersion': 1, 'sources': {}, 'files': {}}
    if manifest.get('schemaVersion') != 1:
        raise SystemExit('official network manifest has unsupported schemaVersion')
    manifest.setdefault('sources', {})
    manifest.setdefault('files', {})
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--amtrak-input')
    parser.add_argument('--mnr-input')
    parser.add_argument('--metrolink-input')
    args = parser.parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    manifest = load_manifest(args.output_dir)
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()

    jobs = [
        ('amtrak-ntad', args.amtrak_input, 'name', AMTRAK, exact_groups,
         ('amtrak-ntad-',)),
        ('mta-rail-branches', args.mnr_input, 'route_name', MNR, mnr_groups,
         ('mnr-',)),
        ('metrolink-scrra', args.metrolink_input, 'Name', METROLINK,
         exact_groups, ('metrolink-scrra-',)),
    ]
    for source_id, path, property_name, mapping, grouper, prefixes in jobs:
        if not path:
            continue
        raw, features = read_geojson(path, source_id)
        raw_sha = digest(raw)
        groups = (grouper(features) if grouper is mnr_groups
                  else grouper(features, property_name, mapping))
        manifest['files'] = {
            key: value for key, value in manifest['files'].items()
            if not key.startswith(prefixes)
        }
        manifest['sources'][source_id] = {
            **SOURCES[source_id], 'rawSha256': raw_sha,
            'featureCount': len(features),
        }
        for key, selected in sorted(groups.items()):
            manifest['files'][key] = write_group(
                args.output_dir, key, selected, source_id, raw_sha)

    manifest_path = os.path.join(args.output_dir, 'manifest.json')
    with open(manifest_path + '.tmp', 'w', encoding='utf-8') as target:
        json.dump(manifest, target, ensure_ascii=False, indent=2)
        target.write('\n')
    os.replace(manifest_path + '.tmp', manifest_path)
    print(f'wrote {len(manifest["files"])} official route networks')


if __name__ == '__main__':
    main()
