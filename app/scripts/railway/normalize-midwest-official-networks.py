#!/usr/bin/env python3
"""Normalize audited Midwest government rail alignments by exact route."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import tempfile
import xml.etree.ElementTree as ET
import zipfile

try:
    import shapefile
except ImportError as exc:  # pragma: no cover - installation error is explicit
    raise SystemExit('pyshp is required to read the government shapefile') from exc


SOURCES = {
    'chicago-metra-kml': {
        'publisher': 'City of Chicago',
        'url': ('https://data.cityofchicago.org/download/'
                'e7du-96jw/application/xml'),
        'metadataUrl': ('https://data.cityofchicago.org/Transportation/'
                        'Metra-Lines-KML/e7du-96jw'),
    },
    'metc-transitways': {
        'publisher': 'Metropolitan Council',
        'url': ('https://resources.gisdata.mn.gov/pub/gdrs/data/pub/'
                'us_mn_state_metc/trans_transitways_generalized/'
                'shp_trans_transitways_generalized.zip'),
        'metadataUrl': ('https://gisdata.mn.gov/dataset/'
                        'us-mn-state-metc-trans-transitways-generalized'),
    },
}

METRA_EXACT_NAMES = {
    'metra-bnsf': {'BNSF', 'BNSF, Heritage, SWS'},
    'metra-hc': {'Heritage', 'Heritage, SWS', 'BNSF, Heritage, SWS'},
    'metra-md-n': {'Milw-N', 'Milw-N, Milw-W, NCS'},
    'metra-md-w': {'Milw-W', 'Milw-W, NCS', 'Milw-N, Milw-W, NCS'},
    'metra-me': {
        'Electric', 'Electric, S. Shore', 'Electric-Blue Island',
        'Electric-Main Line', 'Electric-South Corridor'},
    'metra-ncs': {'NCS', 'Milw-W, NCS', 'Milw-N, Milw-W, NCS'},
    'metra-ri': {'Rock Is.', 'Rock Is.-Branch', 'Rock Is.-Main'},
    'metra-sws': {'SWS', 'Heritage, SWS', 'BNSF, Heritage, SWS'},
    'metra-up-n': {'UP-N', 'UP-N, UP-NW', 'UP-N, UP-NW, UP-W'},
    'metra-up-nw': {'UP-NW', 'UP-N, UP-NW', 'UP-N, UP-NW, UP-W'},
    'metra-up-w': {'UP-W', 'UP-N, UP-NW, UP-W'},
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def distance_m(first, second):
    lon1, lat1 = map(math.radians, first)
    lon2, lat2 = map(math.radians, second)
    dlon, dlat = lon2 - lon1, lat2 - lat1
    value = (math.sin(dlat / 2) ** 2
             + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 12_742_000 * math.asin(math.sqrt(value))


def densify(line, max_segment_m=100.0):
    if len(line) < 2:
        return line
    output = [line[0]]
    for first, second in zip(line, line[1:]):
        steps = max(1, math.ceil(distance_m(first, second) / max_segment_m))
        for index in range(1, steps + 1):
            fraction = index / steps
            output.append([
                first[0] + (second[0] - first[0]) * fraction,
                first[1] + (second[1] - first[1]) * fraction,
            ])
    return output


def parse_metra_kml(raw):
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as exc:
        raise SystemExit(f'Metra KML is invalid: {exc}')
    namespace = {'k': 'http://earth.google.com/kml/2.2'}
    groups = {key: [] for key in METRA_EXACT_NAMES}
    observed = set()
    for placemark in root.findall('.//k:Placemark', namespace):
        official_name = (placemark.findtext('k:name', '', namespace)).strip()
        observed.add(official_name)
        coordinates = placemark.findtext('.//k:coordinates', '', namespace)
        line = []
        for token in coordinates.split():
            values = token.split(',')
            if len(values) >= 2:
                line.append([float(values[0]), float(values[1])])
        if len(line) < 2:
            raise SystemExit(f'Metra {official_name!r}: missing line geometry')
        for key, accepted in METRA_EXACT_NAMES.items():
            if official_name in accepted:
                groups[key].append({
                    'type': 'Feature',
                    'properties': {'officialName': official_name},
                    'geometry': {'type': 'LineString',
                                 'coordinates': densify(line)},
                })
    allowed = set().union(*METRA_EXACT_NAMES.values()) | {'S. Shore'}
    unknown = observed - allowed
    if unknown:
        raise SystemExit(f'Metra KML has unknown official names: {sorted(unknown)}')
    missing = [key for key, rows in groups.items() if not rows]
    if missing:
        raise SystemExit(f'Metra KML has empty routes: {missing}')
    return groups


def inverse_utm15(easting, northing):
    """EPSG:26915 NAD83 / UTM zone 15N to lon/lat.

    NAD83 uses GRS80; the standard inverse Transverse Mercator series below
    is deterministic and avoids silently treating projected metres as WGS84.
    NAD83 and WGS84 differ by far less than the source's planning-scale detail.
    """
    a = 6_378_137.0
    flattening = 1 / 298.257222101
    e2 = flattening * (2 - flattening)
    ep2 = e2 / (1 - e2)
    k0 = 0.9996
    x = float(easting) - 500_000.0
    y = float(northing)
    meridional = y / k0
    mu = meridional / (a * (1 - e2 / 4 - 3 * e2 ** 2 / 64
                            - 5 * e2 ** 3 / 256))
    e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2))
    foot = (mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * math.sin(2 * mu)
            + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * math.sin(4 * mu)
            + 151 * e1 ** 3 / 96 * math.sin(6 * mu)
            + 1097 * e1 ** 4 / 512 * math.sin(8 * mu))
    sin_foot, cos_foot = math.sin(foot), math.cos(foot)
    tan_foot = math.tan(foot)
    c1 = ep2 * cos_foot ** 2
    t1 = tan_foot ** 2
    n1 = a / math.sqrt(1 - e2 * sin_foot ** 2)
    r1 = a * (1 - e2) / (1 - e2 * sin_foot ** 2) ** 1.5
    d = x / (n1 * k0)
    lat = foot - (n1 * tan_foot / r1) * (
        d ** 2 / 2
        - (5 + 3 * t1 + 10 * c1 - 4 * c1 ** 2 - 9 * ep2) * d ** 4 / 24
        + (61 + 90 * t1 + 298 * c1 + 45 * t1 ** 2
           - 252 * ep2 - 3 * c1 ** 2) * d ** 6 / 720)
    lon = math.radians(-93.0) + (
        d - (1 + 2 * t1 + c1) * d ** 3 / 6
        + (5 - 2 * c1 + 28 * t1 - 3 * c1 ** 2
           + 8 * ep2 + 24 * t1 ** 2) * d ** 5 / 120) / cos_foot
    return [math.degrees(lon), math.degrees(lat)]


def parse_metc_zip(path):
    groups = {'metro-transit-blue': [], 'metro-transit-green': []}
    with tempfile.TemporaryDirectory() as directory:
        with zipfile.ZipFile(path) as archive:
            members = archive.namelist()
            wanted = [name for name in members
                      if os.path.basename(name).startswith(
                          'TransitwayAlignmentsGeneralized.')]
            if not wanted:
                raise SystemExit('Met Council archive lacks alignment shapefile')
            archive.extractall(directory, wanted)
        shp = next(os.path.join(directory, name) for name in wanted
                   if name.casefold().endswith('.shp'))
        reader = shapefile.Reader(shp)
        for shape_record in reader.iterShapeRecords():
            properties = shape_record.record.as_dict()
            name = str(properties.get('NameTransi') or '')
            status = str(properties.get('Transitway') or '')
            mode = str(properties.get('Mode') or '')
            if name not in ('Blue Line', 'Green Line'):
                continue
            if status != 'Existing' or mode != 'Light Rail':
                raise SystemExit(
                    f'Met Council {name}: not existing light rail ({status}/{mode})')
            points = [inverse_utm15(x, y) for x, y in shape_record.shape.points]
            offsets = list(shape_record.shape.parts) + [len(points)]
            # Downtown LRT stops can be closer than the source's original
            # planning vertices.  Equal-distance subdivision along the exact
            # authority segment prevents adjacent stations snapping to one
            # graph node without inventing any curvature.
            lines = [densify(points[a:b], max_segment_m=25.0)
                     for a, b in zip(offsets, offsets[1:])
                     if b - a >= 2]
            key = 'metro-transit-' + name.split()[0].casefold()
            geometry = ({'type': 'LineString', 'coordinates': lines[0]}
                        if len(lines) == 1 else
                        {'type': 'MultiLineString', 'coordinates': lines})
            groups[key].append({
                'type': 'Feature',
                'properties': {
                    'officialName': name, 'status': status, 'mode': mode},
                'geometry': geometry,
            })
    if any(not rows for rows in groups.values()):
        raise SystemExit('Met Council archive lacks Blue or Green Line')
    return groups


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
    payload = {
        'type': 'FeatureCollection', 'sourceId': key,
        'source': {**SOURCES[source_id], 'rawSha256': raw_sha},
        'features': features,
    }
    encoded = json.dumps(payload, ensure_ascii=False,
                         separators=(',', ':')).encode()
    path = os.path.join(output_dir, key + '.geojson')
    with open(path + '.tmp', 'wb') as output:
        output.write(encoded)
    os.replace(path + '.tmp', path)
    return {'file': os.path.basename(path), 'features': len(features),
            'sha256': digest(encoded)}


def normalize(output_dir, metra_kml, metc_zip):
    with open(metra_kml, 'rb') as source:
        metra_raw = source.read()
    with open(metc_zip, 'rb') as source:
        metc_raw = source.read()
    groups = parse_metra_kml(metra_raw)
    groups.update(parse_metc_zip(metc_zip))
    manifest = load_manifest(output_dir)
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    raw_by_source = {
        'chicago-metra-kml': metra_raw,
        'metc-transitways': metc_raw,
    }
    for source_id, raw in raw_by_source.items():
        manifest['sources'][source_id] = {
            **SOURCES[source_id], 'rawSha256': digest(raw)}
    os.makedirs(output_dir, exist_ok=True)
    for key, features in sorted(groups.items()):
        source_id = ('chicago-metra-kml' if key.startswith('metra-')
                     else 'metc-transitways')
        manifest['files'][key] = write_group(
            output_dir, key, features, source_id,
            digest(raw_by_source[source_id]))
    path = os.path.join(output_dir, 'manifest.json')
    with open(path + '.tmp', 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2)
        output.write('\n')
    os.replace(path + '.tmp', path)
    return len(groups)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--metra-kml', required=True)
    parser.add_argument('--metc-transitways-zip', required=True)
    args = parser.parse_args()
    print(f'wrote {normalize(args.output_dir, args.metra_kml, args.metc_transitways_zip)} '
          'Midwest official networks')


if __name__ == '__main__':
    main()
