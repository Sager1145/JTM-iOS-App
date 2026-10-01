#!/usr/bin/env python3
"""Stage four source-pinned JR Hokkaido s=110 columns for 2026-09-30."""

import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s110-kamui29-lilac37-39-41-20260930'
CANDIDATE = BASE / f'candidates/jr-{SUFFIX}.json'
SOURCE = f'jr-{SUFFIX}'
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110'
DAY, UNTIL = '2026-09-30', '2026-10-01'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
EXPECTED = {
    '2029M': ('kamui', 'カムイ', '29', '札幌', '旭川', '16:30', '17:55', '(9)', False),
    '3037M': ('lilac', 'ライラック', '37', '札幌', '旭川', '18:30', '19:55', '(9)', True),
    '3039M': ('lilac', 'ライラック', '39', '札幌', '旭川', '19:00', '20:25', '(9)', True),
    '3041M': ('lilac', 'ライラック', '41', '札幌', '旭川', '20:00', '21:25', '(10)', True),
}


def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude:
            continue
        for line in path.read_text(encoding='utf-8').splitlines():
            if line.strip():
                yield json.loads(line)


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n'
                            for row in records), encoding='utf-8')


def validate(candidate):
    if (candidate['candidate_status'], candidate['canonical']) != ('visually_reviewed', False):
        raise ValueError('Review status changed')
    if DAY > json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']:
        raise ValueError('Service date exceeds manifest cutoff')
    trips = candidate['trips']
    if len(trips) != 4 or {t['train_number'] for t in trips} != set(EXPECTED):
        raise ValueError('Expected exactly 2029M, 3037M, 3039M and 3041M')
    services = {r['service_id']: r['canonical_name'] for r in rows('normalized/services*.jsonl')}
    existing = {r['trip_id'] for r in rows('normalized/trips/*/*.jsonl',
                                         BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')}
    for trip in trips:
        number = trip['train_number']
        service, name, public, origin, destination, first, last, platform, green = EXPECTED[number]
        expected_id = f'jr-hokkaido.{service}.{public}.exact-{DAY}'
        actual = (trip['trip_id'], trip['service_id'], trip['service_name'], trip['service_class'],
                  trip['public_number'], trip['origin'], trip['destination'], trip['service_date'],
                  trip['source_id'], trip['source_url'], trip['operating_day_marker'],
                  trip['printed_platforms'])
        expected = (expected_id, service, name, 'limited_express', public, origin, destination,
                    DAY, SOURCE, URL, '毎日', {'札幌': platform})
        if actual != expected:
            raise ValueError(f'Identity, day, source or printed marker changed: {number}')
        if expected_id in existing:
            raise ValueError(f'Duplicate trip {expected_id}')
        icons = ['greensiteidai0.png', 'zensekisitei0.png'] if green else ['zensekisitei0.png']
        if trip['formation_icons'] != icons:
            raise ValueError(f'Formation icons changed: {number}')
        stops = trip['stops']
        if (len(stops) != 7 or stops[0] != [origin, None, first]
                or stops[-1] != [destination, last, None]
                or len({row[0] for row in stops}) != 7):
            raise ValueError(f'Stop chain changed: {number}')
        previous = None
        for station, arrival, departure in stops:
            if arrival is None and departure is None:
                raise ValueError(f'Untimed passenger call: {number} {station}')
            for clock in (arrival, departure):
                if clock is None:
                    continue
                parsed = datetime.strptime(clock, '%H:%M')
                if previous is not None and parsed < previous:
                    raise ValueError(f'Clock reversal: {number} {station}')
                previous = parsed
    return trips


def station_ids(trips):
    package = json.loads((ROOT / 'app/public/rail/jp-2025.json').read_text(encoding='utf-8'))
    result = {}
    for name in {s[0] for t in trips for s in t['stops']}:
        codes = {s[0] for line in package['lines'] if line['operator'] == '北海道旅客鉄道'
                 for s in line['stations'] if s[1] == name}
        if len(codes) != 1:
            raise ValueError(f'Ambiguous JR Hokkaido station: {name} {sorted(codes)}')
        result[name] = 'jp.n02.' + next(iter(codes))
    return result


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding='utf-8'))
    trips = validate(candidate)
    stations = station_ids(trips)
    known = {r['station_id'] for r in rows('normalized/station-identities*.jsonl',
                                           BASE / f'normalized/station-identities-{SUFFIX}.jsonl')}
    new_stations = [{'station_id': sid, 'name_snapshot': name, 'reference_kind': 'current_n02',
                     'current_source_code': sid.removeprefix('jp.n02.'), 'rail_history_id': None}
                    for name, sid in sorted(stations.items()) if sid not in known]
    versions, trip_rows, stop_rows, calendars, exceptions = [], [], [], [], []
    formations, completeness, facts, queue = [], [], [], []
    for trip in trips:
        tid, number = trip['trip_id'], trip['train_number']
        vid, cid = tid + '.version', tid + '.calendar'
        versions.append({'timetable_version_id': vid, 'operator_scope': 'jr-hokkaido',
                         'effective_from': DAY, 'effective_until': UNTIL,
                         'edition_name': 'JR時刻表 令和8年10月号; selected 2026-09-30 s=110 column',
                         'revision_type': 'source_snapshot', 'completeness': 'partial',
                         'source_ids': [SOURCE]})
        trip_rows.append({'trip_id': tid, 'timetable_version_id': vid,
                          'service_id': trip['service_id'], 'calendar_id': cid,
                          'train_number': number, 'public_number': trip['public_number'],
                          'origin_station_id': stations[trip['origin']],
                          'destination_station_id': stations[trip['destination']],
                          'service_class': 'limited_express',
                          'notes': 'Exact-date official column; unprinted clock sides remain unknown.'})
        for sequence, (name, arrival, departure) in enumerate(trip['stops'], 1):
            call_type = 'origin' if sequence == 1 else 'destination' if sequence == len(trip['stops']) else 'passenger_stop'
            stop_rows.append({'trip_id': tid, 'stop_sequence': sequence, 'station_id': stations[name],
                              'arrival_time': arrival, 'departure_time': departure,
                              'day_offset': 0, 'call_type': call_type,
                              'pickup_allowed': int(call_type != 'destination'),
                              'dropoff_allowed': int(call_type != 'origin'),
                              'platform': trip['printed_platforms'].get(name),
                              'time_accuracy': 'minute', 'source_id': SOURCE})
        calendars.append({'calendar_id': cid, 'valid_from': DAY, 'valid_until': UNTIL,
                          'holiday_policy': 'none', **{day: 0 for day in WEEKDAYS}})
        exceptions.append({'calendar_id': cid, 'service_date': DAY, 'exception_type': 'add',
                           'reason': 'Exact selected date on operator timetable', 'source_id': SOURCE})
        green = 'greensiteidai0.png' in trip['formation_icons']
        formations.append({'formation_id': f'{tid}.formation.{DAY}', 'trip_id': tid,
                           'service_date': DAY, 'evidence_kind': 'planned',
                           'all_reserved': True, 'green_car_available': True if green else None,
                           'source_id': SOURCE,
                           'notes': 'Date-selected formation row icons; no car count, vehicle series or per-car diagram inferred.'})
        statuses = {
            'identity': ('verified', 'high', f'Official {number} / {trip["service_name"]} column.'),
            'train_number': ('verified', 'high', f'Official column prints {number}.'),
            'validity_calendar': ('verified', 'high', '2026-09-30 selected; column prints 毎日.'),
            'origin_destination': ('verified', 'high', 'Both endpoints printed.'),
            'stops': ('verified', 'high', 'All seven printed passenger stop rows captured.'),
            'times': ('partial', 'medium', 'All printed clocks captured; unprinted arrival sides remain unknown.'),
            'station_refs': ('verified', 'high', 'Names resolve to current JR Hokkaido N02 groups.'),
            'formation': ('partial', 'high', 'Printed seat icons; car count, series and per-car assignment unknown.'),
            'operator': ('unknown', 'low', 'No dated ordered operator segments.'),
            'route_lines': ('unknown', 'low', 'No dated ordered physical line identities.'),
            'provenance': ('partial', 'medium', 'Official URL pinned; reuse grant unconfirmed.'),
        }
        for dim, (status, confidence, note) in statuses.items():
            completeness.append({'entity_type': 'trip', 'entity_id': tid, 'dimension': dim,
                                 'status': status, 'confidence': confidence, 'notes': note})
            if status in {'verified', 'partial'} and dim not in {'provenance', 'formation'}:
                facts.append({'entity_type': 'trip', 'entity_id': tid, 'field_name': dim,
                              'source_id': 'jtm-current-station-directory' if dim == 'station_refs' else SOURCE,
                              'page_or_locator': 'app/public/rail/jp-2025.json' if dim == 'station_refs'
                              else trip['source_locator'],
                              'confidence': confidence, 'verification_status': status})
            if status != 'verified':
                queue.append({'research_id': f'{tid}.{dim}', 'entity_type': 'trip', 'entity_id': tid,
                              'missing_dimension': dim, 'status': 'open', 'notes': note})
        facts.append({'entity_type': 'trip', 'entity_id': tid,
                      'field_name': 'formation.all_reserved', 'source_id': SOURCE,
                      'page_or_locator': trip['source_locator'] + '; 編成 row zensekisitei0.png',
                      'confidence': 'high', 'verification_status': 'verified'})
        if green:
            facts.append({'entity_type': 'trip', 'entity_id': tid,
                          'field_name': 'formation.green_car_available', 'source_id': SOURCE,
                          'page_or_locator': trip['source_locator'] + '; 編成 row greensiteidai0.png',
                          'confidence': 'high', 'verification_status': 'verified'})
    outputs = {
        BASE / f'sources/source-registry-{SUFFIX}.jsonl': [{
            'source_id': SOURCE, 'publisher': '北海道旅客鉄道株式会社 / 株式会社交通新聞社',
            'title': '［特急］カムイ 29・ライラック 37／39／41 下り 2026年9月30日 列',
            'source_type': 'official_timetable', 'url_or_locator': URL,
            'issue': 'JR時刻表 令和8年10月号', 'publication_date': None,
            'effective_date': DAY, 'accessed_at': DAY,
            'license_status': 'terms_published_no_reuse_grant_identified',
            'redistribution_status': 'verification_only', 'automated_extraction_allowed': False,
            'notes': 'Selected date and train columns visually reviewed. Site prohibits unauthorized reproduction or processing.'}],
        BASE / f'normalized/timetable-versions-{SUFFIX}.jsonl': versions,
        BASE / f'normalized/station-identities-{SUFFIX}.jsonl': new_stations,
        BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl': trip_rows,
        BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl': stop_rows,
        BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl': calendars,
        BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl': exceptions,
        BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl': formations,
        BASE / f'normalized/fact-completeness-{SUFFIX}.jsonl': completeness,
        BASE / f'normalized/fact-sources-{SUFFIX}.jsonl': facts,
        BASE / f'normalized/research-queue-{SUFFIX}.jsonl': queue,
    }
    for path, records in outputs.items():
        write(path, records)
    print(f'Staged 4 selected-day trains, {len(stop_rows)} passenger calls and 4 planned formation facts')


if __name__ == '__main__':
    main()
