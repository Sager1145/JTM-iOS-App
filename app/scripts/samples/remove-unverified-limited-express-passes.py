#!/usr/bin/env python3
"""Remove unsupported physical-route claims from Japan limited-express samples.

The September database cannot establish July/May sample routes. Retain the five
ride-local physical sequences explicitly reviewed on the exact service date.
Other sample passenger calls retain their existing historical verification status.
Regenerate precomputed parts after applying this script: solved geometry is a
visualization hypothesis, never evidence for timetable passing stations.
"""
import argparse
import copy
import json
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
DATA = APP / 'data'
REVIEW = DATA / 'sample-timetable-reviews.json'
AUDIT = DATA / 'sample-passing-station-audit.json'
STORES = (DATA / 'train-store.json', DATA / 'special-samples/new-year-grand-loop.json',
          DATA / 'special-samples/tokyo-limited-express-loop.json')
DISCLOSURE = '通過駅・経由線は未検証のため省略。地図の経路は停車駅間の推定表示で、実際の列車経路の証明ではありません。'


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def clean_train(train, review=None):
    """Keep source-listed passing stations only with exact-date physical review."""
    result = copy.deepcopy(train)
    if train.get('train_type') not in ('特急', '寝台特急'):
        return result, []
    if review is not None and review['date'] != train['date']:
        raise ValueError('Physical route evidence does not cover the sample service date')
    if review and review['status'] == 'ridden_timetable_verified':
        return result, []
    removed = [stop for stop in train['stops'] if stop.get('stop_type') == 'pass_through']
    if train['stops'][0] in removed or train['stops'][-1] in removed:
        raise ValueError('A ridden endpoint cannot be removed as an unverified pass')
    result['stops'] = [stop for stop in result['stops'] if stop.get('stop_type') != 'pass_through']
    # Old station-by-station sections were constructed from the same guessed
    # physical path. Do not union their line names or retain hidden via anchors.
    result['route_sections'] = []
    for field in ('preferred_line_names', 'preferred_operator_names'):
        result.get('route_policy', {}).pop(field, None)
    if review and review.get('section_number_boundary'):
        boundary = review['section_number_boundary']
        after = False
        for left, right in zip(result['stops'], result['stops'][1:]):
            after |= left['name'] == boundary['station']
            result['route_sections'].append({
                'from_n02_station_code': left['n02_station_code'],
                'to_n02_station_code': right['n02_station_code'],
                'number': boundary['after'] if after else boundary['before'],
            })
        if not after:
            raise ValueError('Reviewed number-change boundary is missing')
    notes = result.get('notes') or ''
    if DISCLOSURE not in notes:
        result['notes'] = (notes + '\n' + DISCLOSURE).strip()
    return result, [stop['name'] for stop in removed]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--canonical-only', action='store_true',
                        help='With --check, verify canonical inputs before final cache regeneration')
    args = parser.parse_args()
    reviews = {row['train_id']: row for row in read(REVIEW)['reviews']}
    prior = {row['train_id']: row for row in read(AUDIT)['inventory']} if AUDIT.exists() else {}
    inventory = []
    changed = []
    for path in STORES:
        store = read(path)
        for train in store['trains']:
            if train.get('train_type') not in ('特急', '寝台特急'):
                continue
            review = reviews.get(train['id'])
            updated, removed = clean_train(train, review)
            if updated != train:
                if args.check:
                    raise AssertionError(f"Unsupported physical claims remain: {train['id']}")
                train.clear()
                train.update(updated)
                changed.append(train['id'])
            retained = bool(review and review['status'] == 'ridden_timetable_verified')
            old = prior.get(train['id'], {})
            inventory.append({
                'train_id': train['id'], 'service_date': train['date'],
                'status': 'source_reviewed_physical_sequence' if retained else 'passenger_calls_only_physical_route_unverified',
                'removed_passing_station_names': old.get('removed_passing_station_names', removed),
                'retained_source_listed_passing_station_count': sum(s.get('stop_type') == 'pass_through' for s in train['stops']),
                'review_url': review['url'] if review else None,
                'passenger_timetable_verified': bool(review),
            })
        if not args.check:
            save(path, store)
    audit = {
        'format': 1,
        'scope': 'Japan limited-express and sleeper samples; exact service dates only. No September timetable backprojection.',
        'route_geometry_meaning': 'Precomputed shortest paths are visualization hypotheses, not timetable facts or confirmed passing stations.',
        'counts': {
            'rides_audited': len(inventory),
            'source_reviewed_physical_sequences_retained': sum(r['status'] == 'source_reviewed_physical_sequence' for r in inventory),
            'rides_with_unverified_physical_routes': sum(r['status'] != 'source_reviewed_physical_sequence' for r in inventory),
            'unsupported_passing_station_rows_removed': sum(len(r['removed_passing_station_names']) for r in inventory),
            'source_listed_passing_station_rows_retained': sum(r['retained_source_listed_passing_station_count'] for r in inventory),
        }, 'inventory': inventory,
    }
    if args.check:
        assert read(AUDIT) == audit, 'Passing-station audit stale'
        for path in (() if args.canonical_only else STORES):
            directory = DATA / ('sample-data' if path.name == 'train-store.json' else path.stem + '-data')
            canonical = read(path)
            assert canonical == read(directory / 'sample-full.json'), f'Generated full sample stale: {path}'
            manifest = read(directory / 'manifest.json')
            assert len(canonical['trains']) == manifest['total'] == len(manifest['parts'])
            for train, part_name in zip(canonical['trains'], manifest['parts']):
                assert read(directory / (part_name + '.json'))['train'] == train, f'Generated part stale: {train["id"]}'
    else:
        save(AUDIT, audit)
    print(json.dumps({'changed_rides': changed, **audit['counts']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
