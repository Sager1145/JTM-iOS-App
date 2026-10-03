#!/usr/bin/env python3
"""Recover exact operator GTFS labels using retained feed/stop identities.

The compact packages canonicalize transfer names and uppercase labels. These
are display decisions, not evidence of the operator's original spelling.
This verifier keeps raw stops.txt bytes and their archive digest. It joins the
source station features' feed/operator/stop IDs before considering a tightly
bounded coordinate fallback; it never matches names across a country.
"""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import csv
from datetime import datetime, timezone
import gzip
import hashlib
import html
import io
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

APP = Path(__file__).resolve().parents[2]
COUNTRIES = ('us', 'ca')
SOURCES = APP / 'data/station-english-sources/na'
OUTPUT = APP / 'data/station-english-verified-na.json'
PRIMARY_UPDATES = {
    'denton-county-transportation': ('https://gtfs.remix.com/dcta_denton_tx_us.zip',
                                   'https://www.dcta.net/resources/open-data'),
    'south-florida-regional-trans': ('https://gtfs.tri-rail.com/gtfs.zip',
                                    'https://www.tri-rail.com/'),
}


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def slug(value):
    return re.sub('[^a-z0-9]+', '-', value.lower()).strip('-') or 'x'


def distance(a, b):
    """WGS84 small-distance bound in metres, sufficient for matching gates."""
    x = math.radians(a[0] - b[0]) * math.cos(math.radians((a[1] + b[1]) / 2))
    y = math.radians(a[1] - b[1])
    return 6371000 * math.hypot(x, y)


def stop_rows(raw):
    reader = csv.DictReader(io.StringIO(raw.decode('utf-8-sig'), newline=''))
    reader.fieldnames = [key.strip() for key in reader.fieldnames or []]
    # Keep stop_name verbatim: title casing and directional stripping are not
    # accepted evidence. Trim identifiers/coordinates as the source builder did.
    return {row['stop_id'].strip(): {key: value if key == 'stop_name' else (value or '').strip()
            for key, value in row.items() if key is not None}
            for row in reader if row.get('stop_id')}


def raw_stops(path):
    with zipfile.ZipFile(path) as archive:
        names = [name for name in archive.namelist() if name.rsplit('/', 1)[-1] == 'stops.txt']
        if len(names) != 1:
            raise ValueError('feed requires exactly one stops.txt')
        raw = archive.read(names[0])
        stop_rows(raw)
        return raw


def materialize(feed, archive, output_dir, retrieval, source, retrieved_at, **extra):
    raw = raw_stops(archive)
    prefix = output_dir / (feed['slug'] + '-' + retrieval)
    prefix.parent.mkdir(parents=True, exist_ok=True)
    prefix.with_suffix('.stops.txt.gz').write_bytes(gzip.compress(raw, mtime=0))
    info = {'feed': feed['slug'], 'operator': feed['name'], 'source': source,
            'sha256': sha(archive.read_bytes()), 'stopsSha256': sha(raw),
            'retrievedAt': retrieved_at, 'retrievalMethod': retrieval,
            'rawStops': prefix.with_suffix('.stops.txt.gz').name, **extra}
    if feed['slug'] == 'denton-county-transportation' and retrieval == 'operator-download':
        with zipfile.ZipFile(archive) as bundle:
            tables = {}
            documents = []
            for table in ('routes.txt', 'trips.txt', 'stop_times.txt'):
                data = bundle.read(table)
                raw_name = f'dcta-operator-{table}.gz'
                (output_dir / raw_name).write_bytes(gzip.compress(data, mtime=0))
                documents.append({'rawSource': raw_name, 'sha256': sha(data), 'source': source})
                tables[table] = list(csv.DictReader(io.StringIO(data.decode('utf-8-sig'))))
            rail_routes = {row['route_id'] for row in tables['routes.txt'] if row['route_type'] == '2'}
            rail_trips = {row['trip_id'] for row in tables['trips.txt'] if row['route_id'] in rail_routes}
            info.update({'allowedCoordinateStopIds': sorted({row['stop_id'] for row in tables['stop_times.txt']
                if row['trip_id'] in rail_trips and not (row.get('pickup_type') == row.get('drop_off_type') == '1')}),
                'coordinateRailRouteIds': sorted(rail_routes), 'coordinateToleranceMeters': 50,
                'rawDocuments': documents,
                'coordinateNote': 'Only passenger stops explicitly served by current route_type=2 rail trips qualify for coordinate fallback; bus-platform stops are excluded.'})
    write_json(prefix.with_suffix('.json'), info)
    return info


def refresh(registry, output_dir=SOURCES, workers=8, timeout=70):
    """Try every registry primary URL. Mirrors are never substituted silently."""
    now = datetime.now(timezone.utc).isoformat()
    cache = APP / 'data/raw/na-rail/gtfs'
    def work(feed):
        cached = cache / (str(feed['mdb']) + '.zip')
        # Cache inspection time is explicitly not the unknown original download
        # date. Its role is reproducible recovery of the shipped package input.
        if cached.exists():
            materialize(feed, cached, output_dir, 'package-cache', feed.get('url'),
                        None, inspectedAt=now, originalRetrievalDateKnown=False,
                        cacheArchive=f'data/raw/na-rail/gtfs/{cached.name}')
        update = PRIMARY_UPDATES.get(feed['slug'])
        url = update[0] if update else feed.get('url')
        result = {'feed': feed['slug'], 'attemptedAt': now, 'url': url}
        if not url:
            result['error'] = 'registry has no primary operator feed URL'
            return result
        # HTTP-only legacy entries are first attempted using HTTPS on the same
        # publisher host. curl records the final URL, including redirects.
        urls = list(dict.fromkeys([re.sub('^http:', 'https:', url), url]))
        with tempfile.TemporaryDirectory(prefix='jtm-english-na-') as tmp:
            target = Path(tmp) / 'feed.zip'
            for candidate in urls:
                response = subprocess.run(['curl', '-fL', '--silent', '--show-error',
                    '--connect-timeout', '10', '--max-time', str(timeout),
                    '--output', str(target), '--write-out', '%{url_effective}', candidate],
                    capture_output=True, text=True)
                try:
                    if response.returncode:
                        raise ValueError(response.stderr.strip())
                    info = materialize(feed, target, output_dir, 'operator-download',
                                       response.stdout.strip(), now, requestedSource=candidate,
                                       catalogUrl=update[1] if update else None)
                except (ValueError, zipfile.BadZipFile, OSError) as error:
                    result['error'] = str(error)[:400]
                    continue
                result.update({'sha256': info['sha256'], 'source': info['source']})
                result.pop('error', None)
                break
        print(feed['slug'] + ': ' + ('downloaded' if 'sha256' in result else result['error']), flush=True)
        return result
    with ThreadPoolExecutor(max_workers=workers) as executor:
        results = list(executor.map(work, registry['feeds']))
    write_json(output_dir / 'retrieval-manifest.json', {'attemptedAt': now, 'feeds': results})
    update_shore_line_east(output_dir)
    refresh_wmata(output_dir)
    refresh_smart(output_dir)


def update_shore_line_east(output_dir=SOURCES):
    # CTtransit's own developer page explicitly publishes Amtrak's GTFS as
    # the current Shore Line East feed. IDs changed for six stations; a unique
    # current stop within 50 m joins the old platform to the new published ID.
    path = output_dir / 'amtrak-operator-download.json'
    if path.exists():
        meta = read(path)
        write_json(output_dir / 'shore-line-east-operator-download.json', {
            **meta, 'feed': 'shore-line-east', 'operator': 'Shore Line East',
            'catalogUrl': 'https://apc.ctfastrack.com/about/developers',
            'publishedReplacementFeed': 'amtrak', 'coordinateToleranceMeters': 50,
            'note': 'Official CTtransit developer page explicitly links Amtrak GTFS as the current Shore Line East feed. Retained stop IDs first; otherwise unique current feed stop within 50 m.'})


def website_stop_rows(html):
    """Read WMATA's public serialized Stop objects, including retained GTFS IDs.

    Decode the script string using JSON (never evaluation), then decode complete
    Stop objects. This handles escaped apostrophes, quotes and Unicode names.
    """
    rows = {}
    decoder = json.JSONDecoder()
    for encoded in re.findall(r'<script[^>]*>self\.__next_f\.push\((.*?)\)</script>', html, re.S):
        frame = json.loads(encoded)
        if len(frame) < 2 or not isinstance(frame[1], str):
            continue
        for match in re.finditer(r'\{"__typename":"Stop",', frame[1]):
            stop, _ = decoder.raw_decode(frame[1], match.start())
            gtfs_id = stop.get('gtfsId', '')
            if not gtfs_id.startswith('WMATA_RAIL_BUS_GTFS_STATIC:STN_'):
                continue
            stop_id = gtfs_id.split(':', 1)[1]
            row = {'stop_id': stop_id, 'stop_name': stop['name'],
                   'stop_lat': str(stop['lat']), 'stop_lon': str(stop['lon'])}
            if stop_id in rows and rows[stop_id] != row:
                raise ValueError(f'conflicting public WMATA identity: {stop_id}')
            rows[stop_id] = row
    if not rows:
        raise ValueError('no public WMATA source-ID station records')
    return rows


def refresh_wmata(output_dir=SOURCES):
    """WMATA's own Rider Tools publishes the station IDs without API login."""
    all_rows = {}
    documents = []
    now = datetime.now(timezone.utc).isoformat()
    for route in ('BLUE', 'GREEN', 'ORANGE', 'RED', 'SILVER', 'YELLOW'):
        url = 'https://www.wmata.com/ridertools/line/gtfs/WMATA_RAIL_BUS_GTFS_STATIC%3A' + route
        result = subprocess.run(['curl', '-fL', '--silent', '--show-error', '--connect-timeout', '10',
                                 '--max-time', '40', url], capture_output=True)
        if result.returncode:
            print('wmata-public-' + route + ': ' + result.stderr.decode()[:200], flush=True)
            continue
        raw = result.stdout
        rows = website_stop_rows(raw.decode('utf-8'))
        name = f'wmata-rider-tools-{route.lower()}.html.gz'
        (output_dir / name).write_bytes(gzip.compress(raw, mtime=0))
        documents.append({'source': url, 'sha256': sha(raw), 'rawSource': name})
        for stop_id, row in rows.items():
            if stop_id in all_rows and all_rows[stop_id]['stop_name'] != row['stop_name']:
                raise ValueError(f'conflicting WMATA website label: {stop_id}')
            all_rows.setdefault(stop_id, {**row, 'evidence_source': url,
                                         'evidence_sha256': sha(raw), 'evidence_raw_source': name})
    if not all_rows:
        return
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=list(next(iter(all_rows.values()))))
    writer.writeheader()
    writer.writerows(all_rows.values())
    raw = stream.getvalue().encode('utf-8')
    raw_name = 'wmata-operator-website.stops.txt.gz'
    (output_dir / raw_name).write_bytes(gzip.compress(raw, mtime=0))
    write_json(output_dir / 'wmata-operator-website.json', {
        'feed': 'wmata', 'operator': 'WMATA', 'source': 'https://www.wmata.com/ridertools/lines',
        'sha256': sha(raw), 'stopsSha256': sha(raw), 'rawStops': raw_name,
        'retrievedAt': now, 'retrievalMethod': 'operator-website', 'rawDocuments': documents,
        'note': 'Parsed public WMATA Rider Tools Stop objects retain gtfsId, name, lat and lon. Per-stop evidence points to raw route HTML, not the derived CSV.'})


def smart_directory_records(document):
    """Each official heading owns its own station anchor and embedded map."""
    records = []
    for block in re.split(r'<h4 class="panel-title">', document)[1:]:
        heading = html.unescape(re.sub('<[^>]+>', '', block.split('</h4>', 1)[0])).strip()
        location = re.search(r'!2d(-?[\d.]+)!3d(-?[\d.]+)', block)
        anchor = re.search(r'<a name="([^"]+)"', block)
        if heading and location and anchor:
            lon, lat = map(float, location.groups())
            records.append({'name': heading, 'anchor': anchor[1], 'mapViewport': [lon, lat]})
    if len(records) != 14:
        raise ValueError(f'expected 14 complete SMART official station blocks; got {len(records)}')
    return records


def refresh_smart(output_dir=SOURCES):
    """Corroborate original SMART stop IDs against official station headings.

    The map is an explicitly identified station's dedicated viewport, not a
    survey point. A normalized exact original GTFS label (removing only the
    literal operator prefix SMART) AND a unique matching station within 500 m
    are required. Distances to the closest other station are retained.
    """
    url = 'https://www.sonomamarintrain.org/stations'
    response = subprocess.run(['curl', '-fL', '--silent', '--show-error', '--connect-timeout', '10',
                               '--max-time', '40', url], capture_output=True)
    if response.returncode:
        print('smart-directory: ' + response.stderr.decode()[:200], flush=True)
        return
    raw = response.stdout
    records = smart_directory_records(raw.decode('utf-8'))
    cached_meta = read(output_dir / 'smart-package-cache.json')
    cached_raw = gzip.decompress((output_dir / cached_meta['rawStops']).read_bytes())
    cached = stop_rows(cached_raw)
    parents = [row for row in cached.values() if row.get('location_type') == '1']
    def normalized(value):
        return re.sub(r'^SMART\s+', '', value).casefold().strip()
    output_rows = []
    for record in records:
        ordered = sorted((distance(record['mapViewport'], [float(row['stop_lon']), float(row['stop_lat'])]),
                          row['stop_id']) for row in parents)
        matched = cached[ordered[0][1]]
        if (ordered[0][0] > 500 or ordered[1][0] <= 500
                or normalized(matched['stop_name']) != normalized(record['name'])):
            raise ValueError(f'SMART heading/identity/location mismatch: {record["name"]}')
        for row in cached.values():
            if normalized(row['stop_name']) != normalized(record['name']):
                continue
            output_rows.append({'stop_id': row['stop_id'], 'stop_name': record['name'],
                'stop_lat': row['stop_lat'], 'stop_lon': row['stop_lon'],
                'evidence_source': url + '#' + record['anchor'], 'evidence_sha256': sha(raw),
                'evidence_raw_source': 'smart-station-directory.html.gz',
                'original_published_name': row['stop_name'], 'station_page_anchor': record['anchor'],
                'map_viewport_lon': record['mapViewport'][0], 'map_viewport_lat': record['mapViewport'][1],
                'nearest_station_m': round(ordered[0][0], 3), 'second_nearest_station_m': round(ordered[1][0], 3)})
    raw_name = 'smart-operator-station-directory.stops.txt.gz'
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=list(output_rows[0]))
    writer.writeheader()
    writer.writerows(output_rows)
    derived = stream.getvalue().encode('utf-8')
    (output_dir / raw_name).write_bytes(gzip.compress(derived, mtime=0))
    (output_dir / 'smart-station-directory.html.gz').write_bytes(gzip.compress(raw, mtime=0))
    write_json(output_dir / 'smart-operator-station-directory.json', {
        'feed': 'smart', 'operator': 'Sonoma-Marin Area Rail Transit', 'source': url,
        'sha256': sha(raw), 'stopsSha256': sha(derived), 'rawStops': raw_name,
        'retrievedAt': datetime.now(timezone.utc).isoformat(), 'retrievalMethod': 'operator-website',
        'matchMethod': 'retained-feed-stop-id-and-exact-official-directory-heading-with-dedicated-map',
        'originalArchiveSha256': cached_meta['sha256'],
        'rawDocuments': [{'source': url, 'sha256': sha(raw), 'rawSource': 'smart-station-directory.html.gz'}],
        'note': 'Original source stop IDs and labels are retained from the package-input archive. Each official directory heading must equal the original label after removing the literal SMART prefix. Its dedicated station map viewport must identify that station uniquely within 500 m; another station within 500 m rejects the match. Map viewport coordinates are not station survey coordinates.'})


def source_stop_id(properties, country, feed, operator):
    """Parse only the builder's exact feed/operator-prefixed source identity."""
    code = properties.get('n02_station_code', '')
    prefix = f'{country.upper()}-{feed.upper()}-{slug(operator).upper()}-'
    suffix = '-' + properties.get('n02_group_code', '').upper()
    if not properties.get('n02_group_code') or not code.startswith(prefix) or not code.endswith(suffix):
        return None
    return code[len(prefix):-len(suffix)] or None


def match_stop(station, features, stops, country, feed, operator, coordinate_tolerance=2,
               allowed_coordinate_stop_ids=None):
    """Source-ID joins require the exact package membership and feature anchor.

    ID coordinates may be snapped by the package geometry builder; identity
    does not depend on the snap. Without a retained ID, only one distinct raw
    stop identity within two metres qualifies. Multiple platforms are refused.
    """
    ids = set()
    for feature in features:
        props = feature['properties']
        if props.get('operator') != operator or props.get('n02_group_code') != station[0]:
            continue
        point = props.get('display_point')
        if point and distance(point, station[2:4]) <= 2:
            stop_id = source_stop_id(props, country, feed, operator)
            if stop_id:
                ids.add(stop_id)
    found = [stops[stop_id] for stop_id in sorted(ids) if stop_id in stops]
    if found:
        labels = {row.get('stop_name', '') for row in found}
        if len(labels) == 1 and next(iter(labels)).strip():
            return found, 'retained-feed-operator-stop-id', None
        return [], None, 'retained source IDs have conflicting published labels'
    # No station-name-only fallback. The feed limits the identity domain and
    # the 2 m gate only accommodates rounded source coordinate precision.
    nearby = []
    for row in stops.values():
        if allowed_coordinate_stop_ids is not None and row['stop_id'] not in allowed_coordinate_stop_ids:
            continue
        try:
            point = [float(row['stop_lon']), float(row['stop_lat'])]
        except (KeyError, ValueError):
            continue
        if distance(point, station[2:4]) <= coordinate_tolerance:
            nearby.append(row)
    if len(nearby) == 1 and nearby[0].get('stop_name', '').strip():
        scope = 'rail-stop-in-same-feed' if allowed_coordinate_stop_ids is not None else 'feed-coordinate'
        return nearby, f'unique-{scope}-within-{coordinate_tolerance}m', None
    return [], None, f'retained stop ID absent; no unique same-feed coordinate within {coordinate_tolerance} m'


def load_sources(source_dir):
    sources = defaultdict(list)
    for path in sorted(source_dir.glob('*.json')):
        if path.name == 'retrieval-manifest.json':
            continue
        meta = read(path)
        raw = gzip.decompress((source_dir / meta['rawStops']).read_bytes())
        if sha(raw) != meta['stopsSha256']:
            raise ValueError(f'stale raw source digest: {path.name}')
        for document in meta.get('rawDocuments', []):
            original = gzip.decompress((source_dir / document['rawSource']).read_bytes())
            if sha(original) != document['sha256']:
                raise ValueError(f'stale original document: {document["rawSource"]}')
        sources[meta['feed']].append((meta, stop_rows(raw)))
    return sources


def build(app=APP, source_dir=SOURCES):
    sources = load_sources(source_dir)
    verified, unresolved = {}, []
    inputs, counts = {}, {}
    for country in COUNTRIES:
        package_path = app / f'public/rail/{country}-2025.json'
        features_path = app / f'data/stations-{country}.json'
        inputs[str(package_path.relative_to(app))] = sha(package_path.read_bytes())
        inputs[str(features_path.relative_to(app))] = sha(features_path.read_bytes())
        package, features = read(package_path), read(features_path)['features']
        by_group = defaultdict(list)
        for feature in features:
            by_group[feature['properties'].get('n02_group_code')].append(feature)
        for line in package['lines']:
            feed = line.get('sourceFeed')
            # Prefer fresh operator downloads if their retained IDs remain
            # valid; the archived package source is separately preserved.
            candidates = sorted(sources.get(feed, []), key=lambda entry:
                                entry[0]['retrievalMethod'] not in ('operator-download', 'operator-website'))
            for station in line['stations']:
                key = line['id'] + ':' + station[0]
                identity = {'country': country, 'lineId': line['id'],
                            'stationCode': station[0], 'operator': line['operator'],
                            'name': station[1]}
                reason = 'no primary operator source snapshot'
                selected = None
                for meta, stops in candidates:
                    # An attribution-only cached mirror cannot be promoted.
                    if meta['retrievalMethod'] not in ('operator-download', 'operator-website'):
                        continue
                    found, method, reason = match_stop(station, by_group[station[0]],
                        stops, country, feed, line['operator'], meta.get('coordinateToleranceMeters', 2),
                        meta.get('allowedCoordinateStopIds'))
                    if found:
                        selected = meta, found, method
                        break
                if not selected:
                    if feed == 'ace':
                        reason = 'official 511 GTFS requires API token; registry has no public primary feed URL; ACE website returned HTTP 403'
                    unresolved.append({**identity, 'feed': feed, 'reason': reason})
                    continue
                meta, found, method = selected
                evidence = [{ 'operator': line['operator'], 'feed': feed,
                    'stopId': row['stop_id'], 'publishedName': row['stop_name'],
                    'en': row['stop_name'], 'source': row.get('evidence_source', meta['source']),
                    'lat': float(row['stop_lat']), 'lon': float(row['stop_lon']),
                    'sha256': row.get('evidence_sha256', meta['sha256']), 'stopsSha256': meta['stopsSha256'],
                    'retrievedAt': meta['retrievedAt'], 'matchMethod': meta.get('matchMethod', method),
                    **({'originalArchiveSha256': meta['originalArchiveSha256'],
                        'originalPublishedName': row['original_published_name'],
                        'officialStationAnchor': row['station_page_anchor'],
                        'locationEvidence': {'semantics': 'dedicated official station map viewport center',
                            'viewport': [float(row['map_viewport_lon']), float(row['map_viewport_lat'])],
                            'nearestStationMeters': float(row['nearest_station_m']),
                            'secondNearestStationMeters': float(row['second_nearest_station_m']),
                            'maxMeters': 500,
                            'nameMatch': 'exact original stop label after literal SMART operator prefix removal'}}
                       if meta.get('originalArchiveSha256') else {}),
                    **({'replacementFeedEvidence': meta['catalogUrl'],
                        'publishedReplacementFeed': meta['publishedReplacementFeed']}
                       if meta.get('publishedReplacementFeed') else {}),
                    **({'coordinateRailRouteIds': meta['coordinateRailRouteIds'],
                        'coordinateIdentityEvidence': meta['coordinateNote']}
                       if meta.get('coordinateRailRouteIds') and method.startswith('unique-') else {}),
                    'rawSource': 'data/station-english-sources/na/' + row.get('evidence_raw_source', meta['rawStops'])}
                    for row in found]
                verified[key] = {**identity, 'en': found[0]['stop_name'],
                    'source': evidence[0]['source'], 'identityEvidence': evidence}
        memberships = [row for row in verified.values() if row['country'] == country]
        pending = [row for row in unresolved if row['country'] == country]
        pending_codes = {row['stationCode'] for row in pending}
        all_codes = {station[0] for line in package['lines'] for station in line['stations']}
        counts[country] = {'groups': len(all_codes), 'verifiedGroups': len(all_codes - pending_codes),
                          'memberships': len(memberships) + len(pending),
                          'verifiedMemberships': len(memberships), 'unresolvedMemberships': len(pending)}
    return {'schema': 'station-english-evidence/1', 'countries': list(COUNTRIES),
            'note': 'Exact official labels joined to retained source identities. Unique same-feed coordinates within 2 m are a fallback; documented SLE replacement and rail-route-constrained DCTA matching permit 50 m. SMART requires exact original stop labels and dedicated official station maps, with viewport semantics and nearest-station distances retained. Cached/mirrored attribution alone is never verification. Group verification requires every membership.',
            'inputSha256': inputs, 'coverage': counts,
            'byLineStation': dict(sorted(verified.items())), 'unresolved': unresolved}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--workers', type=int, default=8)
    parser.add_argument('--timeout', type=int, default=70)
    args = parser.parse_args()
    if args.refresh:
        refresh(read(APP / 'scripts/railway/na-feeds.json'), workers=args.workers, timeout=args.timeout)
    result = build()
    if args.check:
        if not OUTPUT.exists() or read(OUTPUT) != result:
            raise SystemExit('station-english-verified-na.json is stale')
    else:
        write_json(OUTPUT, result)
    print(json.dumps(result['coverage'], indent=2))


if __name__ == '__main__':
    main()
