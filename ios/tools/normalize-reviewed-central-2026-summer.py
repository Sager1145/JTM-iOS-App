#!/usr/bin/env python3
"""Normalize JR Central's dated 2026 Hida/Nanki temporary endpoint rows."""
from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
CANDIDATE = BASE / 'candidates/jr-central-20260526-hida-nanki-summer.json'
SOURCE_PATH = BASE / 'sources/source-registry-central-2026-summer.jsonl'
SUFFIX = 'central-2026-summer'
BATCH = 'reviewed-central-2026-summer'
WEEKDAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
DIRECTORY_SOURCE = 'jtm-current-station-directory'


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n' for row in rows), encoding='utf-8')


def rows(pattern, excluded=None):
    for path in sorted(BASE.glob(pattern)):
        if path == excluded or not path.is_file():
            continue
        for raw in path.read_text(encoding='utf-8').splitlines():
            if raw:
                yield json.loads(raw)


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding='utf-8'))
    if (candidate['candidate_status'], candidate['canonical'], candidate['promotion_scope']) != (
        'reviewed_official_pdf', True,
        'only_the_eight_printed_trips_on_explicit_2026_dates_with_endpoint_times',
    ):
        raise ValueError('JR Central 2026 promotion scope changed')
    source = candidate['source']
    source_id = source['source_id']
    if (source_id, source['url_or_locator'], source['publication_date']) != (
        'jr-central-hida-nanki-summer-supplement-20260526',
        'https://jr-central.co.jp/news/release/_pdf/000045605.pdf', '2026-05-26',
    ):
        raise ValueError('JR Central 2026 official source changed')
    if any(row['source_id'] == source_id for row in rows('sources/source-registry*.jsonl', SOURCE_PATH)):
        raise ValueError('Duplicate JR Central 2026 source id')
    as_of = json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))['as_of_date']
    names = {'hida': 'ひだ', 'nanki': '南紀'}
    service_rows = {row['service_id']: row for row in rows('normalized/services*.jsonl')}
    for service_id, name in names.items():
        service = service_rows.get(service_id)
        if not service or service['canonical_name'] != name or service['service_class'] != 'limited_express':
            raise ValueError(f'Missing established limited express identity {service_id}')

    package = json.loads((ROOT / 'app/public/rail/jp-2025.json').read_text(encoding='utf-8'))
    operators = {'名古屋': '東海旅客鉄道', '高山': '東海旅客鉄道', '紀伊勝浦': '西日本旅客鉄道'}
    stations = {}
    for name, operator in operators.items():
        codes = {station[0] for line in package['lines'] if line['operator'] == operator
                 for station in line['stations'] if station[1] == name}
        if len(codes) != 1:
            raise ValueError(f'Ambiguous current station identity {name}: {codes}')
        stations[name] = 'jp.n02.' + codes.pop()
    existing_stations = {row['station_id']: row for row in rows('normalized/station-identities*.jsonl')}
    station_rows = []
    for name, station_id in stations.items():
        expected = {'station_id': station_id, 'name_snapshot': name,
                    'reference_kind': 'current_n02', 'current_source_code': station_id.removeprefix('jp.n02.')}
        existing = existing_stations.get(station_id)
        if existing is not None and any(existing.get(key) != value for key, value in expected.items()):
            raise ValueError(f'Conflicting station identity {station_id}')
        if existing is None:
            station_rows.append(expected)
    if DIRECTORY_SOURCE not in {row['source_id'] for row in rows('sources/source-registry*.jsonl')}:
        raise ValueError('Current station directory source is missing')

    data = defaultdict(list)
    data['station-identities'] = station_rows
    all_dates = sorted({day for group in candidate['date_groups'].values() for day in group})
    if not all_dates or all_dates[-1] > as_of or all_dates[0] != '2026-07-18' or all_dates[-1] != '2026-09-23':
        raise ValueError('Date bounds changed or exceed manifest cutoff')
    for service_id, name in names.items():
        data['service-name-periods'].append(dict(service_id=service_id, name=name, language='ja',
            valid_from=all_dates[0], valid_until=(date.fromisoformat(all_dates[-1])+timedelta(days=1)).isoformat(),
            name_type='display', source_id=source_id))
    if len(candidate['trips']) != 8:
        raise ValueError('Expected exactly eight printed rows')
    trip_ids = set()
    for item in candidate['trips']:
        service_id = item['service_id']
        if service_id not in names or item['service_name'] != names[service_id]:
            raise ValueError('Unexpected service name')
        dates = sorted(set(candidate['date_groups'][item['date_group']]))
        if not dates or dates[-1] > as_of or any(date.fromisoformat(day).isoformat() != day for day in dates):
            raise ValueError('Invalid explicit operating dates')
        number = item['public_number']
        if number not in {'81', '82', '83', '84'}:
            raise ValueError('Unexpected public number')
        trip = f'jr-central.{service_id}.{number}.2026-summer'
        if trip in trip_ids:
            raise ValueError('Duplicate trip')
        trip_ids.add(trip)
        calendar = trip + '.calendar'
        version = trip + '.version'
        start = dates[0]
        until = (date.fromisoformat(dates[-1]) + timedelta(days=1)).isoformat()
        data['timetable-versions'].append(dict(timetable_version_id=version, operator_scope='jr-central',
            effective_from=start, effective_until=until, edition_name='2026 summer temporary Hida/Nanki supplement',
            revision_type='planned_exception', publication_date=source['publication_date'],
            completeness='partial', source_ids=[source_id]))
        data['calendars'].append(dict(calendar_id=calendar, valid_from=start, valid_until=until,
            holiday_policy='none', **{day: 0 for day in WEEKDAYS}))
        data['calendar-exceptions'].extend(dict(calendar_id=calendar, service_date=day,
            exception_type='add', source_id=source_id,
            reason=f'Explicit operating date in official PDF physical page {item["page"]}') for day in dates)
        origin, destination = stations[item['origin']], stations[item['destination']]
        data['trips'].append(dict(trip_id=trip, timetable_version_id=version, service_id=service_id,
            calendar_id=calendar, train_number=None, public_number=number,
            origin_station_id=origin, destination_station_id=destination,
            service_class='limited_express', notes='Official planned temporary train. Only endpoint clocks and explicit dates are known; intermediate calls, internal train number, physical route and actual operation remain unverified.'))
        data['stop-times'].extend([
            dict(trip_id=trip, stop_sequence=1, station_id=origin, arrival_time=None,
                 departure_time=item['departure'], day_offset=0, call_type='origin',
                 pickup_allowed=1, dropoff_allowed=0, time_accuracy='minute', source_id=source_id),
            dict(trip_id=trip, stop_sequence=2, station_id=destination, arrival_time=item['arrival'],
                 departure_time=None, day_offset=0, call_type='destination',
                 pickup_allowed=0, dropoff_allowed=1, time_accuracy='minute', source_id=source_id),
        ])
        statuses = {'identity': 'verified', 'train_number': 'unknown',
                    'operator': 'unknown', 'validity_calendar': 'verified', 'origin_destination': 'verified',
                    'stops': 'partial', 'times': 'partial', 'route_lines': 'unknown',
                    'station_refs': 'verified', 'provenance': 'partial'}
        for dimension, status in statuses.items():
            confidence = 'high' if status == 'verified' else 'low' if status == 'unknown' else 'medium'
            note = ('Official supplement supplies explicit dates and endpoint clocks only. '
                    'Current station IDs are unique name matches, not proof of the physical route.')
            data['fact-completeness'].append(dict(entity_type='trip', entity_id=trip, dimension=dimension,
                status=status, confidence=confidence, notes=note))
            if status != 'unknown':
                data['fact-sources'].append(dict(entity_type='trip', entity_id=trip, field_name=dimension,
                    source_id=DIRECTORY_SOURCE if dimension == 'station_refs' else source_id,
                    page_or_locator='Current N02 directory unique name/code match' if dimension == 'station_refs'
                        else f'Official PDF physical page {item["page"]}, {item["service_name"]} {number} row',
                    confidence=confidence, verification_status=status))
            if status != 'verified':
                data['research-queue'].append(dict(research_id=f'{trip}.{dimension}', entity_type='trip',
                    entity_id=trip, missing_dimension=dimension,
                    status='license_blocked' if dimension == 'provenance' else 'open',
                    notes='Find a dated official all-stop timetable, train number, route/operator evidence, or a reuse grant as applicable.'))
    # Coverage declarations are unique per operator/year/dimension. The root
    # JR Central 2026 declaration remains partial and owns that scope.
    write(SOURCE_PATH, [source])
    write(BASE / f'normalized/coverage-declarations-{SUFFIX}.jsonl', [])
    for entity, records in data.items():
        path = (BASE / f'normalized/{entity}/{BATCH}/seeds.jsonl' if entity in
                {'trips', 'stop-times', 'calendars', 'calendar-exceptions'} else
                BASE / f'normalized/{entity}-{SUFFIX}.jsonl')
        write(path, records)
    print(f'Central 2026 summer: {len(trip_ids)} trips, {len(data["calendar-exceptions"])} exact dates, {len(data["stop-times"])} endpoint rows')


if __name__ == '__main__':
    main()
