#!/usr/bin/env python3
"""Stage the source-pinned JR East Kaiji 11 trip for 2026-09-30."""

import json
from datetime import datetime
from pathlib import Path

from reviewed_timetable_staging import (
    emit_jsonl, iter_jsonl, jr_east_forced_station_ids, stage_jr_east_single_trip,
)

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'east-kaiji11-20260930'
CANDIDATE = BASE / 'candidates/jr-east-kaiji11-20260930.json'
SOURCE = 'jr-east-kaiji11-20260930'
URL = 'https://timetables.jreast.co.jp/2610/train/050/054801.html'
TRIP = 'jr-east.kaiji.11.exact-2026-09-30'
DAY, UNTIL = '2026-09-30', '2026-10-01'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
PRINTED = [['新宿', None, '09:30'], ['立川', '09:58', '09:59'], ['八王子', '10:08', '10:09'], ['大月', '10:36', '10:39'], ['勝沼ぶどう郷', '10:55', '10:56'], ['塩山', '10:59', '11:00'], ['山梨市', '11:04', '11:04'], ['石和温泉', '11:08', '11:09'], ['甲府', '11:15', None]]
PLATFORMS = {'新宿': '１０', '立川': '６', '八王子': '４', '大月': '３', '塩山': '１', '山梨市': '３', '甲府': '１'}


def rows(pattern, exclude=None):
    return iter_jsonl(BASE, pattern, exclude)


def write(path, records):
    emit_jsonl(path, records)


def validate(c):
    expected = ('reviewed_official_html', False, TRIP, 'kaiji', 'かいじ', 'limited_express',
                '11', '3111M', '新宿', '甲府', DAY, SOURCE, URL, PLATFORMS, PRINTED)
    fields = ('candidate_status', 'canonical', 'trip_id', 'service_id', 'service_name',
              'service_class', 'public_number', 'train_number', 'origin', 'destination',
              'service_date', 'source_id', 'source_url', 'printed_platforms', 'stops')
    if tuple(c[field] for field in fields) != expected:
        raise ValueError('Reviewed Kaiji 11 column changed')
    if DAY > json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']:
        raise ValueError('Service date exceeds manifest cutoff')
    services = [r for r in rows('normalized/services*.jsonl') if r['service_id'] == 'kaiji']
    if len(services) != 1 or services[0]['canonical_name'] != 'かいじ':
        raise ValueError('Expected existing Kaiji service identity')
    if any(r['trip_id'] == TRIP for r in rows('normalized/trips/*/*.jsonl', BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')):
        raise ValueError('Duplicate Kaiji 11 trip')
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
        ROOT, [{"stops": stops}], {}, forced_codes={})


def main():
    statuses = {
        'identity': ('verified', 'high', 'Official Kaiji 11 train-detail page.'),
        'train_number': ('verified', 'high', 'Official page prints 3111M and coupling to 2111M until Otsuki.'),
        'validity_calendar': ('verified', 'high', 'September 30 td.ok cell selects this page.'),
        'origin_destination': ('verified', 'high', 'Shinjuku to Kofu endpoints printed.'),
        'stops': ('verified', 'high', 'All 9 passenger stops printed.'),
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
            'title': '特急かいじ 11号（新宿－甲府）停車駅一覧',
            'source_type': 'official_train_timetable',
            'url_or_locator': URL,
            'issue': 'JR時刻表2026年10月号',
            'publication_date': None,
            'effective_date': DAY,
            'accessed_at': DAY,
            'license_status': 'no_reuse_grant_identified',
            'redistribution_status': 'verification_only',
            'automated_extraction_allowed': False,
            'notes': 'September 30 td.ok current-variant cell and 3111M Kaiji portion of coupled train table reviewed.',
        },
        'edition_name': 'JR時刻表2026年10月号; Kaiji 11 exact 2026-09-30',
        'trip_fields': {
            'service_id': 'kaiji',
            'train_number': '3111M',
            'public_number': '11',
            'service_class': 'limited_express',
            'notes': 'Exact-date official column; dated physical route and operator segments remain unknown.',
        },
        'summary': 'Staged Kaiji 11: 1 trip, 9 passenger calls',
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
    )


if __name__ == '__main__':
    main()
