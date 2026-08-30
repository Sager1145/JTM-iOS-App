#!/usr/bin/env python3
"""Normalize reviewed MTA and NJ Transit GIS lines by exact GTFS route.

The authority layers describe physical branches.  Each output below lists
only the official shared trunks and branch features needed by one published
route, so shortest-path routing cannot wander onto a neighbouring branch.
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


LIRR = {
    'lirr-1-babylon': (
        'CITY TERMINAL ZONE', 'WEST HEMPSTEAD', 'BABYLON'),
    'lirr-2-hempstead': ('CITY TERMINAL ZONE', 'HEMPSTEAD'),
    'lirr-3-oyster-bay': (
        'CITY TERMINAL ZONE', 'HEMPSTEAD', 'PORT JEFFERSON', 'OYSTER BAY'),
    'lirr-4-ronkonkoma': (
        'CITY TERMINAL ZONE', 'HEMPSTEAD', 'PORT JEFFERSON', 'RONKONKOMA'),
    'lirr-5-montauk': (
        'CITY TERMINAL ZONE', 'WEST HEMPSTEAD', 'BABYLON', 'MONTAUK'),
    'lirr-6-long-beach': (
        'CITY TERMINAL ZONE', 'FAR ROCKAWAY', 'LONG BEACH'),
    'lirr-7-far-rockaway': ('CITY TERMINAL ZONE', 'FAR ROCKAWAY'),
    'lirr-8-west-hempstead': ('CITY TERMINAL ZONE', 'WEST HEMPSTEAD'),
    'lirr-9-port-washington': ('CITY TERMINAL ZONE', 'PORT WASHINGTON'),
    'lirr-10-port-jefferson': (
        'CITY TERMINAL ZONE', 'HEMPSTEAD', 'PORT JEFFERSON'),
    'lirr-13-greenport': ('RONKONKOMA',),
}

NJT_RAIL = {
    'njt-rail-1-atlantic-city': ('Atlantic City Line',),
    'njt-rail-2-montclair-boonton': ('Montclair-Boonton Line',),
    'njt-rail-3-montclair-boonton': ('Montclair-Boonton Line',),
    'njt-rail-5-main-bergen': ('Main Line', 'Bergen County Line'),
    'njt-rail-6-port-jervis': (
        'Main Line', 'Bergen County Line', 'Southern Tier'),
    'njt-rail-7-morristown': ('Morristown Line',),
    'njt-rail-8-gladstone': ('Gladstone Branch',),
    'njt-rail-9-meadowlands': ('Meadowlands Line',),
    'njt-rail-10-nec': ('Northeast Corridor',),
    'njt-rail-11-njcl': ('North Jersey Coast Line',),
    'njt-rail-12-njcl': ('North Jersey Coast Line',),
    'njt-rail-14-pascack': ('Pascack Valley Line',),
    'njt-rail-15-princeton': ('Princeton Dinky',),
    'njt-rail-16-raritan': ('Raritan Valley Line',),
}

NJT_LIGHT = {
    'njt-light-4-hblr': ('HB', 3),
    'njt-light-13-newark': ('Newark Light Rail', 2),
    'njt-light-17-river': ('RiverLINE', 1),
}

PATH = {
    'path-njt-859-hoboken-33': 'Hoboken-33rd St',
    'path-njt-860-hoboken-wtc': 'Hoboken-WTC',
    'path-njt-861-jsq-33': 'Journal Square-33rd St',
    'path-njt-862-newark-wtc': 'Newark-WTC',
    'path-njt-1024-jsq-33-via-hoboken': 'Journal Square-33rd St via HOB',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def distance_m(first, second):
    lat = math.radians((first[1] + second[1]) / 2.0)
    dx = math.radians(second[0] - first[0]) * math.cos(lat)
    dy = math.radians(second[1] - first[1])
    return math.hypot(dx, dy) * 6_371_008.8


def geometry_lines(feature):
    geometry = feature['geometry']
    coordinates = geometry['coordinates']
    return [coordinates] if geometry['type'] == 'LineString' else coordinates


def close_lirr_published_junctions(features):
    """Close three named MTA digitizing seams, and reject changed source data."""
    features = copy.deepcopy(features)
    rules = (
        # Two Jamaica track pieces in CITY TERMINAL ZONE end beside another
        # vertex in the same MTA layer rather than sharing its coordinate.
        (('CITY TERMINAL ZONE', 'HEMPSTEAD'),
         [-73.80483358499998, 40.70080943700003],
         [-73.80492778599995, 40.70073068500005], 15.0),
        (('CITY TERMINAL ZONE', 'FAR ROCKAWAY'),
         [-73.80695534299997, 40.70011911100005],
         [-73.80702235799998, 40.70019521000006], 15.0),
        # WEST HEMPSTEAD's Jamaica endpoint is a 43 m simplified-line seam
        # to that same published junction, not permission to join any line.
        (('WEST HEMPSTEAD',),
         [-73.80464297899994, 40.700408234000065],
         [-73.80492778599995, 40.70073068500005], 45.0),
    )
    for names, old, new, limit_m in rules:
        gap = distance_m(old, new)
        if gap > limit_m:
            raise SystemExit(
                f'LIRR official junction gap changed: {gap:.2f} m')
        replaced = 0
        for feature in features:
            name = str((feature.get('properties') or {}).get('route_name') or '')
            if name not in names:
                continue
            for line in geometry_lines(feature):
                for index, point in enumerate(line):
                    if point == old:
                        line[index] = list(new)
                        replaced += 1
        if not replaced:
            raise SystemExit('LIRR official junction coordinate changed')
    return features


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
    if any((row.get('geometry') or {}).get('type') not in
           ('LineString', 'MultiLineString') for row in features):
        raise SystemExit(f'{source_id}: contains non-line geometry')
    return raw, features


def exact_groups(features, property_name, mapping):
    by_name = {}
    for feature in features:
        name = str((feature.get('properties') or {}).get(property_name) or '')
        by_name.setdefault(name, []).append(feature)
    groups = {}
    for key, names in mapping.items():
        selected = []
        for name in names:
            candidates = by_name.get(name) or []
            if len(candidates) != 1:
                raise SystemExit(
                    f'{key}: expected one official feature named {name!r}, '
                    f'found {len(candidates)}')
            selected.append(candidates[0])
        groups[key] = selected
    return groups


def light_groups(features):
    by_code = {}
    for feature in features:
        code = str((feature.get('properties') or {}).get('LINE_CODE') or '')
        by_code.setdefault(code, []).append(feature)
    groups = {}
    for key, (code, expected) in NJT_LIGHT.items():
        selected = by_code.get(code) or []
        if len(selected) != expected:
            raise SystemExit(
                f'{key}: expected {expected} official {code!r} features, '
                f'found {len(selected)}')
        groups[key] = selected
    return groups


def path_groups(features):
    return exact_groups(
        features, 'SERVICE', {key: (name,) for key, name in PATH.items()})


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
        sha = digest(source_file.read())
    return {'file': os.path.basename(path), 'features': len(features),
            'sha256': sha}


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
    parser.add_argument('--lirr-input')
    parser.add_argument('--njt-rail-input')
    parser.add_argument('--njt-light-input')
    parser.add_argument('--path-input')
    args = parser.parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    manifest = load_manifest(args.output_dir)
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()

    jobs = (
        ('mta-rail-branches', args.lirr_input, 'route_name', LIRR,
         exact_groups, 'lirr-'),
        ('njt-rail', args.njt_rail_input, 'LINE_NAME', NJT_RAIL,
         exact_groups, 'njt-rail-'),
        ('njt-light', args.njt_light_input, None, NJT_LIGHT,
         light_groups, 'njt-light-'),
        ('njt-path', args.path_input, None, PATH,
         path_groups, 'path-njt-'),
    )
    for source_id, path, prop, mapping, grouper, prefix in jobs:
        if not path:
            continue
        raw, features = read_geojson(path, source_id)
        if source_id == 'mta-rail-branches':
            features = close_lirr_published_junctions(features)
        raw_sha = digest(raw)
        groups = (grouper(features) if prop is None
                  else grouper(features, prop, mapping))
        manifest['files'] = {
            key: value for key, value in manifest['files'].items()
            if not key.startswith(prefix)
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
