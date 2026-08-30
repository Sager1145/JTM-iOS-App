#!/usr/bin/env python3
"""Fail closed when a North American rail package cannot support its claims.

This is the release gate for ``us-2025.json`` and ``ca-2025.json``.  Counts are
not evidence of completeness, so the gate checks the source registry, build
report, geometry comparison, station/segment contract, adaptive grooming
metadata and audited branding together.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys


LOCAL_KINDS = {
    'streetcar', 'tram', 'lightrail', 'metro', 'monorail', 'peoplemover',
    'funicular', 'cable',
}
MID_KINDS = {'commuter', 'regional'}
PROFILE_LIMITS = {
    'street': 25.0,
    'metro': 40.0,
    'commuter': 90.0,
    'regional': 200.0,
    'longhaul': 400.0,
}
GTFS_COLOUR_SOURCE = 'operator GTFS routes.txt route_color'
UNOFFICIAL_COLOUR_SOURCE = re.compile(
    r'\b(random|generated|default|fallback)\b', re.IGNORECASE)


def read(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def finite_pair(pair):
    return (isinstance(pair, list) and len(pair) == 2
            and all(isinstance(v, (int, float)) and math.isfinite(v) for v in pair)
            and -180 <= pair[0] <= 180 and -90 <= pair[1] <= 90)


def add(errors, condition, message):
    if not condition:
        errors.append(message)


def haversine(a, b):
    radius = 6_371_008.8
    lon1, lat1, lon2, lat2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    value = (math.sin(dlat / 2) ** 2
             + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 2 * radius * math.asin(min(1.0, math.sqrt(value)))


def decode_intervals(line):
    stations = line.get('stations') or []
    previous = None
    out = []
    for index, segment in enumerate(line.get('segments') or []):
        coords = [list(point) for point in (segment[2] or [])]
        if segment[1] and previous is not None:
            coords.insert(0, list(previous))
        if coords and stations:
            start = stations[index % len(stations)]
            end = stations[(index + 1) % len(stations)]
            coords[0] = [start[2], start[3]]
            coords[-1] = [end[2], end[3]]
            previous = coords[-1]
        out.append(coords)
    return out


def audit_derived(package, data_dir, errors):
    region = package.get('country', '').lower()
    prefix = region or '<unknown>'
    section_path = os.path.join(data_dir, f'rail-sections-{region}.json')
    station_path = os.path.join(data_dir, f'stations-{region}.json')
    reading_path = os.path.join(data_dir, f'station-readings-{region}.json')
    for path in (section_path, station_path, reading_path):
        add(errors, os.path.isfile(path), f'{prefix}: missing derived artifact {path}')
    if not all(os.path.isfile(path) for path in
               (section_path, station_path, reading_path)):
        return

    expected_sections = [piece for line in package.get('lines') or []
                         for piece in decode_intervals(line)]
    section_features = read(section_path).get('features') or []
    add(errors, len(section_features) == len(expected_sections),
        f'{prefix}: section count differs from decoded package')
    for index, (expected, feature) in enumerate(
            zip(expected_sections, section_features)):
        actual = ((feature.get('geometry') or {}).get('coordinates') or [])
        add(errors, actual == expected,
            f'{prefix}: section {index} geometry differs from decoded package')
        length = sum(haversine(actual[i], actual[i + 1])
                     for i in range(max(0, len(actual) - 1)))
        add(errors, len(actual) >= 2 and length > 1.0,
            f'{prefix}: section {index} is not solver-usable ({length:.3f}m)')

    station_features = read(station_path).get('features') or []
    expected_stations = sum(len(line.get('stations') or [])
                            for line in package.get('lines') or [])
    add(errors, len(station_features) == expected_stations,
        f'{prefix}: station feature count differs from package station rows')
    source_groups = {}
    all_codes = set()
    for feature in station_features:
        props = feature.get('properties') or {}
        source, group = props.get('n02_station_code'), props.get('n02_group_code')
        if source:
            source_groups.setdefault(source, set()).add(group)
            all_codes.add(source)
        if group:
            all_codes.add(group)
    for source, groups in source_groups.items():
        add(errors, len(groups) == 1,
            f'{prefix}: source station {source} maps to multiple physical groups')

    readings = read(reading_path)
    add(errors, readings.get('packageVersion') == package.get('version'),
        f'{prefix}: station readings version differs from package')
    reading_codes = set((readings.get('byCode') or {}).keys())
    missing = all_codes - reading_codes
    add(errors, not missing,
        f'{prefix}: station readings missing {len(missing)} station identities')


def approved_colour_sources(registry, errors):
    """Return the only colour provenance strings a package may claim.

    A valid ``route_color`` is self-authenticating inside the downloaded
    operator feed.  Every non-GTFS colour must instead be an exact registry
    override with a paired source; accepting arbitrary non-empty prose here
    would let a generated/default colour masquerade as official metadata.
    """
    approved = {GTFS_COLOUR_SOURCE}
    for entry in registry.get('feeds') or []:
        slug = entry.get('slug', '<unknown>')
        colours = entry.get('officialColorByRouteId') or {}
        sources = entry.get('officialColorSourceByRouteId') or {}
        add(errors, set(colours) == set(sources),
            f'feed {slug}: official colour/source route ids differ')
        for route_id, colour in colours.items():
            add(errors, isinstance(colour, str) and bool(re.fullmatch(
                r'#?[0-9a-fA-F]{6}', colour)),
                f'feed {slug} route {route_id}: invalid official colour')
            source = sources.get(route_id)
            add(errors, isinstance(source, str) and bool(source.strip()),
                f'feed {slug} route {route_id}: missing official colour source')
            add(errors, not isinstance(source, str)
                or not UNOFFICIAL_COLOUR_SOURCE.search(source),
                f'feed {slug} route {route_id}: colour source describes a non-official colour')
            if isinstance(source, str) and source.strip():
                approved.add(source)
        fallback = entry.get('color')
        fallback_source = entry.get('colorSource')
        add(errors, bool(fallback) == bool(fallback_source),
            f'feed {slug}: fallback colour and source must be paired')
        if fallback:
            add(errors, isinstance(fallback, str) and bool(re.fullmatch(
                r'#?[0-9a-fA-F]{6}', fallback)),
                f'feed {slug}: invalid fallback official colour')
            add(errors, isinstance(fallback_source, str)
                and not UNOFFICIAL_COLOUR_SOURCE.search(fallback_source),
                f'feed {slug}: fallback colour source is not official')
            if isinstance(fallback_source, str):
                approved.add(fallback_source)
    return approved


def audit_package(path, public_root, data_dir, errors, colour_sources=None):
    package = read(path)
    country = package.get('country', os.path.basename(path)).lower()
    lines = package.get('lines') or []
    add(errors, package.get('format') == 'compact-v1', f'{country}: wrong format')
    add(errors, bool(lines), f'{country}: package has no lines')
    ids = [line.get('id') for line in lines]
    add(errors, len(ids) == len(set(ids)), f'{country}: duplicate line ids')

    source = package.get('geometrySource') or {}
    add(errors, source.get('syntheticConnectors') == 0,
        f"{country}: {source.get('syntheticConnectors')} synthetic connectors")
    comparison = source.get('officialGeometryComparison') or {}
    checks = comparison.get('byLine') or {}
    add(errors, comparison.get('lines') == len(lines),
        f'{country}: comparison line count does not match package')
    add(errors, set(ids) == set(checks),
        f'{country}: not every line has an independent geometry comparison')

    for line in lines:
        prefix = f"{country}:{line.get('id', '<missing>')}"
        stations = line.get('stations') or []
        segments = line.get('segments') or []
        add(errors, len(stations) >= 2, f'{prefix}: fewer than two stations')
        expected = len(stations) if line.get('isLoop') else max(0, len(stations) - 1)
        add(errors, len(segments) == expected,
            f'{prefix}: {len(segments)} segments for {len(stations)} stations')
        add(errors, bool(line.get('kind')), f'{prefix}: missing service kind')
        add(errors, bool(line.get('geometrySource')), f'{prefix}: missing geometry source')
        add(errors, bool(line.get('smoothingProfile')), f'{prefix}: missing smoothing profile')
        reference_colour = line.get('colorReference')
        add(errors, isinstance(reference_colour, str) and bool(re.fullmatch(
            r'#[0-9a-fA-F]{6}', reference_colour)),
            f'{prefix}: invalid operator colour reference')
        add(errors, line.get('colorSource') in (colour_sources or ()),
            f'{prefix}: colour source is not GTFS or an exact audited override')
        add(errors, isinstance(line.get('lengthKm'), (int, float))
            and line.get('lengthKm', 0) > 0, f'{prefix}: invalid length')
        for i, station in enumerate(stations):
            add(errors, len(station) >= 4 and finite_pair(station[2:4]),
                f'{prefix}: invalid station coordinate at {i}')
        for i, segment in enumerate(segments):
            ok = (isinstance(segment, list) and len(segment) >= 3
                  and isinstance(segment[2], list) and len(segment[2]) >= 1
                  and all(finite_pair(p) for p in segment[2]))
            add(errors, ok, f'{prefix}: invalid segment geometry at {i}')

        logo = line.get('operatorLogo')
        brand_status = line.get('brandStatus')
        has_audited_logo = (isinstance(logo, str)
                            and logo.startswith('/rail/operator-logos/na/'))
        add(errors, has_audited_logo
            or brand_status in {'restricted', 'audited-unbranded'},
            f'{prefix}: operator branding is neither verified nor explicitly unavailable')
        if isinstance(logo, str) and logo.startswith('/'):
            add(errors, os.path.isfile(os.path.join(public_root, logo.lstrip('/'))),
                f'{prefix}: logo asset does not exist: {logo}')

        check = checks.get(line.get('id')) or {}
        add(errors, check.get('vertices', 0) > 0, f'{prefix}: no checked vertices')
        add(errors, check.get('independent') is True,
            f'{prefix}: geometry comparison is not marked independent')
        built_from = line.get('geometrySource')
        add(errors, built_from not in (check.get('agreedWith') or {}),
            f'{prefix}: geometry was verified against its own {built_from} source')
        add(errors, check.get('unmatched') == 0,
            f"{prefix}: {check.get('unmatched')} vertices have no NARN/OSM match")
        profile = line.get('smoothingProfile')
        limit = PROFILE_LIMITS.get(profile, 0.0)
        add(errors, profile in PROFILE_LIMITS,
            f'{prefix}: unknown smoothing profile {profile!r}')
        add(errors, check.get('maxDeviationMeters', math.inf) <= limit,
            f"{prefix}: deviation {check.get('maxDeviationMeters')}m exceeds {limit}m")

    audit_derived(package, data_dir, errors)
    return len(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--package', action='append', required=True)
    ap.add_argument('--registry', required=True)
    ap.add_argument('--gtfs-manifest', required=True)
    ap.add_argument('--build-report', required=True)
    ap.add_argument('--public-root', required=True)
    ap.add_argument('--data-dir', default=None)
    options = ap.parse_args()
    if options.data_dir is None:
        options.data_dir = os.path.abspath(os.path.join(options.public_root,
                                                        '..', 'data'))

    errors = []
    registry = read(options.registry)
    manifest = read(options.gtfs_manifest)
    report = read(options.build_report)
    brand_audit_path = os.path.join(os.path.dirname(options.registry),
                                    'na-operator-brands.json')
    brand_audit = read(brand_audit_path) if os.path.exists(brand_audit_path) else {}
    audited_unbranded = set((brand_audit.get('unbranded') or {}).keys())
    colour_sources = approved_colour_sources(registry, errors)
    for entry in registry.get('feeds') or []:
        record = manifest.get(str(entry.get('mdb'))) or {}
        add(errors, bool(record) and not record.get('error'),
            f"feed {entry.get('slug')}: unavailable: {record.get('error', 'not downloaded')}")
        add(errors, bool(entry.get('operatorLogo') or entry.get('logoRestricted')
                         or entry.get('slug') in audited_unbranded),
            f"feed {entry.get('slug')}: branding is neither verified nor explicitly unavailable")
    feed_reports = {
        row.get('slug') or row.get('feed'): row
        for row in report.get('feeds') or []
    }
    for entry in registry.get('feeds') or []:
        row = feed_reports.get(entry.get('slug')) or {}
        add(errors, row.get('lines', row.get('built', 0)) > 0,
            f"feed {entry.get('slug')}: built no passenger railway")
    geometry_blockers = (feed_reports.get('geometry-release-blockers') or {}) \
        .get('dropped') or []
    add(errors, not geometry_blockers,
        f'build refused {len(geometry_blockers)} lines with invalid geometry')
    # A feed producing *some* lines does not prove that every official route
    # in it survived. Metrolink built four services while Antelope Valley,
    # Ventura County and 91/Perris were individually refused for unusable
    # alignment. Surface each terminal route failure as a release blocker;
    # interval diagnostics without a route are supporting detail, not another
    # count of the same omission.
    refused_routes = set()
    for slug, row in feed_reports.items():
        if slug == 'geometry-release-blockers':
            continue
        for dropped in row.get('dropped') or []:
            route = dropped.get('route')
            why = dropped.get('why')
            if route and why in {
                    'no usable alignment', 'stop without position',
                    'preferred official trip unavailable'}:
                refused_routes.add((slug, str(route), why))
    for slug, route, why in sorted(refused_routes):
        errors.append(f'feed {slug} route {route}: {why}')

    total = sum(audit_package(path, options.public_root, options.data_dir, errors,
                              colour_sources)
                for path in options.package)
    if errors:
        for message in errors:
            print(f'ERROR {message}', file=sys.stderr)
        print(f'FAILED: {len(errors)} errors across {total} lines', file=sys.stderr)
        raise SystemExit(1)
    print(f'PASS: {total} lines; feeds, geometry, stations, smoothing and branding audited')


if __name__ == '__main__':
    main()
