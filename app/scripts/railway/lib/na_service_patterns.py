"""Apply reviewed NA service-pattern corrections to a built compact-v1 package.

Raw GTFS/official-network inputs are not on this machine, so a display fix
that a rebuild would otherwise make is applied directly to the shipped
package, its solver sections and its station features instead — same
precedent as ``na_station_ids.py`` and ``na_station_approaches.py``: a
reviewed, evidence-carrying catalog, fail-closed matching, and deterministic
re-encoding of compact-v1 segments rather than any re-derived geometry.

Every operation works on FULL per-interval coordinate lists (endpoints
included), decoded from ``line['segments']`` the same way
``na_station_approaches.intervals()`` does, and re-encodes them with the
package's own convention: the first segment of a line has
``continuesFromPrevious == 0`` and carries every vertex; every later segment
has ``continuesFromPrevious == 1`` and omits the vertex shared with the
previous segment's last point (verified against the shipped file).
"""
import copy

import na_build as build
import na_geo as geo


# --------------------------------------------------------------- decoding

def _decode(line):
    """Full [lon, lat] coordinate lists per interval, endpoints included."""
    pieces = []
    for _, continuing, coordinates in line['segments']:
        pieces.append((pieces[-1][-1:] if continuing else []) + coordinates)
    return pieces


def _encode(pieces):
    segments = []
    for i, piece in enumerate(pieces):
        continuing = 0 if i == 0 else 1
        if i > 0 and piece[0] != pieces[i - 1][-1]:
            raise ValueError(f'interval {i}: piece does not start where the '
                              f'previous interval ended: {piece[0]!r} != {pieces[i - 1][-1]!r}')
        segments.append([round(geo.line_length(piece) / 1000, 3), continuing,
                         piece if continuing == 0 else piece[1:]])
    return segments


def _relength(line):
    # Per the catalog's rule: every touched line's lengthKm is the sum of
    # its own (already rounded) segment kilometres, not a re-measurement of
    # the underlying coordinates.
    line['lengthKm'] = round(sum(seg[0] for seg in line['segments']), 3)


def _reprofile(line):
    # ``smoothingProfile`` is the builder's classification of the line from
    # its median station spacing and total length (lib/na_build.profile_for_line,
    # checked by audit-na-package.py as ``line.profile``). Removing stations
    # widens the spacing, so a touched line is re-classified the same way the
    # builder would classify it; the previous value is returned for the ledger.
    previous = line.get('smoothingProfile')
    profile, _ = build.profile_for_line(_decode(line))
    line['smoothingProfile'] = profile.name
    return previous, profile.name


# ------------------------------------------------------------- validation

def _find_station_index(line, name, allow_ends=False):
    matches = [i for i, s in enumerate(line['stations']) if s[1] == name]
    if len(matches) != 1:
        raise ValueError(f"{line['id']}: station name matches {len(matches)} "
                          f"row(s), expected exactly 1: {name!r}")
    index = matches[0]
    if not allow_ends and index in (0, len(line['stations']) - 1):
        raise ValueError(f"{line['id']}: refusing to drop a terminus as an "
                          f"interior station: {name!r}")
    return index


def _find_station_feature(stations, operator, line_name, station_name):
    matches = [f for f in stations['features']
               if f['properties'].get('operator') == operator
               and f['properties'].get('line_name') == line_name
               and f['properties'].get('station_name') == station_name]
    if len(matches) != 1:
        raise ValueError(f'{operator}/{line_name}: station feature matches '
                          f'{len(matches)}, expected exactly 1: {station_name!r}')
    return matches[0]


def _line_codes(sections, operator, line_name):
    for feature in sections['features']:
        props = feature['properties']
        if props['operator'] == operator and props['line_name'] == line_name:
            return props['railway_class_code'], props['institution_type_code']
    raise ValueError(f'no section rows found for {operator}/{line_name}')


# ---------------------------------------------------------- section rows

def _remove_section_rows(sections, operator, line_name, pieces):
    """Remove one row per `piece`, matched by exact geometry; each piece
    must match exactly one row (not-yet-removed by an earlier piece in this
    same call), raising rather than guessing when a piece is ambiguous or
    missing. Returns the position (in the post-removal list) where the
    first removed row used to sit, for reinsertion."""
    features = sections['features']
    removed = [False] * len(features)
    remove_positions = []
    for piece in pieces:
        candidates = [i for i, f in enumerate(features)
                      if not removed[i]
                      and f['properties']['operator'] == operator
                      and f['properties']['line_name'] == line_name
                      and f['geometry']['coordinates'] == piece]
        if len(candidates) != 1:
            raise ValueError(f'{operator}/{line_name}: a piece matches '
                              f'{len(candidates)} section row(s), expected exactly 1')
        removed[candidates[0]] = True
        remove_positions.append(candidates[0])

    remove_set = set(remove_positions)
    first_index = None
    kept = []
    for i, feature in enumerate(features):
        if i in remove_set:
            if first_index is None:
                first_index = len(kept)
            continue
        kept.append(feature)
    sections['features'] = kept
    return first_index if first_index is not None else len(kept)


def _insert_section_row(sections, operator, line_name, class_code, inst_code,
                        coordinates, index):
    row = {
        'type': 'Feature',
        'properties': {
            'railway_class_code': class_code,
            'institution_type_code': inst_code,
            'line_name': line_name,
            'operator': operator,
        },
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
    }
    sections['features'].insert(index, row)
    return row


def _find_row_index(sections, operator, line_name, coordinates):
    matches = [i for i, feature in enumerate(sections['features'])
               if feature['properties']['operator'] == operator
               and feature['properties']['line_name'] == line_name
               and feature['geometry']['coordinates'] == coordinates]
    if len(matches) != 1:
        raise ValueError(f'{operator}/{line_name}: section row for reinsertion matches '
                          f'{len(matches)}, expected exactly 1')
    return matches[0]


# --------------------------------------------------------------- op impls

def _truncate_after(line, sections, station_name):
    index = _find_station_index(line, station_name, allow_ends=True)
    if index == 0:
        raise ValueError(f"{line['id']}: refusing to truncateAfter the first "
                          f'station, which would leave no segments: {station_name!r}')
    if index == len(line['stations']) - 1:
        raise ValueError(f"{line['id']}: truncateAfter station is already "
                          f'the terminus: {station_name!r}')
    decoded = _decode(line)
    operator, line_name = line['operator'], line['name']
    _remove_section_rows(sections, operator, line_name, decoded[index:])
    line['stations'] = line['stations'][:index + 1]
    line['segments'] = _encode(decoded[:index])
    _relength(line)


def _drop_stations(line, sections, names):
    n = len(line['stations'])
    removed = set()
    for name in names:
        index = _find_station_index(line, name)
        if index in removed:
            raise ValueError(f"{line['id']}: duplicate station in dropStations: {name!r}")
        removed.add(index)
    decoded = _decode(line)
    operator, line_name = line['operator'], line['name']
    class_code, inst_code = None, None
    kept = [i for i in range(n) if i not in removed]
    new_pieces = []
    for i in range(len(kept) - 1):
        a, b = kept[i], kept[i + 1]
        if b - a == 1:
            new_pieces.append(decoded[a])
            continue
        piece = list(decoded[a])
        for j in range(a + 1, b):
            piece += decoded[j][1:]
        new_pieces.append(piece)
        if class_code is None:
            class_code, inst_code = _line_codes(sections, operator, line_name)
        old_rows = [decoded[j] for j in range(a, b)]
        insert_at = _remove_section_rows(sections, operator, line_name, old_rows)
        _insert_section_row(sections, operator, line_name, class_code, inst_code,
                            piece, insert_at)
    line['stations'] = [line['stations'][i] for i in kept]
    line['segments'] = _encode(new_pieces)
    _relength(line)


def _rename_targets(package, catalog):
    """Per (operator, line_name, stationId), the newName(s) this batch's
    renameStation repairs request and the ids of the lines that request
    them — used to decide whether a name-ambiguous shared station feature
    (several lines sharing one operator+line_name, keyed by that pair alone
    in stations-us.json) may be renamed for all of them at once."""
    lines_by_id = {line['id']: line for line in package['lines']}
    targets = {}
    for repair in catalog.get('repairs', []):
        if repair.get('op') != 'renameStation':
            continue
        line = lines_by_id.get(repair.get('lineId'))
        if line is None:
            continue
        key = (line['operator'], line['name'], repair.get('stationId'))
        entry = targets.setdefault(key, {'newNames': set(), 'lineIds': set()})
        entry['newNames'].add(repair.get('newName'))
        entry['lineIds'].add(line['id'])
    return targets


def _rename_station(line, stations, station_id, new_name, lines_by_id, rename_targets):
    matches = [i for i, s in enumerate(line['stations']) if s[0] == station_id]
    if len(matches) != 1:
        raise ValueError(f"{line['id']}: stationId matches {len(matches)} row(s), "
                          f'expected exactly 1: {station_id!r}')
    index = matches[0]
    old_name = line['stations'][index][1]
    if any(i != index and s[1] == new_name for i, s in enumerate(line['stations'])):
        raise ValueError(f"{line['id']}: renameStation target name already exists "
                          f'on this line: {new_name!r}')
    line['stations'][index][1] = new_name
    line['stations'][index][4] = new_name
    operator, line_name = line['operator'], line['name']

    feature_matches = [f for f in stations['features']
                        if f['properties'].get('operator') == operator
                        and f['properties'].get('line_name') == line_name
                        and f['properties'].get('n02_group_code') == station_id]
    if len(feature_matches) == 1:
        feature_matches[0]['properties']['station_name'] = new_name
    else:
        # Several lines share this (operator, line_name) and each has its
        # own feature for this station id, indistinguishable by properties
        # alone. Renaming them together is safe only if every such sibling
        # line is itself being renamed to the same name within this batch,
        # or already carries it.
        siblings = [other for other in lines_by_id.values()
                    if other is not line and other['operator'] == operator
                    and other['name'] == line_name
                    and any(row[0] == station_id for row in other['stations'])]
        target = rename_targets.get((operator, line_name, station_id),
                                    {'newNames': set(), 'lineIds': set()})
        covered = target['newNames'] == {new_name} and all(
            sib['id'] in target['lineIds']
            or any(row[0] == station_id and row[1] == new_name for row in sib['stations'])
            for sib in siblings)
        if not covered:
            raise ValueError(f'{operator}/{line_name}: station feature matches '
                              f'{len(feature_matches)}, expected exactly 1: {station_id!r}')
        for feature in feature_matches:
            feature['properties']['station_name'] = new_name

    if old_name != new_name:
        return old_name
    return None


def _insert_station(line, stations, sections, repair):
    after_name, before_name = repair['after'], repair['before']
    row = repair['station']
    after_index = _find_station_index(line, after_name, allow_ends=True)
    before_index = _find_station_index(line, before_name, allow_ends=True)
    if before_index != after_index + 1:
        raise ValueError(f"{line['id']}: insertStation requires 'after' and 'before' to be "
                          f'consecutive stations of the line: {after_name!r}, {before_name!r}')
    station_id, station_name = row[0], row[1]
    if any(s[0] == station_id for s in line['stations']):
        raise ValueError(f"{line['id']}: insertStation station id already exists on the "
                          f'line: {station_id!r}')
    if any(s[1] == station_name for s in line['stations']):
        raise ValueError(f"{line['id']}: insertStation station name already exists on the "
                          f'line: {station_name!r}')

    decoded = _decode(line)
    interval = decoded[after_index]
    point = [row[2], row[3]]
    matches = [j for j in range(1, len(interval) - 1) if interval[j] == point]
    if len(matches) != 1:
        raise ValueError(f"{line['id']}: insertStation vertex matches {len(matches)} "
                          f'interior point(s) of the {after_name!r}->{before_name!r} '
                          f'interval, expected exactly 1')
    split = matches[0]
    piece_a = interval[:split + 1]
    piece_b = interval[split:]

    operator, line_name = line['operator'], line['name']
    class_code, inst_code = _line_codes(sections, operator, line_name)
    insert_at = _remove_section_rows(sections, operator, line_name, [interval])
    _insert_section_row(sections, operator, line_name, class_code, inst_code, piece_a, insert_at)
    _insert_section_row(sections, operator, line_name, class_code, inst_code, piece_b, insert_at + 1)

    line['stations'].insert(before_index, list(row))
    new_pieces = decoded[:after_index] + [piece_a, piece_b] + decoded[before_index:]
    line['segments'] = _encode(new_pieces)
    _relength(line)

    neighbour = piece_b[1] if len(piece_b) > 1 else piece_b[0]
    template = next((f for f in stations['features']
                     if f['properties'].get('operator') == operator
                     and f['properties'].get('line_name') == line_name), None)
    if template is None:
        raise ValueError(f'{operator}/{line_name}: no existing station feature to use as '
                          'a template for insertStation')
    anchor = [round(point[0], 6), round(point[1], 6)]
    stations['features'].append({
        'type': 'Feature',
        'properties': {
            'railway_class_code': template['properties']['railway_class_code'],
            'institution_type_code': template['properties']['institution_type_code'],
            'line_name': line_name,
            'operator': operator,
            'station_name': station_name,
            'n02_station_code': station_id,
            'n02_group_code': station_id,
            'display_point': anchor,
            'time_zone': template['properties'].get('time_zone'),
        },
        'geometry': {'type': 'LineString',
                     'coordinates': [anchor, [round(neighbour[0], 6), round(neighbour[1], 6)]]},
    })


def _merge_stations(line, sections, keep_name, drop_name):
    n = len(line['stations'])
    keep_index = _find_station_index(line, keep_name, allow_ends=True)
    drop_index = _find_station_index(line, drop_name, allow_ends=True)
    if abs(keep_index - drop_index) != 1:
        raise ValueError(f"{line['id']}: mergeStations requires two consecutive "
                          f'stations: {keep_name!r}, {drop_name!r}')
    keep_row, drop_row = line['stations'][keep_index], line['stations'][drop_index]
    distance = geo.haversine(keep_row[2:4], drop_row[2:4])
    if distance > 30:
        raise ValueError(f"{line['id']}: mergeStations pair is {distance:.1f} m apart, "
                          f'over the 30 m limit: {keep_name!r}, {drop_name!r}')

    if drop_index in (0, n - 1):
        if drop_row[2:4] != keep_row[2:4]:
            raise ValueError(f"{line['id']}: refusing to mergeStations at a line end "
                              f"whose coordinates differ from the kept station's: "
                              f'{drop_name!r}')
        operator, line_name = line['operator'], line['name']
        decoded = _decode(line)
        if drop_index == 0:
            _remove_section_rows(sections, operator, line_name, [decoded[0]])
            line['stations'] = line['stations'][1:]
            line['segments'] = _encode(decoded[1:])
        else:
            _remove_section_rows(sections, operator, line_name, [decoded[-1]])
            line['stations'] = line['stations'][:-1]
            line['segments'] = _encode(decoded[:-1])
        _relength(line)
        return

    _drop_stations(line, sections, [drop_name])


def _drop_line(package, lines_by_id, sections, line):
    operator, line_name = line['operator'], line['name']
    decoded = _decode(line)
    if decoded:
        _remove_section_rows(sections, operator, line_name, decoded)
    package['lines'] = [entry for entry in package['lines'] if entry['id'] != line['id']]
    del lines_by_id[line['id']]


def _close_loop(line, stations, seam_station, keep_identity_from):
    first_index, last_index = 0, len(line['stations']) - 1
    first_row, last_row = line['stations'][first_index], line['stations'][last_index]
    if first_row[1] != seam_station:
        raise ValueError(f"{line['id']}: seamStation is not the first station: {seam_station!r}")
    if last_row[1] != keep_identity_from:
        raise ValueError(f"{line['id']}: keepIdentityFrom is not the last station: "
                          f'{keep_identity_from!r}')
    if first_row[2:4] != last_row[2:4]:
        raise ValueError(f"{line['id']}: closeLoop requires identical first/last "
                          f'coordinates, got {first_row[2:4]} vs {last_row[2:4]}')
    operator, line_name = line['operator'], line['name']
    first_feature = _find_station_feature(stations, operator, line_name, first_row[1])
    last_feature = _find_station_feature(stations, operator, line_name, last_row[1])
    # Row 0 keeps its own (already-correct, outgoing-based) geometry; only
    # its identity fields change to the last row's. The duplicate feature
    # for the deleted last row is removed outright.
    first_feature['properties']['station_name'] = last_row[1]
    first_feature['properties']['n02_group_code'] = last_feature['properties']['n02_group_code']
    first_feature['properties']['n02_station_code'] = last_feature['properties']['n02_station_code']
    stations['features'].remove(last_feature)

    new_first_row = [last_row[0], last_row[1], first_row[2], first_row[3],
                     last_row[4], first_row[5], first_row[6]]
    line['stations'][first_index] = new_first_row
    line['stations'].pop(last_index)
    line['isLoop'] = 1
    _relength(line)


def _close_loop_dropping_lead_in(line, stations, sections, repair):
    n = repair['dropFirstStations']
    operator, line_name = line['operator'], line['name']
    decoded = _decode(line)
    dropped_names = [s[1] for s in line['stations'][:n]]
    dropped_pieces = decoded[:n]
    remaining_pieces = decoded[n:]
    closing = [[round(x, 6), round(y, 6)] for x, y in repair['closingGeometry']]
    last_coord = [round(c, 6) for c in line['stations'][-1][2:4]]
    new_first_coord = [round(c, 6) for c in line['stations'][n][2:4]]
    if closing[0] != last_coord:
        raise ValueError(f"{line['id']}: closingGeometry does not start at the last station")
    if closing[-1] != new_first_coord:
        raise ValueError(f"{line['id']}: closingGeometry does not end at the new first station")

    class_code, inst_code = _line_codes(sections, operator, line_name)
    _remove_section_rows(sections, operator, line_name, dropped_pieces)
    after_index = _find_row_index(sections, operator, line_name, remaining_pieces[-1]) + 1
    _insert_section_row(sections, operator, line_name, class_code, inst_code, closing,
                        after_index)

    line['stations'] = line['stations'][n:]
    new_pieces = remaining_pieces + [closing]
    line['segments'] = _encode(new_pieces)
    line['isLoop'] = 1
    _relength(line)

    for name in dropped_names:
        feature = _find_station_feature(stations, operator, line_name, name)
        stations['features'].remove(feature)
    # The former terminus now has an outgoing (closing) interval; the
    # builder prefers the outgoing interval's second point as the
    # station's own approach geometry.
    last_feature = _find_station_feature(stations, operator, line_name,
                                         line['stations'][-1][1])
    last_feature['geometry']['coordinates'][1] = closing[1]


# --------------------------------------------------------------------- API

def _validate_catalog(catalog):
    """Fail-closed structural checks on the catalog itself, before any repair
    is applied. Unknown keys on a repair are fine; missing/malformed required
    ones are not."""
    repairs = catalog.get('repairs') if isinstance(catalog, dict) else None
    if not isinstance(repairs, list):
        raise ValueError("catalog: 'repairs' must be a list")
    seen_ids = set()
    for i, repair in enumerate(repairs):
        if not isinstance(repair, dict):
            raise ValueError(f'repair[{i}]: must be an object')
        line_id = repair.get('lineId')
        label = line_id if isinstance(line_id, str) and line_id.strip() else f'repair[{i}] (lineId={line_id!r})'
        for key in ('lineId', 'op', 'rule'):
            value = repair.get(key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f'{label}: {key!r} must be a non-empty string')
        evidence = repair.get('evidence')
        if (not isinstance(evidence, list) or len(evidence) < 2
                or any(not isinstance(e, str) or not e.strip() for e in evidence)):
            raise ValueError(f'{label}: evidence must be a list of at least 2 non-empty strings')
        repair_id = repair.get('id')
        if repair_id is not None:
            if repair_id in seen_ids:
                raise ValueError(f'{label}: duplicate repair id: {repair_id!r}')
            seen_ids.add(repair_id)
        if repair.get('op') == 'closeLoopDroppingLeadIn':
            drop_first = repair.get('dropFirstStations')
            if not isinstance(drop_first, int) or isinstance(drop_first, bool) or drop_first <= 0:
                raise ValueError(f'{label}: dropFirstStations must be a positive int')
            closing = repair.get('closingGeometry')
            if (not isinstance(closing, list) or len(closing) < 2
                    or any(not isinstance(pt, list) or len(pt) != 2
                           or not all(isinstance(c, (int, float)) and not isinstance(c, bool)
                                      for c in pt)
                           for pt in closing)):
                raise ValueError(f'{label}: closingGeometry must be a list of at least '
                                  '2 [lon, lat] pairs')
        elif repair.get('op') == 'renameStation':
            for key in ('stationId', 'newName'):
                value = repair.get(key)
                if not isinstance(value, str) or not value.strip():
                    raise ValueError(f'{label}: {key!r} must be a non-empty string')
        elif repair.get('op') == 'mergeStations':
            for key in ('keep', 'drop'):
                value = repair.get(key)
                if not isinstance(value, str) or not value.strip():
                    raise ValueError(f'{label}: {key!r} must be a non-empty string')
        elif repair.get('op') == 'insertStation':
            for key in ('after', 'before'):
                value = repair.get(key)
                if not isinstance(value, str) or not value.strip():
                    raise ValueError(f'{label}: {key!r} must be a non-empty string')
            row = repair.get('station')
            valid_row = (
                isinstance(row, list) and len(row) == 7
                and isinstance(row[0], str) and row[0].strip()
                and isinstance(row[1], str) and row[1].strip()
                and all(isinstance(c, (int, float)) and not isinstance(c, bool) for c in row[2:4])
                and isinstance(row[4], str) and row[4].strip()
                and isinstance(row[5], int) and not isinstance(row[5], bool)
                and isinstance(row[6], int) and not isinstance(row[6], bool)
            )
            if not valid_row:
                raise ValueError(f"{label}: 'station' must be [id, name, lon, lat, label, "
                                  'classCode, groupIdx]')


def apply_repairs(package, stations, sections, catalog):
    """Validate and apply the whole catalog; return a summary of the result.

    Returns a dict with the (deep-copied, independent) updated `package`,
    `stations`, `sections`, and a `changes` ledger — one entry per catalog
    repair, carrying its evidence and before/after counts. Raises on any
    ambiguous or missing match rather than guessing.
    """
    _validate_catalog(catalog)
    package = copy.deepcopy(package)
    stations = copy.deepcopy(stations)
    sections = copy.deepcopy(sections)
    lines_by_id = {line['id']: line for line in package['lines']}
    rename_targets = _rename_targets(package, catalog)
    changes = []
    touched_keys = set()

    for repair in catalog['repairs']:
        line_id = repair['lineId']
        op = repair['op']
        line = lines_by_id.get(line_id)
        if line is None:
            raise ValueError(f'reviewed line is missing: {line_id}')
        operator, line_name = line['operator'], line['name']
        touched_keys.add((operator, line_name))
        before = {'stations': len(line['stations']), 'segments': len(line['segments']),
                  'lengthKm': line['lengthKm']}

        if op == 'truncateAfter':
            _truncate_after(line, sections, repair['station'])
        elif op == 'dropStations':
            _drop_stations(line, sections, repair['stations'])
        elif op == 'dropLine':
            _drop_line(package, lines_by_id, sections, line)
        elif op == 'closeLoop':
            _close_loop(line, stations, repair['seamStation'], repair['keepIdentityFrom'])
        elif op == 'closeLoopDroppingLeadIn':
            _close_loop_dropping_lead_in(line, stations, sections, repair)
        elif op == 'renameStation':
            _rename_station(line, stations, repair['stationId'], repair['newName'],
                            lines_by_id, rename_targets)
        elif op == 'mergeStations':
            _merge_stations(line, sections, repair['keep'], repair['drop'])
        elif op == 'insertStation':
            _insert_station(line, stations, sections, repair)
        else:
            raise ValueError(f'unknown op: {op}')

        after = None
        if op != 'dropLine':
            previous_profile, profile = _reprofile(line)
            after = {'stations': len(line['stations']), 'segments': len(line['segments']),
                     'lengthKm': line['lengthKm']}
            if previous_profile != profile:
                after['smoothingProfile'] = {'before': previous_profile, 'after': profile}
        changes.append({
            'id': repair.get('id'),
            'lineId': line_id, 'op': op, 'rule': repair['rule'],
            'evidence': repair['evidence'], 'before': before, 'after': after,
        })

    # Drop any station feature whose name is no longer listed by any
    # surviving line under the same (operator, line_name) key. Two line
    # records can share one line_name (e.g. a diversion pattern retained
    # alongside the regular line); a name still called by either survives.
    surviving = {}
    for line in package['lines']:
        key = (line['operator'], line['name'])
        surviving.setdefault(key, set()).update(row[1] for row in line['stations'])
    kept_features = []
    removed_feature_count = 0
    for feature in stations['features']:
        props = feature['properties']
        key = (props.get('operator'), props.get('line_name'))
        if key in touched_keys and props.get('station_name') not in surviving.get(key, set()):
            removed_feature_count += 1
            continue
        kept_features.append(feature)
    stations['features'] = kept_features

    return {
        'package': package, 'stations': stations, 'sections': sections,
        'changes': changes, 'removedStationFeatures': removed_feature_count,
    }
