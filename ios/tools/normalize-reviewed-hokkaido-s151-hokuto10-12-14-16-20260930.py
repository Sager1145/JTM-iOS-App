#!/usr/bin/env python3
"""Stage four source-pinned JR Hokkaido s=151 Hokuto columns for 2026-09-30."""

import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-s151-hokuto10-12-14-16-20260930'
CANDIDATE = BASE / f'candidates/jr-{SUFFIX}.json'
SOURCE = f'jr-{SUFFIX}'
GUIDE_SOURCE = f'{SOURCE}-train-guide'
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151'
GUIDE_URL = 'https://www.jrhokkaido.co.jp/train/tr003_01.html'
DAY, UNTIL = '2026-09-30', '2026-10-01'
ISSUE = 'JR時刻表 令和8年10月号'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
EXPECTED = {
    '10D': ('10', 16, '10:56', '14:40'),
    '12D': ('12', 16, '12:09', '16:08'),
    '14D': ('14', 16, '13:26', '17:13'),
    '16D': ('16', 16, '14:46', '18:30'),
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
    if candidate['source_issue'] != ISSUE:
        raise ValueError('Live source issue changed')
    if DAY > json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']:
        raise ValueError('Service date exceeds manifest cutoff')
    services = {r['service_id']: r['canonical_name'] for r in rows('normalized/services*.jsonl')}
    if services.get('hokuto') != '北斗':
        raise ValueError('Canonical Hokuto service identity missing')
    trips = candidate['trips']
    if len(trips) != 4 or {t['train_number'] for t in trips} != set(EXPECTED):
        raise ValueError('Expected exactly 10D, 12D, 14D and 16D')
    output = BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl'
    existing = {r['trip_id'] for r in rows('normalized/trips/*/*.jsonl', output)}
    for trip in trips:
        number = trip['train_number']
        public, count, first, last = EXPECTED[number]
        expected_id = f'jr-hokkaido.hokuto.{public}.exact-{DAY}'
        actual = (trip['trip_id'], trip['service_id'], trip['service_name'], trip['service_class'],
                  trip['public_number'], trip['origin'], trip['destination'], trip['service_date'],
                  trip['source_id'], trip['source_url'], trip['operating_day_marker'],
                  trip['printed_platforms'])
        expected = (expected_id, 'hokuto', '北斗', 'limited_express', public, '札幌', '函館',
                    DAY, SOURCE, URL, '毎日', {'札幌': '(8)'})
        if actual != expected:
            raise ValueError(f'Identity, day, source or printed marker changed: {number}')
        if expected_id in existing:
            raise ValueError(f'Duplicate trip {expected_id}')
        if trip['formation_icons'] != ['greensiteidai0.png', 'zensekisitei0.png']:
            raise ValueError(f'Formation icons changed: {number}')
        stops = trip['stops']
        if (len(stops) != count or stops[0] != ['札幌', None, first]
                or stops[-1] != ['函館', last, None]
                or len({row[0] for row in stops}) != count):
            raise ValueError(f'Stop chain changed: {number}')
        if stops[6][0] != '東室蘭' or not all(stops[6][i] for i in (1, 2)):
            raise ValueError(f'East Muroran arrival/departure missing: {number}')
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
    own_stations = BASE / f'normalized/station-identities-{SUFFIX}.jsonl'
    known = {r['station_id'] for r in rows('normalized/station-identities*.jsonl', own_stations)}
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
                         'edition_name': f'{ISSUE}; selected 2026-09-30 s=151 column',
                         'revision_type': 'source_snapshot', 'completeness': 'partial',
                         'source_ids': [SOURCE]})
        trip_rows.append({'trip_id': tid, 'timetable_version_id': vid,
                          'service_id': 'hokuto', 'calendar_id': cid,
                          'train_number': number, 'public_number': trip['public_number'],
                          'origin_station_id': stations['札幌'],
                          'destination_station_id': stations['函館'],
                          'service_class': 'limited_express',
                          'notes': 'Exact-date official column; unprinted clock sides remain unknown.'})
        for sequence, (name, arrival, departure) in enumerate(trip['stops'], 1):
            call_type = ('origin' if sequence == 1 else
                         'destination' if sequence == len(trip['stops']) else 'passenger_stop')
            stop_rows.append({'trip_id': tid, 'stop_sequence': sequence,
                              'station_id': stations[name], 'arrival_time': arrival,
                              'departure_time': departure, 'day_offset': 0,
                              'call_type': call_type,
                              'pickup_allowed': int(call_type != 'destination'),
                              'dropoff_allowed': int(call_type != 'origin'),
                              'platform': trip['printed_platforms'].get(name),
                              'time_accuracy': 'minute', 'source_id': SOURCE})
        calendars.append({'calendar_id': cid, 'valid_from': DAY, 'valid_until': UNTIL,
                          'holiday_policy': 'none', **{day: 0 for day in WEEKDAYS}})
        exceptions.append({'calendar_id': cid, 'service_date': DAY, 'exception_type': 'add',
                           'reason': 'Exact selected date on operator timetable',
                           'source_id': SOURCE})
        formations.append({'formation_id': f'{tid}.formation.{DAY}', 'trip_id': tid,
                           'service_date': DAY, 'evidence_kind': 'planned',
                           'all_reserved': True, 'green_car_available': True,
                           'vehicle_series': 'キハ261系1000代', 'source_id': SOURCE,
                           'notes': 'Date-selected seat icons; JR Hokkaido train guide identifies the standard Hokuto series. No exact-date vehicle set, car count or per-car diagram inferred.'})
        statuses = {
            'identity': ('verified', 'high', f'Official {number} / 北斗 column.'),
            'train_number': ('verified', 'high', f'Official column prints {number}.'),
            'validity_calendar': ('verified', 'high', '2026-09-30 selected; column prints 毎日.'),
            'origin_destination': ('verified', 'high', 'Both endpoints printed.'),
            'stops': ('verified', 'high', 'All numbered passenger stop rows captured; レ rows excluded.'),
            'times': ('partial', 'medium', 'All printed clocks captured; unprinted arrival sides remain unknown.'),
            'station_refs': ('verified', 'high', 'Names resolve to current JR Hokkaido N02 groups.'),
            'formation': ('partial', 'high', 'Printed seat icons and operator-listed standard series; actual vehicle set, car count and per-car assignment unknown.'),
            'operator': ('unknown', 'low', 'No dated ordered operator segments.'),
            'route_lines': ('unknown', 'low', 'No dated ordered physical line identities.'),
            'provenance': ('partial', 'medium', 'Official URL pinned; reuse grant unconfirmed.'),
        }
        for dimension, (status, confidence, note) in statuses.items():
            completeness.append({'entity_type': 'trip', 'entity_id': tid,
                                 'dimension': dimension, 'status': status,
                                 'confidence': confidence, 'notes': note})
            if status in {'verified', 'partial'} and dimension not in {'provenance', 'formation'}:
                facts.append({'entity_type': 'trip', 'entity_id': tid,
                              'field_name': dimension,
                              'source_id': ('jtm-current-station-directory'
                                            if dimension == 'station_refs' else SOURCE),
                              'page_or_locator': ('app/public/rail/jp-2025.json'
                                                  if dimension == 'station_refs'
                                                  else trip['source_locator']),
                              'confidence': confidence, 'verification_status': status})
            if status != 'verified':
                queue.append({'research_id': f'{tid}.{dimension}', 'entity_type': 'trip',
                              'entity_id': tid, 'missing_dimension': dimension,
                              'status': 'open', 'notes': note})
        for field, icon in (('formation.all_reserved', 'zensekisitei0.png'),
                            ('formation.green_car_available', 'greensiteidai0.png')):
            facts.append({'entity_type': 'trip', 'entity_id': tid, 'field_name': field,
                          'source_id': SOURCE,
                          'page_or_locator': f'{trip["source_locator"]}; 編成 row {icon}',
                          'confidence': 'high', 'verification_status': 'verified'})
        facts.append({'entity_type': 'trip', 'entity_id': tid,
                      'field_name': 'formation.vehicle_series', 'source_id': GUIDE_SOURCE,
                      'page_or_locator': '特急北斗（キハ261系1000代）; 列車編成 is basic and subject to change',
                      'confidence': 'medium', 'verification_status': 'partial'})
    outputs = {
        BASE / f'sources/source-registry-{SUFFIX}.jsonl': [
            {'source_id': SOURCE,
             'publisher': '北海道旅客鉄道株式会社 / 株式会社交通新聞社',
             'title': '［特急］北斗 10／12／14／16 上り 2026年9月30日 列',
             'source_type': 'official_timetable', 'url_or_locator': URL,
             'issue': ISSUE, 'publication_date': None,
             'effective_date': DAY, 'accessed_at': DAY,
             'license_status': 'terms_published_no_reuse_grant_identified',
             'redistribution_status': 'verification_only',
             'automated_extraction_allowed': False,
             'notes': 'Selected date and named Hokuto columns visually reviewed. Live exact-URL refresh prints 令和8年10月号; an earlier search cache rendered 9月号. Site prohibits unauthorized reproduction or processing.'},
            {'source_id': GUIDE_SOURCE, 'publisher': '北海道旅客鉄道株式会社',
             'title': '特急北斗（キハ261系1000代）｜列車ガイド',
             'source_type': 'official_train_guide', 'url_or_locator': GUIDE_URL,
             'issue': '2025年3月現在の情報', 'publication_date': None,
             'effective_date': None, 'accessed_at': DAY,
             'license_status': 'terms_published_no_reuse_grant_identified',
             'redistribution_status': 'verification_only',
             'automated_extraction_allowed': False,
             'notes': 'Names the standard Hokuto vehicle series and says the pictured formation is basic and may change. Does not prove exact-date assignment.'}],
        BASE / f'normalized/timetable-versions-{SUFFIX}.jsonl': versions,
        BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl': trip_rows,
        BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl': stop_rows,
        BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl': calendars,
        BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl': exceptions,
        BASE / f'normalized/trip-formations/{SUFFIX}/seeds.jsonl': formations,
        BASE / f'normalized/fact-completeness-{SUFFIX}.jsonl': completeness,
        BASE / f'normalized/fact-sources-{SUFFIX}.jsonl': facts,
        BASE / f'normalized/research-queue-{SUFFIX}.jsonl': queue,
    }
    if new_stations:
        outputs[own_stations] = new_stations
    for path, records in outputs.items():
        write(path, records)
    print(f'Staged 4 selected-day trains, {len(stop_rows)} passenger calls and 4 planned formation facts')


if __name__ == '__main__':
    main()
