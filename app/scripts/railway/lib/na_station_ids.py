"""Apply reviewed, line-scoped station ID splits without rebuilding track."""
import copy
import math


def distance(a, b):
    x, y, u, v = map(math.radians, (*a, *b))
    return 12742000 * math.asin(min(1, math.sqrt(
        math.sin((y-v)/2)**2 + math.cos(y)*math.cos(v)*math.sin((x-u)/2)**2)))


def apply_repairs(package, stations, catalog):
    """Validate the entire plan before returning independent updated objects.

    Each entry pins a line, old ID and observed coordinate. This is a reviewed
    migration, not a distance-based permission to merge arbitrary stations.
    Old IDs stay with one recorded place; every other place has a pinned new
    ID. Applying the same catalog twice is a no-op.
    """
    package, stations = copy.deepcopy(package), copy.deepcopy(stations)
    lines = {line['id']: line for line in package['lines']}
    changes, rows_by_key = [], {}
    for repair in catalog['repairs']:
        if repair['country'].upper() != package['country'].upper():
            continue
        old = repair['oldId']
        for place in repair['places']:
            new = place['id']
            for member in place['members']:
                line = lines.get(member['lineId'])
                if line is None:
                    raise ValueError('reviewed line is missing: ' + member['lineId'])
                matches = [s for s in line['stations'] if s[0] in (old, new)
                           and distance(s[2:4], member['point']) < 2]
                if len(matches) != 1:
                    raise ValueError('reviewed station moved or is ambiguous: ' + member['lineId'] + ':' + old)
                row = matches[0]
                if new != old:
                    key = (line['operator'], line['name'], old)
                    rows_by_key.setdefault(key, []).append((new, member['point']))
                    if row[0] == old:
                        changes.append({'lineId': line['id'], 'oldId': old, 'newId': new})
                        row[0] = new

    for feature in stations['features']:
        props = feature['properties']
        key = (props.get('operator'), props.get('line_name'), props.get('n02_group_code'))
        if key not in rows_by_key:
            continue
        options = {new for new, point in rows_by_key[key]
                   if distance(props['display_point'], point) < 2}
        if len(options) != 1:
            raise ValueError('station feature does not match reviewed membership: ' + str(key))
        new = options.pop()
        old = props['n02_group_code']
        code = props['n02_station_code']
        if not code.endswith(old.upper()):
            raise ValueError('station code suffix disagrees with group: ' + code)
        props['n02_group_code'] = new
        props['n02_station_code'] = code[:-len(old)] + new.upper()

    # A rerun sees new feature IDs; both initial and repeated runs must have
    # a corresponding feature at the same place for every migrated line row.
    for (operator, name, old), members in rows_by_key.items():
        for new, point in members:
            if not any(f['properties'].get('operator') == operator
                       and f['properties'].get('line_name') == name
                       and f['properties'].get('n02_group_code') == new
                       and distance(f['properties']['display_point'], point) < 2
                       for f in stations['features']):
                raise ValueError('missing solver station for ' + name + ':' + old)

    # Never introduce an existing-ID collision while repairing an old one.
    groups = {}
    for line in package['lines']:
        for row in line['stations']:
            groups.setdefault(row[0], []).append(row[2:4])
    for repair in catalog['repairs']:
        for place in repair['places']:
            points = groups.get(place['id'], [])
            if any(distance(a, b) > 2000 for i, a in enumerate(points) for b in points[i+1:]):
                raise ValueError('repaired ID still spans different places: ' + place['id'])
    return package, stations, changes
