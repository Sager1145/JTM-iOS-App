#!/usr/bin/env python3
"""Normalize Canadian authority GIS into route-isolated rail networks.

The build never routes over a city-wide network: every output is restricted
to one published route ID, preventing a shortest-path search from changing
lines at a shared subway or streetcar junction.

Toronto's WGS84 subway shapefile is published by the City of Toronto.  The
input archive and every normalized file are hashed in ``manifest.json`` so a
future refresh cannot silently change the release geometry.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import warnings
import zipfile


TTC_SUBWAY_SOURCE = {
    'publisher': 'City of Toronto / Toronto Transit Commission',
    'catalogUrl': 'https://open.toronto.ca/dataset/ttc-subway-shapefiles/',
    'url': ('https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/'
            'c01c6d71-de1f-493d-91ba-364ce64884ac/resource/'
            '7d68bb52-3285-45d7-a248-7748cb47f6ce/download/'
            'ttc-subway-shapefile-wgs84.zip'),
    'license': 'Open Government Licence – Toronto',
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def shapefile_features(archive_path):
    """Return TTC subway LineStrings from the authority's ZIP shapefile."""
    try:
        import shapefile
    except ImportError as exc:  # pragma: no cover - environment diagnostic
        raise SystemExit('pyshp is required to normalize the TTC shapefile') from exc

    with zipfile.ZipFile(archive_path) as archive:
        shp_name = next((name for name in archive.namelist()
                         if name.lower().endswith('.shp')), None)
        dbf_name = next((name for name in archive.namelist()
                         if name.lower().endswith('.dbf')), None)
        if not shp_name or not dbf_name:
            raise SystemExit('TTC archive lacks .shp or .dbf')
        # The authority's 2018 .shp declares a 100-byte header size although
        # its records and companion index are intact.  pyshp validates all
        # records but warns about that known producer metadata defect.
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', shapefile.PossiblyCorruptFileHeader)
            reader = shapefile.Reader(shp=archive.open(shp_name),
                                      dbf=archive.open(dbf_name))
        fields = [field[0] for field in reader.fields[1:]]
        for shape_record in reader.iterShapeRecords():
            properties = dict(zip(fields, shape_record.record))
            route_id = str(int(properties['RID']))
            points = [[round(float(lon), 7), round(float(lat), 7)]
                      for lon, lat in shape_record.shape.points]
            if len(points) < 2:
                raise SystemExit(f'TTC route {route_id} has empty geometry')
            yield route_id, {
                'type': 'Feature',
                'properties': {
                    'route_id': route_id,
                    'route_name': properties.get('ROUTE_NAME'),
                },
                'geometry': {'type': 'LineString', 'coordinates': points},
            }


def normalize_ttc_subway(archive_path, output_dir, generated_at=None):
    with open(archive_path, 'rb') as source:
        raw = source.read()
    raw_hash = sha256(raw)
    os.makedirs(output_dir, exist_ok=True)
    files = {}
    for route_id, feature in shapefile_features(archive_path):
        key = f'ttc-subway-{route_id}'
        payload = {
            'type': 'FeatureCollection',
            'sourceId': key,
            'source': {**TTC_SUBWAY_SOURCE, 'rawSha256': raw_hash},
            'features': [feature],
        }
        path = os.path.join(output_dir, f'{key}.geojson')
        encoded = json.dumps(payload, ensure_ascii=False,
                             separators=(',', ':')).encode('utf-8')
        with open(path, 'wb') as output:
            output.write(encoded)
        files[key] = {'file': os.path.basename(path), 'features': 1,
                      'sha256': sha256(encoded)}

    # Line 3 is retained in the authority's 2018 file but ceased operation in
    # 2023.  It may be audited historically, but the current TTC GTFS does not
    # publish it and therefore the registry intentionally does not reference it.
    expected = {'ttc-subway-1', 'ttc-subway-2',
                'ttc-subway-3', 'ttc-subway-4'}
    if set(files) != expected:
        raise SystemExit(f'unexpected TTC subway routes: {sorted(files)}')
    path = os.path.join(output_dir, 'manifest.json')
    try:
        with open(path, encoding='utf-8') as source:
            manifest = json.load(source)
    except FileNotFoundError:
        manifest = {'schemaVersion': 1, 'sources': {}, 'files': {}}
    if manifest.get('schemaVersion') != 1:
        raise SystemExit('official network manifest has unsupported schemaVersion')
    manifest['generatedAt'] = (generated_at
                               or dt.datetime.now(dt.timezone.utc).isoformat())
    manifest.setdefault('sources', {})['ttc'] = {
        **TTC_SUBWAY_SOURCE, 'rawSha256': raw_hash}
    manifest.setdefault('files', {}).update(files)
    with open(path, 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2)
        output.write('\n')
    return {'schemaVersion': 1, 'generatedAt': manifest['generatedAt'],
            'sources': {'ttc': manifest['sources']['ttc']}, 'files': files}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ttc-subway-zip', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    manifest = normalize_ttc_subway(args.ttc_subway_zip, args.output_dir)
    print(f'wrote {len(manifest["files"])} TTC route networks')


if __name__ == '__main__':
    main()
