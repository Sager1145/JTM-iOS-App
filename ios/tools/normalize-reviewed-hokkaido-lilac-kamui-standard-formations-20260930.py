#!/usr/bin/env python3
"""Overlay standard series and car counts on all dated Lilac and Kamui formations."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-lilac-kamui-standard-formations-20260930'
CANDIDATE = BASE / f'candidates/jr-{SUFFIX}.json'
FACTS = BASE / f'normalized/fact-sources-{SUFFIX}.jsonl'
SOURCES = BASE / f'sources/source-registry-{SUFFIX}.jsonl'
DAY = '2026-09-30'
ISSUE = 'JR時刻表 令和8年10月号'
TIMETABLES = {
    'down': 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110',
    'up': 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111',
}
GUIDES = {
    'lilac': ('ライラック', '789系0代', 6,
              ['greensiteidai0.png', 'zensekisitei0.png'],
              'https://www.jrhokkaido.co.jp/train/tr033_01.html'),
    'kamui': ('カムイ', '789系1000代', 5, ['zensekisitei0.png'],
              'https://www.jrhokkaido.co.jp/train/tr013_01.html'),
}
EXPECTED = {
    'lilac': {
        '3001M': ('1', 'down'), '3002M': ('2', 'up'), '3003M': ('3', 'down'),
        '3005M': ('5', 'down'), '3008M': ('8', 'up'), '3011M': ('11', 'down'),
        '3012M': ('12', 'up'), '3013M': ('13', 'down'), '3014M': ('14', 'up'),
        '3016M': ('16', 'up'), '3017M': ('17', 'down'), '3020M': ('20', 'up'),
        '3022M': ('22', 'up'), '3023M': ('23', 'down'), '3024M': ('24', 'up'),
        '3025M': ('25', 'down'), '3027M': ('27', 'down'), '3032M': ('32', 'up'),
        '3033M': ('33', 'down'), '3034M': ('34', 'up'), '3037M': ('37', 'down'),
        '3038M': ('38', 'up'), '3039M': ('39', 'down'), '3041M': ('41', 'down'),
        '3044M': ('44', 'up'), '3046M': ('46', 'up'),
    },
    'kamui': {
        '2004M': ('4', 'up'), '2006M': ('6', 'up'), '2007M': ('7', 'down'),
        '2010M': ('10', 'up'), '2018M': ('18', 'up'), '2019M': ('19', 'down'),
        '2021M': ('21', 'down'), '2028M': ('28', 'up'), '2029M': ('29', 'down'),
        '2030M': ('30', 'up'), '2031M': ('31', 'down'), '2035M': ('35', 'down'),
        '2040M': ('40', 'up'), '2042M': ('42', 'up'), '2043M': ('43', 'down'),
        '2045M': ('45', 'down'),
    },
}


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n'
                            for row in rows), encoding='utf-8')


def expected_trips():
    result = {}
    for family, trains in EXPECTED.items():
        service, series, cars, icons, guide = GUIDES[family]
        for number, (public, direction) in trains.items():
            tid = f'jr-hokkaido.{family}.{public}.exact-{DAY}'
            result[number] = {'trip_id': tid, 'formation_id': f'{tid}.formation.{DAY}',
                              'family': family, 'service_name': service,
                              'public_number': public, 'direction': direction,
                              'vehicle_series': series, 'standard_car_count': cars,
                              'formation_icons': icons, 'guide_url': guide}
    return result


def validate_candidate(candidate):
    if (candidate['candidate_status'], candidate['canonical']) != ('visually_reviewed', False):
        raise ValueError('Review status changed')
    if candidate['timetable_sources'] != {
            direction: {'url': url, 'issue': ISSUE}
            for direction, url in TIMETABLES.items()}:
        raise ValueError('Timetable sources changed')
    actual = {}
    for family, family_row in candidate['families'].items():
        service, series, cars, icons, guide = GUIDES[family]
        if {key: family_row[key] for key in ('service_name', 'vehicle_series',
                                               'standard_car_count', 'formation_icons')} != {
                'service_name': service, 'vehicle_series': series,
                'standard_car_count': cars, 'formation_icons': icons}:
            raise ValueError(f'Family formation changed: {family}')
        if family_row['guide_url'] != guide:
            raise ValueError(f'Guide URL changed: {family}')
        for trip in family_row['trains']:
            if trip['train_number'] in actual:
                raise ValueError(f'Duplicate candidate train number: {trip["train_number"]}')
            actual[trip['train_number']] = {**trip, 'family': family}
    expected = expected_trips()
    if len(actual) != 42 or set(actual) != set(expected):
        raise ValueError('Expected exactly 26 Lilac and 16 Kamui trains')
    for number, row in actual.items():
        exp = expected[number]
        if any(row[key] != exp[key] for key in ('trip_id', 'public_number', 'direction', 'family')):
            raise ValueError(f'Candidate train identity changed: {number}')
    return expected


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding='utf-8'))
    expected = validate_candidate(candidate)
    existing_trips = {row['trip_id']: row
                      for path in BASE.glob('normalized/trips/*/*.jsonl')
                      for row in read_jsonl(path)}
    formation_files = {}
    formation_locations = {}
    for path in sorted(BASE.glob('normalized/trip-formations/*/*.jsonl')):
        rows = read_jsonl(path)
        formation_files[path] = rows
        for row in rows:
            if row['trip_id'] in {item['trip_id'] for item in expected.values()}:
                formation_locations.setdefault(row['trip_id'], []).append((path, row))
    facts = []
    touched = set()
    for number, item in expected.items():
        tid, family = item['trip_id'], item['family']
        trip = existing_trips.get(tid)
        if trip is None or (trip['train_number'], trip['service_id'], trip['public_number']) != (
                number, family, item['public_number']):
            raise ValueError(f'Existing train identity changed: {number}')
        locations = formation_locations.get(tid, [])
        if len(locations) != 1:
            raise ValueError(f'Expected one existing formation for {number}: {len(locations)}')
        path, row = locations[0]
        if (row['formation_id'], row['service_date'], row.get('evidence_kind')) != (
                item['formation_id'], DAY, 'planned'):
            raise ValueError(f'Existing formation identity changed: {number}')
        expected_green = True if family == 'lilac' else None
        if not row.get('all_reserved') or row.get('green_car_available') != expected_green:
            raise ValueError(f'Dated formation icons changed: {number}')
        for key, value in (('vehicle_series', item['vehicle_series']),
                           ('car_count', item['standard_car_count'])):
            if row.get(key) not in (None, value):
                raise ValueError(f'Conflicting {key}: {number}')
            row[key] = value
        qualification = (f'Official train-family guide publishes the basic '
                         f'{item["standard_car_count"]}-car {item["vehicle_series"]} formation; '
                         f'basic formation may change and does not prove the actual {DAY} dispatch '
                         'or per-car assignment.')
        if qualification not in row['notes']:
            row['notes'] = row['notes'].rstrip() + ' ' + qualification
        touched.add(path)
        source_id = f'jr-{SUFFIX}-{family}-guide'
        for field in ('vehicle_series', 'car_count'):
            facts.append({'entity_type': 'trip', 'entity_id': tid,
                          'field_name': f'formation.{field}', 'source_id': source_id,
                          'page_or_locator': (f'{item["service_name"]} train guide: '
                                              f'{item["vehicle_series"]}; basic '
                                              f'{item["standard_car_count"]}-car formation; '
                                              'formation may change'),
                          'confidence': 'medium', 'verification_status': 'partial'})
    for path in sorted(touched):
        write_jsonl(path, formation_files[path])
    source_rows = []
    for direction, url in TIMETABLES.items():
        source_rows.append({
            'source_id': f'jr-{SUFFIX}-timetable-{direction}',
            'publisher': '北海道旅客鉄道株式会社 / 株式会社交通新聞社',
            'title': f'［特急］ライラック・カムイ {"下り" if direction == "down" else "上り"} 2026年9月30日 列',
            'source_type': 'official_timetable', 'url_or_locator': url,
            'issue': ISSUE, 'publication_date': None, 'effective_date': DAY,
            'accessed_at': DAY,
            'license_status': 'terms_published_no_reuse_grant_identified',
            'redistribution_status': 'verification_only', 'automated_extraction_allowed': False,
            'notes': 'Selected date, train identities and formation icons visually reviewed. Does not publish car counts or exact-date vehicle assignments.'
        })
    for family, (service, series, cars, _, url) in GUIDES.items():
        source_rows.append({
            'source_id': f'jr-{SUFFIX}-{family}-guide',
            'publisher': '北海道旅客鉄道株式会社',
            'title': f'特急{service}（{series}）｜列車ガイド',
            'source_type': 'official_train_guide', 'url_or_locator': url,
            'issue': '2026年3月現在の情報', 'publication_date': None,
            'effective_date': None, 'accessed_at': DAY,
            'license_status': 'terms_published_no_reuse_grant_identified',
            'redistribution_status': 'verification_only', 'automated_extraction_allowed': False,
            'notes': f'Explicitly publishes the {cars}-car train-family formation as basic; warns that formations may change. Does not prove exact-date dispatch.'
        })
    write_jsonl(SOURCES, source_rows)
    write_jsonl(FACTS, facts)
    print(f'Enriched {len(expected)} existing formations across {len(touched)} owner files')


if __name__ == '__main__':
    main()
