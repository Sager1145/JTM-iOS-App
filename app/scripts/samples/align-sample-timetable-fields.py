#!/usr/bin/env python3
"""Audit every sample against the Japan-only limited-express database.

Apply explicit sample region and only date/calendar/identity-backed timetable fields.
Generated regional station-ID normalization and cached route objects are preserved.
"""
import argparse
import copy
import datetime
import hashlib
import json
import re
import sqlite3
import subprocess
from collections import Counter
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
DATA = APP / 'data'
DB = DATA / 'train-service-history/derived/train-service-timetable.sqlite'
LEDGER = DATA / 'sample-timetable-field-audit.json'
TRAIN_FIELDS = ('number_en', 'train_type', 'vehicle_type', 'company', 'direction', 'notes')
STOP_FIELDS = ('arrival', 'departure', 'actual_arrival', 'actual_departure', 'platform_number')


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    compact = path.name.startswith('part-') or (path.exists() and len(path.read_text().splitlines()) == 1)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=None if compact else 2,
                               separators=(',', ':') if compact else None) + ('' if compact else '\n'))


def datasets():
    for path in sorted(DATA.glob('train-store*.json')):
        region = path.stem.removeprefix('train-store').strip('-') or 'jp'
        yield path.stem, region, path, DATA / ('sample-data' + ('' if region == 'jp' else '-' + region))
    for path in sorted((DATA / 'special-samples').glob('*.json')):
        yield path.stem, 'jp', path, DATA / (path.stem + '-data')


def route_source_hashes(region):
    suffix = '' if region == 'jp' else '-' + region
    paths = [APP / 'public/rail' / f'{region}-2025.json', DATA / f'rail-sections{suffix}.json',
             DATA / f'stations{suffix}.json', DATA / 'matched-routes.json', DATA / 'matched-stops.json']
    history = DATA / f'rail-history{suffix}.json'
    if history.exists():
        paths.append(history)
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def active(connection, trip, day):
    version = connection.execute('select * from timetable_versions where timetable_version_id=?',
                                 (trip['timetable_version_id'],)).fetchone()
    calendar = connection.execute('select * from calendars where calendar_id=?', (trip['calendar_id'],)).fetchone()
    # Version validity is independent of calendar exceptions and never backprojected.
    if not version['effective_from'] <= day < version['effective_until']:
        return False
    exception = connection.execute('select exception_type from calendar_exceptions where calendar_id=? and service_date=?',
                                   (trip['calendar_id'], day)).fetchone()
    if exception:
        return exception[0] == 'add'
    if not calendar['valid_from'] <= day < calendar['valid_until']:
        return False
    weekday = datetime.date.fromisoformat(day).weekday()
    if calendar['holiday_policy'] == 'treat_as_sunday':
        year = int(day[:4])
        status = connection.execute('select status from holiday_calendar_years where year=?', (year,)).fetchone()
        if not status or status[0] != 'verified':
            return False
        if connection.execute('select 1 from holiday_dates where service_date=?', (day,)).fetchone():
            weekday = 6
    return bool(calendar[('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')[weekday]])


def identity_candidates(connection, train):
    """Require a known service name and public number, never operating-number alone."""
    candidates = []
    for trip in connection.execute('select * from trips order by trip_id'):
        names = connection.execute('select name from service_name_periods where service_id=?', (trip['service_id'],))
        matching = [row[0] for row in names if row[0] in train['number']]
        if not matching:
            continue
        public = trip['public_number']
        if public and not any(re.search(re.escape(name) + r'\s*' + re.escape(public) + r'(?!\d)', train['number']) for name in matching):
            continue
        candidates.append(trip)
    return candidates


def ridden_calls(connection, trip, train):
    rows = list(connection.execute('select s.*,i.current_source_code,i.name_snapshot from stop_times s join station_identities i using(station_id) where trip_id=? order by stop_sequence', (trip['trip_id'],)))
    codes = [s.get('n02_station_code') for s in train['stops']]
    if not codes or not codes[0] or not codes[-1]:
        return None
    starts = [i for i, row in enumerate(rows) if row['current_source_code'] == codes[0]]
    ends = [i for i, row in enumerate(rows) if row['current_source_code'] == codes[-1]]
    windows = [rows[a:b + 1] for a in starts for b in ends if a < b]
    return windows[0] if len(windows) == 1 else None


def hhmm(seconds):
    return None if seconds is None else f'{seconds // 3600:02d}:{seconds % 3600 // 60:02d}'


def enrich(connection, train, trip, rows):
    updated = copy.deepcopy(train)
    changes = []
    # Match physical identifiers individually; do not infer missing physical track.
    by_code = {s['n02_station_code']: s for s in updated['stops'] if s.get('n02_station_code')}
    for row in rows:
        stop = by_code.get(row['current_source_code'])
        if stop is None or row['call_type'] not in ('origin', 'passenger_stop', 'destination') or row['time_accuracy'] not in ('minute', 'exact'):
            continue
        override = connection.execute('select * from trip_stop_time_overrides where trip_id=? and service_date=? and stop_sequence=?',
                                      (trip['trip_id'], train['date'], row['stop_sequence'])).fetchone()
        for field in ('arrival', 'departure'):
            # Ride boundaries intentionally omit off-ride arrivals/departures.
            if (field == 'arrival' and stop is updated['stops'][0]) or (field == 'departure' and stop is updated['stops'][-1]):
                continue
            seconds = row[field + '_seconds']
            if override and override[field + '_override'] is not None:
                seconds = override[field + '_seconds_override']
            value = hhmm(seconds)
            if value is not None and stop.get(field) != value:
                stop[field] = value
                changes.append(f"stops.{row['current_source_code']}.{field}")
        platform = row['platform']
        if override and override['platform_override_present']:
            platform = override['platform_override']
        if platform is not None and re.fullmatch(r'\d+', str(platform)) and stop.get('platform_number') != int(platform):
            stop['platform_number'] = int(platform)
            changes.append(f"stops.{row['current_source_code']}.platform_number")
    # Direction/vehicle are set only if dated facts exist, never from brand heuristics.
    if trip['direction'] and updated.get('direction') != trip['direction']:
        updated['direction'] = trip['direction']
        changes.append('direction')
    formation = connection.execute('select vehicle_series from trip_formations where trip_id=? and service_date=?',
                                   (trip['trip_id'], train['date'])).fetchone()
    if formation and formation[0] and updated.get('vehicle_type') != formation[0]:
        updated['vehicle_type'] = formation[0]
        changes.append('vehicle_type')
    return updated, changes


def caption_vehicle(caption):
    match = re.search(r'(?<![A-Za-z0-9])([A-Za-z]?\d+系)(?!統)', caption)
    return match[1] if match else None


def metadata(train):
    return {k: v for k, v in train.items() if k not in ('stops', 'route_sections')}


def latin_captions():
    # Execute the app's actual caption contract, normalizing only bracket width.
    script = r"""
const fs=require('fs'), vm=require('vm');
const source=fs.readFileSync(process.argv[1], 'utf8');
const begin=source.indexOf('function splitLegacyServiceCaption(');
const end=source.indexOf('\nfunction normalizeImportedTrain(',begin);
if(begin<0 || end<0) throw Error('Caption contract unavailable');
const context=vm.createContext({});
vm.runInContext(source.slice(begin,end),context);
const trains=JSON.parse(fs.readFileSync(0,'utf8'));
const result={};
for(const train of trains){
  const caption=train.number.replaceAll('（','(').replaceAll('）',')');
  const split=context.splitLegacyServiceCaption(caption);
  if(split.latinName) result[train.id]=split.latinName;
}
process.stdout.write(JSON.stringify(result));
"""
    trains = [train for _, _, source, _ in datasets() for train in read(source)['trains']]
    result = subprocess.run(['node', '-e', script, str(APP / 'public/app-store-ops.js')],
                            input=json.dumps(trains), text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    connection = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    connection.row_factory = sqlite3.Row
    inventory, counts, seen = [], Counter(), set()
    latin_names = latin_captions()
    for name, region, source, directory in datasets():
        canonical = read(source)
        generated = read(directory / 'sample-full.json') if directory.exists() else None
        manifest = read(directory / 'manifest.json') if generated else None
        expected_sources = route_source_hashes(region) if generated else None
        if generated:
            if args.check:
                assert manifest.get('source_hashes') == expected_sources, f'Stale route inputs: {directory}'
            assert len(canonical['trains']) == len(generated['trains']) == manifest['total'] == len(manifest['parts']), name
        source_dirty = full_dirty = False
        na_station_codes = {feature['properties']['n02_station_code'] for feature in read(DATA / f'stations-{region}.json')['features']} if region in ('us', 'ca') else None
        for index, train in enumerate(canonical['trains']):
            assert train['id'] not in seen, train['id']
            seen.add(train['id'])
            assert train.get('region', region) == region, train['id']
            updated = copy.deepcopy(train)
            updated['region'] = region
            status, matches, fields = 'outside_japan_scope', [], []
            if train['id'] in latin_names:
                updated['number_en'] = latin_names[train['id']]
                fields.append('number_en')
                counts['existing_caption_english_fields'] += 1
            candidates = []
            vehicle_match = caption_vehicle(train['number'])
            if vehicle_match:
                updated['vehicle_type'] = vehicle_match
                fields.append('vehicle_type')
                counts['existing_caption_vehicle_fields'] += 1
            if region == 'jp':
                status = 'outside_limited_express_scope'
                if train['train_type'] in ('特急', '寝台特急'):
                    candidates = identity_candidates(connection, train)
                    matches = [(trip, ridden_calls(connection, trip, train)) for trip in candidates if active(connection, trip, train['date'])]
                    matches = [(trip, rows) for trip, rows in matches if rows is not None]
                    status = 'no_database_trip_identity' if not candidates else 'no_date_valid_ridden_trip'
                    if len(matches) == 1:
                        status = 'date_valid_ridden_trip'
                        updated, timetable_fields = enrich(connection, updated, *matches[0])
                        fields.extend(timetable_fields)
                    elif len(matches) > 1:
                        status = 'ambiguous_date_valid_ridden_trip'
            counts[status] += 1
            counts['inventory'] += 1
            counts['region_' + region] += 1
            if updated != train:
                assert not args.check, f'Unapplied fields: {train["id"]}'
                canonical['trains'][index] = updated
                source_dirty = True
            if generated:
                full_train = generated['trains'][index]
                part_path = directory / (manifest['parts'][index] + '.json')
                part = read(part_path)
                if args.check:
                    assert part.get('source_hashes') == expected_sources, f'Stale route inputs: {part_path}'
                assert full_train['id'] == train['id'] and part['train'] == full_train, part_path
                # Keep generated IDs/routes, overlay only region and changed timetable fields.
                revised = copy.deepcopy(full_train)
                revised['region'] = region
                for field in fields:
                    if not field.startswith('stops.'):
                        revised[field] = updated[field]
                    else:
                        _, code, key = field.split('.')
                        origin_stop = next(s for s in updated['stops'] if s.get('n02_station_code') == code)
                        target = next(s for s in revised['stops'] if s.get('n02_station_code') == code)
                        target[key] = origin_stop[key]
                assert metadata(updated) == metadata(revised), f'Metadata mismatch: {train["id"]}'
                stop_metadata = lambda stops: [{k: v for k, v in stop.items() if k not in ('name', 'n02_station_code')} for stop in stops]
                assert stop_metadata(updated['stops']) == stop_metadata(revised['stops']), f'Stop metadata mismatch: {train["id"]}'
                section_metadata = lambda sections: [{k: v for k, v in section.items() if k not in ('from', 'to', 'from_n02_station_code', 'to_n02_station_code')} for section in sections]
                assert section_metadata(updated.get('route_sections', [])) == section_metadata(revised.get('route_sections', [])), f'Section metadata mismatch: {train["id"]}'
                if revised != full_train:
                    assert not args.check, f'Unapplied generated fields: {train["id"]}'
                    part['train'] = revised
                    save(part_path, part)
                    generated['trains'][index] = revised
                    full_dirty = True
            inventory.append({'dataset': name, 'region': region, 'train_id': train['id'], 'date': train['date'],
                              'status': status, 'identity_candidates': [t['trip_id'] for t in candidates],
                              'matched_trip_id': matches[0][0]['trip_id'] if len(matches) == 1 else None,
                              'aligned_fields': fields,
                              'english_field_source': 'existing_bilingual_caption' if train['id'] in latin_names else None,
                              'vehicle_field_source': 'existing_vehicle_caption' if vehicle_match else None,
                              'missing_train_fields': [k for k in TRAIN_FIELDS if updated.get(k) in (None, '', 'unknown')],
                              'missing_stop_field_counts': {k: sum(s.get(k) in (None, '') for s in updated['stops']) for k in STOP_FIELDS},
                              'missing_section_operating_numbers': sum(not section.get('number') for section in updated.get('route_sections', [])),
                              'unresolved_current_station_ids': [stop['n02_station_code'] for stop in updated['stops'] if stop.get('n02_station_code') not in na_station_codes] if na_station_codes is not None else None,
                              'generated_copy': bool(generated),
                              'generated_station_ids_normalized': bool(generated and [s.get('n02_station_code') for s in updated['stops']] != [s.get('n02_station_code') for s in generated['trains'][index]['stops']])})
        if source_dirty:
            save(source, canonical)
        if full_dirty:
            save(directory / 'sample-full.json', generated)
    missing = Counter(k for item in inventory for k in item['missing_train_fields'])
    ledger = {'format': 1, 'database_sha256': hashlib.sha256(DB.read_bytes()).hexdigest(),
              'scope': 'All sample stores; Japan-only limited express evidence; no timetable backprojection. Missing times at ride boundaries/pass-through stations are often intentional.',
              'counts': dict(sorted(counts.items())), 'missing_train_field_counts': dict(sorted(missing.items())), 'inventory': inventory}
    if args.check:
        assert read(LEDGER) == ledger, 'Field audit ledger stale'
    else:
        save(LEDGER, ledger)
    print(json.dumps(ledger['counts'], ensure_ascii=False))


if __name__ == '__main__':
    main()
