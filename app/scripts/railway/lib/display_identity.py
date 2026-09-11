"""Station and line identity for the v2 display database.

This module is pure stdlib (no dependency on ``lib/na_geo.py`` or any other
project module) so it can be unit tested and reused without pulling in the
rest of the railway build pipeline.

Identity is the package's own station id, never the name: two rows that
share an id are the same station wherever their coordinates or spelling
differ slightly across lines; two rows with the same name but different ids
are different stations (see ``DISPLAY_NETWORK_V2_SPEC.md`` section 4).

``hub_index`` reads ``app/public/rail/display-hubs.json`` (format
``jtm-display-hubs-v1``). As of this writing that file describes hubs
geographically — a centre point, a radius and a trunk line id — and does not
list member station ids for any region. There is therefore currently no way
to map a station id to a hub id from that file, and ``hub_index`` returns an
empty dict for every region until the hubs file grows a per-station member
list.
"""
from __future__ import annotations

import math
import re
import unicodedata
from typing import Dict, List

_EARTH_RADIUS_METRES = 6371008.8

_LATIN_REGIONS = ('us', 'ca')

#: CJK regions where displayLabel disambiguation uses full-width parentheses
#: and no separating space.
_CJK_REGIONS = ('jp', 'tw', 'hk', 'mo', 'kr')

_STATION_SUFFIXES = ('駅', '站', '역')

_LEADING_DIRECTION_CHARS = ('新', '東', '西', '南', '北')

_WHITESPACE_RE = re.compile(r'\s+')


def _strip_all_whitespace(text: str) -> str:
    """Remove ASCII and full-width whitespace (NFKC already folds full-width
    spaces to U+0020, so a plain ``\\s`` strip after normalisation is enough)."""
    return _WHITESPACE_RE.sub('', text)


def name_key(name: str, region: str) -> str:
    """Normalise a station or line name into a comparable key (spec 5.0).

    NFKC normalise -> strip all whitespace -> ``ヶ``/``ヵ`` -> ``ケ``/``カ`` ->
    for Latin regions (us, ca), casefold and strip a trailing " Station" /
    " station" token -> strip a trailing 駅/站/역 suffix only when the name
    is longer than that suffix. Nothing else.
    """
    text = unicodedata.normalize('NFKC', name)
    text = _strip_all_whitespace(text)
    text = text.replace('ヶ', 'ケ').replace('ヵ', 'カ')
    if region in _LATIN_REGIONS:
        text = text.casefold()
        for suffix in ('station',):
            if text.endswith(suffix) and len(text) > len(suffix):
                text = text[: -len(suffix)]
                break
    for suffix in _STATION_SUFFIXES:
        if text.endswith(suffix) and len(text) > len(suffix):
            text = text[: -len(suffix)]
            break
    return text


def _haversine_metres(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    """Great-circle distance between two lon/lat points, in metres."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return _EARTH_RADIUS_METRES * c


def hub_index(display_hubs_doc: dict, region: str) -> Dict[str, str]:
    """Map station id -> hub id for ``region`` from a ``display-hubs.json`` doc.

    The current ``jtm-display-hubs-v1`` schema describes hubs by a centre
    point and radius, not by member station ids, so this always returns an
    empty dict today; it exists so callers have one place to update once the
    hubs file carries a per-station member list.
    """
    result: Dict[str, str] = {}
    for hub in display_hubs_doc.get('hubs', []) or []:
        if hub.get('region') != region:
            continue
        for member_id in hub.get('stationIds', []) or []:
            result[member_id] = hub.get('id')
    return result


def _station_row_fields(row: list):
    station_id = row[0]
    name = row[1]
    lon = row[2]
    lat = row[3]
    roma = row[4] if len(row) > 4 else None
    return station_id, name, lon, lat, roma


def build_station_identity(
    region: str, lines: List[dict], hub_by_station_id: Dict[str, str]
) -> dict:
    """Build the full ``{region}.stations.json`` document (spec section 4)."""
    # Gather every (line, row) occurrence per station id.
    members: Dict[str, list] = {}
    names_by_id: Dict[str, dict] = {}  # id -> {name: count}
    romas_by_id: Dict[str, str] = {}

    sorted_lines = sorted(lines, key=lambda ln: (ln.get('rank', 0), ln.get('id', '')))

    for line in sorted_lines:
        line_id = line.get('id', '')
        operator = line.get('operator', '')
        operator_short = line.get('operatorShort') or operator
        line_name = line.get('name', '')
        for row in line.get('stations', []):
            station_id, name, lon, lat, roma = _station_row_fields(row)
            members.setdefault(station_id, []).append(
                {
                    'lineId': line_id,
                    'operator': operator,
                    'operatorShort': operator_short,
                    'lineName': line_name,
                    'lineRank': line.get('rank', 0),
                    'name': name,
                    'lon': lon,
                    'lat': lat,
                }
            )
            names_by_id.setdefault(station_id, {})
            names_by_id[station_id][name] = names_by_id[station_id].get(name, 0) + 1
            if roma and station_id not in romas_by_id:
                romas_by_id[station_id] = roma

    stations = []
    name_key_to_ids: Dict[str, set] = {}

    for station_id, occurrences in members.items():
        # Canonical name = the most common name among member rows, ties
        # broken by first occurrence (package/rank order).
        name_counts = names_by_id[station_id]
        best_count = max(name_counts.values())
        canonical_name = next(n for n in name_counts if name_counts[n] == best_count)

        key = f'{region}:{station_id}'
        nk = name_key(canonical_name, region)
        name_key_to_ids.setdefault(nk, set()).add(station_id)

        lon_mean = sum(o['lon'] for o in occurrences) / len(occurrences)
        lat_mean = sum(o['lat'] for o in occurrences) / len(occurrences)

        spread = 0.0
        for i in range(len(occurrences)):
            for j in range(i + 1, len(occurrences)):
                d = _haversine_metres(
                    occurrences[i]['lon'], occurrences[i]['lat'],
                    occurrences[j]['lon'], occurrences[j]['lat'],
                )
                if d > spread:
                    spread = d

        line_ids = sorted({o['lineId'] for o in occurrences})
        operators = sorted({o['operator'] for o in occurrences if o['operator']})

        stations.append(
            {
                'key': key,
                'id': station_id,
                'name': canonical_name,
                'nameKey': nk,
                'nameRoma': romas_by_id.get(station_id),
                'lon': lon_mean,
                'lat': lat_mean,
                'spreadMetres': spread,
                'lines': line_ids,
                'operators': operators,
                'hubId': hub_by_station_id.get(station_id),
                'idCollision': spread > 300,
                '_occurrences': occurrences,  # dropped before returning
            }
        )

    # homonymGroups: nameKey shared by >=2 distinct ids in this region.
    homonym_groups: Dict[str, dict] = {}
    for nk, ids in name_key_to_ids.items():
        if len(ids) < 2:
            continue
        keys = sorted(f'{region}:{sid}' for sid in ids)
        by_key = {s['key']: s for s in stations}
        max_sep_km = 0.0
        pts = [(by_key[k]['lon'], by_key[k]['lat']) for k in keys]
        for i in range(len(pts)):
            for j in range(i + 1, len(pts)):
                d_km = _haversine_metres(pts[i][0], pts[i][1], pts[j][0], pts[j][1]) / 1000.0
                if d_km > max_sep_km:
                    max_sep_km = d_km
        homonym_groups[nk] = {'keys': keys, 'maxSeparationKm': max_sep_km}

    for station in stations:
        nk = station['nameKey']
        station['homonymGroup'] = nk if nk in homonym_groups else None

    # idCollisions
    id_collisions = []
    for station in stations:
        if station['idCollision']:
            id_collisions.append(
                {
                    'key': station['key'],
                    'spreadMetres': station['spreadMetres'],
                    'members': [
                        {'lineId': o['lineId'], 'lon': o['lon'], 'lat': o['lat']}
                        for o in station['_occurrences']
                    ],
                }
            )
    id_collisions.sort(key=lambda entry: entry['key'])

    # similarNameGroups (review only, never affects identity/labels).
    is_cjk = region in _CJK_REGIONS
    core_to_keys: Dict[str, set] = {}
    for nk in name_key_to_ids:
        core_to_keys.setdefault(_similar_core(nk, is_cjk), set()).add(nk)

    similar_name_groups = []
    for core, nks in core_to_keys.items():
        if len(nks) < 2:
            continue
        keys = []
        names = []
        for nk in sorted(nks):
            for sid in sorted(name_key_to_ids[nk]):
                keys.append(f'{region}:{sid}')
            # representative display name for this nameKey: first station's
            # canonical name with that key (sorted by id for determinism).
        by_key = {s['key']: s for s in stations}
        keys = sorted(set(keys))
        names = sorted({by_key[k]['name'] for k in keys})
        similar_name_groups.append({'core': core, 'keys': keys, 'names': names})
    similar_name_groups.sort(key=lambda g: g['core'])

    # displayLabel (spec 5.1), assigned after all stations are known.
    _assign_station_display_labels(stations, name_key_to_ids, region, is_cjk)

    for station in stations:
        del station['_occurrences']

    stations.sort(key=lambda s: s['key'])

    return {
        'format': 'jtm-display-stations-v2',
        'region': region,
        'stations': stations,
        'homonymGroups': homonym_groups,
        'idCollisions': id_collisions,
        'similarNameGroups': similar_name_groups,
    }


def _similar_core(nk: str, is_cjk: bool) -> str:
    """Core key used only for the review-oriented similarNameGroups (spec 5)."""
    core = nk
    if is_cjk:
        if core and core[0] in _LEADING_DIRECTION_CHARS and len(core) > 1:
            core = core[1:]
        if core.endswith('前') and len(core) > 1:
            core = core[:-1]
    else:
        # Latin regions: name_key already stripped a trailing "station"
        # token, so the core is the nameKey itself.
        pass
    return core


def _first_line_occurrence(occurrences: list) -> dict:
    """"first line" = lowest-rank, then lexicographically smallest, line id."""
    return min(occurrences, key=lambda o: (o['lineRank'], o['lineId']))


def _assign_station_display_labels(
    stations: List[dict], name_key_to_ids: Dict[str, set], region: str, is_cjk: bool
):
    by_key = {s['key']: s for s in stations}

    def label_for(station, force_rule4: bool) -> str:
        ids_with_same_key = name_key_to_ids.get(station['nameKey'], set())
        occurrences = station['_occurrences']
        first_occ = _first_line_occurrence(occurrences)

        if force_rule4:
            return _paren(station['name'], f"{station['lat']:.2f},{station['lon']:.2f}", is_cjk)

        if len(ids_with_same_key) < 2:
            return station['name']

        # Compare this station's own operator set against the other
        # stations sharing the same nameKey.
        sibling_ids = ids_with_same_key - {station['id']}
        own_operators = set(station['operators'])
        operators_differ = any(
            set(by_key[f'{region}:{sid}']['operators']) != own_operators for sid in sibling_ids
        )
        if operators_differ:
            operator_short = first_occ.get('operatorShort') or first_occ['operator']
            return _paren(station['name'], operator_short, is_cjk)

        own_first_line_name = first_occ['lineName']
        lines_differ = any(
            _first_line_occurrence(by_key[f'{region}:{sid}']['_occurrences'])['lineName']
            != own_first_line_name
            for sid in sibling_ids
        )
        if lines_differ:
            return _paren(station['name'], own_first_line_name, is_cjk)

        return _paren(station['name'], f"{station['lat']:.2f},{station['lon']:.2f}", is_cjk)

    labels = {station['key']: label_for(station, False) for station in stations}
    if len(set(labels.values())) != len(labels):
        # Assert-then-fallback: any residual collision falls to rule 4 for
        # every station involved.
        seen: Dict[str, list] = {}
        for key, label in labels.items():
            seen.setdefault(label, []).append(key)
        for label, keys in seen.items():
            if len(keys) < 2:
                continue
            for key in keys:
                labels[key] = label_for(by_key[key], True)
    if len(set(labels.values())) != len(labels):
        # Rule 5: rule 4 can still collide (two directional tram stops of one
        # operator on one line rounding to the same 0.01°). The station id is
        # the identity, so it is the last-resort disambiguator.
        seen = {}
        for key, label in labels.items():
            seen.setdefault(label, []).append(key)
        for label, keys in seen.items():
            if len(keys) < 2:
                continue
            for key in keys:
                labels[key] = _paren(by_key[key]['name'], by_key[key]['id'], is_cjk)

    for station in stations:
        station['displayLabel'] = labels[station['key']]


def _paren(name: str, extra: str, is_cjk: bool) -> str:
    if is_cjk:
        return f'{name}（{extra}）'
    return f'{name} ({extra})'


def line_display_labels(region: str, lines: List[dict]) -> Dict[str, dict]:
    """lineId -> {displayLabel, nameKey, operatorShort} (spec 5.2)."""
    is_cjk = region in _CJK_REGIONS

    entries = []
    for line in lines:
        nk = name_key(line.get('name', ''), region)
        operator_short = line.get('operatorShort') or line.get('operator', '')
        stations = line.get('stations', [])
        first_station_name = stations[0][1] if stations else ''
        last_station_name = stations[-1][1] if stations else ''
        entries.append(
            {
                'id': line.get('id', ''),
                'name': line.get('name', ''),
                'operator': line.get('operator', ''),
                'operatorShort': operator_short,
                'nameKey': nk,
                'firstStation': first_station_name,
                'lastStation': last_station_name,
            }
        )

    nk_to_ids: Dict[str, list] = {}
    for e in entries:
        nk_to_ids.setdefault(e['nameKey'], []).append(e['id'])

    def build_label(e, level: int) -> str:
        same_name = nk_to_ids[e['nameKey']]
        if level <= 1 and len(same_name) < 2:
            return e['name']
        operators_for_key = {
            next(x for x in entries if x['id'] == lid)['operator'] for lid in same_name
        }
        if level <= 2 and len(operators_for_key) == len(same_name):
            if is_cjk:
                return f"{e['operatorShort']}{e['name']}"
            return f"{e['operatorShort']} {e['name']}"
        span = f"{e['firstStation']}–{e['lastStation']}"
        if is_cjk:
            return f"{e['operatorShort']}{e['name']}（{span}）"
        return f"{e['operatorShort']} {e['name']} ({span})"

    labels = {e['id']: build_label(e, 1) for e in entries}
    if len(set(labels.values())) != len(labels):
        # Fall back to appending the line id in parentheses for whichever
        # entries still collide after the documented three rules.
        seen: Dict[str, str] = {}
        for e in entries:
            label = build_label(e, 1)
            if label in seen and seen[label] != e['id']:
                label = f"{label}（{e['id']}）" if is_cjk else f"{label} ({e['id']})"
            seen.setdefault(label, e['id'])
            labels[e['id']] = label

    result = {}
    for e in entries:
        result[e['id']] = {
            'displayLabel': labels[e['id']],
            'nameKey': e['nameKey'],
            'operatorShort': e['operatorShort'],
        }
    return result


def identity_summary(station_doc: dict, line_labels: Dict[str, dict], lines: List[dict]) -> dict:
    """Identity counters for spec section 6, for one region."""
    line_name_keys: Dict[str, set] = {}
    for line in lines:
        nk = line_labels.get(line.get('id', ''), {}).get('nameKey')
        if nk is None:
            continue
        line_name_keys.setdefault(nk, set()).add(line.get('id'))

    same_name_lines = sum(1 for ids in line_name_keys.values() if len(ids) >= 2)

    return {
        'homonymGroups': len(station_doc.get('homonymGroups', {})),
        'idCollisions': len(station_doc.get('idCollisions', [])),
        'similarNameGroups': len(station_doc.get('similarNameGroups', [])),
        'sameNameLines': same_name_lines,
    }
