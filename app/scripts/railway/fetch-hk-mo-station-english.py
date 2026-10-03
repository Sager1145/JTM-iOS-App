#!/usr/bin/env python3
"""Fetch primary bilingual operator inventories and join only evidenced group identities.

Online: python3 app/scripts/railway/fetch-hk-mo-station-english.py
Offline reproduction: --source-dir DIR with URL-key.raw files captured from sources.
The snapshot stores extracted source records and SHA-256 hashes; package English names
and package flags are never evidence. Unmatched/ambiguous identities remain unresolved.
"""
import argparse
import csv
import hashlib
import html
import io
import json
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
URLS = {
    'mtr': 'https://opendata.mtr.com.hk/data/mtr_lines_and_stations.csv',
    'lr': 'https://opendata.mtr.com.hk/data/light_rail_routes_and_stops.csv',
    'tram_en': 'https://static.data.gov.hk/tramways/datasets/tram_stops/summary_tram_stops_en.csv',
    'tram_tc': 'https://static.data.gov.hk/tramways/datasets/tram_stops/summary_tram_stops_tc.csv',
    'mo': 'https://www.mlm.com.mo/en/route.html',
    'mtr_map_en': 'https://www.mtr.com.hk/en/customer/services/system_map.html',
    'mtr_map_ch': 'https://www.mtr.com.hk/ch/customer/services/system_map.html',
}
DIRECTIONS = {'Westbound': '西行', 'Eastbound': '東行', 'Southbound': '南行', 'Northbound': '北行'}

def norm(name):
    return re.sub(r'\s+', '', name).replace('（', '(').replace('）', ')').replace('茘', '荔')

def unique(records, key):
    values = {}
    for r in records:
        k = r[key]
        if k in values and (values[k]['name'], values[k]['en']) != (r['name'], r['en']):
            raise ValueError(f'Conflicting official bilingual identity: {k}')
        values[k] = r
    return list(values.values())

def csv_rows(data):
    return list(csv.DictReader(io.StringIO(data.decode('utf-8-sig'))))

def parse_sources(raw):
    records = []
    for key, operator, code_field in [('mtr', 'MTR', 'Station Code'), ('lr', 'MTR Light Rail', 'Stop ID')]:
        rows = []
        for r in csv_rows(raw[key]):
            if not r[code_field]:
                continue
            rows.append({'operator': operator, 'code': r[code_field], 'name': r['Chinese Name'],
                         'en': r['English Name'], 'source': URLS[key],
                         'sourceCode': r.get('Stop Code', r[code_field])})
        records.extend(unique(rows, 'code'))
    # The MTR CSV excludes Racecourse. Both map tables reference the same rac.pdf.
    pair = []
    for key in ['mtr_map_en', 'mtr_map_ch']:
        text = raw[key].decode('utf-8')
        names = [re.search(r'<td\b[^>]*>(.*?)</td>', m.group(1), re.S | re.I).group(1)
                 for m in re.finditer(r'<tr\b[^>]*>(.*?)</tr>', text, re.S | re.I)
                 if '/maps/rac.pdf' in m.group(1)]
        if len(names) != 1:
            raise ValueError('Racecourse bilingual map identity missing or ambiguous')
        pair.append(html.unescape(re.sub('<[^>]+>', '', names[0])).strip())
    records.append({'operator': 'MTR', 'code': 'RAC', 'sourceCode': 'rac.pdf', 'name': pair[1],
                    'en': pair[0], 'source': URLS['mtr_map_en'], 'identitySource': URLS['mtr_map_ch']})
    ens, tcs = csv_rows(raw['tram_en']), csv_rows(raw['tram_tc'])
    if len(ens) != len(tcs):
        raise ValueError('Tram bilingual inventories differ in length')
    trams = []
    for en, tc in zip(ens, tcs):
        if en['Stops Code'] != tc['車站代號'] or DIRECTIONS.get(en['Traveling Direction']) != tc['行駛方向']:
            raise ValueError('Tram bilingual row identity mismatch')
        trams.append({'operator': 'Hong Kong Tramways', 'code': en['Stops Code'],
                      'name': tc['車站名稱'], 'en': en['Stops Name'], 'source': URLS['tram_en'],
                      'identitySource': URLS['tram_tc'], 'direction': en['Traveling Direction']})
    records.extend(trams)
    text = raw['mo'].decode('utf-8')
    # Pair Chinese map identities and English route-selector names by the same data index.
    chinese = {}
    for attrs, content in re.findall(r'<span\b([^>]*class="selectPoint"[^>]*)>(.*?)</span\s*>', text, re.S):
        index = re.search(r'data-index="([^"]+)"', attrs)
        if index and re.search('[\u4e00-\u9fff]', content):
            chinese[index.group(1)] = html.unescape(content.strip())
    names = {}
    for block in re.findall(r'var\s+(?:taipa_line|Hengqin_line|spv_line)\s*=\s*\[(.*?)\];', text, re.S):
        for en, code in re.findall(r'\{\s*text:\s*"([^"]+)"\s*,\s*value:\s*"([^"]+)"\s*,?\s*\}', block, re.S):
            en = re.sub(r' \(Transfer to [^)]*\)$', '', en)
            if code in names and names[code] != en:
                raise ValueError('Conflicting Macao selector identity')
            names[code] = en
    if len(names) != 15 or set(names) != set(chinese):
        raise ValueError('Macao bilingual route-index inventory incomplete')
    records.extend({'operator': 'Macao LRT', 'code': code, 'name': chinese[code], 'en': en,
                    'source': URLS['mo']} for code, en in names.items())
    return records

def match_group(country, group, name, operator, records):
    if country == 'hk':
        category = 'MTR Light Rail' if '-lr-' in group else 'MTR' if '-mtr-' in group else 'Hong Kong Tramways'
        expected_operator = 'MTR' if category.startswith('MTR') else '香港電車'
        if operator != expected_operator:
            return None
        token = group.rsplit('-', 1)[1].upper()
        candidates = [r for r in records if r['operator'] == category and norm(r['name']) == norm(name)
                      and (r['code'].upper() == token or category == 'Hong Kong Tramways' and r['code'] == 'T')]
    else:
        if operator != '澳門輕軌':
            return None
        # Lotus is labelled 蓮花口岸站 in the operator map but paired to the official
        # selector's Lotus identity by data-index 7.1. Keep that discrepancy visible.
        candidates = [r for r in records if r['operator'] == 'Macao LRT'
                      and (r['name'].removesuffix('站') == name or
                           group == 'mo-official-mlm-lotus' and r['code'] == '7.1' and name == '蓮花')]
    identities = {(r['name'], r['en'], r['code']) for r in candidates}
    return candidates[0] if len(identities) == 1 else None

def build_snapshot(packages, records, sources, retrieved):
    out = {'schemaVersion': 1, 'retrievedAt': retrieved, 'sources': sources, 'sourceRecords': records, 'byCountry': {}}
    for country, package in packages.items():
        groups = {}
        for line in package['lines']:
            for station in line['stations']:
                group, name = station[:2]
                identity = (name, line['operator'])
                if group in groups and groups[group] != identity:
                    raise ValueError(f'Conflicting package group identity: {group}')
                groups[group] = identity
        entries, unresolved = {}, []
        for group, (name, operator) in sorted(groups.items()):
            r = match_group(country, group, name, operator, records)
            if not r:
                unresolved.append({'code': group, 'name': name, 'operator': operator, 'reason': 'No unique operator-scoped bilingual source identity'})
                continue
            evidence = {'operator': r['operator'], 'sourceStationCode': r['code'], 'sourceName': r['name'],
                        'matchMethod': 'operator-scoped-code-and-Chinese-name' if country == 'hk' and r['code'] != 'T' else 'operator-scoped-bilingual-identity',
                        'retrievedAt': retrieved}
            if 'identitySource' in r:
                evidence['identitySource'] = r['identitySource']
            if 'sourceCode' in r:
                evidence['sourceCode'] = r['sourceCode']
            if country == 'mo':
                evidence['matchMethod'] = 'operator-bilingual-shared-route-index'
            entries[group] = {'name': name, 'en': r['en'], 'source': r['source'], 'retrievedAt': retrieved,
                              'identityEvidence': evidence}
        out['byCountry'][country] = {'byCode': entries, 'unresolved': unresolved,
                                    'coverage': {'packageGroups': len(groups), 'verifiedGroups': len(entries), 'unresolvedGroups': len(unresolved)}}
    return out

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/hk-mo-station-english-official.json')
    args = parser.parse_args()
    retrieved = datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
    raw = {key: (args.source_dir / f'{key}.raw').read_bytes() if args.source_dir else urllib.request.urlopen(url, timeout=60).read()
           for key, url in URLS.items()}
    sources = [{'id': key, 'url': url, 'retrievedAt': retrieved, 'sha256': hashlib.sha256(raw[key]).hexdigest()} for key, url in URLS.items()]
    packages = {c: json.loads((ROOT / f'public/rail/{c}-2025.json').read_text()) for c in ['hk', 'mo']}
    out = build_snapshot(packages, parse_sources(raw), sources, retrieved)
    args.output.write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({c: v['coverage'] for c, v in out['byCountry'].items()}))

if __name__ == '__main__':
    main()
