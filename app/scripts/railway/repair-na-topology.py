#!/usr/bin/env python3
"""Apply the exact reviewed NA endpoint/covered-branch catalog to an app tree.

Run on a private copy of app, inspect its changes, then promote the four US
files. This command writes no aggregate report, manifest, database or other
region. The catalog freezes the reviewed inputs; a different release needs a
new review. No track is derived, moved or replaced by this correction.
"""
import argparse
import copy
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / 'lib'))
import na_geo as geo
from na_build import profile_for_line
from na_release import release_locks
from na_service_patterns import _decode


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(',', ':')).encode()).hexdigest()


def _expect(value, expected, label):
    if digest(value) != expected:
        raise ValueError(f'{label}: reviewed input fingerprint changed')


def _samples(pieces):
    for piece in pieces:
        cumul = geo.cumulative(piece)
        for i in range(int(cumul[-1] // 25) + 1):
            yield geo.interpolate(piece, cumul, i * 25)
        yield piece[-1]


def _coverage(a, b):
    return max(min(geo.project_to_line(point, piece)[0] for piece in b)
               for point in _samples(a))


def _directional_edge(package, stations, sections, line, repair, reviewed_at):
    """Retain the survey and give its own endpoints their own line anchors."""
    extra = line['extraSegments'][repair['extraIndex']]
    geometry = extra['geometry']
    if any(entry['id'] == repair['newLineId'] for entry in package['lines']):
        raise ValueError(f"{repair['newLineId']}: line already exists without repair ledger")
    if repair['geometrySource'] == line['geometrySource']:
        raise ValueError('directional edge requires a distinct reviewed survey')
    rows = []
    positions = []
    for key, point in zip(('fromStationId', 'toStationId'), (geometry[0], geometry[-1])):
        matches = [row for row in line['stations'] if row[0] == repair[key]]
        if len(matches) != 1:
            raise ValueError(f"{line['id']}: directional endpoint station ambiguous")
        positions.append(line['stations'].index(matches[0]))
        row = list(matches[0])
        row[2:4] = point
        rows.append(row)
    if round(geo.line_length(geometry) / 1000, 3) != extra['km']:
        raise ValueError(f"{line['id']}: reviewed directional edge mileage inconsistent")
    first, last = sorted(positions)
    displacement = _coverage([geometry], _decode(line)[first:last])
    if displacement <= 30:
        raise ValueError(f"{line['id']}: directional edge has no reviewed physical divergence")
    branch = {k: copy.deepcopy(v) for k, v in line.items()
              if k not in ('segments', 'stations', 'extraSegments', 'isLoop', 'branchOf')}
    branch.update({'id': repair['newLineId'], 'branchOf': line['id'],
                   'geometrySource': repair['geometrySource'], 'stations': rows,
                   'segments': [[extra['km'], 0, copy.deepcopy(geometry)]],
                   'lengthKm': extra['km'],
                   'directionSpecificGeometry': {
                       'canonicalLineId': line['id'],
                       'canonicalGeometrySource': line['geometrySource'],
                       'geometrySource': repair['geometrySource'],
                       'maxDeviationMeters': repair['maxDeviationMeters'],
                       'measuredDeviationMeters': round(displacement, 3),
                       'reviewedAt': reviewed_at,
                       'source': copy.deepcopy(repair['source']),
                       'evidence': copy.deepcopy(repair['evidence']),
                       'originalExtraEvidence': extra['evidence']}})
    # Classification follows the new branch's own station spacing. Its survey
    # stays byte-for-byte unchanged; this does not run any grooming pass.
    branch['smoothingProfile'] = profile_for_line([geometry])[0].name
    for i, row in enumerate(rows):
        matches = [f for f in stations['features']
                   if f['properties'].get('operator') == line['operator']
                   and f['properties'].get('line_name') == line['name']
                   and f['properties'].get('n02_group_code') == row[0]]
        if len(matches) != 1:
            raise ValueError(f"{line['id']}: canonical station feature ambiguous: {row[0]}")
        feature = copy.deepcopy(matches[0])
        feature['properties']['display_point'] = row[2:4]
        feature['properties']['n02_station_code'] += '-DIRECTION1'
        neighbour = geometry[1] if i == 0 else geometry[-2]
        feature['geometry']['coordinates'] = [row[2:4], neighbour]
        stations['features'].append(feature)
    template = next((f for f in sections['features']
                     if f['properties'].get('operator') == line['operator']
                     and f['properties'].get('line_name') == line['name']), None)
    if template is None:
        raise ValueError(f"{line['id']}: canonical section template missing")
    section = copy.deepcopy(template)
    section['geometry']['coordinates'] = copy.deepcopy(geometry)
    sections['features'].append(section)
    package['lines'].insert(package['lines'].index(line) + 1, branch)
    # The old extra carried its own attribution only in prose. Once it becomes
    # a named geometrySource, expose the same source in the package inventory.
    source = repair['source']
    package.setdefault('geometrySource', {}).setdefault('verifiedOfficialNetworks', {})[
        repair['geometrySource']] = {
            'sourceId': 'sfmta', 'publisher': source['publisher'], 'url': source['url'],
            'rawSha256': source['rawSha256'], 'sha256': source['normalizedSha256']}
    line['extraSegments'].pop(repair['extraIndex'])
    if not line['extraSegments']:
        del line['extraSegments']
    return {'newLineId': branch['id'], 'removedExtraIndex': repair['extraIndex'],
            'fromStationId': rows[0][0], 'toStationId': rows[1][0],
            'retainedKilometers': extra['km'], 'addedStationFeatures': 2,
            'addedIntervals': 1}


def _remove_branch(package, stations, sections, branch, trunk, repair):
    if branch.get('branchOf') != trunk['id']:
        raise ValueError(f"{branch['id']}: branch parent differs from reviewed trunk")
    if (branch['geometrySource'] != trunk['geometrySource']
            or branch['operator'] != trunk['operator'] or branch['name'] != trunk['name']
            or branch.get('extraSegments') or branch.get('isLoop')):
        raise ValueError(f"{branch['id']}: physical identity or topology changed")
    index = {row[0]: i for i, row in enumerate(trunk['stations'])}
    aliases = repair.get('stationAliases', {})
    positions = [index.get(aliases.get(row[0], row[0])) for row in branch['stations']]
    if (None in positions or any(a >= b for a, b in zip(positions, positions[1:]))):
        raise ValueError(f"{branch['id']}: station mapping no longer follows trunk")
    pieces = _decode(branch)
    window = _decode(trunk)[positions[0]:positions[-1]]
    distances = (_coverage(pieces, window), _coverage(window, pieces))
    if max(distances) > repair['maxCoverageDistanceMeters']:
        raise ValueError(f"{branch['id']}: branch contains a distinct physical edge "
                         f'({max(distances):.2f} m)')

    # Section rows have no line id. Match the exact decoded branch geometry,
    # removing one row per interval; an identical shared row is interchangeable.
    for piece in pieces:
        matches = [f for f in sections['features']
                   if f['properties'].get('operator') == branch['operator']
                   and f['properties'].get('line_name') == branch['name']
                   and f['geometry'].get('coordinates') == piece]
        if not matches:
            raise ValueError(f"{branch['id']}: reviewed section row missing")
        sections['features'].remove(matches[0])

    # Each builder station feature carries the interval's neighbouring vertex.
    # Name-only filtering would leave both PM endpoint features or remove both
    # UTA 900 East features. Remove precisely one branch-owned occurrence.
    for i, row in enumerate(branch['stations']):
        neighbour = pieces[i][1] if i < len(pieces) else pieces[i - 1][-2]
        matches = [f for f in stations['features']
                   if f['properties'].get('operator') == branch['operator']
                   and f['properties'].get('line_name') == branch['name']
                   and f['properties'].get('n02_group_code') == row[0]
                   and f['properties'].get('station_name') == row[1]
                   and f['properties'].get('display_point') == row[2:4]
                   and f['geometry'].get('coordinates') == [row[2:4], neighbour]]
        if not matches:
            raise ValueError(f"{branch['id']}: reviewed station feature missing: {row[0]}")
        stations['features'].remove(matches[0])
    package['lines'].remove(branch)
    package.get('buildInputsByLine', {}).pop(branch['id'], None)
    return {'removedIntervals': len(pieces), 'removedStationFeatures': len(branch['stations']),
            'stationAliases': aliases,
            'coverageMeters': {'branchToTrunk': round(distances[0], 3),
                               'trunkToBranch': round(distances[1], 3)}}


def apply_repairs(package, stations, sections, readings, catalog):
    """Return isolated copies; failure never mutates the caller's input."""
    package, stations, sections, readings = map(copy.deepcopy,
                                                (package, stations, sections, readings))
    if catalog.get('country') != 'us':
        raise ValueError('this reviewed catalog applies only to US data')
    applied = set()
    ledger = package.get('topologyRepair')
    while ledger:
        applied.update(change['id'] for change in ledger.get('changes', []))
        ledger = ledger.get('previousRepair')
    changes = []
    for repair in catalog['repairs']:
        if repair['id'] in applied:
            continue
        if not repair.get('source') or not repair.get('evidence'):
            raise ValueError(f"{repair['id']}: source and evidence required")
        by_id = {line['id']: line for line in package['lines']}
        line = by_id.get(repair['lineId'])
        if line is None:
            raise ValueError(f"{repair['lineId']}: reviewed line missing without repair ledger")
        _expect(line, repair['expectedLineSha256'], line['id'])
        details = {}
        if repair['op'] == 'materializeDirectionalEdge':
            details = _directional_edge(package, stations, sections, line, repair,
                                        catalog['reviewedAt'])
        elif repair['op'] == 'removeCoveredBranch':
            trunk = by_id.get(repair['trunkId'])
            if trunk is None:
                raise ValueError(f"{line['id']}: trunk missing")
            _expect(trunk, repair['expectedTrunkSha256'], trunk['id'])
            details = _remove_branch(package, stations, sections, line, trunk, repair)
        else:
            raise ValueError(f"unsupported reviewed operation: {repair['op']}")
        changes.append({k: repair[k] for k in ('id', 'lineId', 'op', 'source', 'evidence')}
                       | details)

    # Keep existing translations/metadata; only keys without a station feature
    # are pruned. Shared PM endpoint identities and Stadium's canonical identity
    # remain. No global station identity migration is performed.
    if changes:
        valid_codes = {f['properties'][key] for f in stations['features']
                       for key in ('n02_station_code', 'n02_group_code')}
        valid_names = {f['properties']['station_name'] for f in stations['features']}
        readings['byCode'] = {k: v for k, v in readings['byCode'].items() if k in valid_codes}
        readings['byName'] = {k: v for k, v in readings['byName'].items() if k in valid_names}
        for feature in stations['features']:
            props = feature['properties']
            for key in ('n02_station_code', 'n02_group_code'):
                code = props[key]
                if code not in readings['byCode']:
                    readings['byCode'][code] = copy.deepcopy(
                        readings['byName'][props['station_name']])
        readings['stats'] = {'byCode': len(readings['byCode']), 'byName': len(readings['byName'])}
    return {'package': package, 'stations': stations, 'sections': sections,
            'readings': readings, 'changes': changes}


def _write(path, value):
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n')
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', required=True, type=Path)
    parser.add_argument('--catalog', type=Path, default=HERE / 'na-topology-repairs.json')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    paths = {'package': args.app_root / 'public/rail/us-2025.json',
             'stations': args.app_root / 'data/stations-us.json',
             'sections': args.app_root / 'data/rail-sections-us.json',
             'readings': args.app_root / 'data/station-readings-us.json'}
    with release_locks([args.app_root / 'public/rail', args.app_root / 'data']):
        inputs = {key: json.loads(path.read_text()) for key, path in paths.items()}
        result = apply_repairs(**inputs, catalog=json.loads(args.catalog.read_text()))
        changes = result['changes']
        print(json.dumps({'repairs': len(changes), 'dryRun': args.dry_run,
                          'changes': [{k: v for k, v in c.items()
                                       if k not in ('source', 'evidence')} for c in changes]}))
        if args.dry_run or not changes:
            return
        timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
        ledger = {'generatedAt': timestamp, 'catalogSha256': hashlib.sha256(
            args.catalog.read_bytes()).hexdigest(), 'changes': changes,
            'inputSha256': {key: hashlib.sha256(path.read_bytes()).hexdigest()
                            for key, path in paths.items()}}
        if inputs['package'].get('topologyRepair'):
            ledger['previousRepair'] = inputs['package']['topologyRepair']
        result['package']['topologyRepair'] = ledger
        result['package']['generatedAt'] = timestamp
        for key, path in paths.items():
            _write(path, result[key])


if __name__ == '__main__':
    main()
