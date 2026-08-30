#!/usr/bin/env python3
"""Download Québec MTQ's official railway centrelines with provenance."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.request
from datetime import datetime, timezone


METADATA_URL = (
    'https://www.donneesquebec.ca/recherche/api/3/action/'
    'package_show?id=reseau-ferroviaire')
GEOJSON_URL = (
    'https://ws.mapserver.transports.gouv.qc.ca/swtq?service=wfs&version=2.0.0'
    '&request=getfeature&typename=ms:reseau_chfer_qc&outfile=ReseauFerroviaire'
    '&srsname=EPSG:4326&outputformat=geojson')
RESOURCE_ID = '5b5cd483-4f03-48f9-9522-66eb79b67c32'


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'JTM-rail-builder/1'})
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read()


def atomic_write(path, data):
    temporary = path + '.tmp'
    with open(temporary, 'wb') as output:
        output.write(data)
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-dir', required=True)
    options = parser.parse_args()
    os.makedirs(options.source_dir, exist_ok=True)

    metadata_bytes = fetch(METADATA_URL)
    geometry_bytes = fetch(GEOJSON_URL)
    metadata = json.loads(metadata_bytes)
    geometry = json.loads(geometry_bytes)
    if not metadata.get('success') or not geometry.get('features'):
        raise SystemExit('official Québec response was incomplete')
    resource = next(
        item for item in metadata['result']['resources']
        if item.get('id') == RESOURCE_ID)

    geometry_path = os.path.join(options.source_dir, 'quebec-rail.geojson')
    atomic_write(geometry_path, geometry_bytes)
    manifest = {
        'authority': 'Québec Ministère des Transports et de la Mobilité durable',
        'dataset': metadata['result']['title'],
        'metadataUrl': METADATA_URL,
        'resourceUrl': GEOJSON_URL,
        'resourceId': RESOURCE_ID,
        'license': metadata['result']['license_title'],
        'licenseUrl': metadata['result']['license_url'],
        'resourceLastModified': resource.get('last_modified'),
        'downloadedAt': datetime.now(timezone.utc).isoformat(),
        'featureCount': len(geometry['features']),
        'sha256': hashlib.sha256(geometry_bytes).hexdigest(),
    }
    atomic_write(
        os.path.join(options.source_dir, 'quebec-rail-manifest.json'),
        json.dumps(manifest, ensure_ascii=False, indent=2).encode('utf-8'))
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
