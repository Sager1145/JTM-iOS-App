#!/usr/bin/env python3
"""Overlay official train-family basic formations on four dated Hokkaido trips."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-okhotsk4-sarobetsu4-soya52d-suzuran12-standard-formations-20260930'
CANDIDATE = BASE / f'candidates/jr-{SUFFIX}.json'
FACTS = BASE / f'normalized/fact-sources-{SUFFIX}.jsonl'
SOURCES = BASE / f'sources/source-registry-{SUFFIX}.jsonl'
DAY = '2026-09-30'
ISSUE = 'JR時刻表 令和8年10月号'
TIMETABLES = {
    's111': 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111',
    's151': 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151',
}
GUIDES = {
    'okhotsk': ('オホーツク', 'キハ283系', 3, ['zensekisitei0.png'],
                 'https://www.jrhokkaido.co.jp/train/tr010_01.html'),
    'sarobetsu': ('サロベツ', 'キハ261系0代', 4,
                  ['greensiteidai0.png', 'zensekisitei0.png'],
                  'https://www.jrhokkaido.co.jp/train/tr011_01.html'),
    'soya': ('宗谷', 'キハ261系0代', 4,
             ['greensiteidai0.png', 'zensekisitei0.png'],
             'https://www.jrhokkaido.co.jp/train/tr008_01.html'),
    'suzuran': ('すずらん', None, 5, ['zensekisitei0.png'],
                'https://www.jrhokkaido.co.jp/train/tr012_01.html'),
}
EXPECTED = {
    'okhotsk': ('74D', '4', 'jr-hokkaido.okhotsk.4.exact-2026-09-30'),
    'sarobetsu': ('6064D', '4',
                  'jr-hokkaido.sarobetsu.4-dated-20260930.2026-09-30'),
    'soya': ('52D', None, 'jr-hokkaido.soya.52d.exact-2026-09-30'),
    'suzuran': ('1012M', '12', 'jr-hokkaido.suzuran.12.exact-2026-09-30'),
}


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n'
                            for row in rows), encoding='utf-8')


def validate_candidate(candidate):
    if (candidate['candidate_status'], candidate['canonical']) != ('visually_reviewed', False):
        raise ValueError('Review status changed')
    if candidate['timetable_sources'] != {
            key: {'url': url, 'issue': ISSUE} for key, url in TIMETABLES.items()}:
        raise ValueError('Timetable sources changed')
    actual = {}
    for family, family_row in candidate['families'].items():
        service, series, cars, icons, guide = GUIDES[family]
        expected_fields = {
            'service_name': service, 'guide_url': guide, 'vehicle_series': series,
            'standard_car_count': cars, 'formation_icons': icons,
        }
        if any(family_row[key] != value for key, value in expected_fields.items()):
            raise ValueError(f'Family formation changed: {family}')
        if family == 'suzuran' and family_row['published_vehicle_series'] != [
                '785系', '789系1000代']:
            raise ValueError('Suzuran published alternatives changed')
        if len(family_row['trains']) != 1:
            raise ValueError(f'Expected one train for {family}')
        train = family_row['trains'][0]
        number, public, trip_id = EXPECTED[family]
        if (train['train_number'], train['public_number'], train['trip_id']) != (
                number, public, trip_id):
            raise ValueError(f'Train identity changed: {family}')
        actual[family] = {**train, 'service_name': service, 'vehicle_series': series,
                          'standard_car_count': cars, 'formation_icons': icons,
                          'guide_url': guide}
    if set(actual) != set(EXPECTED):
        raise ValueError('Expected exactly four service families')
    return actual


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding='utf-8'))
    expected = validate_candidate(candidate)
    existing_trips = {row['trip_id']: row
                      for path in BASE.glob('normalized/trips/*/*.jsonl')
                      for row in read_jsonl(path)}
    target_ids = {item['trip_id'] for item in expected.values()}
    formation_files = {}
    formation_locations = {}
    for path in sorted(BASE.glob('normalized/trip-formations/*/*.jsonl')):
        rows = read_jsonl(path)
        formation_files[path] = rows
        for row in rows:
            if row['trip_id'] in target_ids:
                formation_locations.setdefault(row['trip_id'], []).append((path, row))
    facts = []
    touched = set()
    for family, item in expected.items():
        tid = item['trip_id']
        trip = existing_trips.get(tid)
        if trip is None or (trip['train_number'], trip['service_id'], trip['public_number']) != (
                item['train_number'], family, item['public_number']):
            raise ValueError(f'Existing train identity changed: {family}')
        locations = formation_locations.get(tid, [])
        if len(locations) != 1:
            raise ValueError(f'Expected one existing formation for {family}: {len(locations)}')
        path, row = locations[0]
        formation_id = f'{tid}.formation.{DAY}'
        if (row['formation_id'], row['service_date'], row.get('evidence_kind')) != (
                formation_id, DAY, 'planned'):
            raise ValueError(f'Existing formation identity changed: {family}')
        expected_green = True if family in ('sarobetsu', 'soya') else None
        if not row.get('all_reserved') or row.get('green_car_available') != expected_green:
            raise ValueError(f'Dated formation icons changed: {family}')
        fields = [('car_count', item['standard_car_count'])]
        if item['vehicle_series'] is not None:
            fields.insert(0, ('vehicle_series', item['vehicle_series']))
        for key, value in fields:
            if row.get(key) not in (None, value):
                raise ValueError(f'Conflicting {key}: {family}')
            row[key] = value
        if family == 'suzuran':
            qualification = (
                'Official train-family guide publishes separate basic 5-car 785-series and '
                '789-series 1000-subseries formations; the dated page does not select a series. '
                f'Basic formation may change and does not prove the actual {DAY} dispatch or '
                'per-car assignment.')
        else:
            qualification = (
                f'Official train-family guide publishes the basic '
                f'{item["standard_car_count"]}-car {item["vehicle_series"]} formation; basic '
                f'formation may change and does not prove the actual {DAY} dispatch or per-car '
                'assignment.')
        if qualification not in row['notes']:
            row['notes'] = row['notes'].rstrip() + ' ' + qualification
        touched.add(path)
        source_id = f'jr-{SUFFIX}-{family}-guide'
        for key, _ in fields:
            locator = (f'{item["service_name"]} train guide: separate basic 5-car 785-series '
                       'and 789-series 1000-subseries formations; exact series unknown'
                       if family == 'suzuran' else
                       f'{item["service_name"]} train guide: {item["vehicle_series"]}; basic '
                       f'{item["standard_car_count"]}-car formation; formation may change')
            facts.append({'entity_type': 'trip', 'entity_id': tid,
                          'field_name': f'formation.{key}', 'source_id': source_id,
                          'page_or_locator': locator, 'confidence': 'medium',
                          'verification_status': 'partial'})
    for path in sorted(touched):
        write_jsonl(path, formation_files[path])

    source_rows = []
    for page, url in TIMETABLES.items():
        source_rows.append({
            'source_id': f'jr-{SUFFIX}-timetable-{page}',
            'publisher': '北海道旅客鉄道株式会社 / 株式会社交通新聞社',
            'title': f'JR北海道 列車時刻表 {page} 2026年9月30日 列',
            'source_type': 'official_timetable', 'url_or_locator': url,
            'issue': ISSUE, 'publication_date': None, 'effective_date': DAY,
            'accessed_at': DAY,
            'license_status': 'terms_published_no_reuse_grant_identified',
            'redistribution_status': 'verification_only',
            'automated_extraction_allowed': False,
            'notes': ('Selected date, train identities and formation icons visually reviewed. '
                      'Does not publish car counts or exact-date vehicle assignments.'),
        })
    for family, (service, series, cars, _, url) in GUIDES.items():
        if family == 'suzuran':
            title = '特急すずらん（785系・789系1000代）｜列車ガイド'
            notes = ('Explicitly publishes separate 5-car basic formations for 785 series and '
                     '789 series 1000 subseries; warns that formations may change. Does not '
                     'identify the exact-date series or dispatch.')
        else:
            title = f'特急{service}（{series}）｜列車ガイド'
            notes = (f'Explicitly publishes the {cars}-car train-family formation as basic; '
                     'warns that formations may change. Does not prove exact-date dispatch.')
        source_rows.append({
            'source_id': f'jr-{SUFFIX}-{family}-guide',
            'publisher': '北海道旅客鉄道株式会社', 'title': title,
            'source_type': 'official_train_guide', 'url_or_locator': url,
            'issue': '2026年3月現在の情報', 'publication_date': None,
            'effective_date': None, 'accessed_at': DAY,
            'license_status': 'terms_published_no_reuse_grant_identified',
            'redistribution_status': 'verification_only',
            'automated_extraction_allowed': False, 'notes': notes,
        })
    write_jsonl(SOURCES, source_rows)
    write_jsonl(FACTS, facts)
    print(f'Enriched {len(expected)} existing formations across {len(touched)} owner files')


if __name__ == '__main__':
    main()
