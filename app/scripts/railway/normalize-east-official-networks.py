#!/usr/bin/env python3
"""Normalize reviewed MassGIS and SEPTA linework into route-only graphs.

GTFS supplies service identity, station order, and the operator's display
colour.  These public-agency GIS layers supply only the physical alignment.
Every output key is isolated to one GTFS route so a graph search cannot jump
onto an adjacent line at a junction.

WMATA is intentionally absent.  Its official static GTFS is a schedule feed,
not independent surveyed GIS linework, and therefore must not receive the
verified-official-geometry/direct-chord exception from this normalizer.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import urllib.request


SOURCES = {
    'massgis-mbta-rapid': {
        'publisher': ('MassGIS (Bureau of Geographic Information), '
                      'Commonwealth of Massachusetts EOTSS'),
        'url': ('https://arcgisserver.digital.mass.gov/arcgisserver/rest/'
                'services/AGOL/MBTA_Rapid_Transit/FeatureServer/4/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
        'metadataUrl': ('https://www.mass.gov/info-details/'
                        'massgis-data-mbta-rapid-transit'),
    },
    'massgis-mbta-commuter': {
        'publisher': ('MassGIS (Bureau of Geographic Information), '
                      'Commonwealth of Massachusetts EOTSS'),
        'url': ('https://services9.arcgis.com/zkB26wYVlNoTUmsC/ArcGIS/'
                'rest/services/MassGIS_trains/FeatureServer/2/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
        'metadataUrl': ('https://www.mass.gov/info-details/'
                        'massgis-data-trains'),
    },
    'septa-high-speed': {
        'publisher': 'SEPTA Planning Division',
        'url': ('https://opendata.arcgis.com/api/v3/datasets/'
                '1e7754ca5f7d47e480a628e282466428_0/downloads/data?'
                'format=geojson&spatialRefId=4326'),
        'metadataUrl': ('https://opendataphilly.org/datasets/'
                        'septa-routes-stops-locations/'),
    },
    'septa-trolley': {
        'publisher': 'SEPTA Planning Division',
        'url': ('https://opendata.arcgis.com/api/v3/datasets/'
                '33944ef79d2249aca38561a68dc3e06f_0/downloads/data?'
                'format=geojson&spatialRefId=4326'),
        'metadataUrl': ('https://opendataphilly.org/datasets/'
                        'septa-routes-stops-locations/'),
    },
}


MBTA_RAPID_KEYS = {
    'Blue': 'mbta-rapid-blue',
    'Orange': 'mbta-rapid-orange',
    'Red': 'mbta-rapid-red',
    'Mattapan': 'mbta-rapid-mattapan',
    'Green-B': 'mbta-rapid-green-b',
    'Green-C': 'mbta-rapid-green-c',
    'Green-D': 'mbta-rapid-green-d',
    'Green-E': 'mbta-rapid-green-e',
}

MBTA_COMMUTER_LINES = {
    # CapeFLYER joins its Cape main-line feature to the active
    # Middleborough/Lakeville corridor into Boston.
    'CapeFlyer': ('CapeFLYER', 'Middleborough/Lakeville'),
    'CR-Fairmount': ('Fairmount',),
    'CR-NewBedford': ('South Coast', 'Middleborough/Lakeville'),
    'CR-Fitchburg': ('Fitchburg',),
    'CR-Foxboro': ('Foxboro', 'Franklin', 'Providence/Stoughton'),
    'CR-Worcester': ('Framingham/Worcester',),
    # Foxboro service is published inside the Franklin GTFS route.
    'CR-Franklin': ('Franklin', 'Foxboro', 'Fairmount'),
    'CR-Greenbush': ('Greenbush',),
    # The Wildcat Branch is used by Haverhill service patterns.
    'CR-Haverhill': ('Haverhill', 'Wildcat Branch'),
    'CR-Kingston': ('Kingston/Plymouth',),
    'CR-Lowell': ('Lowell',),
    'CR-Needham': ('Needham',),
    'CR-Newburyport': ('Newburyport/Rockport',),
    # One operator-published Providence pattern runs via Fairmount rather
    # than Back Bay; both named MassGIS corridors are therefore eligible.
    'CR-Providence': ('Providence/Stoughton', 'Fairmount'),
}

SEPTA_HIGH_SPEED_KEYS = {
    'B': ('septa-b1', 'septa-b3'),
    'L': ('septa-l1',),
    'M': ('septa-m1',),
}

SEPTA_TROLLEY_KEYS = {
    route_id: f'septa-{route_id.lower()}'
    for route_id in ('D1', 'D2', 'G1', 'T1', 'T2', 'T3', 'T4', 'T5')
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


def _tokens(value):
    return set(re.findall(r'[A-Z0-9]+', str(value or '').upper()))


def mbta_rapid_groups(features):
    groups = {key: [] for key in MBTA_RAPID_KEYS.values()}
    seen_lines = set()
    for feature in features:
        properties = feature.get('properties') or {}
        line = str(properties.get('LINE') or '').upper()
        route = str(properties.get('ROUTE') or '')
        seen_lines.add(line)
        if line == 'BLUE':
            groups['mbta-rapid-blue'].append(feature)
        elif line == 'ORANGE':
            groups['mbta-rapid-orange'].append(feature)
        elif line == 'RED':
            if route == 'Mattapan Trolley':
                groups['mbta-rapid-mattapan'].append(feature)
            else:
                groups['mbta-rapid-red'].append(feature)
        elif line == 'GREEN':
            route_tokens = _tokens(route)
            for branch in 'BCDE':
                # The operator GTFS snapshot through-runs B and C trains to
                # Medford/Tufts and includes an E short pattern to Union
                # Square.  Admit only those explicitly named MassGIS pieces,
                # not the entire Green Line graph.
                through_medford = (
                    branch in 'BC' and route == 'E - Medford/Tufts')
                shared_extension = (
                    branch in 'BC' and route_tokens == {'D', 'E'})
                e_union_short = (
                    branch == 'E' and route == 'D - Union Square')
                if (branch in route_tokens or through_medford
                        or shared_extension or e_union_short):
                    groups[f'mbta-rapid-green-{branch.lower()}'].append(feature)
        elif line != 'SILVER':
            raise SystemExit(f'MassGIS rapid layer has unknown LINE {line!r}')
    required = {'BLUE', 'ORANGE', 'RED', 'GREEN'}
    if not required.issubset(seen_lines):
        raise SystemExit('MassGIS rapid layer is missing a rail line')
    return groups


def mbta_commuter_groups(features):
    groups = {
        f'mbta-commuter-{route_id.lower()}': []
        for route_id in MBTA_COMMUTER_LINES
    }
    for feature in features:
        properties = feature.get('properties') or {}
        line = str(properties.get('COMM_LINE') or '')
        status = str(properties.get('COMMRAIL') or '')
        # Only current/seasonal lines are eligible.  South Coast is the one
        # reviewed exception: the October 2025 MassGIS layer still carries P
        # on its newly opened consolidated feature while the official MBTA
        # GTFS publishes active Fall River/New Bedford service over it.
        if status not in ('Y', 'S') and line != 'South Coast':
            continue
        for route_id, accepted_lines in MBTA_COMMUTER_LINES.items():
            if line in accepted_lines:
                groups[f'mbta-commuter-{route_id.lower()}'].append(feature)
    return groups


def septa_high_speed_groups(features):
    groups = {
        key: []
        for keys in SEPTA_HIGH_SPEED_KEYS.values()
        for key in keys
    }
    seen = set()
    for feature in features:
        route = str((feature.get('properties') or {}).get('Route') or '')
        seen.add(route)
        keys = SEPTA_HIGH_SPEED_KEYS.get(route)
        if keys is None:
            raise SystemExit(f'SEPTA high-speed layer has unknown Route {route!r}')
        for key in keys:
            groups[key].append(feature)
    if seen != set(SEPTA_HIGH_SPEED_KEYS):
        raise SystemExit('SEPTA high-speed layer is missing a route')
    return groups


def septa_trolley_groups(features):
    groups = {key: [] for key in SEPTA_TROLLEY_KEYS.values()}
    seen = set()
    for feature in features:
        route = str((feature.get('properties') or {}).get('Route') or '')
        seen.add(route)
        key = SEPTA_TROLLEY_KEYS.get(route)
        if key is None:
            raise SystemExit(f'SEPTA trolley layer has unknown Route {route!r}')
        groups[key].append(feature)
    if seen != set(SEPTA_TROLLEY_KEYS):
        raise SystemExit('SEPTA trolley layer is missing a route')
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
        ('massgis-mbta-rapid', inputs.get('massgis_mbta_rapid_input'),
         mbta_rapid_groups),
        ('massgis-mbta-commuter', inputs.get('massgis_mbta_commuter_input'),
         mbta_commuter_groups),
        ('septa-high-speed', inputs.get('septa_high_speed_input'),
         septa_high_speed_groups),
        ('septa-trolley', inputs.get('septa_trolley_input'),
         septa_trolley_groups),
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
    parser.add_argument('--massgis-mbta-rapid-input')
    parser.add_argument('--massgis-mbta-commuter-input')
    parser.add_argument('--septa-high-speed-input')
    parser.add_argument('--septa-trolley-input')
    args = parser.parse_args()
    written = normalize(args.output_dir, vars(args))
    print(f'wrote {written} east route-specific official networks')


if __name__ == '__main__':
    main()
