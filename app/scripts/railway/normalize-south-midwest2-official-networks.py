#!/usr/bin/env python3
"""Normalize audited Texas/Midwest/South urban-rail GIS by exact route.

Every source here was checked for independence from the operator's own GTFS
before it was admitted: a layer that a city generates *from* the feed proves
nothing the feed does not already say, and the pipeline refuses it.  Route
isolation is always by a published attribute, never by which linework happens
to lie near a station.

Keys that another normalizer already owns are deliberately not reused.
``houston-metro-900`` (METRO's transit-layers service), ``metra-ri`` /
``metra-up-w`` (the City of Chicago KML) and ``cats-blue`` are left alone; the
upstream authorities found here are published beside them under their own keys
so the two can be compared rather than silently swapped.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))
import na_geo as geo


SOURCES = {
    'nctcog-existing-rail-lines': {
        'publisher': ('North Central Texas Council of Governments (NCTCOG), '
                      'Transportation Department'),
        'url': ('https://geospatial.nctcog.org/map/rest/services/'
                'Transportation/DFWMaps_Transit/MapServer/2/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'detroit-people-mover-route': {
        'publisher': 'City of Detroit, Open Data Portal',
        'url': ('https://services2.arcgis.com/qvkbeam7Wirps6zC/arcgis/rest/'
                'services/Detroit_People_Mover_Route/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'detroit-qline-route': {
        'publisher': 'City of Detroit, Open Data Portal',
        'url': ('https://services2.arcgis.com/qvkbeam7Wirps6zC/arcgis/rest/'
                'services/QLine_Route/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'cagis-cincinnati-streetcar': {
        'publisher': ('CAGIS - Cincinnati Area Geographic Information System '
                      '(City of Cincinnati / Hamilton County)'),
        'url': ('https://services.arcgis.com/JyZag7oO4NteHGiq/arcgis/rest/'
                'services/Open_Data_Feature_Collection/FeatureServer/13/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'milwaukee-dpw-streetcar': {
        'publisher': 'City of Milwaukee, Department of Public Works',
        'url': ('https://milwaukeemaps.milwaukee.gov/arcgis/rest/services/'
                'DPW/DPW_streetcar/MapServer/1/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'cats-gold-line': {
        'publisher': 'Charlotte Area Transit System / City of Charlotte',
        'url': ('https://services.arcgis.com/9Nl857LBlQVyzq54/arcgis/rest/'
                'services/LYNX_Gold_Line_Route/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'rta-metra-rail-lines': {
        'publisher': ('Regional Transportation Authority of Northeastern '
                      'Illinois, Mapping and GIS Portal'),
        'url': ('https://services5.arcgis.com/NIHJ1cAxHq972sDH/ArcGIS/rest/'
                'services/Transit_Services_FS/FeatureServer/5/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'houston-metrorail-lines': {
        'publisher': ('Metropolitan Transit Authority of Harris County '
                      '(METRO)'),
        'url': ('https://services5.arcgis.com/p8QKnlioaN3sruqA/arcgis/rest/'
                'services/METRORail_LRT_Lines___Stations_WFL1/FeatureServer/'
                '5/query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
}

# NCTCOG publishes shared trackage once, under a compound ``Line`` value, the
# same way the Metra KML does.  Each public route therefore claims every value
# its trains actually run over, and no value is invented: the eighteen strings
# below are exactly the eighteen the layer contains.
NCTCOG_LINE_VALUES = {
    'dart-blue': {'Blue', 'Red/Blue', 'Red/Blue/Orange',
                  'Red/Blue/Green/Orange'},
    'dart-green': {'Green', 'Green/Orange', 'Red/Blue/Green/Orange'},
    'dart-orange': {'Orange', 'Green/Orange', 'Red/Orange', 'Red/Orange-Peak',
                    'Red/Blue/Orange', 'Red/Blue/Green/Orange'},
    'dart-red': {'Red', 'Red/Blue', 'Red/Orange', 'Red/Orange-Peak',
                 'Red/Blue/Orange', 'Red/Blue/Green/Orange'},
    'dart-silver': {'Silver', 'TEXRail/Silver'},
    'dart-tre': {'Trinity Railway Express', 'TRE/TEXRail'},
    'dart-m-line': {'M-Line'},
    'dallas-streetcar': {'Dallas Streetcar'},
    'texrail': {'TEXRail', 'TRE/TEXRail', 'TEXRail/Silver'},
    'dcta-a-train': {'A-train'},
}

# The three NCTCOG routes whose ``Line`` value is unique to one operator; the
# check is a guard against a republish reusing the string for someone else.
NCTCOG_AGENCY = {
    'dart-m-line': 'MATA',
    'dallas-streetcar': 'City of Dallas',
    'dcta-a-train': 'DCTA',
}

# The RTA asset register carries one feature per line, so ``NAME`` isolates a
# service outright.  Only the three lines the Chicago KML cannot route are
# taken; the remaining eight stay on their existing key so the two sources
# disagree in the open rather than one quietly replacing the other. UP-N
# joined RI and UP-W here because the Chicago KML disagrees with the
# independent rail reference by 364 m near Kenosha (na-feeds.json's
# officialNetworkDefectByRouteId) -- the RTA/CMAP "Metra Rail Lines" layer
# names it distinctly as 'UPN', same as the other two.
RTA_METRA_NAMES = {
    'rta-metra-ri': 'RID',
    'rta-metra-up-n': 'UPN',
    'rta-metra-up-w': 'UPW',
}
RTA_METRA_ALL_NAMES = {
    'BNSF', 'HC', 'MDN', 'MDW', 'ME', 'NCS', 'RID', 'SS', 'SWS', 'UPN',
    'UPNW', 'UPW'}

# METRO names the Purple Line by its corridor.  ``Status`` is stale — it still
# reads "Construction" for a line open since 2015 — so the selector is
# ``NAME``, cross-checked against ``LineColor``.
HOUSTON_LINE_NAMES = {'houston-metrorail-900': ('Southeast', 'Purple')}
HOUSTON_ALL_NAMES = {
    ('East End', 'Green'), ('Main - Fannin', 'Red'), ('North', 'Red'),
    ('Southeast', 'Purple')}

# Milwaukee's ``STATUS`` is stale in the same way ("Construction through fall
# 2018" for track that has carried passengers since then), so the route name is
# the only attribute worth trusting.  The L-Line is the 2023 Lakefront
# extension and is not a separate GTFS route.
MILWAUKEE_ROUTE_NAMES = {'The M-Line', 'The L-Line'}

KEY_SOURCE = {
    **{key: 'nctcog-existing-rail-lines' for key in NCTCOG_LINE_VALUES},
    'detroit-dpm': 'detroit-people-mover-route',
    'qline': 'detroit-qline-route',
    'cincinnati-connector': 'cagis-cincinnati-streetcar',
    'milwaukee-hop': 'milwaukee-dpw-streetcar',
    'cats-gold': 'cats-gold-line',
    **{key: 'rta-metra-rail-lines' for key in RTA_METRA_NAMES},
    'houston-metrorail-900': 'houston-metrorail-lines',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_source(source_id, path):
    """The government bytes, from disk when given and from the publisher else.

    A source that will not answer is reported with the transport's own error
    and left out of the manifest; guessing at a mirror would put geometry of
    unknown origin behind an official key.
    """
    if path:
        with open(path, 'rb') as handle:
            return handle.read()
    request = urllib.request.Request(
        SOURCES[source_id]['url'],
        headers={'User-Agent': 'JTM railway data builder/1.0'})
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return response.read()
    except (urllib.error.URLError, OSError) as exc:
        raise SystemExit(f'{source_id}: official source unavailable: {exc}')


def parse(raw, source_id):
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
    return features


def lines_of(feature):
    geometry = feature.get('geometry') or {}
    if geometry.get('type') == 'LineString':
        return [geometry.get('coordinates') or []]
    return geometry.get('coordinates') or []


def normalized_feature(feature, simplify_m=0.0):
    """One authority feature, thinned then evenly resampled along itself.

    Simplification only ever drops source vertices and densification only ever
    subdivides the segments that survive, so the result stays on the line the
    authority drew.  25 m is chosen because several of these routes have stops
    a block apart, and a coarser graph snaps two of them onto one node.
    """
    output = []
    for line in lines_of(feature):
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


def nctcog_groups(features):
    observed = set()
    for feature in features:
        properties = feature.get('properties') or {}
        status = str(properties.get('ServiceStatus') or '')
        if status != 'In Revenue Service':
            raise SystemExit(
                f'NCTCOG carries non-revenue trackage: {status!r}')
        observed.add(str(properties.get('Line') or ''))
    allowed = set().union(*NCTCOG_LINE_VALUES.values())
    unknown = observed - allowed
    if unknown:
        raise SystemExit(f'NCTCOG has unreviewed Line values: {sorted(unknown)}')
    groups = {}
    for key, wanted in NCTCOG_LINE_VALUES.items():
        selected = [row for row in features
                    if str((row.get('properties') or {}).get('Line') or '')
                    in wanted]
        agency = NCTCOG_AGENCY.get(key)
        if agency and any(str((row.get('properties') or {}).get('Agency')
                              or '') != agency for row in selected):
            raise SystemExit(f'{key}: NCTCOG Line value changed operator')
        groups[key] = [normalized_feature(row) for row in selected]
    return groups


def detroit_dpm_group(features):
    # The layer is the People Mover's track footprint and holds nothing else,
    # so the endpoint itself isolates the service.  All 29 features are kept:
    # the loop is three of them and the rest are short connecting stubs that
    # the graph needs to close it.
    return [normalized_feature(row) for row in features]


def detroit_qline_group(features):
    names = {str((row.get('properties') or {}).get('name') or '')
             for row in features}
    if names != {'Q-Line'}:
        raise SystemExit(f'Detroit QLine layer changed names: {sorted(names)}')
    return [normalized_feature(row) for row in features]


def cincinnati_group(features):
    # CAGIS leaves ``REFNAME`` null on the fourteen features that continue the
    # same track set; every value it does publish must still be the streetcar,
    # or the layer has gained a second railway and this key would merge two.
    named = {str((row.get('properties') or {}).get('REFNAME') or '')
             for row in features} - {''}
    if named != {'Cincinnati Streetcar Route'}:
        raise SystemExit(
            f'CAGIS layer 13 is no longer streetcar-only: {sorted(named)}')
    # 0.47 m between vertices is CAD track geometry; 2 m keeps every curve the
    # graph can express and drops an order of magnitude of surveyor detail.
    return [normalized_feature(row, simplify_m=2.0) for row in features]


def milwaukee_group(features):
    observed = {str((row.get('properties') or {}).get('ROUTENAME') or '')
                for row in features}
    unknown = observed - MILWAUKEE_ROUTE_NAMES
    if unknown:
        raise SystemExit(f'Milwaukee DPW has unknown routes: {sorted(unknown)}')
    return [normalized_feature(row) for row in features
            if (row.get('properties') or {}).get('ROUTENAME') == 'The M-Line']


def cats_gold_group(features):
    # The layer is explicitly a phased alignment and its renderer defines a
    # "Future Phase" class, so the in-service filter is what stops a later
    # republish shipping track nobody has built.
    return [normalized_feature(row, simplify_m=0.5) for row in features
            if (row.get('properties') or {}).get('Project_De') == 'In Service']


def rta_metra_groups(features):
    observed = {str((row.get('properties') or {}).get('NAME') or '')
                for row in features}
    if observed != RTA_METRA_ALL_NAMES:
        raise SystemExit(
            f'RTA Metra asset register changed: {sorted(observed)}')
    return {key: [normalized_feature(row) for row in features
                  if str((row.get('properties') or {}).get('NAME') or '')
                  == name]
            for key, name in RTA_METRA_NAMES.items()}


def houston_groups(features):
    observed = {(str((row.get('properties') or {}).get('NAME') or ''),
                 str((row.get('properties') or {}).get('LineColor') or ''))
                for row in features}
    if observed != HOUSTON_ALL_NAMES:
        raise SystemExit(f'METRO rail lines changed: {sorted(observed)}')
    return {key: [normalized_feature(row) for row in features
                  if (str((row.get('properties') or {}).get('NAME') or ''),
                      str((row.get('properties') or {}).get('LineColor')
                          or '')) == pair]
            for key, pair in HOUSTON_LINE_NAMES.items()}


def route_groups(parsed):
    groups = {}
    groups.update(nctcog_groups(parsed['nctcog-existing-rail-lines']))
    groups['detroit-dpm'] = detroit_dpm_group(
        parsed['detroit-people-mover-route'])
    groups['qline'] = detroit_qline_group(parsed['detroit-qline-route'])
    groups['cincinnati-connector'] = cincinnati_group(
        parsed['cagis-cincinnati-streetcar'])
    groups['milwaukee-hop'] = milwaukee_group(parsed['milwaukee-dpw-streetcar'])
    groups['cats-gold'] = cats_gold_group(parsed['cats-gold-line'])
    groups.update(rta_metra_groups(parsed['rta-metra-rail-lines']))
    groups.update(houston_groups(parsed['houston-metrorail-lines']))
    if set(groups) != set(KEY_SOURCE):
        raise SystemExit('normalizer produced an unowned route key')
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


def write_group(output_dir, key, features, source_id, raw_sha):
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
    return {'file': filename, 'features': len(features),
            'sha256': digest(encoded)}


def normalize(output_dir, inputs):
    raw = {source_id: read_source(source_id, inputs.get(source_id))
           for source_id in SOURCES}
    parsed = {source_id: parse(value, source_id)
              for source_id, value in raw.items()}
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
        manifest['files'][key] = write_group(
            output_dir, key, features, source_id, digest(raw[source_id]))
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    path = os.path.join(output_dir, 'manifest.json')
    with open(path + '.tmp', 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2)
        output.write('\n')
    os.replace(path + '.tmp', path)
    return manifest, groups


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    for source_id in SOURCES:
        parser.add_argument(f'--{source_id}-input', default=None)
    args = parser.parse_args()
    inputs = {source_id: getattr(args, source_id.replace('-', '_') + '_input')
              for source_id in SOURCES}
    manifest, groups = normalize(args.output_dir, inputs)
    print(f'wrote {len(groups)} route-isolated south/midwest networks; '
          f'manifest now contains {len(manifest["files"])} files')


if __name__ == '__main__':
    main()
