"""Reviewed, exact-vertex station-window overrides for retained NA packages.

The catalog carries both the rejected window and a contiguous published peer
survey window. Changed inputs fail closed; no geometry is inferred at runtime.
"""
import copy
import hashlib
import json

import na_geo as geo


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False,
                                    separators=(',', ':')).encode()).hexdigest()


def intervals(line):
    result = []
    for _, continuing, coordinates in line['segments']:
        result.append((result[-1][-1:] if continuing else []) + coordinates)
    return result


def apply_repairs(package, stations, sections, catalog):
    """Return repaired copies and a change ledger; reject stale/partial inputs."""
    package, stations, sections = copy.deepcopy((package, stations, sections))
    lines = {line['id']: line for line in package['lines']}
    changes = []
    for repair in catalog['repairs']:
        line = lines[repair['lineId']]
        station_index = [s[0] for s in line['stations']].index(repair['stationId'])
        decoded = intervals(line)
        updates = []
        for window in repair['windows']:
            incoming = window['side'] == 'incoming'
            index = station_index - 1 if incoming else station_index
            piece = decoded[index]
            if piece.count(window['seam']) != 1:
                raise ValueError(f"{repair['id']}: ambiguous or missing exact seam")
            seam_index = piece.index(window['seam'])
            old = piece[seam_index:] if incoming else piece[:seam_index + 1]
            new = window['coordinates']
            if old == new:
                continue
            if digest(old) != window['oldCoordinatesSha256']:
                raise ValueError(f"{repair['id']}: source window changed; review required")
            if ((new[0] if incoming else new[-1]) != window['seam'] or
                    (new[-1] if incoming else new[0]) != repair['anchor']):
                raise ValueError(f"{repair['id']}: replacement is not seam/anchor bounded")
            replacement = (piece[:seam_index] + new if incoming else
                           new + piece[seam_index + 1:])
            updates.append((index, piece, replacement))
        if not updates:
            if line['stations'][station_index][2:4] != repair['anchor']:
                raise ValueError(f"{repair['id']}: already repaired geometry has wrong anchor")
            continue
        if len(updates) != 2 or line['stations'][station_index][2:4] != repair['oldAnchor']:
            raise ValueError(f"{repair['id']}: partially applied repair")

        for index, old, new in updates:
            matching = [f for f in sections['features']
                        if f['properties']['operator'] == line['operator']
                        and f['properties']['line_name'] == line['name']
                        and f['geometry']['coordinates'] == old]
            if len(matching) != 1:
                raise ValueError(f"{repair['id']}: section {index} missing or ambiguous")
            matching[0]['geometry']['coordinates'] = new
            decoded[index] = new
            row = line['segments'][index]
            row[0] = round(geo.line_length(new) / 1000, 3)
            row[2] = new[1:] if row[1] else new

        line['stations'][station_index][2:4] = repair['anchor']
        line['lengthKm'] = round(sum(geo.line_length(p) for p in decoded) / 1000, 3)
        matching = [f for f in stations['features']
                    if f['properties']['operator'] == line['operator']
                    and f['properties']['line_name'] == line['name']
                    and f['properties']['n02_group_code'] == repair['stationId']]
        if len(matching) != 1:
            raise ValueError(f"{repair['id']}: station membership missing or ambiguous")
        feature = matching[0]
        feature['properties']['display_point'] = repair['anchor']
        feature['geometry']['coordinates'] = [repair['anchor'], decoded[station_index][1]]
        # Keep the route-wide primary source and explicitly identify the bounded
        # secondary source. Calling the whole line NTAD/GTFS would be false.
        record = {'id': repair['id'], 'stationId': repair['stationId'],
                  'intervals': [u[0] for u in updates],
                  'seams': [w['seam'] for w in repair['windows']],
                  'anchor': repair['anchor'], 'evidence': repair['evidence'],
                  'catalogSha256': digest(catalog)}
        line.setdefault('stationApproachRepairs', []).append(record)
        comparison = package.get('geometrySource', {}).get(
            'officialGeometryComparison', {}).get('byLine', {}).get(line['id'])
        if comparison is not None:
            comparison['scope'] = ('Pre-stationApproachRepair full-line comparison; '
                                   'replacement windows are evidenced separately in '
                                   'stationApproachRepairs, not remeasured by this override')
        changes.append({'lineId': line['id'], **record})
    # A catalog extension retains earlier windows verbatim. Refresh their
    # reference to the complete current catalog without reapplying geometry.
    catalog_hash = digest(catalog)
    known_ids = {repair['id'] for repair in catalog['repairs']}
    metadata_updated = False
    for line in package['lines']:
        for record in line.get('stationApproachRepairs', []):
            if record['id'] in known_ids and record['catalogSha256'] != catalog_hash:
                record['catalogSha256'] = catalog_hash
                metadata_updated = True
    if changes or metadata_updated:
        package['stationApproachRepair'] = {
            'catalogVersion': catalog['version'], 'reviewedAt': catalog['reviewedAt'],
            'catalogSha256': catalog_hash, 'method': catalog['method'],
            'changes': [{'lineId': line['id'], **record}
                        for line in package['lines']
                        for record in line.get('stationApproachRepairs', [])],
        }
    return package, stations, sections, changes
