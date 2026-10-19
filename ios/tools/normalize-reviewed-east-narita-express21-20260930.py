#!/usr/bin/env python3
"""Stage the source-pinned JR East Narita Express 21 trip for 2026-09-30."""

import json
from datetime import datetime
from pathlib import Path

from reviewed_timetable_staging import (
    emit_jsonl, iter_jsonl, jr_east_forced_station_ids, stage_jr_east_single_trip,
)

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'east-narita-express21-20260930'
CANDIDATE = BASE / 'candidates/jr-east-narita-express21-20260930.json'
SOURCE = 'jr-east-narita-express21-20260930'
URL = 'https://timetables.jreast.co.jp/2610/train/075/076511.html'
TRIP = 'jr-east.narita-express.21.exact-2026-09-30'
DAY, UNTIL = '2026-09-30', '2026-10-01'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
PRINTED = [['新宿', None, '11:08'], ['渋谷', '11:13', '11:14'], ['品川', '11:22', '11:23'], ['東京', '11:30', '11:33'], ['空港第２ビル', '12:27', '12:29'], ['成田空港', '12:31', None]]
PLATFORMS = {'新宿': '５', '品川': '１３', '東京': '４'}


def rows(pattern, exclude=None):
    return iter_jsonl(BASE, pattern, exclude)


def write(path, records):
    emit_jsonl(path, records)


def validate(c):
    expected = ('reviewed_official_html', False, TRIP, 'narita-express', '成田エクスプレス', 'limited_express',
                '21', '2221M', '新宿', '成田空港', DAY, SOURCE, URL, PLATFORMS, PRINTED)
    fields = ('candidate_status', 'canonical', 'trip_id', 'service_id', 'service_name',
              'service_class', 'public_number', 'train_number', 'origin', 'destination',
              'service_date', 'source_id', 'source_url', 'printed_platforms', 'stops')
    if tuple(c[field] for field in fields) != expected:
        raise ValueError('Reviewed Narita Express 21 column changed')
    if c['calendar_observation'] != {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'} or c['equipment'] != ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'] or c['formation'] is not None or c['train_number_segments'] != [{'from_sequence': 1, 'to_sequence': 4, 'train_number': '2221M'}, {'from_sequence': 4, 'to_sequence': 6, 'train_number': '2021M'}] or c['printed_operating_labels'] != ['１１月７日は運休', '１１月７日は運休'] or c['printed_remarks'] != ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です', '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です']:
        raise ValueError('Printed calendar/seat/number segments changed')
    if c['printed_through_station'] != '東京' or c['printed_coupling'] != []:
        raise ValueError('Through operation distinction changed')
    if DAY > json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']:
        raise ValueError('Service date exceeds manifest cutoff')
    services = [r for r in rows('normalized/services*.jsonl') if r['service_id'] == 'narita-express']
    if len(services) != 1 or services[0]['canonical_name'] != '成田エクスプレス':
        raise ValueError('Expected existing Narita Express service identity')
    if any(r['trip_id'] == TRIP for r in rows('normalized/trips/*/*.jsonl', BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')):
        raise ValueError('Duplicate Narita Express 21 trip')
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
        ROOT, [{"stops": stops}], {'空港第２ビル': '空港第2ビル'}, forced_codes={'東京': {'003766'}})


def main():
    statuses = {
        'identity': ('verified', 'high', 'Official Narita Express 21 train-detail page.'),
        'train_number': ('verified', 'high', 'Official page prints 2221M.'),
        'validity_calendar': ('verified', 'high', 'September 30 td.ok cell selects this page.'),
        'origin_destination': ('verified', 'high', '新宿 to 成田空港 endpoints printed.'),
        'stops': ('verified', 'high', 'All 6 passenger stops printed.'),
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
            'title': '特急成田エクスプレス 21号（新宿－成田空港）停車駅一覧',
            'source_type': 'official_train_timetable',
            'url_or_locator': URL,
            'issue': 'JR時刻表2026年10月号',
            'publication_date': None,
            'effective_date': DAY,
            'accessed_at': DAY,
            'license_status': 'no_reuse_grant_identified',
            'redistribution_status': 'verification_only',
            'automated_extraction_allowed': False,
            'notes': 'September 30 td.ok current-variant cell and full 2221M station table reviewed.',
        },
        'edition_name': 'JR時刻表2026年10月号; Narita Express 21 exact 2026-09-30',
        'trip_fields': {
            'service_id': 'narita-express',
            'train_number': '2221M',
            'public_number': '21',
            'service_class': 'limited_express',
            'notes': 'Exact-date official column; dated physical route and operator segments remain unknown.',
        },
        'summary': 'Staged Narita Express 21: 1 trip, 6 passenger calls',
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
        extra_outputs=lambda c: {BASE / f'normalized/trip-number-segments/{SUFFIX}/seeds.jsonl': [dict(segment, trip_id=TRIP) for segment in c['train_number_segments']]},
    )


if __name__ == '__main__':
    main()
