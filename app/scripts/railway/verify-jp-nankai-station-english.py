#!/usr/bin/env python3
"""Verify Nankai English through bilingual official line indices and station IDs."""
import argparse
import copy
from collections import defaultdict
import gzip
import hashlib
import html
import json
from pathlib import Path
import re
import unicodedata

APP = Path(__file__).resolve().parents[2]
SOURCES = APP / 'data/station-english-sources/jp-nankai'
PACKAGE = APP / 'public/rail/jp-2025.json'
OUTPUT = APP / 'data/station-english-verified-jp-nankai.json'
REVIEW = APP / 'data/station-english-sources/jp-nankai-native-review/reviewed-native-identities.json'
OPERATOR = '南海電気鉄道'
ROUTES = {'南海本線': 'nankai_line', '空港線': 'airport_line', '高師浜線': 'takashinohama_line',
          '多奈川線': 'tanagawa_line', '加太線': 'kada_line', '和歌山港線': 'wakayamako_line',
          '高野線': 'koya_line', '泉北線': 'semboku_line', '鋼索線': 'kousaku_line'}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def native(value):
    return unicodedata.normalize('NFKC', value).replace('ヶ', 'ケ')


def plain(value):
    return html.unescape(re.sub(r'<[^>]*>', '', value)).strip()


def load_sources(directory=SOURCES):
    manifest = json.loads((directory / 'manifest.json').read_text())
    documents, metadata = {}, {}
    for entry in manifest:
        if not entry.get('rawFile'):
            continue
        raw = gzip.decompress((directory / entry['rawFile']).read_bytes())
        if sha(raw) != entry['sha256']:
            raise ValueError('source hash mismatch: ' + entry['rawFile'])
        documents[entry['id']] = raw.decode('utf8')
        metadata[entry['id']] = entry
    if '<option value="/en_railway">English</option>' not in documents.get('operator-home', ''):
        raise ValueError('official operator English-site ownership link absent')
    return documents, metadata, manifest


def station_rows(document, language):
    prefix = '/en_railway' if language == 'en' else ''
    rows = {}
    for block in re.split(r'<div class="el-station-block__item">', document)[1:]:
        name = re.search(r'<span class="el-station-block__item__detail__name">(.*?)</span>', block, re.S)
        station = re.search(r'href="' + prefix + r'/traffic/station/([^"/#]+)\.html', block)
        number = re.search(r'NK<span class="el-station-block__item__detail__numbering__item__number">(.*?)</span>', block, re.S)
        if name and station and number:
            row = {'stationId': station[1], 'stationNumber': 'NK' + plain(number[1]), 'name': plain(name[1])}
            if row['stationId'] in rows and rows[row['stationId']] != row:
                raise ValueError('conflicting official station ID: ' + row['stationId'])
            rows[row['stationId']] = row
    return rows


def bilingual_rows(documents, metadata):
    output = defaultdict(list)
    for source_id in documents:
        if not source_id.startswith('ja-'):
            continue
        route = source_id.removeprefix('ja-')
        english_id = 'en-' + route
        if english_id not in documents:
            continue
        ja = station_rows(documents[source_id], 'ja')
        en = station_rows(documents[english_id], 'en')
        for station_id in ja.keys() & en.keys():
            japanese, english = ja[station_id], en[station_id]
            if japanese['stationNumber'] != english['stationNumber']:
                raise ValueError('bilingual station number disagreement: ' + station_id)
            if not re.search(r'[A-Za-z]', english['name']):
                continue
            evidence = {'operator': OPERATOR, 'officialStationId': station_id,
                'stationNumber': japanese['stationNumber'], 'ja': japanese['name'], 'en': english['name'],
                'source': metadata[english_id]['source'], 'identitySource': metadata[source_id]['source'],
                'stationSource': 'https://www.nankai.co.jp/en_railway/traffic/station/' + station_id + '.html',
                'japaneseStationSource': 'https://www.nankai.co.jp/traffic/station/' + station_id + '.html',
                'sha256': metadata[english_id]['sha256'], 'identitySha256': metadata[source_id]['sha256'],
                'retrievedAt': metadata[english_id]['retrievedAt'], 'officialRouteId': route,
                'ownershipSource': metadata['operator-home']['source'],
                'ownershipSha256': metadata['operator-home']['sha256'],
                'matchMethod': 'same station page ID and NK station number in official Japanese/English line indices + exact operator/native identity'}
            output[(route, native(japanese['name']))].append(evidence)
    return output



# Explicit native-code exceptions, bounded to the four reviewed memberships.
EXPECTED_REVIEWS = {
    '007356': ('難波', 'なんば', 'namba', 'NK01', 'nankai_line', 'reviewed-native-alias'),
    '008294': ('和歌山大学前', '和歌山大学前(ふじと台)', 'wadaimae', 'NK43', 'nankai_line', 'reviewed-native-substation-name'),
    '007402': ('今宮戎', '今宮戎', 'imamiyaebisu', 'NK02', 'koya_line', 'reviewed-physical-line-service-index-difference'),
    '007452': ('萩ノ茶屋', '萩ノ茶屋', 'haginochaya', 'NK04', 'koya_line', 'reviewed-physical-line-service-index-difference'),
}
REVIEWED_SOURCE_HASHES = {'station-namba': '5ec5c52226ba19f01968953494241cf68992595b85297a7b1f5d40f42b3b517d', 'community-wadaimae': '6c80c12dfb32cf31f2a3fbc0417848ead5a0d3badfcb654a338660dfa1e05396', 'news-namba-260324': '534574c7fa8e08084cd85be9a4917fd8a6ec3eb1672be15c551c858d4250a44a', 'company-securities': 'fe2a0e5933c150c306ad580b52697b3d69758398cd5bba30a2e4f7f88b29ca79', 'securities-109th': 'ae826253cd13e04bb202fc948c4ab79bda9aa29f8d71785f351335bac90ece17', 'handbook-2023': 'd8d468d7578fa87ddc4b6e96295ff66af6942834f0c9ac88f69cc19c50411a04'}


def load_review(path=REVIEW):
    review = json.loads(path.read_text())
    records = {entry['id']: entry for entry in review['sourceRecords']}
    if set(records) != set(REVIEWED_SOURCE_HASHES):
        raise ValueError('reviewed native source coverage changed')
    documents = {}
    for source_id, entry in records.items():
        if entry['sha256'] != REVIEWED_SOURCE_HASHES[source_id]:
            raise ValueError('unreviewed native source SHA: ' + source_id)
        raw = gzip.decompress(((APP / review['rawDirectory']) / entry['rawFile']).read_bytes())
        if sha(raw) != entry['sha256']:
            raise ValueError('reviewed native source hash mismatch: ' + source_id)
        if entry['rawFile'].endswith('.html.gz'):
            documents[source_id] = raw.decode('utf8')
    if ('<span class="el-heading-station__numbering__item__number">01</span>' not in documents['station-namba']
            or '難波駅' not in plain(documents['station-namba'])
            or '南海電鉄難波駅1階' not in plain(documents['news-namba-260324'])):
        raise ValueError('reviewed namba native identity statement absent')
    wadaimae = plain(documents['community-wadaimae'])
    if ('「和歌山大学前」に決定しました。' not in wadaimae or '副駅名にもなっています。' not in wadaimae
            or '/traffic/station/wadaimae.html' not in documents['community-wadaimae']):
        raise ValueError('reviewed wadaimae native identity statement absent')
    return review


def reviewed_records(package, records, review):
    result = copy.deepcopy(records)
    primary = {entry['id']: entry for entry in review['sourceRecords']}
    rules = {entry['packageStationCode']: entry for entry in review['rules']}
    if set(rules) != set(EXPECTED_REVIEWS):
        raise ValueError('reviewed native membership coverage changed')
    line = next(line for line in package['lines'] if line['operator'] == OPERATOR and line['id'] == 'jp-南海電気鉄道-南海本線')
    members = {station[0]: station[1] for station in line['stations']}
    for code, expected in EXPECTED_REVIEWS.items():
        rule = rules[code]
        required = ({'handbook-2023', 'station-namba', 'news-namba-260324'} if code == '007356' else
                    {'community-wadaimae'} if code == '008294' else {'handbook-2023', 'securities-109th'})
        if {proof['sourceId'] for proof in rule.get('proof', [])} != required:
            raise ValueError('reviewed native proof coverage changed: ' + code)
        observed = (rule['packageNative'], rule['officialNative'], rule['officialStationId'], rule['stationNumber'],
                    rule.get('evidenceRoute', rule['packageRoute']), rule['kind'])
        if observed != expected or rule['packageRoute'] != 'nankai_line':
            raise ValueError('unreviewed native alias or service membership: ' + code)
        if members.get(code) != rule['packageNative']:
            raise ValueError('reviewed package code/native identity mismatch: ' + code)
        candidates = result.get((observed[4], native(rule['officialNative'])), [])
        matches = [entry for entry in candidates if (entry['officialStationId'], entry['stationNumber'], entry['ja'])
                   == (rule['officialStationId'], rule['stationNumber'], rule['officialNative'])]
        if len(matches) != 1:
            raise ValueError('reviewed official native station identity mismatch: ' + code)
        entry = copy.deepcopy(matches[0])
        entry['reviewedPackageIdentity'] = {key: value for key, value in rule.items() if key != 'proof'}
        entry['reviewedNativeIdentityEvidence'] = [{**proof, **primary[proof['sourceId']]} for proof in rule['proof']]
        entry['matchMethod'] += ' + bounded reviewed native identity rule ' + rule['kind']
        result[(rule['packageRoute'], native(rule['packageNative']))] = [entry]
    return result


def build(package, records, manifest, review=None):
    if review is not None:
        records = reviewed_records(package, records, review)
    verified, unresolved = {}, []
    groups = defaultdict(set)
    for line in package['lines']:
        if line['operator'] == OPERATOR:
            for station in line['stations']:
                groups[native(station[1])].add(station[0])
    for line in package['lines']:
        if line['operator'] != OPERATOR:
            continue
        route = 'shiomibashi_line' if line['id'].endswith('高野線-2') else ROUTES.get(line['name'])
        for station in line['stations']:
            identity = {'country': 'jp', 'lineId': line['id'], 'stationCode': station[0],
                        'operator': OPERATOR, 'name': station[1]}
            candidates = records.get((route, native(station[1])), [])
            signatures = {(r['officialStationId'], r['stationNumber'], r['en']) for r in candidates}
            if not candidates or len(signatures) != 1 or len(groups[native(station[1])]) != 1:
                unresolved.append({**identity, 'reason': 'official station native label differs or is absent on the matching operator line index' if not candidates else 'ambiguous official station identity within operator/native name'})
                continue
            evidence = candidates[0]
            verified[line['id'] + ':' + station[0]] = {**identity, 'en': evidence['en'],
                'source': evidence['source'], 'identityEvidence': [evidence]}
    return {'schema': 'station-english-evidence/1', 'countries': ['jp'],
        'note': 'Current operator-owned bilingual line indices joined by shared station page slug and NK station number. Native package labels require exact identity except Unicode width and ケ/ヶ typography. No existing package English field or kana romanization provides evidence.',
        'retrievedAt': max(r['retrievedAt'] for r in manifest if r.get('retrievedAt')),
        'sources': manifest, 'byLineStation': dict(sorted(verified.items())), 'unresolved': unresolved,
        'coverage': {'verifiedLineStations': len(verified), 'verifiedStationGroups': len({r['stationCode'] for r in verified.values()}),
                     'unresolvedLineStations': len(unresolved), 'unresolvedStationGroups': len({r['stationCode'] for r in unresolved})}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    documents, metadata, manifest = load_sources()
    review = load_review()
    result = build(json.loads(PACKAGE.read_text()), bilingual_rows(documents, metadata), manifest, review)
    result['note'] = 'Official bilingual station IDs and NK numbers plus four bounded, native-only reviewed alias and physical-versus-service membership proofs. Existing package English or romanization supplies no identity evidence.'
    result['reviewedIdentityRules'] = review['rules']
    result['additionalPrimarySources'] = review['sourceRecords']
    result['retrievedAt'] = max(result['retrievedAt'], *(entry['retrievedAt'] for entry in review['sourceRecords']))
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        if OUTPUT.read_text() != encoded:
            raise SystemExit('Nankai evidence is stale')
    else:
        OUTPUT.write_text(encoded)
    print(json.dumps(result['coverage'], ensure_ascii=False))


if __name__ == '__main__':
    main()
