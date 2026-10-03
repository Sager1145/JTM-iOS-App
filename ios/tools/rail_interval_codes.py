"""Physical interval identity shared with RailCore and the Web display network.

The compact package remains positional. IDs use the owning full line ID and
unordered endpoint IDs; repeated pairs carry an occurrence suffix. A chain
retains travel order separately, so reversing a journey reverses its code list.
"""
from collections import Counter, defaultdict
import heapq
import itertools

NEX_SOURCE = 'https://www.jreast.co.jp/train/express/nex.html'
NEX_PREFIX = 'jp-東日本旅客鉄道-'


def interval_rows(package):
    rows = []
    for line in package['lines']:
        stations = line['stations']
        pairs = [(str(stations[index][0]), str(stations[(index + 1) % len(stations)][0]))
                 for index in range(len(line['segments']))
                 if index + 1 < len(stations) or line.get('isLoop')]
        bases = [line['id'] + '@' + ':'.join(sorted(pair)) for pair in pairs]
        counts, seen = Counter(bases), Counter()
        for index, ((left, right), base) in enumerate(zip(pairs, bases)):
            seen[base] += 1
            code = base if counts[base] == 1 else f'{base}~{seen[base]}'
            rows.append(dict(section_code=code, line_id=line['id'],
                             from_station_code=left, to_station_code=right,
                             segment_index=index, line_name=line['name'],
                             operator_name=line.get('operator', '')))
    return rows


def line_chain(line, from_code, to_code, rows):
    ids = [str(station[0]) for station in line['stations']]
    if ids.count(from_code) != 1 or ids.count(to_code) != 1:
        return []
    start, end = ids.index(from_code), ids.index(to_code)
    by_index = {row['segment_index']: row['section_code'] for row in rows if row['line_id'] == line['id']}
    indices = range(start, end) if start < end else range(start - 1, end - 1, -1)
    return [by_index[index] for index in indices]


def nex_route_sections(package, calls):
    """Resolve only the reviewed NEX corridors, excluding parallel surface track.

    JR East identifies Sobu/Narita/Yokosuka as NEX infrastructure. Package
    identity 総武線-3 owns the Tokyo underground and Hinkaku/Yokosuka corridor.
    The bounded western connections are Yamanote Shinagawa–Shinjuku and Chuo
    west of Shinjuku; Tokaido is allowed only south of Tsurumi where it owns
    the shared Yokosuka alignment in this package.
    """
    intervals = interval_rows(package)
    by_line = {line['id']: line for line in package['lines']}
    graph = defaultdict(list)
    for row in intervals:
        name = row['line_id'].removeprefix(NEX_PREFIX)
        line = by_line[row['line_id']]
        index = row['segment_index']
        allowed = name in {'総武線', '総武線-3', '成田線-2', '成田線-3'}
        if name == '東海道線': allowed = index >= 11 and index < 18
        if name == '山手線': allowed = index < 8
        if name == '中央線': allowed = index >= 37 and index < 58
        if not row['line_id'].startswith(NEX_PREFIX) or not allowed: continue
        length = float(line['segments'][index][0])
        a, b = row['from_station_code'], row['to_station_code']
        graph[a].append((b, length, row))
        graph[b].append((a, length, row))
    sections = []
    for start, end in zip(calls, calls[1:]):
        a, b = start.get('current_source_code'), end.get('current_source_code')
        if not a or not b: return []
        serial = itertools.count()
        queue = [(0.0, next(serial), a, [])]
        visited = set()
        found = None
        while queue:
            cost, _, node, path = heapq.heappop(queue)
            if node in visited: continue
            visited.add(node)
            if node == b:
                found = path
                break
            for neighbor, length, row in graph[node]:
                if neighbor not in visited:
                    heapq.heappush(queue, (cost + length, next(serial), neighbor, path + [row]))
        if not found: return []
        sections.append(dict(
            from_n02_station_code=a, to_n02_station_code=b,
            line_names=list(dict.fromkeys(row['line_name'] for row in found)),
            operator_names=['東日本旅客鉄道'],
            line_ids=list(dict.fromkeys(row['line_id'] for row in found)),
            section_codes=[row['section_code'] for row in found]))
    return sections


def populate_interval_tables(connection, package, data):
    rows = interval_rows(package)
    connection.executemany(
        'INSERT INTO rail_intervals VALUES (:section_code,:line_id,:from_station_code,:to_station_code,:segment_index)', rows)
    lines = {line['id']: line for line in package['lines']}
    stations = {row['station_id']: row for row in data['station_identities']}
    for segment in data['trip_line_segments']:
        line = lines.get(segment.get('current_n02_line_id'))
        if not line or segment.get('reference_kind') != 'current_n02': continue
        left, right = stations[segment['from_station_id']], stations[segment['to_station_id']]
        codes = line_chain(line, left.get('current_source_code'), right.get('current_source_code'), rows)
        for position, code in enumerate(codes):
            connection.execute('INSERT INTO trip_line_interval_codes VALUES (?,?,?,?)',
                               (segment['trip_id'], segment['sequence'], position, code))
    stops = defaultdict(list)
    for stop in data['stop_times']:
        if stop['call_type'] in {'origin', 'passenger_stop', 'destination'}:
            stops[stop['trip_id']].append(stop)
    count = 0
    for trip in data['trips']:
        if trip['service_id'] != 'narita-express': continue
        calls = [stations[stop['station_id']] for stop in sorted(stops[trip['trip_id']], key=lambda row: row['stop_sequence'])]
        sections = nex_route_sections(package, calls)
        import json
        for sequence, section in enumerate(sections):
            connection.execute('INSERT INTO trip_physical_route_sections VALUES (?,?,?,?)',
                               (trip['trip_id'], sequence, json.dumps(section, ensure_ascii=False, separators=(',', ':')), NEX_SOURCE))
        count += bool(sections)
    return count


def attach_to_database(database_path, package_path):
    """Refresh only derived identity tables on an existing reviewed artifact."""
    import json
    import sqlite3
    import hashlib
    from pathlib import Path
    connection = sqlite3.connect(database_path)
    connection.row_factory = sqlite3.Row
    data = {table: [dict(row) for row in connection.execute('SELECT * FROM ' + table)]
            for table in ('station_identities', 'trip_line_segments', 'stop_times', 'trips')}
    package = json.loads(Path(package_path).read_text(encoding='utf-8'))
    connection.execute('PRAGMA foreign_keys=ON')
    connection.executescript('''
        CREATE TABLE IF NOT EXISTS rail_intervals (
            section_code TEXT PRIMARY KEY, line_id TEXT NOT NULL,
            from_station_code TEXT NOT NULL, to_station_code TEXT NOT NULL,
            segment_index INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS trip_line_interval_codes (
            trip_id TEXT NOT NULL, segment_sequence INTEGER NOT NULL,
            position INTEGER NOT NULL, section_code TEXT NOT NULL REFERENCES rail_intervals(section_code),
            PRIMARY KEY (trip_id, segment_sequence, position),
            FOREIGN KEY (trip_id, segment_sequence) REFERENCES trip_line_segments(trip_id, sequence));
        CREATE TABLE IF NOT EXISTS trip_physical_route_sections (
            trip_id TEXT NOT NULL REFERENCES trips(trip_id), sequence INTEGER NOT NULL,
            route_section_json TEXT NOT NULL, source_url TEXT NOT NULL,
            PRIMARY KEY (trip_id, sequence));
    ''')
    with connection:
        connection.execute('DELETE FROM trip_physical_route_sections')
        connection.execute('DELETE FROM trip_line_interval_codes')
        connection.execute('DELETE FROM rail_intervals')
        count = populate_interval_tables(connection, package, data)
        connection.execute('INSERT OR REPLACE INTO metadata VALUES (?,?)',
                           ('physical_route_package_hash', hashlib.sha256(Path(package_path).read_bytes()).hexdigest()))
        connection.execute('INSERT OR REPLACE INTO metadata VALUES (?,?)',
                           ('physical_route_identity_version', 'rail-interval-codes-v1'))
        errors = connection.execute('PRAGMA foreign_key_check').fetchall()
        if errors: raise ValueError(f'foreign key errors: {errors[:3]}')
    connection.close()
    return count


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--package', required=True)
    args = parser.parse_args()
    print(f'Attached physical corridor chains for {attach_to_database(args.database, args.package)} NEX trips.')
