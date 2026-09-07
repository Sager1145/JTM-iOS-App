#!/usr/bin/env python3
"""Normalize exact City of El Paso and NCTCOG revenue-rail alignments."""
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
    'sunmetro-streetcar': {
        'publisher': 'City of El Paso / Sun Metro',
        'url': ('https://gis.elpasotexas.gov/arcgis/rest/services/SunMetro/'
                'StreetcarRoute/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&outSR=4326&returnGeometry=true&f=geojson'),
        'metadataUrl': ('https://gis.elpasotexas.gov/arcgis/rest/services/'
                        'SunMetro/StreetcarRoute/FeatureServer/0'),
    },
    'nctcog-existing-rail-lines': {
        'publisher': ('North Central Texas Council of Governments (NCTCOG), '
                      'Transportation Department'),
        'url': ('https://geospatial.nctcog.org/map/rest/services/'
                'Transportation/DFWMaps_Transit/MapServer/2/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
}

TEXRAIL_LINES = {'TEXRail', 'TRE/TEXRail', 'TEXRail/Silver'}
TEXRAIL_AGENCIES = {
    'Trinity Metro', 'TRE/Trinity Metro', 'Trinity Metro/DART'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def parse(path, source_id):
    with open(path, 'rb') as source:
        raw = source.read()
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{source_id}: invalid GeoJSON: {exc}')
    features = payload.get('features') or []
    if payload.get('type') != 'FeatureCollection' or not features:
        raise SystemExit(f'{source_id}: empty/non-FeatureCollection source')
    for feature in features:
        if (feature.get('geometry') or {}).get('type') not in (
                'LineString', 'MultiLineString'):
            raise SystemExit(f'{source_id}: non-line geometry')
    return raw, features


def normalized_feature(feature):
    geometry = feature.get('geometry') or {}
    lines = ([geometry.get('coordinates') or []]
             if geometry.get('type') == 'LineString'
             else geometry.get('coordinates') or [])
    dense = [geo.densify(geo.dedupe(line), 25.0)
             for line in lines if len(line) >= 2]
    if not dense:
        raise SystemExit('official feature has no usable line geometry')
    output_geometry = ({'type': 'LineString', 'coordinates': dense[0]}
                       if len(dense) == 1 else
                       {'type': 'MultiLineString', 'coordinates': dense})
    return {'type': 'Feature',
            'properties': dict(feature.get('properties') or {}),
            'geometry': output_geometry}


def sunmetro_group(features):
    ids = {(row.get('properties') or {}).get('Id') for row in features}
    if len(features) != 3 or ids != {0, 1}:
        raise SystemExit(
            f'Sun Metro streetcar layer changed: {len(features)} features, '
            f'Ids={sorted(ids, key=str)}')
    return [normalized_feature(row) for row in features]


def texrail_group(features):
    selected = []
    for row in features:
        properties = row.get('properties') or {}
        if str(properties.get('Line') or '') not in TEXRAIL_LINES:
            continue
        status = str(properties.get('ServiceStatus') or '')
        agency = str(properties.get('Agency') or '')
        if status != 'In Revenue Service' or agency not in TEXRAIL_AGENCIES:
            raise SystemExit(
                f'NCTCOG TEXRail changed authority/status: {agency!r}/{status!r}')
        selected.append(normalized_feature(row))
    if len(selected) != 8:
        raise SystemExit(
            f'NCTCOG TEXRail expected 8 revenue segments, got {len(selected)}')
    return selected


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
    payload = {'type': 'FeatureCollection', 'sourceId': key,
               'source': {**SOURCES[source_id], 'rawSha256': raw_sha},
               'features': features}
    encoded = json.dumps(payload, ensure_ascii=False,
                         separators=(',', ':')).encode()
    filename = key + '.geojson'
    path = os.path.join(output_dir, filename)
    with open(path + '.tmp', 'wb') as output:
        output.write(encoded)
    os.replace(path + '.tmp', path)
    return {'file': filename, 'features': len(features),
            'sha256': digest(encoded)}


def normalize(output_dir, sunmetro_input, nctcog_input):
    os.makedirs(output_dir, exist_ok=True)
    raw_sun, sun_features = parse(sunmetro_input, 'sunmetro-streetcar')
    raw_nct, nct_features = parse(nctcog_input,
                                  'nctcog-existing-rail-lines')
    groups = {
        'sunmetro-streetcar': sunmetro_group(sun_features),
        'nctcog-texrail': texrail_group(nct_features),
    }
    source_for_key = {
        'sunmetro-streetcar': 'sunmetro-streetcar',
        'nctcog-texrail': 'nctcog-existing-rail-lines',
    }
    raw_for_source = {
        'sunmetro-streetcar': raw_sun,
        'nctcog-existing-rail-lines': raw_nct,
    }
    counts = {
        'sunmetro-streetcar': len(sun_features),
        'nctcog-existing-rail-lines': len(nct_features),
    }
    manifest = load_manifest(output_dir)
    for source_id, raw in raw_for_source.items():
        manifest['sources'][source_id] = {
            **SOURCES[source_id], 'rawSha256': digest(raw),
            'featureCount': counts[source_id]}
    for key, rows in groups.items():
        source_id = source_for_key[key]
        manifest['files'][key] = write_group(
            output_dir, key, rows, source_id,
            digest(raw_for_source[source_id]))
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
    parser.add_argument('--sunmetro-input', required=True)
    parser.add_argument('--nctcog-input', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, args.sunmetro_input,
                         args.nctcog_input)
    print('wrote 2 west/central route-isolated official networks; '
          f'manifest now contains {len(manifest["files"])} files')


if __name__ == '__main__':
    main()
