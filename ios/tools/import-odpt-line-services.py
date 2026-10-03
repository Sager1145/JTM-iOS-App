#!/usr/bin/env python3
"""Normalize an offline licensed ODPT export using explicit reviewed identity maps."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def iso_date(value):
    if not isinstance(value, str) or dt.date.fromisoformat(value).isoformat() != value:
        raise ValueError('Expected an ISO Gregorian date')
    return value


def time_seconds(value, previous):
    if value is None:
        return None
    parts = value.split(':')
    if len(parts) not in (2, 3) or not all(part.isdigit() for part in parts):
        raise ValueError('Invalid ODPT time: ' + value)
    hour, minute = map(int, parts[:2])
    second = int(parts[2]) if len(parts) == 3 else 0
    if hour > 47 or minute > 59 or second > 59:
        raise ValueError('ODPT time outside supported service day')
    seconds = hour * 3600 + minute * 60 + second
    # Preserve explicit 24:xx values. Unqualified clocks after midnight
    # inherit the established day, but a daytime regression is not a 24-hour wait.
    if hour < 24 and previous >= 86400:
        seconds += (previous // 86400) * 86400
    if seconds < previous:
        if hour < 6 and previous % 86400 >= 18 * 3600:
            seconds += 86400
        else:
            raise ValueError('Backwards times without an evidenced midnight transition')
    if seconds >= 172800:
        raise ValueError('More than one midnight crossing or inconsistent times')
    return seconds


def mapped(mapping, category, identity):
    value = mapping.get(category, {}).get(identity)
    if not isinstance(value, dict):
        raise ValueError(f'Unmapped or ambiguous {category} identity: {identity}')
    return value


def references(value):
    if value is None:
        return []
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise ValueError('Invalid previous/next train references')
    return value


def normalize(rows, mapping, provenance, package):
    if not isinstance(rows, list):
        raise ValueError('Expected an ODPT TrainTimetable array')
    start, end = iso_date(provenance['validFrom']), iso_date(provenance['validUntil'])
    observed = iso_date(provenance['observedOn'])
    if start >= end or not provenance['sourceURL'].startswith('https://'):
        raise ValueError('Invalid source URL or validity interval')
    registry = {line['id']: line for line in package['lines']}
    inventory = {}
    trips = []
    seen = set()
    for row in rows:
        if row.get('@type') != 'odpt:TrainTimetable':
            raise ValueError('Only odpt:TrainTimetable records are accepted')
        identity = row.get('owl:sameAs')
        if not isinstance(identity, str) or not identity or identity in seen:
            raise ValueError('Missing or duplicate ODPT trip identity')
        seen.add(identity)
        railway = mapped(mapping, 'railways', row.get('odpt:railway'))
        line_ids = railway['lineIDs']
        if not isinstance(line_ids, list) or not line_ids or len(set(line_ids)) != len(line_ids):
            raise ValueError('Ambiguous physical line mapping')
        operator = mapped(mapping, 'operators', row.get('odpt:operator'))['operatorName']
        if operator != railway['operatorName']:
            raise ValueError('Operator does not match reviewed railway mapping')
        kind = mapped(mapping, 'trainTypes', row.get('odpt:trainType'))
        calendar = mapped(mapping, 'calendars', row.get('odpt:calendar'))
        dates = calendar['serviceDates']
        if not dates or any(not start <= iso_date(date) < end for date in dates):
            raise ValueError('Calendar dates must fall within the explicit effective interval')
        station_codes = set()
        for lid in line_ids:
            line = registry.get(lid)
            if line is None or line['operator'] != operator:
                raise ValueError('Unknown compact line or wrong operator: ' + lid)
            station_codes.update(station[0] for station in line['stations'])
        if not isinstance(row.get('odpt:trainNumber', ''), str):
            raise ValueError('Train number must be a string; no service class inference')
        stops, previous = [], -1
        for call in row.get('odpt:trainTimetableObject', []):
            station_id = call.get('odpt:arrivalStation') or call.get('odpt:departureStation')
            if call.get('odpt:arrivalStation') and call.get('odpt:departureStation') and call['odpt:arrivalStation'] != call['odpt:departureStation']:
                raise ValueError('Arrival and departure station disagree')
            station = mapped(mapping, 'stations', station_id)
            if station['stationCode'] not in station_codes:
                raise ValueError('Station is not on an explicitly mapped physical line')
            arrival = time_seconds(call.get('odpt:arrivalTime'), previous)
            departure = time_seconds(call.get('odpt:departureTime'), arrival if arrival is not None else previous)
            if arrival is None and departure is None:
                raise ValueError('Stop has no time')
            previous = departure if departure is not None else arrival
            stops.append(dict(stationCode=station['stationCode'], stationName=station['stationName'],
                              arrivalSeconds=arrival, departureSeconds=departure))
        if len(stops) < 2:
            raise ValueError('At least two researched calls are required')
        for lid in line_ids:
            line = registry[lid]
            entry = inventory.setdefault(lid, dict(lineID=lid, operatorName=operator, lineName=line['name'],
                aliases=[], coverage='partial', kinds=[], note='Imported licensed ODPT export; only explicit dates and mapped sections are covered.'))
            evidence = dict(id=hashlib.sha256((lid + row['odpt:trainType'] + provenance['sourceURL'] + start + end).encode()).hexdigest()[:20],
                displayName=kind['displayName'], trainType=kind['trainType'], sourceURL=provenance['sourceURL'],
                validFrom=start, validUntil=end, scope=railway['scope'], fromStationCode=None, toStationCode=None, observedOn=observed)
            if evidence not in entry['kinds']:
                entry['kinds'].append(evidence)
        trips.append(dict(id=identity, trainNumber=row.get('odpt:trainNumber') or '', trainType=kind['trainType'],
            operatorName=operator, lineIDs=line_ids, serviceDates=sorted(set(dates)), sourceURL=provenance['sourceURL'],
            coverage='partial', note='Published ODPT stop calls for explicitly reviewed calendar dates; not an actual-operation report.',
            stops=stops, sourceOperatorID=row['odpt:operator'], sourceRailwayID=row['odpt:railway'],
            sourceTrainTypeID=row['odpt:trainType'], sourceCalendarID=row['odpt:calendar'], previousTrainIDs=references(row.get('odpt:previousTrain')), nextTrainIDs=references(row.get('odpt:nextTrain'))))
    return dict(schemaVersion=1, inventoryVersion=package['version'], observedOn=observed,
                lines=list(inventory.values()), trips=trips)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', required=True, type=Path)
    parser.add_argument('--mapping', required=True, type=Path)
    parser.add_argument('--provenance', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--package', type=Path, default=ROOT / 'app/public/rail/jp-2025.json')
    args = parser.parse_args()
    read = lambda path: json.loads(path.read_text())
    result = normalize(read(args.export), read(args.mapping), read(args.provenance), read(args.package))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f"Imported {len(result['trips'])} explicitly dated trips across {len(result['lines'])} mapped lines")

if __name__ == '__main__':
    main()
