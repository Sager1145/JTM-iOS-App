#!/usr/bin/env python3
"""Rebuild JR West evidence from retained operator-published station signs.

English is copied verbatim from ekiSignBox__romanization, never transliterated.
Native identity is exact within JR West's directory. Duplicate native labels
require an explicit directory result line, prefecture, and official station ID.
The older nationwide reservation PDF and train-guide masters are retained for
source discovery but do not authorize promotion across operators.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import html
import json
from pathlib import Path
import re
import unicodedata

APP = Path(__file__).resolve().parents[2]
RAW = APP / 'data/station-english-sources/jp-west'
OUTPUT = APP / 'data/station-english-verified-jp-west.json'
OPERATOR = '西日本旅客鉄道'


def norm(value):
    return unicodedata.normalize('NFKC', value).replace('ヶ', 'ケ').replace('ヵ', 'カ')


def field(text, cls):
    match = re.search(r'<(?:h2|span)[^>]*class="' + re.escape(cls) + r'"[^>]*>(.*?)</(?:h2|span)>', text, re.S)
    return html.unescape(re.sub(r'<[^>]+>', '', match[1])).strip() if match else None


def station_sign(text):
    qualified_name = field(text, 'ekiSignBox__name')
    name = qualified_name
    # Directory signs qualify homonyms with their published prefecture.
    # Strip only that explicit suffix; preserve the full published label below.
    if qualified_name:
        qualifier = re.fullmatch(r'(.*)[（(]([^（）()]+[都道府県])[）)]', qualified_name)
        if qualifier:
            name = qualifier[1].strip()
    en = field(text, 'ekiSignBox__romanization')
    ids = set(re.findall(r'class="ekiSignBox__link"[^>]*>\s*<a href="/top\?id=(\d+)"', text))
    if not name or not en or len(ids) != 1:
        return None
    station_id = next(iter(ids))
    return {'name': name, 'en': en, 'officialQualifiedName': qualified_name, 'officialStationId': station_id,
            'source': 'https://eki.jr-odekake.net/top?id=' + station_id}


def search_results(text):
    result = []
    for block in re.split(r'<div class="ekiSearch__results__item">', text)[1:]:
        heading = re.search(r'<h4 class="ekiSearch__results__title"><a href="/top\?id=(\d+)"><span>(.*?)</span>', block, re.S)
        lines = re.search(r'<ul class="ekiSearch__results__lines">(.*?)</ul>', block, re.S)
        if not heading or not lines:
            continue
        label = html.unescape(heading[2]).strip()
        result.append({'officialStationId': heading[1], 'label': label,
                       'name': re.split('[（(]', label)[0].strip(),
                       'officialLines': [html.unescape(x).strip() for x in re.findall(r'<li><span>(.*?)</span>', lines[1], re.S)]})
    return result


def source_rows(root=RAW):
    manifest = json.loads((root / 'manifest.json').read_text())
    searches, stations = {}, {}
    for meta in manifest:
        if not meta.get('file'):
            raise ValueError('Missing retained source: ' + meta['id'])
        raw = (root / meta['file']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != meta['sha256']:
            raise ValueError('Source digest mismatch: ' + meta['file'])
        if meta['file'].endswith('.html'):
            text = raw.decode('utf-8')
            sign = station_sign(text)
            if sign:
                stations[sign['officialStationId']] = {**sign, 'meta': meta}
            if meta.get('keyword'):
                searches[meta['keyword']] = {'sign': sign, 'results': search_results(text), 'meta': meta}
    return manifest, searches, stations


def select_station(name, line, searches, stations, duplicated=False):
    search = searches.get(name)
    if not search:
        return None, 'No retained operator directory search'
    if search['sign'] and norm(search['sign']['name']) == norm(name) and not duplicated:
        return stations[search['sign']['officialStationId']], None
    candidates = [r for r in search['results'] if norm(r['name']) == norm(name)]
    if duplicated:
        # JR West publishes the Kansai Main Line's Osaka section as 大和路線.
        lines = {line, '大和路線'} if line == '関西線' else {line}
        candidates = [r for r in candidates if lines.intersection(r['officialLines'])]
    if len(candidates) != 1:
        return None, 'Native station identity requires an unambiguous published line match'
    row = candidates[0]
    station = stations.get(row['officialStationId'])
    if not station or norm(station['name']) != norm(name):
        return None, 'No retained bilingual sign for the directory station ID'
    return {**station, 'identity': row, 'identityMeta': search['meta']}, None


def build(app=APP, root=RAW):
    package_path = app / 'public/rail/jp-2025.json'
    package = json.loads(package_path.read_text())
    manifest, searches, stations = source_rows(root)
    name_groups = defaultdict(set)
    for line in package['lines']:
        if line['operator'] == OPERATOR:
            for code, name, *_ in line['stations']:
                name_groups[norm(name)].add(code)
    verified, unresolved = {}, []
    for line in package['lines']:
        if line['operator'] != OPERATOR:
            continue
        for code, name, *_ in line['stations']:
            record, reason = select_station(name, line['name'], searches, stations, len(name_groups[norm(name)]) > 1)
            if not record:
                unresolved.append({'country': 'jp', 'lineId': line['id'], 'stationCode': code,
                                   'operator': OPERATOR, 'name': name, 'reason': reason})
                continue
            meta = record['meta']
            evidence = {key: record[key] for key in ('name', 'en', 'officialStationId', 'source')}
            if record.get('officialQualifiedName'):
                evidence['officialQualifiedName'] = record['officialQualifiedName']
            if meta.get('retrievedAtBasis'):
                evidence['retrievedAtBasis'] = meta['retrievedAtBasis']
            evidence.update(operator=OPERATOR, retrievedAt=meta['retrievedAt'], sha256=meta['sha256'],
                            rawFile=meta['file'], identitySource=meta['source'],
                            matchMethod='operator_directory_exact_native_name_and_bilingual_sign_id')
            if record.get('identity'):
                identity_meta = record['identityMeta']
                if identity_meta.get('retrievedAtBasis'):
                    evidence['identityRetrievedAtBasis'] = identity_meta['retrievedAtBasis']
                evidence.update(officialLines=record['identity']['officialLines'],
                                officialQualifiedName=record['identity']['label'],
                                identitySource=identity_meta['source'], identitySha256=identity_meta['sha256'],
                                identityRetrievedAt=identity_meta['retrievedAt'], identityRawFile=identity_meta['file'],
                                matchMethod='operator_directory_exact_native_name_and_published_line_station_id')
            verified[line['id'] + ':' + code] = {'country': 'jp', 'lineId': line['id'],
                'stationCode': code, 'operator': OPERATOR, 'name': name,
                'en': record['en'], 'source': record['source'], 'sourceURL': record['source'],
                'identityEvidence': [evidence]}
    return {'schema': 'station-english-evidence/1', 'countries': ['jp'],
            'packageVersion': package['version'],
            'packageSha256': hashlib.sha256(package_path.read_bytes()).hexdigest(),
            'note': 'Current JR West operator station-sign labels, copied verbatim. Native-name duplicates require published line identities. Discovery PDF and train-guide data are not English verification evidence.',
            'sources': manifest, 'byLineStation': dict(sorted(verified.items())), 'unresolved': unresolved,
            'coverage': {'verifiedMemberships': len(verified), 'unresolvedMemberships': len(unresolved),
                         'groupsWithVerifiedMembership': len({r['stationCode'] for r in verified.values()}),
                         'unresolvedReasons': dict(sorted(Counter(r['reason'] for r in unresolved).items()))}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    snapshot = build()
    text = json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        if OUTPUT.read_text() != text:
            raise SystemExit('JR West station English evidence is stale')
    else:
        OUTPUT.write_text(text)
    print(json.dumps(snapshot['coverage'], ensure_ascii=False))


if __name__ == '__main__':
    main()
