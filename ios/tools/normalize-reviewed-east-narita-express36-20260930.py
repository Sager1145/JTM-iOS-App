#!/usr/bin/env python3
"""Stage the source-pinned JR East Narita Express 36 trip for 2026-09-30."""

import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'east-narita-express36-20260930'
CANDIDATE = BASE / 'candidates/jr-east-narita-express36-20260930.json'
SOURCE = 'jr-east-narita-express36-20260930'
URL = 'https://timetables.jreast.co.jp/2610/train/075/076611.html'
TRIP = 'jr-east.narita-express.36.exact-2026-09-30'
DAY, UNTIL = '2026-09-30', '2026-10-01'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
PRINTED = [['成田空港', None, '16:19'], ['空港第２ビル', '16:21', '16:23'], ['東京', '17:18', '17:22'], ['品川', '17:28', '17:29'], ['渋谷', '17:37', '17:38'], ['新宿', '17:43', None]]
PLATFORMS = {'東京': '２', '品川': '１５', '新宿': '５'}


def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude:
            continue
        for line in path.read_text(encoding='utf-8').splitlines():
            if line.strip():
                yield json.loads(line)


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n' for row in records), encoding='utf-8')


def validate(c):
    expected = ('reviewed_official_html', False, TRIP, 'narita-express', '成田エクスプレス', 'limited_express',
                '36', '2036M', '成田空港', '新宿', DAY, SOURCE, URL, PLATFORMS, PRINTED)
    fields = ('candidate_status', 'canonical', 'trip_id', 'service_id', 'service_name',
              'service_class', 'public_number', 'train_number', 'origin', 'destination',
              'service_date', 'source_id', 'source_url', 'printed_platforms', 'stops')
    if tuple(c[field] for field in fields) != expected:
        raise ValueError('Reviewed Narita Express 36 column changed')
    if c['calendar_observation'] != {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'} or c['equipment'] != ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'] or c['formation'] is not None or c['train_number_segments'] != [{'from_sequence': 1, 'to_sequence': 3, 'train_number': '2036M'}, {'from_sequence': 3, 'to_sequence': 6, 'train_number': '2236M'}] or c['printed_operating_labels'] != ['１１月７日は運休', '１１月７日は運休'] or c['printed_remarks'] != ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です', '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です']:
        raise ValueError('Printed calendar/seat/number segments changed')
    if c['printed_through_station'] != '東京' or c['printed_coupling'] != []:
        raise ValueError('Through operation distinction changed')
    if DAY > json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']:
        raise ValueError('Service date exceeds manifest cutoff')
    services = [r for r in rows('normalized/services*.jsonl') if r['service_id'] == 'narita-express']
    if len(services) != 1 or services[0]['canonical_name'] != '成田エクスプレス':
        raise ValueError('Expected existing Kaiji service identity')
    if any(r['trip_id'] == TRIP for r in rows('normalized/trips/*/*.jsonl', BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')):
        raise ValueError('Duplicate Narita Express 36 trip')
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
    package = json.loads((ROOT / 'app/public/rail/jp-2025.json').read_text(encoding='utf-8'))
    result = {}
    for name, _, _ in stops:
        codes = {s[0] for line in package['lines'] if line['operator'] == '東日本旅客鉄道'
                 for s in line['stations'] if s[1] == {'空港第２ビル':'空港第2ビル'}.get(name,name)}
        if name == '東京':
            codes &= {'003766'}
        if len(codes) != 1:
            raise ValueError(f'Ambiguous JR East station: {name} {sorted(codes)}')
        result[name] = 'jp.n02.' + next(iter(codes))
    return result


def main():
    c = json.loads(CANDIDATE.read_text(encoding='utf-8'))
    validate(c)
    stations = station_ids(c['stops'])
    known = {r['station_id'] for r in rows('normalized/station-identities*.jsonl', BASE / f'normalized/station-identities-{SUFFIX}.jsonl')}
    station_rows = [{'station_id': sid, 'name_snapshot': name, 'reference_kind': 'current_n02',
                     'current_source_code': sid.removeprefix('jp.n02.'), 'rail_history_id': None}
                    for name, sid in sorted(stations.items()) if sid not in known]
    vid, cid = TRIP + '.version', TRIP + '.calendar'
    stops = []
    for sequence, (name, arrival, departure) in enumerate(c['stops'], 1):
        call_type = 'origin' if sequence == 1 else 'destination' if sequence == len(c['stops']) else 'passenger_stop'
        stops.append({'trip_id': TRIP, 'stop_sequence': sequence, 'station_id': stations[name],
                      'arrival_time': arrival, 'departure_time': departure, 'day_offset': 0,
                      'call_type': call_type, 'pickup_allowed': int(call_type != 'destination'),
                      'dropoff_allowed': int(call_type != 'origin'), 'platform': PLATFORMS.get(name),
                      'time_accuracy': 'minute', 'source_id': SOURCE})
    statuses = {
        'identity': ('verified', 'high', 'Official Narita Express 36 train-detail page.'),
        'train_number': ('verified', 'high', 'Official page prints 2036M.'),
        'validity_calendar': ('verified', 'high', 'September 30 td.ok cell selects this page.'),
        'origin_destination': ('verified', 'high', '成田空港 to 新宿 endpoints printed.'),
        'stops': ('verified', 'high', 'All 6 passenger stops printed.'),
        'times': ('verified', 'high', 'All printed arrival/departure clocks captured.'),
        'station_refs': ('verified', 'high', 'Current JR East N02 station-group matches.'),
        'operator': ('unknown', 'low', 'No dated ordered operator segments.'),
        'route_lines': ('unknown', 'low', 'No dated ordered physical line identities.'),
        'provenance': ('partial', 'medium', 'Official page pinned; reuse grant unconfirmed.'),
    }
    completeness = [{'entity_type': 'trip', 'entity_id': TRIP, 'dimension': dim,
                     'status': status, 'confidence': confidence, 'notes': note}
                    for dim, (status, confidence, note) in statuses.items()]
    facts = [{'entity_type': 'trip', 'entity_id': TRIP, 'field_name': dim,
              'source_id': 'jtm-current-station-directory' if dim == 'station_refs' else SOURCE,
              'page_or_locator': 'app/public/rail/jp-2025.json' if dim == 'station_refs' else c['source_locator'],
              'confidence': confidence, 'verification_status': status}
             for dim, (status, confidence, _) in statuses.items() if status == 'verified']
    queue = [{'research_id': f'{TRIP}.{dim}', 'entity_type': 'trip', 'entity_id': TRIP,
              'missing_dimension': dim, 'status': 'open', 'notes': note}
             for dim, (status, _, note) in statuses.items() if status != 'verified']
    outputs = {
        BASE / f'normalized/trip-number-segments/{SUFFIX}/seeds.jsonl': [dict(segment, trip_id=TRIP) for segment in c['train_number_segments']],
        BASE / f'sources/source-registry-{SUFFIX}.jsonl': [{
            'source_id': SOURCE, 'publisher': '東日本旅客鉄道株式会社 / 株式会社交通新聞社',
            'title': '特急成田エクスプレス 36号（成田空港－新宿）停車駅一覧',
            'source_type': 'official_train_timetable', 'url_or_locator': URL,
            'issue': 'JR時刻表2026年10月号', 'publication_date': None,
            'effective_date': DAY, 'accessed_at': DAY,
            'license_status': 'no_reuse_grant_identified', 'redistribution_status': 'verification_only',
            'automated_extraction_allowed': False,
            'notes': 'September 30 td.ok current-variant cell and full 2036M station table reviewed.',
        }],
        BASE / f'normalized/timetable-versions-{SUFFIX}.jsonl': [{
            'timetable_version_id': vid, 'operator_scope': 'jr-east',
            'effective_from': DAY, 'effective_until': UNTIL,
            'edition_name': 'JR時刻表2026年10月号; Narita Express 36 exact 2026-09-30',
            'revision_type': 'source_snapshot', 'completeness': 'partial', 'source_ids': [SOURCE]}],
        BASE / f'normalized/station-identities-{SUFFIX}.jsonl': station_rows,
        BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl': [{
            'trip_id': TRIP, 'timetable_version_id': vid, 'service_id': 'narita-express', 'calendar_id': cid,
            'train_number': '2036M', 'public_number': '36',
            'origin_station_id': stations['成田空港'], 'destination_station_id': stations['新宿'],
            'service_class': 'limited_express',
            'notes': 'Exact-date official column; dated physical route and operator segments remain unknown.'}],
        BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl': stops,
        BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl': [{
            'calendar_id': cid, 'valid_from': DAY, 'valid_until': UNTIL,
            'holiday_policy': 'none', **{day: 0 for day in WEEKDAYS}}],
        BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl': [{
            'calendar_id': cid, 'service_date': DAY, 'exception_type': 'add',
            'reason': 'September 30 current-variant calendar cell', 'source_id': SOURCE}],
        BASE / f'normalized/fact-completeness-{SUFFIX}.jsonl': completeness,
        BASE / f'normalized/fact-sources-{SUFFIX}.jsonl': facts,
        BASE / f'normalized/research-queue-{SUFFIX}.jsonl': queue,
    }
    for path, records in outputs.items():
        write(path, records)
    print('Staged Narita Express 36: 1 trip, 6 passenger calls')


if __name__ == '__main__':
    main()
