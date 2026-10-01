#!/usr/bin/env python3
"""Add two missing, source-pinned planned Taisetsu formation rows."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-taisetsu3591d-3592d-planned-formations-20260930'
CANDIDATE = BASE / f'candidates/jr-{SUFFIX}.json'
OUTPUT = BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl'
FACTS = BASE / f'normalized/fact-sources-{SUFFIX}.jsonl'
SOURCES = BASE / f'sources/source-registry-{SUFFIX}.jsonl'
DAY = '2026-09-30'
GUIDE_URL = 'https://www.jrhokkaido.co.jp/global/cn/train/guide/abashiri.html'
GUIDE_SOURCE = f'jr-{SUFFIX}-guide'
EXPECTED = {
    '3591D': ('jr-hokkaido.taisetsu.3591d.exact-2026-09-30',
              'jr-hokkaido-okhotsk1-taisetsu3591d-20260930',
              'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110'),
    '3592D': ('jr-hokkaido.taisetsu.3592d.exact-2026-09-30',
              'jr-hokkaido-okhotsk2-taisetsu3592d-20260930',
              'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111'),
}


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
    if candidate['guide_source']['url'] != GUIDE_URL:
        raise ValueError('Guide source changed')
    trips = candidate['trips']
    if len(trips) != 2 or {row['train_number'] for row in trips} != set(EXPECTED):
        raise ValueError('Expected exactly 3591D and 3592D')

    canonical_trips = {row['trip_id']: row
                       for path in BASE.glob('normalized/trips/*/*.jsonl')
                       for row in read_jsonl(path)}
    existing_formations = [row
                           for path in BASE.glob('normalized/trip-formations/*/*.jsonl')
                           if path != OUTPUT
                           for row in read_jsonl(path)]
    existing_keys = {(row['trip_id'], row['service_date']) for row in existing_formations}
    source_ids = {row['source_id']
                  for path in BASE.glob('sources/*.jsonl')
                  if path != SOURCES
                  for row in read_jsonl(path)}

    formations = []
    facts = []
    for trip in trips:
        tid, source_id, url = EXPECTED[trip['train_number']]
        expected = (tid, source_id, url, DAY, '大雪', [], False, None, None, None)
        actual = (trip['existing_trip_id'], trip['timetable_source_id'], trip['timetable_url'],
                  trip['service_date'], trip['service_name'], trip['formation_icons'],
                  trip['all_reserved'], trip['vehicle_series'], trip['car_count'],
                  trip['green_car_available'])
        if actual != expected:
            raise ValueError(f'Formation candidate changed: {trip["train_number"]}')
        if canonical_trips.get(tid, {}).get('train_number') != trip['train_number']:
            raise ValueError(f'Existing train identity changed: {trip["train_number"]}')
        if source_id not in source_ids:
            raise ValueError(f'Existing timetable source missing: {source_id}')
        if (tid, DAY) in existing_keys:
            raise ValueError(f'Formation already exists outside overlay: {trip["train_number"]}')
        formations.append({
            'formation_id': trip['formation_id'], 'trip_id': tid, 'service_date': DAY,
            'evidence_kind': 'planned', 'all_reserved': False, 'source_id': source_id,
            'notes': ('Selected-date timetable formation cell is blank; current official service guide '
                      'states all seats are unreserved. Vehicle series, car count, Green-car availability '
                      'and the actual 2026-09-30 dispatched set remain unknown.'),
        })
        facts.append({
            'entity_type': 'trip', 'entity_id': tid, 'field_name': 'formation.all_reserved',
            'source_id': GUIDE_SOURCE,
            'page_or_locator': candidate['guide_source']['locator'],
            'confidence': 'high', 'verification_status': 'verified',
        })

    source = {
        'source_id': GUIDE_SOURCE, 'publisher': '北海道旅客鉄道株式会社',
        'title': '網走方面｜列車ガイド｜特別快速大雪号',
        'source_type': 'official_train_guide', 'url_or_locator': GUIDE_URL,
        'issue': '掲載内容は2026年3月現在', 'publication_date': None,
        'effective_date': None, 'accessed_at': DAY,
        'license_status': 'terms_published_no_reuse_grant_identified',
        'redistribution_status': 'verification_only', 'automated_extraction_allowed': False,
        'notes': ('Current official guide identifies 特別快速大雪 as 旭川–網走 and all-unreserved. '
                  'It does not identify an exact-date vehicle series, car count, Green car or actual set.'),
    }
    write_jsonl(OUTPUT, formations)
    write_jsonl(FACTS, facts)
    write_jsonl(SOURCES, [source])
    print('Added 2 missing planned Taisetsu formation rows; vehicle and car count remain unknown')


if __name__ == '__main__':
    main()
