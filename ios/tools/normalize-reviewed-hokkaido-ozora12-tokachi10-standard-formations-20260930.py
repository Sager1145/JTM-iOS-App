#!/usr/bin/env python3
"""Enrich existing Ozora/Tokachi rows with official basic formation fields."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-ozora12-tokachi10-standard-formations-20260930'
CANDIDATE = BASE / f'candidates/jr-{SUFFIX}.json'
FORMATIONS = BASE / 'normalized/trip-formations/reviewed-formations-20260930/seeds.jsonl'
FACTS = BASE / f'normalized/fact-sources-{SUFFIX}.jsonl'
DAY = '2026-09-30'


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n'
                            for row in rows), encoding='utf-8')


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding='utf-8'))
    if (candidate['candidate_status'], candidate['canonical']) != ('visually_reviewed', False):
        raise ValueError('Review status changed')
    families = candidate['families']
    expected = {'ozora': (12, 'https://www.jrhokkaido.co.jp/train/tr007_01.html'),
                'tokachi': (10, 'https://www.jrhokkaido.co.jp/train/tr005_01.html')}
    if set(families) != set(expected):
        raise ValueError('Expected Ozora and Tokachi only')
    for key, (count, url) in expected.items():
        family = families[key]
        if (len(family['train_numbers']), family['vehicle_series'],
                family['standard_car_count'], family['guide_url']) != (
                count, 'キハ261系1000代', 4, url):
            raise ValueError(f'Guide-level formation changed: {key}')

    trips = [row for path in BASE.glob('normalized/trips/*/*.jsonl')
             for row in read_jsonl(path)]
    by_service_number = {(row.get('service_id'), row['train_number']): row for row in trips}
    formations = read_jsonl(FORMATIONS)
    by_trip = {row['trip_id']: row for row in formations if row['service_date'] == DAY}
    if len({row['formation_id'] for row in formations}) != len(formations):
        raise ValueError('Duplicate pre-existing formation IDs')
    source_rows = {row['source_id']: row for path in BASE.glob('sources/*.jsonl')
                   for row in read_jsonl(path)}
    facts = []
    touched = set()
    for service_id, family in families.items():
        source = source_rows.get(family['guide_source_id'])
        if source is None or source['url_or_locator'] != family['guide_url']:
            raise ValueError(f'Guide registry mismatch: {service_id}')
        for number in family['train_numbers']:
            trip = by_service_number.get((service_id, number))
            if trip is None:
                raise ValueError(f'Existing trip missing: {service_id} {number}')
            row = by_trip.get(trip['trip_id'])
            if row is None or row.get('evidence_kind') != 'planned':
                raise ValueError(f'Existing planned formation missing: {number}')
            for key, value in (('vehicle_series', family['vehicle_series']),
                               ('car_count', family['standard_car_count'])):
                if row.get(key) not in (None, value):
                    raise ValueError(f'Conflicting {key}: {number}')
                row[key] = value
            note = ('Official train-family guide publishes a basic 4-car キハ261系1000代 formation; '
                    f'the guide warns that formations may change, so this does not prove the actual {DAY} dispatch.')
            if note not in row['notes']:
                row['notes'] = row['notes'].rstrip() + ' ' + note
            touched.add(trip['trip_id'])
            for field in ('vehicle_series', 'car_count'):
                facts.append({
                    'entity_type': 'trip', 'entity_id': trip['trip_id'],
                    'field_name': f'formation.{field}', 'source_id': family['guide_source_id'],
                    'page_or_locator': (f'{family["service_name"]} guide and basic-formation image: '
                                        f'{family["vehicle_series"]}, 4 cars; formation may change'),
                    'confidence': 'medium', 'verification_status': 'partial',
                })
    if len(touched) != 22:
        raise ValueError('Expected exactly 22 enriched formations')
    write_jsonl(FORMATIONS, formations)
    write_jsonl(FACTS, facts)
    print('Enriched 22 existing Ozora/Tokachi formations with guide-level 4-car standard')


if __name__ == '__main__':
    main()
