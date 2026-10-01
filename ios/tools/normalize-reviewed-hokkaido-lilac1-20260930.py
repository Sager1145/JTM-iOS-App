#!/usr/bin/env python3
"""Stage JR Hokkaido Lilac 1 from the selected 2026-09-30 column."""

import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-lilac1-20260930'
CANDIDATE = BASE / 'candidates/jr-hokkaido-lilac1-20260930.json'
SOURCE = 'jr-hokkaido-lilac1-20260930'
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110'
DAY, UNTIL = '2026-09-30', '2026-10-01'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
PRINTED = [
    ['札幌', None, '06:29'], ['岩見沢', None, '06:54'], ['美唄', None, '07:05'],
    ['砂川', None, '07:17'], ['滝川', None, '07:23'], ['深川', None, '07:37'],
    ['旭川', '07:56', None],
]


def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude:
            continue
        for line in path.read_text(encoding='utf-8').splitlines():
            if line.strip():
                yield json.loads(line)


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n' for row in data), encoding='utf-8')


def validate(c):
    expected = ('visually_reviewed', False, 'jr-hokkaido.lilac.1.exact-2026-09-30',
                'lilac', 'ライラック', 'limited_express', '1', '3001M', '札幌', '旭川',
                DAY, SOURCE, URL, {'札幌': '(9)'}, PRINTED)
    fields = ('candidate_status', 'canonical', 'trip_id', 'service_id', 'service_name',
              'service_class', 'public_number', 'train_number', 'origin', 'destination',
              'service_date', 'source_id', 'source_url', 'printed_platforms', 'stops')
    if tuple(c[field] for field in fields) != expected:
        raise ValueError('Reviewed Lilac 1 column changed')
    if DAY > json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']:
        raise ValueError('Service date exceeds manifest cutoff')
    services = [r for r in rows('normalized/services*.jsonl') if r['service_id'] == 'lilac']
    if len(services) != 1 or services[0]['canonical_name'] != 'ライラック':
        raise ValueError('Expected existing Lilac service identity')
    if any(r['trip_id'] == c['trip_id'] for r in rows(
            'normalized/trips/*/*.jsonl', BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')):
        raise ValueError('Duplicate Lilac 1 trip')
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
        codes = {s[0] for line in package['lines'] if line['operator'] == '北海道旅客鉄道'
                 for s in line['stations'] if s[1] == name}
        if len(codes) != 1:
            raise ValueError(f'Ambiguous JR Hokkaido station: {name} {sorted(codes)}')
        result[name] = 'jp.n02.' + next(iter(codes))
    return result


def main():
    c = json.loads(CANDIDATE.read_text(encoding='utf-8'))
    validate(c)
    station_map = station_ids(c['stops'])
    known = {r['station_id'] for r in rows('normalized/station-identities*.jsonl', BASE / f'normalized/station-identities-{SUFFIX}.jsonl')}
    station_rows = [{'station_id': sid, 'name_snapshot': name, 'reference_kind': 'current_n02',
                     'current_source_code': sid.removeprefix('jp.n02.'), 'rail_history_id': None}
                    for name, sid in sorted(station_map.items()) if sid not in known]
    tid, vid, cid = c['trip_id'], c['trip_id'] + '.version', c['trip_id'] + '.calendar'
    stops = []
    for sequence, (name, arrival, departure) in enumerate(c['stops'], 1):
        call_type = 'origin' if sequence == 1 else 'destination' if sequence == len(c['stops']) else 'passenger_stop'
        stops.append({'trip_id': tid, 'stop_sequence': sequence, 'station_id': station_map[name],
                      'arrival_time': arrival, 'departure_time': departure, 'day_offset': 0,
                      'call_type': call_type, 'pickup_allowed': int(call_type != 'destination'),
                      'dropoff_allowed': int(call_type != 'origin'),
                      'platform': c['printed_platforms'].get(name), 'time_accuracy': 'minute', 'source_id': SOURCE})
    statuses = {
        'identity': ('verified', 'high', 'Official 3001M / ライラック 1 first column.'),
        'train_number': ('verified', 'high', 'Official column prints 3001M.'),
        'validity_calendar': ('verified', 'high', 'Official selector is 2026-09-30.'),
        'origin_destination': ('verified', 'high', 'Sapporo and Asahikawa endpoints printed.'),
        'stops': ('verified', 'high', 'Seven passenger calls printed.'),
        'times': ('partial', 'medium', 'Intermediate arrival sides are unprinted.'),
        'station_refs': ('verified', 'high', 'Current JR Hokkaido N02 station-group matches.'),
        'operator': ('unknown', 'low', 'No dated ordered operator segments.'),
        'route_lines': ('unknown', 'low', 'No dated ordered physical line identities.'),
        'provenance': ('partial', 'medium', 'Official page pinned; reuse grant unconfirmed.'),
    }
    completeness = [{'entity_type': 'trip', 'entity_id': tid, 'dimension': dim,
                     'status': status, 'confidence': confidence, 'notes': note}
                    for dim, (status, confidence, note) in statuses.items()]
    facts = [{'entity_type': 'trip', 'entity_id': tid, 'field_name': dim,
              'source_id': 'jtm-current-station-directory' if dim == 'station_refs' else SOURCE,
              'page_or_locator': 'app/public/rail/jp-2025.json' if dim == 'station_refs' else c['source_locator'],
              'confidence': confidence, 'verification_status': status}
             for dim, (status, confidence, _) in statuses.items()
             if status in {'verified', 'partial'} and dim != 'provenance']
    queue = [{'research_id': f'{tid}.{dim}', 'entity_type': 'trip', 'entity_id': tid,
              'missing_dimension': dim, 'status': 'open', 'notes': note}
             for dim, (status, _, note) in statuses.items() if status != 'verified']
    outputs = {
        BASE / f'sources/source-registry-{SUFFIX}.jsonl': [{
            'source_id': SOURCE, 'publisher': '北海道旅客鉄道株式会社 / 株式会社交通新聞社',
            'title': '［特急］ライラック 1 下り 2026年9月30日 3001M 列',
            'source_type': 'official_timetable', 'url_or_locator': URL,
            'issue': 'JR時刻表 令和8年10月号', 'publication_date': None,
            'effective_date': DAY, 'accessed_at': DAY,
            'license_status': 'terms_published_no_reuse_grant_identified',
            'redistribution_status': 'verification_only', 'automated_extraction_allowed': False,
            'notes': 'Selected date and first train column visually reviewed; unauthorized reproduction or processing prohibited by site.',
        }],
        BASE / f'normalized/service-name-periods-{SUFFIX}.jsonl': [{
            'service_id': 'lilac', 'name': 'ライラック', 'language': 'ja',
            'valid_from': DAY, 'valid_until': UNTIL, 'name_type': 'display', 'source_id': SOURCE}],
        BASE / f'normalized/timetable-versions-{SUFFIX}.jsonl': [{
            'timetable_version_id': vid, 'operator_scope': 'jr-hokkaido',
            'effective_from': DAY, 'effective_until': UNTIL,
            'edition_name': 'JR時刻表 令和8年10月号; selected Lilac 1 column',
            'revision_type': 'source_snapshot', 'completeness': 'partial', 'source_ids': [SOURCE]}],
        BASE / f'normalized/station-identities-{SUFFIX}.jsonl': station_rows,
        BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl': [{
            'trip_id': tid, 'timetable_version_id': vid, 'service_id': 'lilac', 'calendar_id': cid,
            'train_number': '3001M', 'public_number': '1',
            'origin_station_id': station_map['札幌'], 'destination_station_id': station_map['旭川'],
            'service_class': 'limited_express',
            'notes': 'Exact-date official column; unprinted intermediate arrival sides remain unknown.'}],
        BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl': stops,
        BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl': [{
            'calendar_id': cid, 'valid_from': DAY, 'valid_until': UNTIL,
            'holiday_policy': 'none', **{day: 0 for day in WEEKDAYS}}],
        BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl': [{
            'calendar_id': cid, 'service_date': DAY, 'exception_type': 'add',
            'reason': 'Exact selected date on operator timetable', 'source_id': SOURCE}],
        BASE / f'normalized/fact-completeness-{SUFFIX}.jsonl': completeness,
        BASE / f'normalized/fact-sources-{SUFFIX}.jsonl': facts,
        BASE / f'normalized/research-queue-{SUFFIX}.jsonl': queue,
    }
    for path, records in outputs.items():
        write(path, records)
    print('Staged Lilac 1: 1 trip, 7 passenger calls')


if __name__ == '__main__':
    main()
