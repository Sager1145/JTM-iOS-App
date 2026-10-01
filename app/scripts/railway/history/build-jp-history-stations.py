#!/usr/bin/env python3
"""Build explicit station entities and dated name/operator/line memberships.

N02 group codes are observed identity keys, not proof of uninterrupted historical
identity. An explicit reviewed station_entity_id overrides them. Uncoded stations
retain a geometry-based provisional identity rather than a fuzzy name merge.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

from temporal_source import coords, select


def token(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:24]


def build(source, overlay, stations):
    current = copy.deepcopy(stations)
    for stamp in overlay['retirements']:
        if 'stations' not in stamp['match'].get('targets', ['sections', 'stations']):
            continue
        for station in select(current, {'line': stamp['match']['line_name'],
                                        'operator': stamp['match']['operator']}, stamp['match']['bbox']):
            p = station['properties']
            p['history_id'] = stamp['history_id']
            for key in ('valid_from', 'valid_to'):
                if stamp.get(key):
                    p[key] = stamp[key]
    events = source['events'] + source.get('temporal_events', [])
    entities = {}
    memberships = {}
    for feature in current + overlay['stations']:
        p = feature['properties']
        hid = p.get('history_id', '')
        owners = [event for event in events if hid == event['id'] or hid.startswith(event['id'] + '.')]
        event = max(owners, key=lambda e: len(e['id']), default={})
        group = p.get('n02_group_code')
        identity = event.get('station_entity_id')
        basis = 'reviewed_source_identity'
        if not identity:
            basis = 'observed_n02_group_code' if group else 'provisional_geometry_identity'
            identity = 'jp.station.' + token(['n02_group', group] if group else ['geometry', coords(feature)])
        entity = entities.setdefault(identity, {'station_entity_id': identity,
            'identity_basis': basis, 'memberships': []})
        name, line, operator = p['station_name'], p['line_name'], p['operator']
        mid = 'jp.station-membership.' + token([identity, name, line, operator])
        membership = memberships.setdefault(mid, {'station_membership_id': mid,
            'station_entity_id': identity, 'station_name': name, 'line_name': line,
            'operator': operator, 'observations': []})
        if mid not in entity['memberships']:
            entity['memberships'].append(mid)
        pair = p.get('service_validity', [p.get('valid_from'), p.get('valid_to')])
        observation = {'service_validity': pair, 'geometry_id': token(feature['geometry']),
            'n02_station_code': p.get('n02_station_code'), 'n02_group_code': group,
            'history_id': hid or None, 'source_event_id': event.get('id'),
            'source': p.get('source'), 'review_status': event.get('review', {}).get('status',
                'current_snapshot_observation' if not hid else 'legacy_curated')}
        if observation not in membership['observations']:
            membership['observations'].append(observation)
    return {'schema_version': '1', 'history_revision': overlay['revision'],
        'policy': {'fuzzy_name_identity_merge': False,
            'unbounded_dates_mean_unknown': True, 'all_historical_names_verified': False},
        'summary': {'station_entities': len(entities), 'station_memberships': len(memberships),
                    'provisional_entities': sum(e['identity_basis'] == 'provisional_geometry_identity'
                                                for e in entities.values())},
        'entities': sorted(entities.values(), key=lambda e: e['station_entity_id']),
        'memberships': sorted(memberships.values(), key=lambda m: m['station_membership_id'])}


def main():
    root = Path(__file__).resolve().parents[4]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=str(root / 'app/data/generated/jp-history-stations.json'))
    args = parser.parse_args()
    read = lambda path: json.loads((root / path).read_text())
    value = build(read('app/scripts/railway/jp-rail-history-events.json'),
                  read('app/data/rail-history.json'), read('app/data/stations.json')['features'])
    Path(args.output).write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n')
    print(json.dumps(value['summary'], sort_keys=True))


if __name__ == '__main__':
    main()
