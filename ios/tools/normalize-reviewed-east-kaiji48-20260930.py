#!/usr/bin/env python3
"""Stage the source-pinned JR East Kaiji 48 trip for 2026-09-30."""

import json
from datetime import datetime
from pathlib import Path

from reviewed_timetable_staging import (
    emit_jsonl, iter_jsonl, jr_east_forced_station_ids, stage_jr_east_single_trip,
)

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'east-kaiji48-20260930'
CANDIDATE = BASE / 'candidates/jr-east-kaiji48-20260930.json'
SOURCE = 'jr-east-kaiji48-20260930'
URL = 'https://timetables.jreast.co.jp/2610/train/060/063471.html'
TRIP = 'jr-east.kaiji.48.exact-2026-09-30'
DAY, UNTIL = '2026-09-30', '2026-10-01'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
PRINTED = [['甲府', None, '18:01'], ['石和温泉', '18:06', '18:06'], ['山梨市', '18:10', '18:11'], ['塩山', '18:15', '18:15'], ['大月', '18:40', '18:43'], ['八王子', '19:09', '19:10'], ['立川', '19:19', '19:20'], ['新宿', '19:48', None]]
PLATFORMS = {'甲府': '２', '山梨市': '１', '塩山': '３', '大月': '５', '八王子': '２', '立川': '３', '新宿': '９'}


def rows(pattern, exclude=None):
    return iter_jsonl(BASE, pattern, exclude)


def write(path, records):
    emit_jsonl(path, records)


def validate(c):
    expected = ('reviewed_official_html', False, TRIP, 'kaiji', 'かいじ', 'limited_express',
                '48', '3148M', '甲府', '新宿', DAY, SOURCE, URL, PLATFORMS, PRINTED)
    fields = ('candidate_status', 'canonical', 'trip_id', 'service_id', 'service_name',
              'service_class', 'public_number', 'train_number', 'origin', 'destination',
              'service_date', 'source_id', 'source_url', 'printed_platforms', 'stops')
    if tuple(c[field] for field in fields) != expected:
        raise ValueError('Reviewed Kaiji 48 column changed')
    if c['calendar_observation'] != {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'} or c['equipment'] != ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'] or c['formation'] is not None:
        raise ValueError('Calendar/equipment/formation changed')
    if c['printed_operating_label'] != '平日運転' or c['printed_remarks'] != ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です'] or c['printed_coupling'] != '大月－新宿は2148Mを併結' or c['direction'] != 'up':
        raise ValueError('Printed operating/seat/coupling facts changed')
    if DAY > json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']:
        raise ValueError('Service date exceeds manifest cutoff')
    services = [r for r in rows('normalized/services*.jsonl') if r['service_id'] == 'kaiji']
    if len(services) != 1 or services[0]['canonical_name'] != 'かいじ':
        raise ValueError('Expected existing Kaiji service identity')
    if any(r['trip_id'] == TRIP for r in rows('normalized/trips/*/*.jsonl', BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')):
        raise ValueError('Duplicate Kaiji 48 trip')
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
        'identity': ('verified', 'high', 'Official Kaiji 48 train-detail page.'),
        'train_number': ('verified', 'high', 'Official page prints 3148M.'),
        'validity_calendar': ('verified', 'high', 'September 30 td.ok cell selects this page.'),
        'origin_destination': ('verified', 'high', '甲府 to 新宿 endpoints printed.'),
        'stops': ('verified', 'high', 'All 8 passenger stops printed.'),
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
            'title': '特急かいじ 48号（甲府－新宿）停車駅一覧',
            'source_type': 'official_train_timetable',
            'url_or_locator': URL,
            'issue': 'JR時刻表2026年10月号',
            'publication_date': None,
            'effective_date': DAY,
            'accessed_at': DAY,
            'license_status': 'no_reuse_grant_identified',
            'redistribution_status': 'verification_only',
            'automated_extraction_allowed': False,
            'notes': 'September 30 td.ok current-variant cell and full 3148M station table reviewed.',
        },
        'edition_name': 'JR時刻表2026年10月号; Kaiji 48 exact 2026-09-30',
        'trip_fields': {
            'service_id': 'kaiji',
            'train_number': '3148M',
            'public_number': '48',
            'direction': 'up',
            'service_class': 'limited_express',
            'notes': '大月－新宿は2148Mを併結; Exact-date official Kaiji column; dated physical route/operator segments and formation remain unknown.',
        },
        'summary': 'Staged Kaiji 48: 1 trip, 8 passenger calls',
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
