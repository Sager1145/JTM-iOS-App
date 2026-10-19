"""Compile reviewed rich source timelines into the unchanged runtime v1.

Selectors deliberately require complete current features inside a bbox. They
cannot invent a station-to-station slice of a national shapefile. If a selector
does not isolate the intended interval, refine the source geometry first.
"""
import copy
import datetime
import hashlib
import json
import math
import re

IDENTITY_KINDS = {'line_rename', 'operator_rename', 'operator_transfer', 'identity_split',
                  'identity_merge', 'station_rename', 'station_relocation'}
SOURCE_KINDS = IDENTITY_KINDS | {'opening', 'closure', 'relocation', 'station_opening',
                                'station_closure', 'suspension', 'resumption'}


def day(value):
    if value is None:
        return None
    if not isinstance(value, str) or len(value) != 10:
        raise ValueError('date must be YYYY-MM-DD')
    if datetime.date.fromisoformat(value).isoformat() != value:
        raise ValueError('date must be YYYY-MM-DD')
    return value


def periods(value, label):
    if not isinstance(value, list) or not value:
        raise ValueError(f'{label}: non-empty periods required')
    result = []
    for pair in value:
        if not isinstance(pair, list) or len(pair) != 2:
            raise ValueError(f'{label}: interval must be [from, to]')
        a, b = map(day, pair)
        if a is None and b is None or a and b and a >= b:
            raise ValueError(f'{label}: empty or unbounded interval')
        if result and (result[-1][1] is None or a is None or a < result[-1][1]):
            raise ValueError(f'{label}: periods must be ordered and disjoint')
        result.append([a, b])
    return result


def reviewed_historical_periods(event):
    """Validate surveyed predecessors and return their exact service intervals."""
    geometry = event.get('geometry', {})
    entries = geometry.get('historical_periods')
    if entries is None:
        return None
    label = event.get('id', '?') + '.geometry.historical_periods'
    if event.get('kind') not in IDENTITY_KINDS:
        raise ValueError(label + ': only identity events support surveyed predecessor periods')
    if any(key in geometry for key in ('historical_sections', 'historical_stations')):
        raise ValueError(label + ': cannot be combined with flat historical geometry')
    if not isinstance(entries, list) or not entries:
        raise ValueError(label + ': non-empty periods required')
    result = []
    for index, entry in enumerate(entries):
        item = f'{label}[{index}]'
        if not isinstance(entry, dict):
            raise ValueError(item + ': object required')
        pair = periods([entry.get('service_period')], item)[0]
        if entry.get('source') != 'N02' or not re.fullmatch(r'N02-\d{2}', entry.get('release', '')):
            raise ValueError(item + ': source N02 and release N02-YY required')
        if entry.get('licence_status') != 'redistributable':
            raise ValueError(item + ': geometry redistribution not established')
        if not entry.get('alignment_id'):
            raise ValueError(item + ': alignment_id required')
        identity = entry.get('historical_identity')
        if not isinstance(identity, dict) or not identity.get('line') or not identity.get('operator'):
            raise ValueError(item + ': historical line/operator required')
        if not isinstance(entry.get('selector'), dict):
            raise ValueError(item + ': selector required')
        evidence = entry.get('evidence')
        if not isinstance(evidence, list) or not evidence or not all(
                isinstance(e, dict) and e.get('authority') and e.get('reference')
                and e.get('date_precision') == 'exact_day' for e in evidence):
            raise ValueError(item + ': exact-day evidence required')
        result.append(pair)
    expected_start = day(event.get('valid_from'))
    transition = day(event.get('date'))
    if transition is None:
        raise ValueError(label + ': exact transition required')
    if result[0][0] != expected_start:
        raise ValueError(label + ': periods must start at event valid_from')
    for previous, following in zip(result, result[1:]):
        if previous[1] != following[0]:
            raise ValueError(label + ': periods must be exactly contiguous')
    if result[-1][1] != transition:
        raise ValueError(label + ': periods must end at the event transition')
    return result


def validate(event):
    if not event.get('id'):
        raise ValueError('source event needs id')
    if (event.get('kind') or 'closure') not in SOURCE_KINDS:
        raise ValueError(event['id'] + ': unsupported source event kind')
    if event.get('date_precision') != 'exact_day':
        raise ValueError(f"{event['id']}: only exact_day may enter the solver")
    if event.get('review', {}).get('status') != 'verified':
        raise ValueError(f"{event['id']}: source event is not reviewed")
    evidence = event.get('evidence')
    if not isinstance(evidence, list) or not evidence or not all(
            e.get('reference') and e.get('authority') and e.get('date_precision') == 'exact_day'
            for e in evidence):
        raise ValueError(f"{event['id']}: exact-day evidence required")
    for key in ('corridor_id', 'alignment_id', 'service_identity_id'):
        if not event.get(key):
            raise ValueError(f"{event['id']}: {key} required")
    if event.get('geometry', {}).get('licence_status') != 'redistributable':
        raise ValueError(f"{event['id']}: geometry redistribution not established")
    if event.get('geometry', {}).get('source') == 'N05':
        if not event['geometry'].get('permission_reference'):
            raise ValueError(f"{event['id']}: N05 permission required")
    if 'service_periods' in event:
        periods(event['service_periods'], event['id'])
    if 'infrastructure_periods' in event:
        periods(event['infrastructure_periods'], event['id'] + '.infrastructure')
    if 'service_partition' in event:
        p = event['service_partition']
        if not isinstance(p.get('longitude'), (int, float)) or not -180 < p['longitude'] < 180:
            raise ValueError(event['id'] + ': partition needs WGS84 longitude')
        for side in ('lower', 'upper'):
            periods(p[side + '_periods'], event['id'] + '.' + side)
    reviewed_historical_periods(event)
    if 'predecessor_event_ids' in event:
        dependencies = event['predecessor_event_ids']
        if (event.get('kind') != 'opening' or not isinstance(dependencies, list)
                or not dependencies or not all(isinstance(item, str) and item for item in dependencies)
                or len(set(dependencies)) != len(dependencies)):
            raise ValueError(event['id'] + ': opening predecessor event ids must be unique and non-empty')
        pair = periods(event.get('service_periods'), event['id'])
        if len(pair) != 1 or pair[0][0] is None or pair[0][1] is not None:
            raise ValueError(event['id'] + ': predecessor constraint needs one open-ended opening period')


def coords(feature):
    c = feature['geometry']['coordinates']
    return [c] if c and isinstance(c[0], (int, float)) else c


def select(features, identity, bbox=None, names=None):
    out = []
    for f in features:
        p = f['properties']
        if p.get('N02_003', p.get('line_name')) != identity['line']:
            continue
        if p.get('N02_004', p.get('operator')) != identity['operator']:
            continue
        if names and p.get('station_name', p.get('N02_005')) not in names:
            continue
        if bbox and not all(bbox[0] <= c[0] <= bbox[2] and bbox[1] <= c[1] <= bbox[3]
                            for c in coords(f)):
            continue
        out.append(f)
    return out


def bounds(features):
    points = [c for f in features for c in coords(f)]
    return [min(c[0] for c in points) - 1e-8, min(c[1] for c in points) - 1e-8,
            max(c[0] for c in points) + 1e-8, max(c[1] for c in points) + 1e-8]


def _distance_m(a, b):
    mx = 111320.0 * math.cos(math.radians((a[1] + b[1]) / 2.0))
    return math.hypot((a[0] - b[0]) * mx, (a[1] - b[1]) * 110540.0)


def _segment_distance_m(point, a, b):
    mx = 111320.0 * math.cos(math.radians(point[1]))
    ax, ay = (a[0] - point[0]) * mx, (a[1] - point[1]) * 110540.0
    bx, by = (b[0] - point[0]) * mx, (b[1] - point[1]) * 110540.0
    vx, vy = bx - ax, by - ay
    squared = vx * vx + vy * vy
    t = 0.0 if squared == 0 else max(0.0, min(1.0, -(ax * vx + ay * vy) / squared))
    return math.hypot(ax + t * vx, ay + t * vy)


def _feature_length_m(feature):
    return sum(_distance_m(a, b) for line in _geometry_lines(feature)
               for a, b in zip(line, line[1:]))


def _geometry_lines(feature):
    value = feature['geometry']['coordinates']
    if not value:
        return []
    if isinstance(value[0], (int, float)):
        return [[value]]
    if value[0] and isinstance(value[0][0], (int, float)):
        return [value]
    return value


def geometry_matches_current(old_features, current_features, target):
    """Whether surveyed predecessor geometry is the current alignment.

    Sections require every predecessor vertex within 30 m of current track and
    aggregate length within three percent. Station geometry is small enough
    that every predecessor vertex simply has to be within 50 m of a current
    platform/point.
    """
    if not old_features or not current_features:
        return False
    current_lines = [line for feature in current_features for line in _geometry_lines(feature) if line]
    if not current_lines:
        return False

    def nearest(point):
        distances = []
        for line in current_lines:
            if len(line) == 1:
                distances.append(_distance_m(point, line[0]))
            else:
                distances.extend(_segment_distance_m(point, a, b) for a, b in zip(line, line[1:]))
        return min(distances, default=math.inf)

    limit = 30.0 if target == 'sections' else 50.0
    if any(nearest(point) > limit for feature in old_features
           for line in _geometry_lines(feature) for point in line):
        return False
    if target == 'sections':
        old_length = sum(_feature_length_m(feature) for feature in old_features)
        current_length = sum(_feature_length_m(feature) for feature in current_features)
        if current_length == 0 or abs(old_length - current_length) / current_length > 0.03:
            return False
    return True


def _identity_code_values(features, target, raw, spelled):
    values = set()
    for feature in features:
        properties = feature['properties']
        value = properties.get(raw, properties.get(spelled))
        if value not in (None, ''):
            values.add(str(value))
    return values


# inherit_exact_current_station_codes deep-copies stations and may add only these.
_CURRENT_COPY_KEYS = ('n02_station_code', 'n02_group_code', 'station_code_basis')


def _feature_code_signature(feature):
    properties = {key: value for key, value in feature.get('properties', {}).items()
                  if key not in _CURRENT_COPY_KEYS}
    return (json.dumps(feature.get('geometry'), sort_keys=True, ensure_ascii=False),
            json.dumps(properties, sort_keys=True, ensure_ascii=False))


def _predecessor_code_features(old_features, chosen):
    """Current features carry the successor operator's class codes.

    Only a distinct historical geometry collection can supply predecessor codes.
    The same-geometry path passes the current features through as `old_features`,
    and station identity then deep-copies them to attach lookup codes. Those copies
    are not predecessor geometry.
    """
    if not old_features:
        return []
    if {id(feature) for feature in old_features} == {id(feature) for feature in chosen}:
        return []
    if {_feature_code_signature(feature) for feature in old_features} == {
            _feature_code_signature(feature) for feature in chosen}:
        return []
    return old_features


def identity_period(event, chosen, universe, identity, historical_identity,
                    pair, target, index, source=None, historical_features=None):
    out = stamp(event, chosen, universe, identity, pair, target,
                f'.identity.period{index}.{target}')
    out['as'] = {'N02_003': historical_identity['line'],
                 'N02_004': historical_identity['operator']}
    old_features = historical_features or []
    predecessor_features = _predecessor_code_features(old_features, chosen)
    operator_changed = historical_identity.get('operator') != identity.get('operator')
    for raw, spelled in (('N02_001', 'railway_class_code'),
                         ('N02_002', 'institution_type_code')):
        old_values = _identity_code_values(predecessor_features, target, raw, spelled)
        explicit = historical_identity.get(raw, historical_identity.get(spelled))
        if operator_changed and not old_values and explicit in (None, ''):
            raise ValueError(
                f"{event['id']}: operator change requires before.{raw} "
                f"when no historical geometry supplies predecessor codes")
        if explicit not in (None, ''):
            old_values.add(str(explicit))
        current_values = _identity_code_values(chosen, target, raw, spelled)
        # No predecessor geometry and no explicit code means the class code is
        # unchanged. Current features are the successor, so their codes are not
        # a predecessor source.
        if not old_values or old_values == current_values:
            continue
        if len(old_values) != 1:
            raise ValueError(
                f"{event['id']}: identity period cannot represent {target} {raw} values "
                f"{sorted(old_values)}")
        out['as'][raw] = next(iter(old_values))
    if target == 'stations' and historical_identity.get('station'):
        out['as']['N02_005'] = historical_identity['station']
        out['match']['station_name'] = identity['station']
    if source:
        out['source'] = source
    if event.get('official_event_id'):
        out['official_event_id'] = event['official_event_id']
    return out


def isolated_opening_stamps(event, chosen, universe, identity, pair, target):
    """Stamp new-since-release features without also dating preexisting ones.

    One bbox is used when it selects exactly the new features. Otherwise each
    feature gets its own bbox. A feature whose own bbox still contains a
    preexisting feature cannot be stamped.
    """
    suffix = '.current.' + target
    try:
        return [stamp(event, chosen, universe, identity, pair, target, suffix)]
    except ValueError as error:
        if 'unrelated' not in str(error):
            raise
    stamps = []
    for index, feature in enumerate(chosen):
        try:
            stamps.append(stamp(
                event, [feature], universe, identity, pair, target, suffix + f'.part{index}'))
        except ValueError as error:
            if 'unrelated' not in str(error):
                raise
            raise ValueError(
                f"{event['id']}: {target} feature {index} cannot be stamped "
                'without a preexisting feature inside its bbox')
    return stamps


def stamp(event, chosen, universe, identity, pair, target, suffix):
    if not chosen:
        raise ValueError(f"{event['id']}: no {target} matched")
    bbox = bounds(chosen)
    matches = select(universe, identity, bbox)
    if {id(f) for f in matches} != {id(f) for f in chosen}:
        raise ValueError(f"{event['id']}: bbox also selects unrelated {target}")
    out = {'history_id': event['id'] + suffix,
           'match': {'line_name': identity['line'], 'operator': identity['operator'],
                     'bbox': bbox, 'targets': [target]},
           'source': '; '.join(e['reference'] for e in event['evidence'])}
    if pair[0]:
        out['valid_from'] = pair[0]
    if pair[1]:
        out['valid_to'] = pair[1]
    return out


def variant(event, feature, pair, target, index, identity=None, surveyed_period=None):
    out = copy.deepcopy(feature)
    p = out['properties']
    for k in ('valid_from', 'valid_to', 'service_validity', 'infrastructure_validity',
              'history_id', 'kind', 'temporal_kind'):
        p.pop(k, None)
    if surveyed_period is None:
        # Compatibility contract: legacy variants hash the complete source
        # feature before identity rewriting, exactly as runtime v1 has shipped.
        token_basis = out
    else:
        token_basis = {'target': target, 'geometry': out['geometry']}
    if surveyed_period is not None and target == 'stations':
        # Coordinates carry lineage across releases; a source code disambiguates
        # the rare case of distinct platforms with identical surveyed geometry.
        token_basis['station'] = (p.get('n02_station_code') or p.get('n02_group_code')
                                  or p.get('station_name'))
    token = hashlib.sha256(json.dumps(token_basis, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]
    p['history_id'] = (event['id'] + '.sections' if target == 'sections' else
                       (f"{event['id']}.stations.{token}.period{index}" if surveyed_period is not None else
                        f"{event['id']}.period{index}.{target}.{token}"))
    if identity:
        if target == 'sections':
            p['N02_003'], p['N02_004'] = identity['line'], identity['operator']
        else:
            p['line_name'], p['operator'] = identity['line'], identity['operator']
            if identity.get('station'):
                p['station_name'] = identity['station']
            # Surveyed station codes remain lookup keys across identity changes.
            # Date-aware candidate deduplication retains their temporal variants.
    p['service_validity'] = pair
    if pair[0]:
        p['valid_from'] = pair[0]
    if pair[1]:
        p['valid_to'] = pair[1]
    infra = event.get('infrastructure_periods', [])
    containing = [i for i in infra if (i[0] is None or pair[0] and i[0] <= pair[0])
                  and (i[1] is None or pair[1] and pair[1] <= i[1])]
    if infra:
        if len(containing) != 1:
            raise ValueError(f"{event['id']}: service period needs one containing infrastructure period")
        p['infrastructure_validity'] = containing[0]
    evidence = surveyed_period.get('evidence', []) if surveyed_period is not None else event['evidence']
    source = '; '.join(e['reference'] for e in evidence)
    p['source'] = (surveyed_period['release'] + '; ' + source
                   if surveyed_period is not None else source)
    return out


def inherit_exact_current_station_codes(old_features, current_features, current_identity):
    """Copy lookup codes only across an exact, unique surveyed geometry match."""
    result = copy.deepcopy(old_features)
    for old in result:
        old_name = old['properties']['station_name']
        current_name = current_identity.get('station', old_name)
        same = [feature for feature in current_features
                if feature['properties']['station_name'] == current_name
                and feature['geometry'] == old['geometry']]
        if len(same) != 1:
            continue
        copied = False
        for key in ('n02_station_code', 'n02_group_code'):
            if not old['properties'].get(key) and same[0]['properties'].get(key):
                old['properties'][key] = same[0]['properties'][key]
                copied = True
        if copied:
            old['properties']['station_code_basis'] = 'exact_current_geometry_identity'
    return result


def apply_new_since_release(event, chosen, snapshot_covered):
    """Keep only current features the named N02 release does not already cover.

    An opening selector may set ``new_since_release`` to an ``N02-YY`` label.
    ``snapshot_covered(label, feature)`` is the builder's same-class test
    (at least 90 percent of 25 m samples within 40 m). Other kinds cannot
    use the option: a rename or transfer is not a new alignment.
    """
    release = (event.get('geometry') or {}).get('selector', {}).get('new_since_release')
    if not release:
        return chosen
    label = event.get('id', '?')
    if event.get('kind') != 'opening':
        raise ValueError(label + ': new_since_release is only valid on an opening')
    if not isinstance(release, str) or not re.fullmatch(r'N02-\d{2}', release):
        raise ValueError(label + ': new_since_release must be N02-YY')
    if snapshot_covered is None:
        raise ValueError(label + ': new_since_release requires snapshot coverage')
    return [feature for feature in chosen if not snapshot_covered(release, feature)]


def compile_event(event, current_sections, current_stations, snapshot_covered=None):
    """Current geometry timelines and same-alignment identity changes.

    Moved stations require an explicit historical feature collection; this
    compiler never moves a point based on a station name alone.
    """
    validate(event)
    kind = event.get('kind')
    if kind in ('identity_split', 'identity_merge'):
        memberships = event.get('memberships')
        if not isinstance(memberships, list) or not memberships:
            raise ValueError(event['id'] + ': split/merge requires explicit memberships')
        out = {'sections': [], 'stations': [], 'retirements': [], 'identity_periods': []}
        ids = set()
        for membership in memberships:
            if not membership.get('id') or membership['id'] in ids:
                raise ValueError(event['id'] + ': membership ids must be unique')
            ids.add(membership['id'])
            child = copy.deepcopy(event)
            child.pop('memberships')
            child.update(membership)
            child['id'] = event['id'] + '.' + membership['id']
            child['kind'] = 'line_rename'
            part = compile_event(child, current_sections, current_stations, snapshot_covered)
            for target in out:
                out[target].extend(part[target])
        return out
    identity = event.get('after') or {'line': event['line'], 'operator': event['operator']}
    selector = event.get('geometry', {}).get('selector', {})
    bbox = selector.get('bbox', event.get('bbox'))
    if event.get('segment') and not bbox and selector.get('scope') != 'whole_identity':
        raise ValueError(event['id'] + ': a station interval needs an isolated selector; whole identity must be explicit')
    targets = ['stations'] if kind in ('station_rename', 'station_relocation',
                                      'station_opening', 'station_closure') else ['sections', 'stations']
    out = {'sections': [], 'stations': [], 'retirements': [], 'identity_periods': []}
    historical_period_pairs = None
    if kind in IDENTITY_KINDS:
        transition = day(event.get('date'))
        if transition is None or not event.get('before') or not event.get('after'):
            raise ValueError(f"{event['id']}: before/after and exact transition required")
        historical_period_pairs = reviewed_historical_periods(event)
        pairs = ((historical_period_pairs or [[event.get('valid_from'), transition]])
                 + [[transition, None]])
        periods(pairs, event['id'])
    else:
        pairs = periods(event['service_periods'], event['id'])
    for target, universe in [('sections', current_sections), ('stations', current_stations)]:
        if target not in targets:
            continue
        names = selector.get('stations')
        if target == 'stations' and identity.get('station'):
            names = [identity['station']]
        chosen = select(universe, identity, bbox, names if target == 'stations' else None)
        chosen = apply_new_since_release(event, chosen, snapshot_covered)
        if not chosen and (event.get('geometry') or {}).get('selector', {}).get('new_since_release'):
            # This target is entirely preexisting. Do not stamp it.
            continue
        if not chosen:
            historical = event['geometry'].get('historical_' + target, [])
            if not historical or kind in IDENTITY_KINDS:
                raise ValueError(f"{event['id']}: no current {target}; provide reviewed snapshot geometry")
            for index, pair in enumerate(pairs):
                for f in historical:
                    out[target].append(variant(event, f, pair, target, index))
            continue
        predecessor_sets = []
        if historical_period_pairs is not None:
            for index, (historical_period, pair) in enumerate(zip(
                    event['geometry']['historical_periods'], historical_period_pairs)):
                old_features = historical_period.get('historical_' + target)
                if not old_features:
                    raise ValueError(f"{event['id']}: historical period {index} {target} selector matched nothing")
                if target == 'stations':
                    old_features = inherit_exact_current_station_codes(old_features, chosen, identity)
                predecessor_sets.append((index, pair, old_features,
                                         historical_period['historical_identity'],
                                         historical_period['release'] + '; ' + '; '.join(
                                             e['reference'] for e in historical_period['evidence'])))
            if not event.get('_force_geometry_history') and kind != 'station_relocation' and all(
                    geometry_matches_current(old_features, chosen, target)
                    for _, _, old_features, _, _ in predecessor_sets):
                for index, pair, old_features, old_identity, period_source in predecessor_sets:
                    out['identity_periods'].append(identity_period(
                        event, chosen, universe, identity, old_identity, pair,
                        target, index, period_source, old_features))
                continue
            out['retirements'].append(stamp(event, chosen, universe, identity, pairs[-1],
                                            target, '.current.' + target))
            for index, pair, old_features, old_identity, _ in predecessor_sets:
                for feature in old_features:
                    out[target].append(variant(
                        event, feature, pair, target, index,
                        old_identity, event['geometry']['historical_periods'][index]))
            continue
        old_features = chosen
        supplied = event['geometry'].get('historical_' + target)
        if supplied is not None:
            old_features = supplied
            if not old_features:
                raise ValueError(event['id'] + ': historical ' + target + ' selector matched nothing')
        if kind == 'station_relocation':
            old_features = event['geometry'].get('historical_stations', [])
            if not old_features:
                raise ValueError(f"{event['id']}: station relocation needs historical station geometry")
        if target == 'stations' and kind in IDENTITY_KINDS - {'station_relocation'}:
            old_features = inherit_exact_current_station_codes(old_features, chosen, identity)
        # A deep copy of the current stations still carries the successor class
        # codes. Only supplied historical geometry may contribute predecessor codes.
        code_features = old_features if supplied is not None else None
        force_historical = (event.get('_force_geometry_history')
                            or target in event.get('geometry', {}).get(
                                'force_historical_targets', []))
        if not force_historical \
                and kind in {'operator_transfer', 'operator_rename', 'line_rename', 'station_rename'} \
                and geometry_matches_current(old_features, chosen, target):
            out['identity_periods'].append(identity_period(
                event, chosen, universe, identity, event['before'], pairs[0], target, 0,
                historical_features=code_features))
            continue
        if (event.get('geometry') or {}).get('selector', {}).get('new_since_release'):
            out['retirements'].extend(isolated_opening_stamps(
                event, chosen, universe, identity, pairs[-1], target))
        else:
            out['retirements'].append(stamp(event, chosen, universe, identity, pairs[-1],
                                            target, '.current.' + target))
        for index, pair in enumerate(pairs[:-1]):
            for f in old_features:
                out[target].append(variant(event, f, pair, target, index,
                                           event.get('before') if kind in IDENTITY_KINDS else None))
    if (event.get('geometry') or {}).get('selector', {}).get('new_since_release') \
            and kind == 'opening' and not any(out[key] for key in out):
        raise ValueError(event['id'] + ': new_since_release removed every current feature')
    return out


def normalize_identity_periods(identity_periods, current_sections, current_stations):
    """Validate selectors and reject periods that overlap on a current feature."""
    seen_ids = set()
    selected = {'sections': {}, 'stations': {}}
    for period in identity_periods:
        history_id = period.get('history_id')
        if not history_id or history_id in seen_ids:
            raise ValueError('duplicate identity period id: ' + str(history_id))
        seen_ids.add(history_id)
        pair = periods([[period.get('valid_from'), period.get('valid_to')]], history_id)[0]
        if pair[1] is None:
            raise ValueError(history_id + ': identity period requires valid_to')
        match = period.get('match', {})
        targets = match.get('targets', ['sections', 'stations'])
        found = False
        for target, universe in [('sections', current_sections), ('stations', current_stations)]:
            if target not in targets:
                continue
            names = [match['station_name']] if target == 'stations' and match.get('station_name') else None
            matches = select(universe, {'line': match.get('line_name'),
                                        'operator': match.get('operator')},
                             match.get('bbox'), names)
            found = found or bool(matches)
            for feature in matches:
                prior = selected[target].setdefault(id(feature), [])
                if any((a is None or pair[1] > a) and (pair[0] is None or b > pair[0])
                       for a, b, _ in prior):
                    other = next(item[2] for item in prior
                                 if (item[0] is None or pair[1] > item[0])
                                 and (pair[0] is None or item[1] > pair[0]))
                    raise ValueError(f'{history_id}: overlaps identity period {other}')
                prior.append((pair[0], pair[1], history_id))
        if not found:
            raise ValueError(history_id + ': unmatched identity period')
    return identity_periods


def normalize_stamps(retirements, current_sections, current_stations):
    """Reject incompatible intersections; order v1 bounds to avoid overwrites.

    Runtime stamps overwrite a field when present. Monotonic ordering and
    separate start/end stamps make each final value the intersection, without
    requiring a runtime schema change or broadening one stamp's selector.
    """
    starts, ends = [], []
    identities = set()
    for r in retirements:
        if r['history_id'] in identities:
            raise ValueError('duplicate retirement id: ' + r['history_id'])
        identities.add(r['history_id'])
        pair = r.get('service_validity', [r.get('valid_from'), r.get('valid_to')])
        if pair == [None, None] and 'infrastructure_validity' in r:
            pair = r['infrastructure_validity']
        pair = periods([pair], r['history_id'])[0]
        targets = r['match'].get('targets', ['sections', 'stations'])
        found = False
        for target, universe in [('sections', current_sections), ('stations', current_stations)]:
            if target in targets and select(universe, {'line': r['match']['line_name'],
                                                     'operator': r['match']['operator']}, r['match']['bbox']):
                found = True
        if not found:
            raise ValueError(r['history_id'] + ': unmatched retirement')
        r = copy.deepcopy(r)
        r.pop('service_validity', None)
        r.pop('valid_from', None)
        r.pop('valid_to', None)
        if pair[0] and pair[1]:
            # Preserve the old id for the end stamp (coverage and relocation).
            start = copy.deepcopy(r)
            start['history_id'] += '.from'
            start['valid_from'] = pair[0]
            starts.append(start)
            r['valid_to'] = pair[1]
            ends.append(r)
        elif pair[0]:
            r['valid_from'] = pair[0]
            starts.append(r)
        else:
            r['valid_to'] = pair[1]
            ends.append(r)
    out = sorted(starts, key=lambda r: (r['valid_from'], r['history_id'])) + sorted(
        ends, key=lambda r: (r['valid_to'], r['history_id']), reverse=True)
    if len({r['history_id'] for r in out}) != len(out):
        raise ValueError('compiled retirement ids collide after interval splitting')
    for target, universe in [('sections', current_sections), ('stations', current_stations)]:
        effective = {}
        for r in out:
            if target not in r['match'].get('targets', ['sections', 'stations']):
                continue
            for f in select(universe, {'line': r['match']['line_name'],
                                      'operator': r['match']['operator']}, r['match']['bbox']):
                a, b = effective.get(id(f), (f['properties'].get('valid_from'), f['properties'].get('valid_to')))
                a = max(filter(None, [a, r.get('valid_from')]), default=None)
                b = min(filter(None, [b, r.get('valid_to')]), default=None)
                if a and b and a >= b:
                    raise ValueError(r['history_id'] + ': incompatible stamps leave empty service interval')
                effective[id(f)] = a, b
    return out


def constrain_opening_predecessors(events, sections, stations,
                                   current_sections, current_stations,
                                   identity_periods=None, snapshot_covered=None):
    """Intersect explicit, geometry-exact identity predecessors with opening days.

    Current stamps cannot constrain a differently named historical operator.
    A reviewed dependency supplies that identity; exact geometry supplies the
    feature correspondence. No proximity matching or implicit lineage is used.
    """
    by_id = {event['id']: event for event in events}
    result = {'sections': copy.deepcopy(sections), 'stations': copy.deepcopy(stations)}
    return_identity_periods = identity_periods is not None
    result_identity_periods = copy.deepcopy(identity_periods or [])
    for event in events:
        dependencies = event.get('predecessor_event_ids')
        if dependencies is None:
            continue
        validate(event)
        start = event['service_periods'][0][0]
        identity = event.get('after') or {'line': event['line'], 'operator': event['operator']}
        selector = event['geometry'].get('selector', {})
        for dependency in dependencies:
            predecessor = by_id.get(dependency)
            if not predecessor or predecessor.get('kind') not in IDENTITY_KINDS:
                raise ValueError(event['id'] + ': unknown identity predecessor ' + dependency)
            if predecessor.get('after') != identity:
                raise ValueError(event['id'] + ': predecessor successor identity differs')
            for target, universe in [('sections', current_sections), ('stations', current_stations)]:
                chosen = select(universe, identity, selector.get('bbox', event.get('bbox')),
                                selector.get('stations') if target == 'stations' else None)
                chosen = apply_new_since_release(event, chosen, snapshot_covered)
                if not chosen:
                    raise ValueError(event['id'] + ': no current ' + target + ' for predecessor constraint')
                candidates = [feature for feature in result[target]
                              if feature['properties'].get('history_id', '').startswith(dependency + '.')]
                period_candidates = [period for period in result_identity_periods
                                     if period.get('history_id', '').startswith(dependency + '.')
                                     and target in period.get('match', {}).get(
                                         'targets', ['sections', 'stations'])]
                if not candidates and period_candidates:
                    if len(period_candidates) != 1:
                        raise ValueError(event['id'] + ': predecessor identity period is ambiguous')
                    period = period_candidates[0]
                    period_matches = select(
                        universe, {'line': period['match']['line_name'],
                                   'operator': period['match']['operator']},
                        period['match']['bbox'],
                        ([period['match']['station_name']]
                         if target == 'stations' and period['match'].get('station_name') else None))
                    if not chosen or not {id(feature) for feature in chosen}.issubset(
                            {id(feature) for feature in period_matches}):
                        raise ValueError(event['id'] + ': predecessor identity selector differs')
                    lower = max(filter(None, [period.get('valid_from'), start]))
                    if lower >= period['valid_to']:
                        result_identity_periods.remove(period)
                    else:
                        period['valid_from'] = lower
                    continue
                removed = set()
                for current in chosen:
                    matches = [feature for feature in candidates if feature['geometry'] == current['geometry']]
                    # Multiple surveyed service periods may legitimately share
                    # one geometry. Each must have a distinct service interval.
                    if not matches or len({tuple(feature['properties'].get('service_validity', []))
                                           for feature in matches}) != len(matches):
                        raise ValueError(event['id'] + ': predecessor geometry is missing or ambiguous')
                    for feature in matches:
                        properties = feature['properties']
                        lower, upper = properties.get('service_validity',
                                                      [properties.get('valid_from'), properties.get('valid_to')])
                        lower = max(filter(None, [lower, start]))
                        if upper is not None and lower >= upper:
                            removed.add(id(feature))
                            continue
                        properties['service_validity'] = [lower, upper]
                        properties['valid_from'] = lower
                        properties['source'] = '; '.join(dict.fromkeys(
                            [properties.get('source', ''), event['id']]
                            + [proof['reference'] for proof in event['evidence']]))
                result[target] = [feature for feature in result[target] if id(feature) not in removed]
    if return_identity_periods:
        return result['sections'], result['stations'], result_identity_periods
    return result['sections'], result['stations']


def expand_legacy_periods(events, sections, stations):
    """Apply source timelines after surveyed retired geometry has been compiled.

    Keeping discovery independent of service dates means legally retired track
    can retain its infrastructure end while the solver stops at suspension.
    """
    timelines = {e['id']: e for e in events if 'service_periods' in e}
    for event in timelines.values():
        validate(event)
    outputs = []
    for target, features in [('sections', sections), ('stations', stations)]:
        expanded = []
        for feature in features:
            hid = feature['properties']['history_id']
            matching = [e for eid, e in timelines.items() if hid == eid or hid.startswith(eid + '.')]
            if not matching:
                expanded.append(feature)
                continue
            if len(matching) != 1:
                raise ValueError(hid + ': ambiguous source timeline')
            e = matching[0]
            partition = e.get('service_partition')
            pieces = [(feature, e['service_periods'], '')]
            if partition:
                if target == 'sections':
                    pieces = []
                    for side, points in split_longitude(coords(feature), partition['longitude']):
                        piece = copy.deepcopy(feature)
                        piece['geometry']['coordinates'] = points
                        piece['properties']['service_partition_side'] = side
                        pieces.append((piece, partition[side + '_periods'], '.' + side))
                else:
                    name = feature['properties']['station_name']
                    if name in partition.get('upper_stations', []):
                        pieces = [(feature, partition['upper_periods'], '')]
            for piece, timeline, suffix in pieces:
                for i, pair in enumerate(periods(timeline, e['id'])):
                    f = variant(e, piece, pair, target, i)
                    # The first identity stays compatible with relocation detection.
                    f['properties']['history_id'] = (hid if target == 'sections' else
                        hid + suffix + ('' if i == 0 else f'.period{i}'))
                    expanded.append(f)
        outputs.append(expanded)
    return outputs


def split_longitude(points, longitude):
    """Cut only along existing measured segments, preserving every vertex.

    A reviewed meridian selector is useful on a monotone coastal corridor.
    It is not a general station-to-station matcher; loops require explicit
    alignment selectors. Both sides share the same quantized cut vertex.
    """
    output = []
    def add(side, a, b):
        if a == b:
            return
        if output and output[-1][0] == side and output[-1][1][-1] == a:
            output[-1][1].append(b)
        else:
            output.append((side, [a, b]))
    for a, b in zip(points, points[1:]):
        low_a, low_b = a[0] <= longitude, b[0] <= longitude
        if low_a == low_b:
            add('lower' if low_a else 'upper', list(a), list(b))
        else:
            t = (longitude - a[0]) / (b[0] - a[0])
            cut = [round(longitude, 5), round(a[1] + t * (b[1] - a[1]), 5)]
            add('lower' if low_a else 'upper', list(a), cut)
            add('lower' if low_b else 'upper', cut, list(b))
    return output
