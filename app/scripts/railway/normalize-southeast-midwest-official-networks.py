#!/usr/bin/env python3
"""Normalize official Southeast/Midwest urban-rail GIS by exact route."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os


SOURCES = {
    'atlanta-official-heavy-rail': {
        'publisher': 'City of Atlanta / MARTA Special Projects and Analysis',
        'url': ('https://services5.arcgis.com/5RxyIIJ9boPdptdo/arcgis/rest/'
                'services/Official_MARTA_Heavy_Rail_Lines_2021/'
                'FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'atlanta-official-streetcar': {
        'publisher': 'City of Atlanta / Atlanta Streetcar',
        'url': ('https://services5.arcgis.com/5RxyIIJ9boPdptdo/arcgis/rest/'
                'services/Official_Streetcar_Rail_Line_2021/FeatureServer/0/'
                'query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'miami-dade-metrorail': {
        'publisher': 'Miami-Dade County / Miami-Dade Transit',
        'url': ('https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/'
                'services/MetroRail_gdb/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&outSR=4326&returnGeometry=true&f=geojson'),
        'metadataUrl': ('https://gisweb.miamidade.gov/GISSelfServices/Data/'
                        'HTML/MetroRail.htm'),
    },
    'miami-dade-metromover': {
        'publisher': 'Miami-Dade County / Miami-Dade Transit',
        'url': ('https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/'
                'services/MetroMover_gdb/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&outSR=4326&returnGeometry=true&f=geojson'),
        'metadataUrl': ('https://gisweb.miamidade.gov/GISSelfServices/Data/'
                        'HTML/MetroMover.htm'),
    },
    'maryland-mta-light-rail': {
        'publisher': 'MD iMAP / Maryland Transit Administration',
        'url': ('https://mdgeodata.md.gov/imap/rest/services/Transportation/'
                'MD_Transit/FeatureServer/3/query?where=1%3D1&outFields=*&'
                'outSR=4326&returnGeometry=true&f=geojson'),
    },
    'maryland-mta-metro': {
        'publisher': 'MD iMAP / Maryland Transit Administration',
        'url': ('https://mdgeodata.md.gov/imap/rest/services/Transportation/'
                'MD_Transit/FeatureServer/5/query?where=1%3D1&outFields=*&'
                'outSR=4326&returnGeometry=true&f=geojson'),
    },
    'modot-kc-streetcar': {
        'publisher': 'Missouri Department of Transportation',
        'url': ('https://services1.arcgis.com/VVapzOPgBae5joyC/ArcGIS/rest/'
                'services/MoDOT_LRTP_and_SFRP_Layers_WFL1/FeatureServer/9/'
                'query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'modot-stl-metrolink': {
        'publisher': 'Missouri Department of Transportation',
        'url': ('https://services1.arcgis.com/VVapzOPgBae5joyC/ArcGIS/rest/'
                'services/MoDOT_LRTP_and_SFRP_Layers_WFL1/FeatureServer/10/'
                'query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
}

MARTA_KEYS = {
    'Blue': 'marta-blue', 'Gold': 'marta-gold',
    'Green': 'marta-green', 'Red': 'marta-red',
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
    lon1, lat1 = map(math.radians, first)
    lon2, lat2 = map(math.radians, second)
    dlon, dlat = lon2 - lon1, lat2 - lat1
    value = (math.sin(dlat / 2) ** 2
             + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 12_742_000 * math.asin(math.sqrt(value))


def densify_line(line, max_segment_m=100.0):
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


def densify_feature(feature):
    geometry = feature.get('geometry') or {}
    coordinates = geometry.get('coordinates') or []
    if geometry.get('type') == 'LineString':
        dense = densify_line(coordinates)
    else:
        dense = [densify_line(line) for line in coordinates]
    return {**feature,
            'properties': dict(feature.get('properties') or {}),
            'geometry': {**geometry, 'coordinates': dense}}


def marta_groups(features):
    groups = {key: [] for key in MARTA_KEYS.values()}
    for feature in features:
        name = str((feature.get('properties') or {}).get('Name') or '')
        if name not in MARTA_KEYS:
            raise SystemExit(f'MARTA has unknown official line {name!r}')
        groups[MARTA_KEYS[name]].append(densify_feature(feature))
    return groups


def active_maryland(features, label, directions):
    selected = []
    for feature in features:
        properties = feature.get('properties') or {}
        status = str(properties.get('Line_Statu') or '')
        if status.casefold() == 'active':
            direction = str(properties.get('Direction') or '')
            if direction in directions:
                selected.append(densify_feature(feature))
        elif status:
            continue
        else:
            raise SystemExit(f'{label}: feature without official line status')
    if not selected:
        raise SystemExit(f'{label}: no active official linework')
    return selected


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


def normalize(output_dir, inputs):
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    raw = {key: read(path) for key, path in inputs.items()}
    parsed = {key: parse(value, key) for key, value in raw.items()}
    groups = {}
    groups.update(marta_groups(parsed['atlanta-official-heavy-rail']))
    streetcar = [densify_feature(row)
                 for row in parsed['atlanta-official-streetcar']
                 if not str((row.get('properties') or {}).get('ST_NAME') or '')
                 .casefold().startswith(('shop track', 'store track'))]
    groups['marta-streetcar'] = streetcar
    groups['miami-metrorail'] = [densify_feature(row)
                                 for row in parsed['miami-dade-metrorail']]
    groups['miami-metromover'] = [densify_feature(row)
                                  for row in parsed['miami-dade-metromover']]
    groups['maryland-light-rail'] = active_maryland(
        parsed['maryland-mta-light-rail'], 'Maryland Light Rail',
        {'NB', 'NB / SB', 'Penn Station Access'})
    groups['maryland-metro'] = active_maryland(
        parsed['maryland-mta-metro'], 'Maryland Metro', {'NB'})
    groups['modot-kc-streetcar'] = [densify_feature(row)
                                    for row in parsed['modot-kc-streetcar']]
    groups['modot-stl-metrolink'] = [densify_feature(row)
                                     for row in parsed['modot-stl-metrolink']]
    key_source = {
        **{key: 'atlanta-official-heavy-rail' for key in MARTA_KEYS.values()},
        'marta-streetcar': 'atlanta-official-streetcar',
        'miami-metrorail': 'miami-dade-metrorail',
        'miami-metromover': 'miami-dade-metromover',
        'maryland-light-rail': 'maryland-mta-light-rail',
        'maryland-metro': 'maryland-mta-metro',
        'modot-kc-streetcar': 'modot-kc-streetcar',
        'modot-stl-metrolink': 'modot-stl-metrolink',
    }
    for source_id, value in raw.items():
        manifest['sources'][source_id] = {
            **SOURCES[source_id], 'rawSha256': digest(value),
            'featureCount': len(parsed[source_id])}
    for key, features in sorted(groups.items()):
        source_id = key_source[key]
        manifest['files'][key] = write_group(
            output_dir, key, features, source_id, digest(raw[source_id]))
    path = os.path.join(output_dir, 'manifest.json')
    with open(path + '.tmp', 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2)
        output.write('\n')
    os.replace(path + '.tmp', path)
    return len(groups)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    for key in SOURCES:
        parser.add_argument('--' + key, required=True)
    args = parser.parse_args()
    inputs = {key: getattr(args, key.replace('-', '_')) for key in SOURCES}
    print(f'wrote {normalize(args.output_dir, inputs)} southeast/midwest networks')


if __name__ == '__main__':
    main()
