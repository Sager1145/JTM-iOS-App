#!/usr/bin/env python3
"""Stage the dated 71D and 3591D down timetable columns."""

import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'hokkaido-okhotsk1-taisetsu3591d-20260930'
CANDIDATE = BASE / 'candidates/jr-hokkaido-okhotsk1-taisetsu3591d-20260930.json'
SOURCE = 'jr-hokkaido-okhotsk1-taisetsu3591d-20260930'
URL = 'https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110'
DAY, UNTIL = '2026-09-30', '2026-10-01'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
EXPECTED = {
    '71D': ('okhotsk', 'オホーツク', 'limited_express', '1', '札幌', '網走', 17, '06:52', '12:17'),
    '3591D': ('taisetsu', '大雪', 'special_rapid', None, '旭川', '網走', 11, '12:38', '16:32'),
}


def read_rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude:
            continue
        for raw in path.read_text(encoding='utf-8').splitlines():
            if raw.strip():
                yield json.loads(raw)


def write_jsonl(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n' for row in records), encoding='utf-8')


def validate(candidate):
    if candidate['candidate_status'] != 'visually_reviewed' or candidate['canonical'] is not False:
        raise ValueError('Candidate review/status changed')
    if DAY > json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']:
        raise ValueError('Date exceeds manifest cutoff')
    trips = candidate['trips']
    if len(trips) != 2 or {trip['train_number'] for trip in trips} != set(EXPECTED):
        raise ValueError('Expected 71D and 3591D')
    services = {row['service_id']: row for row in read_rows('normalized/services*.jsonl')}
    if any(services.get(service, {}).get('canonical_name') != name
           for service, name in (('okhotsk', 'オホーツク'), ('taisetsu', '大雪'))):
        raise ValueError('Reviewed service identities must already exist')
    prior_trips = {row['trip_id'] for row in read_rows('normalized/trips/*/*.jsonl', BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')}
    for trip in trips:
        number = trip['train_number']
        service, name, kind, public, origin, destination, count, first, last = EXPECTED[number]
        identity = f'jr-hokkaido.{service}.{public if public else number.lower()}.exact-{DAY}'
        if (trip['trip_id'], trip['service_id'], trip['service_name'], trip['service_class'],
                trip['public_number'], trip['origin'], trip['destination'], trip['service_date'],
                trip['source_id'], trip['source_url']) != (
                identity, service, name, kind, public, origin, destination, DAY, SOURCE, URL):
            raise ValueError(f'Identity or source changed: {number}')
        if identity in prior_trips:
            raise ValueError(f'Duplicate trip: {identity}')
        stops = trip['stops']
        if len(stops) != count or stops[0] != [origin, None, first] or stops[-1] != [destination, last, None]:
            raise ValueError(f'Endpoints or stop count changed: {number}')
        if len({stop[0] for stop in stops}) != count:
            raise ValueError(f'Duplicate station: {number}')
        if trip['printed_platforms'] != ({'札幌': '(10)'} if number == '71D' else {}):
            raise ValueError(f'Printed platform changed: {number}')
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
    if trips[0]['stops'][6] != ['旭川', '08:28', '08:31']:
        raise ValueError('71D Asahikawa arrival/departure changed')
    return trips


def station_ids(trips):
    package = json.loads((ROOT / 'app/public/rail/jp-2025.json').read_text(encoding='utf-8'))
    result = {}
    for name in {stop[0] for trip in trips for stop in trip['stops']}:
        codes = {station[0] for line in package['lines'] if line['operator'] == '北海道旅客鉄道'
                 for station in line['stations'] if station[1] == name}
        if len(codes) != 1:
            raise ValueError(f'Ambiguous JR Hokkaido station group: {name} {sorted(codes)}')
        result[name] = 'jp.n02.' + next(iter(codes))
    return result


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding='utf-8'))
    trips = validate(candidate)
    stations = station_ids(trips)
    known = {row['station_id'] for row in read_rows('normalized/station-identities*.jsonl', BASE / f'normalized/station-identities-{SUFFIX}.jsonl')}
    station_rows = [{'station_id': sid, 'name_snapshot': name, 'reference_kind': 'current_n02',
                     'current_source_code': sid.removeprefix('jp.n02.'), 'rail_history_id': None}
                    for name, sid in sorted(stations.items()) if sid not in known]
    versions, trip_rows, stop_rows, calendars, exceptions = [], [], [], [], []
    completeness, facts, queue = [], [], []
    for trip in trips:
        tid, number = trip['trip_id'], trip['train_number']
        vid, cid = tid + '.version', tid + '.calendar'
        versions.append({'timetable_version_id': vid, 'operator_scope': 'jr-hokkaido',
                         'effective_from': DAY, 'effective_until': UNTIL,
                         'edition_name': 'JR時刻表 令和8年10月号; selected exact 2026-09-30 column',
                         'revision_type': 'source_snapshot', 'completeness': 'partial', 'source_ids': [SOURCE]})
        trip_rows.append({'trip_id': tid, 'timetable_version_id': vid, 'service_id': trip['service_id'],
                          'calendar_id': cid, 'train_number': number, 'public_number': trip['public_number'],
                          'origin_station_id': stations[trip['origin']], 'destination_station_id': stations[trip['destination']],
                          'service_class': trip['service_class'],
                          'notes': 'Exact-date official column; unprinted intermediate arrival sides remain unknown.'})
        for sequence, (name, arrival, departure) in enumerate(trip['stops'], 1):
            call_type = 'origin' if sequence == 1 else 'destination' if sequence == len(trip['stops']) else 'passenger_stop'
            stop_rows.append({'trip_id': tid, 'stop_sequence': sequence, 'station_id': stations[name],
                              'arrival_time': arrival, 'departure_time': departure, 'day_offset': 0,
                              'call_type': call_type, 'pickup_allowed': int(call_type != 'destination'),
                              'dropoff_allowed': int(call_type != 'origin'), 'platform': trip['printed_platforms'].get(name),
                              'time_accuracy': 'minute', 'source_id': SOURCE})
        calendars.append({'calendar_id': cid, 'valid_from': DAY, 'valid_until': UNTIL,
                          'holiday_policy': 'none', **{weekday: 0 for weekday in WEEKDAYS}})
        exceptions.append({'calendar_id': cid, 'service_date': DAY, 'exception_type': 'add',
                           'reason': 'Exact selected date on operator timetable', 'source_id': SOURCE})
        statuses = {
            'identity': ('verified', 'high', f'Official {number} / {trip["service_name"]} column.'),
            'train_number': ('verified', 'high', f'Official column prints {number}.'),
            'validity_calendar': ('verified', 'high', 'Official selector is 2026-09-30.'),
            'origin_destination': ('verified', 'high', 'First and last timed passenger calls printed.'),
            'stops': ('verified', 'high', 'All passenger calls in selected column captured.'),
            'times': ('partial', 'medium', 'All printed clocks captured; most intermediate arrival sides are blank.'),
            'station_refs': ('verified', 'high', 'Names resolve to current JR Hokkaido N02 station groups.'),
            'operator': ('unknown', 'low', 'No dated ordered operator-segment proof.'),
            'route_lines': ('unknown', 'low', 'No dated ordered physical-line identities.'),
            'provenance': ('partial', 'medium', 'Official URL pinned; reuse grant unconfirmed.'),
        }
        for dimension, (status, confidence, note) in statuses.items():
            completeness.append({'entity_type': 'trip', 'entity_id': tid, 'dimension': dimension,
                                 'status': status, 'confidence': confidence, 'notes': note})
            if status in {'verified', 'partial'} and dimension != 'provenance':
                facts.append({'entity_type': 'trip', 'entity_id': tid, 'field_name': dimension,
                              'source_id': 'jtm-current-station-directory' if dimension == 'station_refs' else SOURCE,
                              'page_or_locator': 'app/public/rail/jp-2025.json' if dimension == 'station_refs' else trip['source_locator'],
                              'confidence': confidence, 'verification_status': status})
            if status != 'verified':
                queue.append({'research_id': f'{tid}.{dimension}', 'entity_type': 'trip', 'entity_id': tid,
                              'missing_dimension': dimension, 'status': 'open', 'notes': note})
    outputs = {
        BASE / f'sources/source-registry-{SUFFIX}.jsonl': [{
            'source_id': SOURCE, 'publisher': '北海道旅客鉄道株式会社 / 株式会社交通新聞社',
            'title': '［特急］オホーツク 1・［特快］大雪 3591D 下り 2026年9月30日 列',
            'source_type': 'official_timetable', 'url_or_locator': URL,
            'issue': 'JR時刻表 令和8年10月号', 'publication_date': None,
            'effective_date': DAY, 'accessed_at': DAY,
            'license_status': 'terms_published_no_reuse_grant_identified',
            'redistribution_status': 'verification_only', 'automated_extraction_allowed': False,
            'notes': 'Selected date, second and ninth train columns visually reviewed. Site prohibits unauthorized reproduction or processing.',
        }],
        BASE / f'normalized/timetable-versions-{SUFFIX}.jsonl': versions,
        BASE / f'normalized/station-identities-{SUFFIX}.jsonl': station_rows,
        BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl': trip_rows,
        BASE / f'normalized/stop-times/{SUFFIX}/seeds.jsonl': stop_rows,
        BASE / f'normalized/calendars/{SUFFIX}/seeds.jsonl': calendars,
        BASE / f'normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl': exceptions,
        BASE / f'normalized/fact-completeness-{SUFFIX}.jsonl': completeness,
        BASE / f'normalized/fact-sources-{SUFFIX}.jsonl': facts,
        BASE / f'normalized/research-queue-{SUFFIX}.jsonl': queue,
    }
    for path, records in outputs.items():
        write_jsonl(path, records)
    print(f'Staged 2 down trains and {len(stop_rows)} passenger calls')


if __name__ == '__main__':
    main()
