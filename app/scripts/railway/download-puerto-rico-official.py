#!/usr/bin/env python3
"""Inspect ATI's official Puerto Rico SHP, rejecting GTFS-derived geometry.

The current government archive identifies its records as ``PRITA_GTFS`` and
links them back to Remix.  It therefore cannot be an independent spatial
cross-check for the same GTFS and this downloader fails closed before writing
an ``official-geom`` artifact.
"""
from __future__ import annotations

import argparse
import gzip
import io
import json
import os
import urllib.request
import zipfile


SOURCE_URL = ('https://docs.pr.gov/files/ATI/DATOS_ABIERTOS/'
              'SHP%20FILES/PRITA_SHP_FILE.zip')


def assert_independent(record):
    evidence = ' '.join(str(record.get(key) or '')
                        for key in ('map_name', 'url')).casefold()
    if 'gtfs' in evidence or 'remix.com' in evidence:
        raise SystemExit(
            'ATI SHP identifies itself as PRITA_GTFS/Remix-derived; it is not '
            'eligible as an independent railway centreline')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output-dir', required=True)
    ap.add_argument('--url', default=SOURCE_URL)
    options = ap.parse_args()

    try:
        import shapefile
    except ImportError as exc:
        raise SystemExit('pyshp is required to read ATI official SHP data') from exc

    request = urllib.request.Request(
        options.url, headers={'User-Agent': 'JTM-RailMap official-data audit'})
    with urllib.request.urlopen(request, timeout=180) as response:
        archive = response.read()
    with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
        reader = shapefile.Reader(
            shp=io.BytesIO(bundle.read('directions.shp')),
            shx=io.BytesIO(bundle.read('directions.shx')),
            dbf=io.BytesIO(bundle.read('directions.dbf')),
            encoding='utf-8')
        lines = []
        for row in reader.iterShapeRecords():
            record = row.record.as_dict()
            if (record.get('vehicle_ty') or '').strip().lower() != 'rail':
                continue
            assert_independent(record)
            parts = list(row.shape.parts) + [len(row.shape.points)]
            for start, end in zip(parts, parts[1:]):
                points = [[round(float(x), 7), round(float(y), 7)]
                          for x, y in row.shape.points[start:end]]
                if len(points) > 1:
                    lines.append(points)

    payload = {
        'sourceId': 'pr-ati-shp',
        'authority': 'Autoridad de Transporte Integrado de Puerto Rico',
        'sourceUrl': options.url,
        'publication': 'PRITA_SHP_FILE.zip (2025-05-30)',
        'lines': lines,
    }
    os.makedirs(options.output_dir, exist_ok=True)
    path = os.path.join(options.output_dir, 'puerto-rico-ati.json.gz')
    with gzip.open(path, 'wt', encoding='utf-8') as output:
        json.dump(payload, output, ensure_ascii=False, separators=(',', ':'))
    print(f'wrote {path}: {len(lines)} official rail alignments')


if __name__ == '__main__':
    main()
