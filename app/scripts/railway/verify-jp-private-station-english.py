#!/usr/bin/env python3
"""Build reproducible private-railway English evidence from official snapshots.

Bilingual station headers and station master records supply the names. No
existing package English field or kana romanization supplies evidence. Japanese
native spelling selects an unambiguous identity within the exact operator;
line/group keys are retained to prevent interchange labels leaking to others.
"""
import argparse
from collections import defaultdict
import hashlib
import gzip
import html
import json
from pathlib import Path
import re
import unicodedata

APP = Path(__file__).resolve().parents[2]
SOURCES = APP / 'data/station-english-sources/jp-private'
PACKAGE = APP / 'public/rail/jp-2025.json'
OUTPUT = APP / 'data/station-english-verified-jp-private.json'
OPERATORS = {'近畿日本鉄道', '名古屋鉄道', '阪急電鉄', '京阪電気鉄道', '東急電鉄', '西武鉄道',
             '東武鉄道', '京成電鉄', '小田急電鉄', '京王電鉄'}


def text(value):
    return ' '.join(html.unescape(re.sub(r'<[^>]*>', '', value)).split())


def normalize(value):
    value = re.sub(r'[\U000E0100-\U000E01EF\uFE00-\uFE0F]', '', value)
    value = re.sub(r'[(（]阪急[)）]$', '', value)
    return unicodedata.normalize('NFKC', value).replace('ヶ', 'ケ').replace('ヵ', 'カ').replace(' ', '')


def field(document, class_name, tag=None):
    pattern = r'<(' + (tag or r'\w+') + r')\b[^>]*class="[^"]*\b' + re.escape(class_name) + r'\b[^"]*"[^>]*>(.*?)</\1>'
    match = re.search(pattern, document, re.S)
    return text(match.group(2)) if match else ''


def load_sources(directory):
    # Retry successes supersede failures; all requests remain in the manifest.
    manifest = json.loads((directory / 'manifest.json').read_text())
    documents, metadata = {}, {}
    for source in manifest:
        if not source.get('rawFile'):
            continue
        raw = (directory / source['rawFile']).read_bytes()
        if source.get('compression') == 'gzip':
            raw = gzip.decompress(raw)
        if hashlib.sha256(raw).hexdigest() != source['sha256']:
            raise ValueError('source hash mismatch: ' + source['rawFile'])
        documents[source['id']] = raw.decode('utf8', errors='replace')
        metadata[source['id']] = source
    return documents, metadata, manifest


def official_records(documents, metadata):
    output = []

    def append(operator, station_id, japanese, english, source_id, method):
        if not japanese or not english or not re.search(r'[A-Za-z]', english):
            return
        item = metadata[source_id]
        output.append({'operator': operator, 'officialStationId': station_id,
                       'ja': japanese, 'en': english, 'source': item['source'],
                       'identitySource': item['source'], 'retrievedAt': item['retrievedAt'],
                       'sha256': item['sha256'], 'matchMethod': method})

    if 'kintetsu-master' in documents:
        for station in json.loads(documents['kintetsu-master']):
            # The master also lists connecting railway stations. Only records
            # carrying Kintetsu's own route and English fields qualify.
            if station.get('路線1') and station.get('駅名英語'):
                append('近畿日本鉄道', str(station['駅コード']).zfill(5), station['駅名'],
                       station['駅名英語'], 'kintetsu-master', 'official bilingual station master ID + operator + unique native identity')
    if 'hankyu-en' in documents:
        for match in re.finditer(r'<a\b[^>]*href="([^"]*/station/([^/"?]+)\.html)(?:#[^"]*)?"[^>]*>\s*<dl class="name">(.*?)</dl>', documents['hankyu-en'], re.S):
            block = match.group(3)
            native = re.search(r'<dd class="station">\s*<!--wovn-src:(.*?)-->(.*?)</dd>', block, re.S)
            if native:
                append('阪急電鉄', match.group(2), text(native.group(1)), text(native.group(2)),
                       'hankyu-en', 'official bilingual station index + shared station page ID + operator + unique native identity')
    if 'keisei-station-map-ja' in documents:
        options = {'jp': {}, 'etc': {}}
        for m in re.finditer(r'<select name="(jp|etc)"[^>]*>(.*?)</select>', documents['keisei-station-map-ja'], re.S):
            options[m.group(1)].update({code: text(label) for code, label in re.findall(r'<option value="(\d+)"[^>]*>(.*?)</option>', m.group(2), re.S)})
        for station_id in sorted(options['jp'].keys() & options['etc'].keys()):
            append('京成電鉄', station_id, options['jp'][station_id], options['etc'][station_id],
                   'keisei-station-map-ja',
                   'official Japanese/English station map selectors + same numeric station map ID + operator + unique native identity')
    if 'tobu-en' in documents and 'tobu-station-ja' in documents:
        native = {m.group(1): text(m.group(2)) for m in re.finditer(r'<a[^>]*href="/railway/guide/station/info/(\d+)/"[^>]*>(.*?)</a>', documents['tobu-station-ja'], re.S)}
        for m in re.finditer(r'<a[^>]*href="/en/service/station/(\d+)\.html"[^>]*>(.*?)</a>', documents['tobu-en'], re.S):
            japanese = native.get(m.group(1), '')
            english = field(m.group(2), 'ttl', 'span').removesuffix(' Sta.')
            if japanese and english:
                append('東武鉄道', m.group(1), japanese, english, 'tobu-en',
                       'official English/Japanese station indices + same numeric station page ID + operator + unique native identity')
                output[-1]['identitySource'] = metadata['tobu-station-ja']['source']
                output[-1]['identitySha256'] = metadata['tobu-station-ja']['sha256']
    if 'seibu-ja' in documents:
        document = documents['seibu-ja']
        for m in re.finditer(r'<a[^>]*href="([^"]+)"[^>]*>\s*<div class="station__header__inner">(.*?)</a>', document, re.S):
            japanese = field(m.group(2), 'station__name__main', 'h4')
            english = field(m.group(2), 'station__name__sub', 'p')
            if japanese and english:
                append('西武鉄道', m.group(1).rstrip('/').removesuffix('/index.html').rsplit('/', 1)[-1],
                       japanese, english, 'seibu-ja',
                       'official bilingual station index + shared station page ID + operator + unique native identity')
    for source_id, document in documents.items():
        if source_id.startswith('meitetsu-station-'):
            append('名古屋鉄道', source_id.removeprefix('meitetsu-station-'),
                   field(document, 'stName1', 'span'), field(document, 'stName3', 'span'), source_id,
                   'official bilingual station header + station page ID + operator + unique native identity')
        elif source_id.startswith('keihan-station-'):
            append('京阪電気鉄道', source_id.removeprefix('keihan-station-'),
                   field(document, 'station-detail-heading1__title', 'h1'),
                   field(document, 'station-detail-heading1__furigana--romaji', 'div'), source_id,
                   'official bilingual station header + station page ID + operator + unique native identity')
        elif source_id.startswith('tokyu-station-'):
            name = field(document, 'portal-station__name-kanji', 'span')
            english = re.search(r'<dl class="portal-station__name">.*?<dd lang="en">(.*?)</dd>', document, re.S)
            append('東急電鉄', source_id.removeprefix('tokyu-station-'), name,
                   text(english.group(1)) if english else '', source_id,
                   'official station English notation + station page ID + operator + unique native identity')
        elif source_id.startswith('tokyu-web-'):
            names = re.search(r'L\d+: ([^\n]+)\nL\d+: \nL\d+: 英語表記\nL\d+: +([^\n]+)', document)
            if names:
                append('東急電鉄', source_id.removeprefix('tokyu-web-'), names.group(1), names.group(2), source_id,
                       'official station English notation in retained web text + station page ID + operator + unique native identity')
        elif source_id.startswith('seibu-station-'):
            append('西武鉄道', source_id.removeprefix('seibu-station-'),
                   field(document, 'main__title', 'h1'), field(document, 'main__text', 'p'), source_id,
                   'official bilingual station header + station page ID + operator + unique native identity')
    return output


def build(package, records, manifest):
    by_identity = defaultdict(list)
    for record in records:
        by_identity[(record['operator'], normalize(record['ja']))].append(record)
    groups_by_name = defaultdict(set)
    for line in package['lines']:
        if line['operator'] in OPERATORS:
            for station in line['stations']:
                groups_by_name[(line['operator'], normalize(station[1]))].add(station[0])
    output, unresolved = {}, []
    for line in package['lines']:
        if line['operator'] not in OPERATORS:
            continue
        for station in line['stations']:
            identity = (line['operator'], normalize(station[1]))
            candidates = by_identity.get(identity, [])
            signatures = {(r['officialStationId'], r['en']) for r in candidates}
            # Duplicate display entries on different lines can represent the
            # same official station ID; conflicting identities remain open.
            reason = None
            if not candidates:
                reason = {'東武鉄道': 'official English station index lists six major stations; other English labels require station-sign image verification', '京王電鉄': 'official station headers and bilingual route PDF use image/vector glyph labels; no retained identity-matched English text', '小田急電鉄': 'official Japanese headers omit English text and current bilingual route PDF uses vector glyph labels', '京成電鉄': 'station absent from bilingual station-map selector or native name differs', '阪急電鉄': 'package station absent from official Hankyu bilingual station index', '京阪電気鉄道': 'shared station absent from official Keihan bilingual station header index'}.get(line['operator'], 'no retained official bilingual station identity for this operator/native name')
            elif len(signatures) != 1 or len(groups_by_name[identity]) != 1:
                reason = 'ambiguous official station ID or English label within operator/native identity'
            if reason:
                unresolved.append({'country': 'jp', 'lineId': line['id'], 'stationCode': station[0],
                                   'operator': line['operator'], 'name': station[1], 'reason': reason})
                continue
            evidence = candidates[0]
            output[line['id'] + ':' + station[0]] = {
                'country': 'jp', 'lineId': line['id'], 'stationCode': station[0],
                'operator': line['operator'], 'name': station[1], 'en': evidence['en'],
                'source': evidence['source'], 'identityEvidence': [evidence]}
    stats = {}
    for operator in sorted(OPERATORS):
        verified = [r for r in output.values() if r['operator'] == operator]
        missing = [r for r in unresolved if r['operator'] == operator]
        stats[operator] = {'verifiedLineStations': len(verified), 'verifiedStationGroups': len({r['stationCode'] for r in verified}),
                           'unresolvedLineStations': len(missing), 'unresolvedStationGroups': len({r['stationCode'] for r in missing})}
    return {'schema': 'station-english-evidence/1', 'countries': ['jp'],
            'retrievedAt': max(r['retrievedAt'] for r in manifest if r.get('retrievedAt')),
            'sources': manifest, 'byLineStation': dict(sorted(output.items())), 'unresolved': unresolved,
            'coverage': {'verifiedLineStations': len(output), 'verifiedStationGroups': len({r['stationCode'] for r in output.values()}),
                         'unresolvedLineStations': len(unresolved), 'byOperator': stats}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, default=SOURCES)
    parser.add_argument('--package', type=Path, default=PACKAGE)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    documents, metadata, manifest = load_sources(args.source_dir)
    result = build(json.loads(args.package.read_text()), official_records(documents, metadata), manifest)
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        if args.output.read_text() != encoded:
            raise SystemExit('private railway station English evidence needs regeneration')
    else:
        args.output.write_text(encoded)
    print(json.dumps(result['coverage'], ensure_ascii=False))


if __name__ == '__main__':
    main()
