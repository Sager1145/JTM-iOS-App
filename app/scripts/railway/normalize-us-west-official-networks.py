#!/usr/bin/env python3
"""Normalize operator-published Sound Transit and VTA rail geometry.

The output is deliberately route-specific.  A city-wide rail graph is unsafe:
at flat junctions it can silently send a service down another line.  Sound
Transit also publishes future construction in the same archive, so this
normalizer accepts only COMPLETE Link and OPERATIONAL Sounder records.

The Sound Transit shapefiles use NAD83 StatePlane Washington North (US feet).
The small inverse Lambert implementation below avoids making the reproducible
data build depend on a system GDAL or PROJ installation.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import sys
import warnings
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))
from lib import na_geo as geo
from lib import na_official


SOURCES = {
    'sound-transit': {
        'publisher': 'Sound Transit',
        'url': ('https://www.soundtransit.org/sites/default/files/2024-10/'
                'STPublicData.zip'),
    },
    'vta': {
        'publisher': 'Santa Clara Valley Transportation Authority',
        'url': ('https://gis.vta.org/gis/rest/services/LRT_BART/MapServer/6/'
                'query?where=1%3D1&outFields=*&returnGeometry=true&'
                'outSR=4326&f=geojson'),
    },
}

SOUND_KEYS = (
    'sound-link-1', 'sound-link-2', 'sound-link-t',
    'sounder-north', 'sounder-south',
)
VTA_KEYS = ('vta-blue', 'vta-green', 'vta-orange')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def _lambert_constants():
    # ESRI WKT in STPublicData.zip: GRS 1980 / Washington North FIPS 4601,
    # EPSG:2926 parameters, with US survey feet.
    semi_major = 6_378_137.0
    flattening = 1.0 / 298.257222101
    eccentricity = math.sqrt(2 * flattening - flattening * flattening)
    lat0 = math.radians(47.0)
    lon0 = math.radians(-120.8333333333333)
    standard1 = math.radians(47.5)
    standard2 = math.radians(48.73333333333333)

    def m(latitude):
        sine = math.sin(latitude)
        return math.cos(latitude) / math.sqrt(
            1.0 - eccentricity * eccentricity * sine * sine)

    def t(latitude):
        sine = math.sin(latitude)
        return (math.tan(math.pi / 4.0 - latitude / 2.0)
                / (((1.0 - eccentricity * sine)
                    / (1.0 + eccentricity * sine))
                   ** (eccentricity / 2.0)))

    cone = ((math.log(m(standard1)) - math.log(m(standard2)))
            / (math.log(t(standard1)) - math.log(t(standard2))))
    scale = m(standard1) / (cone * t(standard1) ** cone)
    rho0 = semi_major * scale * t(lat0) ** cone
    return semi_major, eccentricity, lon0, cone, scale, rho0


LAMBERT = _lambert_constants()
US_FOOT_METERS = 1200.0 / 3937.0
FALSE_EASTING_FEET = 1_640_416.666666667


def washington_stateplane_to_wgs84(x_feet, y_feet):
    """Return ``[longitude, latitude]`` for one EPSG:2926-like point."""
    semi_major, eccentricity, lon0, cone, scale, rho0 = LAMBERT
    x = (float(x_feet) - FALSE_EASTING_FEET) * US_FOOT_METERS
    y = float(y_feet) * US_FOOT_METERS
    rho = math.copysign(math.hypot(x, rho0 - y), cone)
    t_value = (rho / (semi_major * scale)) ** (1.0 / cone)
    theta = math.atan2(x, rho0 - y)
    latitude = math.pi / 2.0 - 2.0 * math.atan(t_value)
    for _ in range(12):
        sine = math.sin(latitude)
        latitude = math.pi / 2.0 - 2.0 * math.atan(
            t_value * (((1.0 - eccentricity * sine)
                        / (1.0 + eccentricity * sine))
                       ** (eccentricity / 2.0)))
    longitude = lon0 + theta / cone
    return [round(math.degrees(longitude), 8),
            round(math.degrees(latitude), 8)]


def _shape_lines(shape):
    starts = list(shape.parts) + [len(shape.points)]
    lines = []
    for start, end in zip(starts, starts[1:]):
        points = [washington_stateplane_to_wgs84(*point[:2])
                  for point in shape.points[start:end]]
        deduped = []
        for point in points:
            if not deduped or point != deduped[-1]:
                deduped.append(point)
        if len(deduped) >= 2:
            lines.append(deduped)
    return lines


def _line_feature(lines, properties):
    geometry = ({'type': 'LineString', 'coordinates': lines[0]}
                if len(lines) == 1 else
                {'type': 'MultiLineString', 'coordinates': lines})
    return {'type': 'Feature', 'properties': properties,
            'geometry': geometry}


def _densify_lines(lines, maximum_m=25.0):
    """Add points on, never away from, the authority's own centreline."""
    return [geo.densify(line, maximum_m) for line in lines]


def _feature_lines(feature):
    geometry = feature.get('geometry') or {}
    coordinates = geometry.get('coordinates') or []
    return ([coordinates] if geometry.get('type') == 'LineString'
            else coordinates if geometry.get('type') == 'MultiLineString'
            else [])


def _densify_feature(feature):
    return _line_feature(
        _densify_lines(_feature_lines(feature)),
        dict(feature.get('properties') or {}))


def _read_sound_layer(archive, layer):
    try:
        import shapefile
    except ImportError as exc:
        raise SystemExit('pyshp is required to normalize Sound Transit GIS') from exc
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        reader = shapefile.Reader(
            shp=archive.open(f'{layer}.shp'),
            shx=archive.open(f'{layer}.shx'),
            dbf=archive.open(f'{layer}.dbf'), encoding='cp1252')
        records = []
        for row in reader.iterShapeRecords():
            lines = _shape_lines(row.shape)
            if lines:
                records.append((row.record.as_dict(), lines))
        return records


def sound_groups(archive_path):
    groups = {key: [] for key in SOUND_KEYS}
    with zipfile.ZipFile(archive_path) as archive:
        required = {f'{stem}.{suffix}'
                    for stem in ('LINKLine', 'SNDRLine')
                    for suffix in ('shp', 'shx', 'dbf', 'prj')}
        missing = required - set(archive.namelist())
        if missing:
            raise SystemExit('Sound Transit archive is missing: '
                             + ', '.join(sorted(missing)))

        for props, lines in _read_sound_layer(archive, 'LINKLine'):
            status = str(props.get('STATUS') or '').upper()
            description = str(props.get('DESCRIPTIO') or '')
            line = str(props.get('LINE') or '').strip().upper()
            if status != 'COMPLETE':
                continue
            keys = []
            if line == '1' or description == 'Lynnwood Link':
                keys.append('sound-link-1')
            if description == 'East Link' and line == '2':
                keys.append('sound-link-2')
            if line == 'T' or description in ('Tacoma Link',
                                               'Hilltop Tacoma Link'):
                keys.append('sound-link-t')
            for key in keys:
                groups[key].append(_line_feature(_densify_lines(lines), {
                    'status': status, 'description': description,
                    'line': line,
                }))

        for props, lines in _read_sound_layer(archive, 'SNDRLine'):
            status = str(props.get('STATUS') or '').upper()
            segment = str(props.get('SEGMENT') or '')
            if status != 'OPERATIONAL':
                continue
            key = {'Sounder North': 'sounder-north',
                   'Sounder South': 'sounder-south'}.get(segment)
            if key:
                groups[key].append(_line_feature(_densify_lines(lines), {
                    'status': status, 'segment': segment,
                }))
    return groups


def vta_groups(raw):
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'VTA response is not valid GeoJSON: {exc}')
    if payload.get('type') != 'FeatureCollection':
        raise SystemExit('VTA source is not a GeoJSON FeatureCollection')
    groups = {key: [] for key in VTA_KEYS}
    mapping = {'Blue': 'vta-blue', 'Green': 'vta-green',
               'Orange': 'vta-orange'}
    seen = set()
    for feature in payload.get('features') or []:
        properties = feature.get('properties') or {}
        abbreviation = str(properties.get('LineAbbr') or '')
        seen.add(abbreviation)
        key = mapping.get(abbreviation)
        if key is None:
            # EBRC is VTA's BART extension, not VTA light-rail service.
            if abbreviation != 'EBRC':
                raise SystemExit(f'VTA dataset has unknown LineAbbr {abbreviation!r}')
            continue
        geometry = feature.get('geometry') or {}
        if geometry.get('type') not in ('LineString', 'MultiLineString'):
            raise SystemExit(f'{key}: VTA feature is not line geometry')
        groups[key].append(_densify_feature(feature))
    if not {'Blue', 'Green', 'Orange'}.issubset(seen):
        raise SystemExit('VTA dataset is missing a regular light-rail line')
    # VTA's Blue feature omits its downtown shared track: its two substantial
    # pieces stop about 1.1 km apart, while the Green feature supplies that
    # surveyed common corridor.  Cut only the required path from Green rather
    # than exposing the entire neighbouring service to Blue's route graph.
    blue_lines = sorted(_feature_lines(groups['vta-blue'][0]),
                        key=geo.line_length, reverse=True)[:2]
    if len(blue_lines) != 2:
        raise SystemExit('VTA Blue does not contain its two expected main pieces')
    endpoint_pairs = [
        (geo.haversine(first, second), first, second)
        for first in (blue_lines[0][0], blue_lines[0][-1])
        for second in (blue_lines[1][0], blue_lines[1][-1])
    ]
    gap_m, first, second = min(endpoint_pairs)
    if not 500.0 < gap_m < 2_000.0:
        raise SystemExit('VTA Blue shared-corridor gap changed unexpectedly')
    shared = na_official.PassengerNetwork(
        groups['vta-green'], endpoint_join_m=15.0)
    intervals, routing = shared.route_stations(
        [first, second], max_snap_m=30.0)
    if not intervals or len(intervals) != 1:
        raise SystemExit('VTA Green cannot supply Blue shared corridor: '
                         + json.dumps(routing, separators=(',', ':')))
    groups['vta-blue'].append(_line_feature([intervals[0]], {
        'LineAbbr': 'Blue', 'sharedTrackFrom': 'Green',
        'selection': 'official Blue gap endpoints routed on official Green',
    }))
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
        'type': 'FeatureCollection', 'sourceId': key,
        'source': {**source, 'rawSha256': raw_sha},
        'features': features,
    }
    encoded = json.dumps(payload, ensure_ascii=False,
                         separators=(',', ':')).encode('utf-8')
    path = os.path.join(output_dir, f'{key}.geojson')
    with open(path + '.tmp', 'wb') as output:
        output.write(encoded)
    os.replace(path + '.tmp', path)
    return {'file': os.path.basename(path), 'features': len(features),
            'sha256': digest(encoded)}


def normalize(output_dir, sound_input, vta_input):
    os.makedirs(output_dir, exist_ok=True)
    manifest = _load_manifest(output_dir)

    with open(sound_input, 'rb') as source:
        sound_raw = source.read()
    sound_sha = digest(sound_raw)
    manifest['sources']['sound-transit'] = {
        **SOURCES['sound-transit'], 'rawSha256': sound_sha,
    }
    for key, features in sorted(sound_groups(sound_input).items()):
        manifest['files'][key] = _write_group(
            output_dir, key, features, 'sound-transit', sound_sha)

    with open(vta_input, 'rb') as source:
        vta_raw = source.read()
    vta_sha = digest(vta_raw)
    manifest['sources']['vta'] = {
        **SOURCES['vta'], 'rawSha256': vta_sha,
    }
    for key, features in sorted(vta_groups(vta_raw).items()):
        manifest['files'][key] = _write_group(
            output_dir, key, features, 'vta', vta_sha)

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
    parser.add_argument('--sound-input', required=True)
    parser.add_argument('--vta-input', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, args.sound_input, args.vta_input)
    print(f'wrote {len(SOUND_KEYS) + len(VTA_KEYS)} western route networks; '
          f'manifest now contains {len(manifest["files"])} files')


if __name__ == '__main__':
    main()
