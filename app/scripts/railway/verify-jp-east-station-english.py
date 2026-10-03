#!/usr/bin/env python3
"""Pair JR East's official bilingual timetable rows by retained station IDs."""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import gzip
import hashlib
import html
import json
from pathlib import Path
import re
import string
import subprocess
import unicodedata
from urllib.parse import urlencode

APP = Path(__file__).resolve().parents[2]
SOURCES = APP / 'data/station-english-sources/jp-east'
OUTPUT = APP / 'data/station-english-verified-jp-east.json'
OPERATOR = '東日本旅客鉄道'
BASE = 'https://timetables.jreast.co.jp'
# Explicit N02 inventory labels versus the publisher's timetable labels.
# These aliases never change native station names or create romanizations.
ROUTE_ALIASES = {
    '中央線': ('中央本線',), '信越線': ('信越本線',), '奥羽線': ('奥羽本線',),
    '東北線': ('東北本線',), '羽越線': ('羽越本線',),
    '総武線': ('総武本線', '総武線各駅停車', '総武線快速'),
    '東北新幹線': ('東北・北海道新幹線',),
    '赤羽線': ('埼京線',),
}
REVIEWED_NATIVE_VARIANTS = {'文挟': '文挾'}


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def plain(value):
    return html.unescape(re.sub('<[^>]*>', '', value)).strip()


def native_identity(value):
    # Width and the conventional ケ/ヶ place-name typography are spelling
    # variants, not readings. Only one separately reviewed kanji variant is
    # accepted; phonetic approximations never enter identity matching.
    return unicodedata.normalize('NFKC', REVIEWED_NATIVE_VARIANTS.get(value, value)).replace('ヶ', 'ケ')


def table_rows(document, language):
    result = []
    for block in re.findall(r'<tr\b[^>]*>(.*?)</tr>', document, re.S):
        station = re.search(r'<th\b[^>]*class="eki"[^>]*>\s*<a href="([^"]*list(\d+)\.html)">(.*?)</a>', block, re.S)
        prefecture = re.search(r'<td\b[^>]*class="token"[^>]*>(.*?)</td>', block, re.S)
        routes = re.search(r'<td\b[^>]*class="rosen"[^>]*>(.*?)</td>', block, re.S)
        if not station or not prefecture or not routes:
            continue
        label = plain(station[3])
        native = label.split('(', 1)[0].strip() if language == 'ja' else label
        route_names = [plain(value) for value in re.findall(r'<span>(.*?)</span>', routes[1], re.S)]
        result.append({'stationId': station[2], 'name': native, 'publishedLabel': label,
                       'prefecture': plain(prefecture[1]),
                       'routes': sorted(set(value for value in route_names if value and value != '/')),
                       'stationUrl': BASE + station[1]})
    return result


def station_detail_row(document, station_id):
    title = re.search(r'<div class="estation-nameplate">\s*<h1>(.*?)<span>', document, re.S)
    if not title or f'StationCd={int(station_id)}' not in document:
        raise ValueError('station detail must publish its native heading and matching numeric station ID')
    routes = sorted(set(plain(value) for value in re.findall(r'<tr>\s*<th>(.*?)</th>\s*<td>', document, re.S)))
    return {'stationId': station_id, 'name': plain(title[1]), 'publishedLabel': plain(title[1]),
            'prefecture': None, 'routes': routes,
            'stationUrl': BASE + '/timetable/list' + station_id + '.html'}


def fetch(url):
    result = subprocess.run(['curl', '-fL', '--silent', '--show-error', '--connect-timeout', '10',
                             '--max-time', '40', url], capture_output=True)
    if result.returncode:
        raise ValueError(result.stderr.decode('utf-8', errors='replace')[:300])
    return result.stdout


def refresh(output_dir=SOURCES, workers=8):
    output_dir.mkdir(parents=True, exist_ok=True)
    root = fetch(BASE + '/')
    (output_dir / 'ja-index.html.gz').write_bytes(gzip.compress(root, mtime=0))
    select = re.search(r'<select name="rosen"[^>]*>(.*?)</select>', root.decode('utf-8'), re.S)
    if not select:
        raise ValueError('official Japanese route selector absent')
    route_ids = [(code, plain(name)) for code, name in re.findall(r'<option value="(\d+)">(.*?)</option>', select[1], re.S)]
    queries = [('en', 'letter-' + letter, BASE + '/cgi-bin/en/st_search.cgi?' +
                urlencode({'mode': 0, 'ekimei': letter})) for letter in string.ascii_lowercase]
    queries += [('ja', 'route-' + code, BASE + '/cgi-bin/st_search.cgi?' +
                 urlencode({'mode': 1, 'rosen': code})) for code, _ in route_ids]
    now = datetime.now(timezone.utc).isoformat()
    def work(query):
        language, key, url = query
        entry = {'language': language, 'key': key, 'source': url, 'retrievedAt': now}
        try:
            raw = fetch(url)
            records = table_rows(raw.decode('utf-8'), language)
            filename = language + '-' + key + '.html.gz'
            (output_dir / filename).write_bytes(gzip.compress(raw, mtime=0))
            entry.update({'sha256': sha(raw), 'rawSource': filename, 'rows': len(records)})
        except ValueError as error:
            entry['error'] = str(error)
        print(language + '-' + key + ': ' + str(entry.get('rows', entry.get('error'))), flush=True)
        return entry
    with ThreadPoolExecutor(max_workers=workers) as executor:
        entries = list(executor.map(work, queries))
    write(output_dir / 'manifest.json', {'publisher': OPERATOR, 'retrievedAt': now,
          'routeSelector': {'source': BASE + '/', 'sha256': sha(root), 'rawSource': 'ja-index.html.gz'},
          'publishedRoutes': [{'id': code, 'name': name} for code, name in route_ids], 'sources': entries})
    complete_unpaired_stations(output_dir)


def complete_unpaired_stations(output_dir=SOURCES):
    manifest, tables = load_tables(output_dir)
    for station_id in sorted(set(tables['en']) - set(tables['ja'])):
        url = BASE + '/timetable/list' + station_id + '.html'
        raw = fetch(url)
        station_detail_row(raw.decode('utf-8'), station_id)
        filename = 'ja-station-' + station_id + '.html.gz'
        (output_dir / filename).write_bytes(gzip.compress(raw, mtime=0))
        manifest['sources'].append({'language': 'ja', 'key': 'station-' + station_id,
            'source': url, 'sha256': sha(raw), 'rawSource': filename, 'rows': 1,
            'retrievedAt': datetime.now(timezone.utc).isoformat(),
            'recordType': 'station-detail', 'stationId': station_id})
    write(output_dir / 'manifest.json', manifest)


def load_tables(source_dir=SOURCES):
    manifest = read(source_dir / 'manifest.json')
    tables = {'ja': {}, 'en': {}}
    for source in manifest['sources']:
        if source.get('error'):
            continue
        raw = gzip.decompress((source_dir / source['rawSource']).read_bytes())
        if sha(raw) != source['sha256']:
            raise ValueError(f'stale raw JR East source: {source["rawSource"]}')
        records = [station_detail_row(raw.decode('utf-8'), source['stationId'])] if source.get('recordType') == 'station-detail' else table_rows(raw.decode('utf-8'), source['language'])
        for record in records:
            record = {**record, 'sourceEvidence': {key: source[key] for key in
                      ('source', 'sha256', 'rawSource', 'retrievedAt')}}
            previous = tables[source['language']].get(record['stationId'])
            if previous and any(previous[key] != record[key] for key in ('name', 'prefecture', 'routes')):
                raise ValueError(f'conflicting official station ID: {record["stationId"]}')
            tables[source['language']].setdefault(record['stationId'], record)
    return manifest, tables


def match_station(native, package_route, japanese, english, native_index=None):
    wanted_routes = {package_route, *ROUTE_ALIASES.get(package_route, ())}
    native_matches = native_index.get(native_identity(native), []) if native_index is not None else [
        record for record in japanese.values() if native_identity(record['name']) == native_identity(native)]
    matches = [record for record in native_matches if wanted_routes.intersection(record['routes'])
               and record['stationId'] in english]
    if len(matches) == 1:
        jp = matches[0]
        return jp, english[jp['stationId']], None
    if len(matches) > 1:
        return None, None, 'multiple official station IDs share this native name and route'
    if not native_matches:
        return None, None, 'native station absent from official Japanese route tables'
    if any(record['stationId'] not in english for record in native_matches):
        return None, None, 'official station ID has no English search-table row'
    if len(native_matches) == 1:
        jp = native_matches[0]
        return jp, english[jp['stationId']], None
    return None, None, 'native station exists but package route has no supported official route identity'


def build(app=APP, source_dir=SOURCES):
    manifest, tables = load_tables(source_dir)
    native_index = defaultdict(list)
    for record in tables['ja'].values():
        native_index[native_identity(record['name'])].append(record)
    package = read(app / 'public/rail/jp-2025.json')
    verified, unresolved = {}, []
    for line in package['lines']:
        if line['operator'] != OPERATOR:
            continue
        for station in line['stations']:
            identity = {'country': 'jp', 'lineId': line['id'], 'stationCode': station[0],
                        'operator': OPERATOR, 'name': station[1]}
            jp, en, reason = match_station(station[1], line['name'], tables['ja'], tables['en'], native_index)
            if reason:
                unresolved.append({**identity, 'route': line['name'], 'reason': reason})
                continue
            japanese_source, english_source = jp['sourceEvidence'], en['sourceEvidence']
            evidence = {'operator': OPERATOR, 'stationId': jp['stationId'], 'ja': jp['name'],
                'en': en['name'], 'prefecture': jp['prefecture'], 'englishPrefecture': en['prefecture'],
                'officialRoutes': jp['routes'], 'officialEnglishRoutes': en['routes'],
                'packageRoute': line['name'], 'source': english_source['source'],
                'japaneseSource': japanese_source['source'], 'stationSource': en['stationUrl'],
                'japaneseStationSource': jp['stationUrl'],
                'sha256': english_source['sha256'], 'japaneseSha256': japanese_source['sha256'],
                'retrievedAt': english_source['retrievedAt'],
                'rawSource': 'data/station-english-sources/jp-east/' + english_source['rawSource'],
                'japaneseRawSource': 'data/station-english-sources/jp-east/' + japanese_source['rawSource'],
                'nativeIdentity': 'exact' if jp['name'] == station[1] else
                                  'reviewed-kanji-variant' if station[1] in REVIEWED_NATIVE_VARIANTS else
                                  'width-or-place-name-Ke-typographic-variant',
                'nativePackageName': station[1],
                'matchMethod': 'native-name-and-operator-route-paired-by-official-timetable-station-id'
                    if {line['name'], *ROUTE_ALIASES.get(line['name'], ())}.intersection(jp['routes']) else
                    'unique-native-identity-in-bilingual-operator-directory-paired-by-official-station-id',
                **({'reviewedRouteCrosswalk': {'package': line['name'], 'official':
                    sorted(set(ROUTE_ALIASES[line['name']]).intersection(jp['routes']))}}
                   if line['name'] in ROUTE_ALIASES else {})}
            verified[line['id'] + ':' + station[0]] = {**identity, 'en': en['name'],
                'source': english_source['source'], 'identityEvidence': [evidence]}
    all_groups = {station[0] for line in package['lines'] if line['operator'] == OPERATOR for station in line['stations']}
    pending_groups = {row['stationCode'] for row in unresolved}
    return {'schema': 'station-english-evidence/1', 'countries': ['jp'],
        'note': 'Japanese and English official timetable rows are paired by exact numeric publisher station ID. Package memberships require native name and operator; published routes qualify homonyms, while a unique native identity in the full operator directory may cover physical-line versus service-line differences. Explicit width/ケ/ヶ typography and reviewed 文挟/文挾 variants are accepted. No romanization is generated. JR East-only coverage does not verify another operator sharing the same group.',
        'inputSha256': {'public/rail/jp-2025.json': sha((app / 'public/rail/jp-2025.json').read_bytes()),
                        'data/station-english-sources/jp-east/manifest.json': sha((source_dir / 'manifest.json').read_bytes())},
        'sourceCoverage': {'japaneseStations': len(tables['ja']), 'englishStations': len(tables['en']),
                           'pairedStations': len(set(tables['ja']) & set(tables['en'])),
                           'sourceFailures': [source for source in manifest['sources'] if source.get('error')]},
        'coverage': {'jrEastGroups': len(all_groups), 'verifiedJrEastGroups': len(all_groups - pending_groups),
                     'jrEastMemberships': len(verified) + len(unresolved),
                     'verifiedMemberships': len(verified), 'unresolvedMemberships': len(unresolved)},
        'byLineStation': dict(sorted(verified.items())), 'unresolved': unresolved}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--workers', type=int, default=8)
    args = parser.parse_args()
    if args.refresh:
        refresh(workers=args.workers)
    result = build()
    if args.check:
        if not OUTPUT.exists() or read(OUTPUT) != result:
            raise SystemExit('station-english-verified-jp-east.json is stale')
    else:
        write(OUTPUT, result)
    print(json.dumps({'sourceCoverage': result['sourceCoverage'], 'coverage': result['coverage']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
