#!/usr/bin/env python3
"""Normalize reviewed Southeast/South-Central government rail GIS.

Every output is route-isolated and retains the raw government download hash.
Sources explicitly generated from GTFS are intentionally absent.
"""
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
    'cats-blue-line': {
        'publisher': 'Charlotte Area Transit System / City of Charlotte',
        'url': ('https://services.arcgis.com/9Nl857LBlQVyzq54/arcgis/rest/'
                'services/LYNX_Blue_Line_Route/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'dcgis-streetcar': {
        'publisher': ('District Department of Transportation / '
                      'District of Columbia GIS'),
        'url': ('https://maps2.dcgis.dc.gov/dcgis/rest/services/DCGIS_DATA/'
                'Transportation_Rail_Bus_WebMercator/MapServer/113/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'fdot-brightline': {
        'publisher': ('Florida Department of Transportation, Freight and '
                      'Multimodal Operations Office'),
        'url': ('https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/'
                'services/Rail_System_Layers_2025/FeatureServer/9/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'fdot-sunrail': {
        'publisher': ('Florida Department of Transportation, Freight and '
                      'Multimodal Operations Office'),
        'url': ('https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/'
                'services/Rail_System_Layers_2025/FeatureServer/2/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
}

KEY_SOURCE = {
    'cats-blue': 'cats-blue-line',
    'dc-streetcar': 'dcgis-streetcar',
    'fdot-brightline': 'fdot-brightline',
    'fdot-sunrail': 'fdot-sunrail',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def lines(feature):
    geometry = feature.get('geometry') or {}
    if geometry.get('type') == 'LineString':
        return [geometry.get('coordinates') or []]
    if geometry.get('type') == 'MultiLineString':
        return geometry.get('coordinates') or []
    raise SystemExit('official GIS contains non-line geometry')


def normalized_feature(feature, simplify_m=0.0):
    output = []
    for line in lines(feature):
        if len(line) < 2:
            continue
        cleaned = geo.dedupe(line)
        if simplify_m:
            cleaned = geo.simplify(cleaned, simplify_m)
        output.append(geo.densify(cleaned, 25.0))
    if not output:
        raise SystemExit('official GIS feature has no usable line')
    geometry = ({'type': 'LineString', 'coordinates': output[0]}
                if len(output) == 1 else
                {'type': 'MultiLineString', 'coordinates': output})
    return {'type': 'Feature',
            'properties': dict(feature.get('properties') or {}),
            'geometry': geometry}


def parse(raw, source_id):
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{source_id}: invalid GeoJSON: {exc}')
    features = payload.get('features') or []
    if payload.get('type') != 'FeatureCollection' or not features:
        raise SystemExit(f'{source_id}: empty/non-FeatureCollection source')
    return features


def route_groups(parsed):
    # CATS publishes both physical tracks.  One complete, consistently named
    # track is the surveyed centreline proxy; retaining both would turn one
    # public route into a self-overlapping loop.
    cats_names = {'NorthBound-Track 1', 'BLE Northbound-Track 1'}
    cats = [normalized_feature(row, simplify_m=0.5)
            for row in parsed['cats-blue-line']
            if (row.get('properties') or {}).get('TrackDescr') in cats_names]
    if len(cats) != 2:
        raise SystemExit('CATS Blue official GIS track inventory changed')

    dc = [normalized_feature(row)
          for row in parsed['dcgis-streetcar']
          if ((row.get('properties') or {}).get('LINE_STATUS') == 'Active'
              and (row.get('properties') or {}).get('LINE') ==
              'Union Station - Benning Rd')]
    if {str((row.get('properties') or {}).get('DIRECTION'))
        for row in parsed['dcgis-streetcar']
        if (row.get('properties') or {}).get('LINE_STATUS') == 'Active'} != {
            'To Union Station', 'To Benning Rd'}:
        raise SystemExit('DC Streetcar official directions changed')

    brightline = [normalized_feature(row)
                  for row in parsed['fdot-brightline']
                  if (row.get('properties') or {}).get('PASSENGER') ==
                  'Brightline']
    # FDOT also tags a proposed airport connection as SunRail.  The current
    # GTFS service is the active CSX corridor, so ORUZ project segments are
    # excluded rather than leaking a future orphan branch into the package.
    sunrail = [normalized_feature(row)
               for row in parsed['fdot-sunrail']
               if ((row.get('properties') or {}).get('COMMUTERRL') == 'SunRail'
                   and (row.get('properties') or {}).get('RRCO') == 'CSX')]
    groups = {'cats-blue': cats, 'dc-streetcar': dc,
              'fdot-brightline': brightline, 'fdot-sunrail': sunrail}
    for key, features in groups.items():
        if not features:
            raise SystemExit(f'{key}: official source has no route geometry')
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


def normalize(output_dir, inputs):
    raw = {}
    parsed = {}
    for source_id, path in inputs.items():
        with open(path, 'rb') as source:
            raw[source_id] = source.read()
        parsed[source_id] = parse(raw[source_id], source_id)
    groups = route_groups(parsed)
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    for source_id in SOURCES:
        manifest['sources'][source_id] = {
            **SOURCES[source_id], 'rawSha256': digest(raw[source_id]),
            'featureCount': len(parsed[source_id]),
        }
    for key, features in sorted(groups.items()):
        source_id = KEY_SOURCE[key]
        raw_sha = digest(raw[source_id])
        payload = {'type': 'FeatureCollection', 'sourceId': key,
                   'source': {**SOURCES[source_id], 'rawSha256': raw_sha},
                   'features': features}
        encoded = json.dumps(payload, ensure_ascii=False,
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
    for source_id in SOURCES:
        parser.add_argument('--' + source_id, required=True)
    args = parser.parse_args()
    inputs = {source_id: getattr(args, source_id.replace('-', '_'))
              for source_id in SOURCES}
    manifest = normalize(args.output_dir, inputs)
    print('wrote 4 route-isolated south-central networks; manifest now '
          f'contains {len(manifest["files"])} files')


if __name__ == '__main__':
    main()
