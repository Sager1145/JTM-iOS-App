#!/usr/bin/env python3
"""Stage the source-pinned JR East Kaiji 2 trip for 2026-09-30."""

import json
from datetime import datetime
from pathlib import Path

from reviewed_timetable_staging import (
    emit_jsonl, iter_jsonl, jr_east_forced_station_ids, stage_jr_east_single_trip,
)

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'east-kaiji2-20260930'
CANDIDATE = BASE / 'candidates/jr-east-kaiji2-20260930.json'
SOURCE = 'jr-east-kaiji2-20260930'
URL = 'https://timetables.jreast.co.jp/2610/train/085/087651.html'
TRIP = 'jr-east.kaiji.2.exact-2026-09-30'
DAY, UNTIL = '2026-09-30', '2026-10-01'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
PRINTED = [
    ['竜王', None, '06:58'], ['甲府', '07:02', '07:03'],
    ['石和温泉', '07:08', '07:09'], ['山梨市', '07:13', '07:13'],
    ['塩山', '07:17', '07:18'], ['大月', '07:36', '07:36'],
    ['八王子', '08:03', '08:04'], ['立川', '08:12', '08:13'],
    ['新宿', '08:43', '08:44'], ['東京', '08:59', None],
]
PLATFORMS = {'竜王': '２', '甲府': '２', '山梨市': '１', '塩山': '３',
             '大月': '５', '八王子': '２', '立川': '３', '新宿': '７', '東京': '２'}


def rows(pattern, exclude=None):
    return iter_jsonl(BASE, pattern, exclude)


def write(path, records):
    emit_jsonl(path, records)


def validate(c):
    expected = ('reviewed_official_html', False, TRIP, 'kaiji', 'かいじ', 'limited_express',
                '2', '5102M', '竜王', '東京', DAY, SOURCE, URL, PLATFORMS, PRINTED)
    fields = ('candidate_status', 'canonical', 'trip_id', 'service_id', 'service_name',
              'service_class', 'public_number', 'train_number', 'origin', 'destination',
              'service_date', 'source_id', 'source_url', 'printed_platforms', 'stops')
    if tuple(c[field] for field in fields) != expected:
        raise ValueError('Reviewed Kaiji 2 column changed')
    if DAY > json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']:
        raise ValueError('Service date exceeds manifest cutoff')
    if any(r['service_id'] == 'kaiji' for r in rows('normalized/services*.jsonl', BASE / f'normalized/services-{SUFFIX}.jsonl')):
        raise ValueError('Kaiji service already exists; reconcile before staging')
    if any(r['trip_id'] == TRIP for r in rows('normalized/trips/*/*.jsonl', BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')):
        raise ValueError('Duplicate Kaiji 2 trip')
    previous = None
    for _, arrival, departure in c['stops']:
        for clock in (arrival, departure):
            if clock is None:
                continue
            parsed = datetime.strptime(clock, '%H:%M')
            if previous is not None and parsed < previous:
                raise ValueError('Clock reversal')
            previous = parsed


def station_ids(stops):
    return jr_east_forced_station_ids(
        ROOT, [{"stops": stops}], {}, forced_codes={'東京': {'003766'}})


def main():
    statuses = {
        'identity': ('verified', 'high', 'Official Kaiji 2 train-detail page.'),
        'train_number': ('verified', 'high', 'Official page prints 5102M.'),
        'validity_calendar': ('verified', 'high', 'September 30 td.ok cell selects this page.'),
        'origin_destination': ('verified', 'high', 'Ryuō to Tokyo endpoints printed.'),
        'stops': ('verified', 'high', 'All 10 passenger stops printed.'),
        'times': ('verified', 'high', 'All printed arrival/departure clocks captured.'),
        'station_refs': ('verified', 'high', 'Current JR East N02 station-group matches.'),
        'operator': ('unknown', 'low', 'No dated ordered operator segments.'),
        'route_lines': ('unknown', 'low', 'No dated ordered physical line identities.'),
        'provenance': ('partial', 'medium', 'Official page pinned; reuse grant unconfirmed.'),
    }
    copy = {
        'source_record': {
            'source_id': SOURCE,
            'publisher': '東日本旅客鉄道株式会社 / 株式会社交通新聞社',
            'title': '特急かいじ 2号（竜王－東京）停車駅一覧',
            'source_type': 'official_train_timetable',
            'url_or_locator': URL,
            'issue': 'JR時刻表2026年10月号',
            'publication_date': None,
            'effective_date': DAY,
            'accessed_at': DAY,
            'license_status': 'no_reuse_grant_identified',
            'redistribution_status': 'verification_only',
            'automated_extraction_allowed': False,
            'notes': 'September 30 td.ok current-variant cell and full 5102M station table reviewed.',
        },
        'edition_name': 'JR時刻表2026年10月号; Kaiji 2 exact 2026-09-30',
        'trip_fields': {
            'service_id': 'kaiji',
            'train_number': '5102M',
            'public_number': '2',
            'service_class': 'limited_express',
            'notes': 'Exact-date official column; dated physical route and operator segments remain unknown.',
        },
        'summary': 'Staged Kaiji 2: 1 trip, 10 passenger calls',
    }
    stage_jr_east_single_trip(
        base=BASE,
        candidate_path=CANDIDATE,
        suffix=SUFFIX,
        trip_id=TRIP,
        day=DAY,
        until=UNTIL,
        source_id=SOURCE,
        weekdays=WEEKDAYS,
        platforms=PLATFORMS,
        validate=validate,
        station_ids=station_ids,
        rows=rows,
        write=write,
        statuses=statuses,
        copy=copy,
        extra_outputs=lambda c: {BASE / f'normalized/services-{SUFFIX}.jsonl': [
            {
                'service_id': 'kaiji',
                'canonical_name': 'かいじ',
                'service_class': 'limited_express',
                'jr_scope': 'jr',
                'historical_generation': 1,
                'first_verified_date': DAY,
                'last_verified_date': DAY,
            },
        ], BASE / f'normalized/service-name-periods-{SUFFIX}.jsonl': [
            {
                'service_id': 'kaiji',
                'name': 'かいじ',
                'language': 'ja',
                'valid_from': DAY,
                'valid_until': UNTIL,
                'name_type': 'display',
                'source_id': SOURCE,
            },
        ]},
    )


if __name__ == '__main__':
    main()
