"""Compile reviewed rich source timelines into the unchanged runtime v1.

Selectors deliberately require complete current features inside a bbox. They
cannot invent a station-to-station slice of a national shapefile. If a selector
does not isolate the intended interval, refine the source geometry first.
"""
import copy
import datetime
import hashlib
import json
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


def compile_event(event, current_sections, current_stations):
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
        out = {'sections': [], 'stations': [], 'retirements': []}
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
            part = compile_event(child, current_sections, current_stations)
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
    out = {'sections': [], 'stations': [], 'retirements': []}
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
        if not chosen:
            historical = event['geometry'].get('historical_' + target, [])
            if not historical or kind in IDENTITY_KINDS:
                raise ValueError(f"{event['id']}: no current {target}; provide reviewed snapshot geometry")
            for index, pair in enumerate(pairs):
                for f in historical:
                    out[target].append(variant(event, f, pair, target, index))
            continue
        out['retirements'].append(stamp(event, chosen, universe, identity, pairs[-1],
                                        target, '.current.' + target))
        if historical_period_pairs is not None:
            for index, (historical_period, pair) in enumerate(zip(
                    event['geometry']['historical_periods'], historical_period_pairs)):
                old_features = historical_period.get('historical_' + target)
                if not old_features:
                    raise ValueError(f"{event['id']}: historical period {index} {target} selector matched nothing")
                if target == 'stations':
                    old_features = inherit_exact_current_station_codes(old_features, chosen, identity)
                for feature in old_features:
                    out[target].append(variant(
                        event, feature, pair, target, index,
                        historical_period['historical_identity'], historical_period))
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
        for index, pair in enumerate(pairs[:-1]):
            for f in old_features:
                out[target].append(variant(event, f, pair, target, index,
                                           event.get('before') if kind in IDENTITY_KINDS else None))
    return out


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


def constrain_opening_predecessors(events, sections, stations, current_sections, current_stations):
    """Intersect explicit, geometry-exact identity predecessors with opening days.

    Current stamps cannot constrain a differently named historical operator.
    A reviewed dependency supplies that identity; exact geometry supplies the
    feature correspondence. No proximity matching or implicit lineage is used.
    """
    by_id = {event['id']: event for event in events}
    result = {'sections': copy.deepcopy(sections), 'stations': copy.deepcopy(stations)}
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
                if not chosen:
                    raise ValueError(event['id'] + ': no current ' + target + ' for predecessor constraint')
                candidates = [feature for feature in result[target]
                              if feature['properties'].get('history_id', '').startswith(dependency + '.')]
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
