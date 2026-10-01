#!/usr/bin/env python3
"""Stage two date-selected JR Kyushu train-detail columns without shared rebuild."""
import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SUFFIX = 'kyushu-hyuga13-14-16-20260930'
DATE, UNTIL = '2026-09-30', '2026-10-01'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
FILES = tuple(f'jr-kyushu-hyuga{n}-20260930.json' for n in (13, 14, 16))
EXPECTED = {
    '5083M': ('hyuga', 'ひゅうが', '13', '延岡', '宮崎空港', 10, '17:35', '18:59', '９月１９・２２・２３日は運休'),
    '5084M': ('hyuga', 'ひゅうが', '14', '宮崎空港', '延岡', 10, '21:30', '23:04', '毎日運転'),
    '5086M': ('hyuga', 'ひゅうが', '16', '南宮崎', '延岡', 9, '22:40', '23:58', '毎日運転'),
}


def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude or not path.is_file():
            continue
        for line in path.read_text(encoding='utf-8').splitlines():
            if line.strip():
                yield json.loads(line)


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n'
                            for row in records), encoding='utf-8')


def read_candidates():
    manifest = json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))
    if DATE > manifest['as_of_date']:
        raise ValueError('Service date exceeds manifest cutoff')
    trips = []
    for filename in FILES:
        candidate = json.loads((BASE / 'candidates' / filename).read_text(encoding='utf-8'))
        if (candidate['candidate_status'], candidate['canonical'], candidate['service_date']) != ('reviewed_official_html', False, DATE):
            raise ValueError('Candidate review state or date changed')
        trip, = candidate['trips']
        if candidate['candidate_id'] != filename.removesuffix('.json'):
            raise ValueError('Candidate identity changed')
        trips.append(trip)
    if {t['train_number'] for t in trips} != set(EXPECTED):
        raise ValueError('Train-number set changed')
    existing_trips = {r['trip_id'] for r in rows('normalized/trips/*/*.jsonl', BASE / f'normalized/trips/{SUFFIX}/seeds.jsonl')}
    existing_sources = {r['source_id']: r for r in rows(
        'sources/source-registry*.jsonl', BASE / f'sources/source-registry-{SUFFIX}.jsonl')}
    for trip in trips:
        number = trip['train_number']
        sid, name, public, origin, destination, count, first, last, marker = EXPECTED[number]
        tid = f'jr-kyushu.{sid}.{public}.{DATE}'
        source_id = f'jr-kyushu-{sid}{public}-20260930'
        if (trip['trip_id'], trip['service_id'], trip['service_name'], trip['service_class'], trip['public_number'],
            trip['origin'], trip['destination'], trip['source_id'], trip['operating_day_marker']) != (
            tid, sid, name, 'limited_express', public, origin, destination, source_id, marker):
            raise ValueError(f'Trip identity changed: {number}')
        if tid in existing_trips or source_id in existing_sources or 'd=20260930' not in trip['source_url']:
            raise ValueError(f'Duplicate trip/source or undated source: {number}')
        stops = trip['stops']
        if len(stops) != count or stops[0][:3] != [origin, None, first] or stops[-1][:3] != [destination, last, None] or len({s[0] for s in stops}) != count:
            raise ValueError(f'Stop chain changed: {number}')
        previous = None
        for station, arrival, departure, platform in stops:
            if arrival is None and departure is None:
                raise ValueError(f'Untimed call: {number} {station}')
            if platform is not None and (station, platform) not in set():
                raise ValueError(f'Unexpected platform: {number} {station}')
            for clock in (arrival, departure):
                if clock is not None:
                    parsed = datetime.strptime(clock, '%H:%M')
                    if previous is not None and parsed < previous:
                        raise ValueError(f'Clock reversal: {number} {station}')
                    previous = parsed
    return trips


def station_ids(trips):
    package = json.loads((ROOT / 'app/public/rail/jp-2025.json').read_text(encoding='utf-8'))
    result = {}
    for name in {stop[0] for trip in trips for stop in trip['stops']}:
        matches = {station[0] for line in package['lines'] if line['operator'] == '九州旅客鉄道'
                   for station in line['stations'] if station[1] == name}
        if len(matches) != 1:
            raise ValueError(f'Ambiguous station: {name} {sorted(matches)}')
        result[name] = 'jp.n02.' + next(iter(matches))
    return result


def main():
    trips = read_candidates()
    stations = station_ids(trips)
    known_stations = {r['station_id'] for r in rows('normalized/station-identities*.jsonl', BASE / f'normalized/station-identities-{SUFFIX}.jsonl')}
    new_stations = [{'station_id': sid, 'name_snapshot': name, 'reference_kind': 'current_n02',
                     'current_source_code': sid.removeprefix('jp.n02.'), 'rail_history_id': None}
                    for name, sid in sorted(stations.items()) if sid not in known_stations]
    versions, trip_rows, stop_rows, calendars, exceptions = [], [], [], [], []
    formations, completeness, facts, queue, sources = [], [], [], [], []
    for trip in trips:
        tid, number, sid, source_id = trip['trip_id'], trip['train_number'], trip['service_id'], trip['source_id']
        version_id, calendar_id = tid + '.version', tid + '.calendar'
        versions.append({'timetable_version_id': version_id, 'operator_scope': 'jr-kyushu',
                         'effective_from': DATE, 'effective_until': UNTIL,
                         'edition_name': 'JR時刻表2026年10月号 selected 2026-09-30 train detail',
                         'revision_type': 'source_snapshot', 'completeness': 'partial', 'source_ids': [source_id]})
        trip_rows.append({'trip_id': tid, 'timetable_version_id': version_id, 'service_id': sid,
                          'calendar_id': calendar_id, 'train_number': number, 'public_number': trip['public_number'],
                          'origin_station_id': stations[trip['origin']], 'destination_station_id': stations[trip['destination']],
                          'service_class': 'limited_express',
                          'notes': 'Selected-date official detail; printed passenger calls and clocks only.'})
        for sequence, (name, arrival, departure, platform) in enumerate(trip['stops'], 1):
            call = 'origin' if sequence == 1 else 'destination' if sequence == len(trip['stops']) else 'passenger_stop'
            stop_rows.append({'trip_id': tid, 'stop_sequence': sequence, 'station_id': stations[name],
                              'arrival_time': arrival, 'departure_time': departure, 'day_offset': 0,
                              'call_type': call, 'pickup_allowed': int(call != 'destination'),
                              'dropoff_allowed': int(call != 'origin'), 'platform': platform,
                              'time_accuracy': 'minute', 'source_id': source_id})
        calendars.append({'calendar_id': calendar_id, 'valid_from': DATE, 'valid_until': UNTIL,
                          'holiday_policy': 'none', **{day: 0 for day in WEEKDAYS}})
        exceptions.append({'calendar_id': calendar_id, 'service_date': DATE, 'exception_type': 'add',
                           'reason': 'Exact date selected on operator page', 'source_id': source_id})
        formations.append({'formation_id': f'{tid}.formation.{DATE}', 'trip_id': tid,
                           'service_date': DATE, 'evidence_kind': 'planned', 'all_reserved': False,
                           'green_car_available': True, 'source_id': source_id,
                           'notes': 'Printed seat categories: ' + ' / '.join(trip['formation_seat_text'])
                           + '. Vehicle series, car count and individual car assignments are not date-confirmed.'})
        statuses = {
            'identity': ('verified','high','Official detail prints train name and public number.'),
            'train_number': ('verified','high',f'Official detail prints {number}.'),
            'validity_calendar': ('verified','high',f'Selected date {DATE}; {trip["operating_day_marker"]}.'),
            'origin_destination': ('verified','high','Both endpoints printed.'),
            'stops': ('verified','high','Every printed passenger stop captured.'),
            'times': ('verified','high','All printed arrival/departure clock sides retained.'),
            'station_refs': ('verified','high','Names resolve to current JR Kyushu N02 stations.'),
            'formation': ('partial','high','Printed seat categories only; consist and car details unverified.'),
            'operator': ('unknown','low','Ordered operator boundaries not independently established.'),
            'route_lines': ('unknown','low','Dated ordered physical line identities not established.'),
            'provenance': ('partial','medium','Official URL pinned; reuse grant unconfirmed.'),
        }
        for dimension, (status, confidence, note) in statuses.items():
            completeness.append({'entity_type':'trip','entity_id':tid,'dimension':dimension,
                                 'status':status,'confidence':confidence,'notes':note})
            if status in {'verified','partial'} and dimension != 'provenance':
                facts.append({'entity_type':'trip','entity_id':tid,'field_name':dimension,
                              'source_id':'jtm-current-station-directory' if dimension == 'station_refs' else source_id,
                              'page_or_locator':'app/public/rail/jp-2025.json' if dimension == 'station_refs' else trip['source_locator'],
                              'confidence':confidence,'verification_status':status})
            if status != 'verified':
                queue.append({'research_id':f'{tid}.{dimension}','entity_type':'trip','entity_id':tid,
                              'missing_dimension':dimension,'status':'open','notes':note})
        sources.append({'source_id':source_id,'publisher':'九州旅客鉄道株式会社 / 株式会社交通新聞社',
                        'title':f'{trip["service_name"]} {trip["public_number"]}号 列車詳細 2026年9月30日',
                        'source_type':'official_train_timetable','url_or_locator':trip['source_url'],
                        'issue':'JR時刻表2026年10月号','publication_date':None,'effective_date':DATE,
                        'accessed_at':DATE,'license_status':'third_party_timetable_data_terms_apply',
                        'redistribution_status':'verification_only','automated_extraction_allowed':False,
                        'notes':'Date-selected official train detail visually reviewed. No HTML snapshot redistributed.'})
    outputs = {
        BASE / f'sources/source-registry-{SUFFIX}.jsonl': sources,
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
    print(f'Staged {len(trip_rows)} trips, {len(stop_rows)} passenger calls and {len(formations)} seat-category formations')


if __name__ == '__main__':
    main()
