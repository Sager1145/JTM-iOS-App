#!/usr/bin/env python3
"""Build Taiwan station English evidence from hashed official PTX snapshots.

Only operator-specific bilingual station identities present in an official
StationOfLine response are admitted. A package flag or existing English value
never supplies evidence. Run offline after fetching the raw files recorded in
station-english-sources/tw/manifest.json; --check verifies reproducibility.
AFR station-page evidence is maintained separately by the unified catalog.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
SOURCES = APP / 'data/station-english-sources/tw'
PACKAGE = APP / 'public/rail/tw-2025.json'
OUTPUT = APP / 'data/station-english-verified-tw.json'

RULES = [
    ('tw-thsr', 'THSR', '台灣高速鐵路股份有限公司', ['THSR']),
    ('tw-tra-chengzhui', 'TRA', '國營臺灣鐵路股份有限公司', ['CZ']),
    ('tw-tra-coast', 'TRA', '國營臺灣鐵路股份有限公司', ['WL-C']),
    ('tw-tra-jiji', 'TRA', '國營臺灣鐵路股份有限公司', ['JJ']),
    ('tw-tra-liujia', 'TRA', '國營臺灣鐵路股份有限公司', ['LJ']),
    ('tw-tra-neiwan', 'TRA', '國營臺灣鐵路股份有限公司', ['NW']),
    ('tw-tra-pingxi', 'TRA', '國營臺灣鐵路股份有限公司', ['PX']),
    ('tw-tra-shalun', 'TRA', '國營臺灣鐵路股份有限公司', ['SH']),
    ('tw-tra-shenao', 'TRA', '國營臺灣鐵路股份有限公司', ['SA']),
    ('tw-tra-north-link', 'TRA', '國營臺灣鐵路股份有限公司', ['EL']),
    ('tw-tra-taitung', 'TRA', '國營臺灣鐵路股份有限公司', ['EL', 'SL']),
    ('tw-tra-yilan', 'TRA', '國營臺灣鐵路股份有限公司', ['EL', 'SU']),
    ('tw-tra-south-link', 'TRA', '國營臺灣鐵路股份有限公司', ['SL']),
    ('tw-tra-pingtung', 'TRA', '國營臺灣鐵路股份有限公司', ['WL', 'SL']),
    ('tw-tra', 'TRA', '國營臺灣鐵路股份有限公司', ['WL']),
    ('tw-trtc-y', 'NTMC', '新北大眾捷運股份有限公司', ['Y']),
    ('tw-ntmetro-lb', 'NTMC', '新北大眾捷運股份有限公司', ['LB']),
    ('tw-trtc', 'TRTC', '臺北大眾捷運股份有限公司', None),
    ('tw-tym', 'TYMC', '桃園大眾捷運股份有限公司', ['A']),
    ('tw-tcmrt', 'TMRT', '臺中捷運股份有限公司', ['G']),
    ('tw-krtc', 'KRTC', '高雄捷運股份有限公司', None),
    ('tw-ntmetro-v', 'NTDLRT', '新北大眾捷運股份有限公司', ['V']),
    ('tw-ntmetro-k', 'NTALRT', '新北大眾捷運股份有限公司', ['K']),
    ('tw-klrt', 'KLRT', '高雄捷運股份有限公司', ['C']),
]


def normalize_name(name):
    # Official Zh_tw differs in 臺/台 and in whether the station suffix is
    # displayed. Slash components are considered only for merged group names.
    return str(name).strip().replace('臺', '台').replace(' ', '').removesuffix('站')


def distance_km(row, official):
    pos = official.get('StationPosition', {})
    lon, lat = pos.get('PositionLon'), pos.get('PositionLat')
    if lon is None or lat is None:
        return math.inf
    return math.hypot((float(lon) - row[2]) * 111.32 * math.cos(math.radians(row[3])),
                      (float(lat) - row[3]) * 110.574)


def mapping(line):
    for prefix, system, operator, line_ids in RULES:
        if line['id'].startswith(prefix):
            if line['operator'] != operator:
                raise ValueError(f"operator mismatch: {line['id']}: {line['operator']}")
            if line_ids is None:
                line_ids = [line['id'].split('-')[2].upper()]
            return system, line_ids
    return None, []


def load_sources(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    source_data = {}
    for item in manifest:
        if 'rawFile' not in item:
            continue
        raw = (directory / item['rawFile']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != item['sha256']:
            raise ValueError(f"source hash mismatch: {item['rawFile']}")
        if not item.get('retrievedAt') or not item['source'].startswith('https://ptx.transportdata.tw/'):
            raise ValueError(f"invalid provenance: {item['rawFile']}")
        rows = json.loads(raw)
        if len(rows) != item['count']:
            raise ValueError(f"source count mismatch: {item['rawFile']}")
        source_data[(item['system'], item.get('kind', 'station'))] = (rows, item)
    return source_data, manifest


def match_station(row, stations, members):
    full = normalize_name(row[1])
    names = {full}
    names.update(normalize_name(part) for part in row[1].split('/'))
    candidates = [s for s in stations if str(s['StationID']) in members
                  and normalize_name(s['StationName']['Zh_tw']) in names
                  and distance_km(row, s) <= 2.0]
    exact = [s for s in candidates if normalize_name(s['StationName']['Zh_tw']) == full]
    if exact:
        candidates = exact
    # A shared map group can carry another operator's UID. It is never used
    # as an authority for the requested line. Membership + bilingual native
    # identity + a nearby official position must still select a unique row.
    if len(candidates) != 1:
        return None, 'no unique operator/line/native-name/position identity'
    candidate = candidates[0]
    if not candidate['StationName'].get('En', '').strip():
        return None, 'official station identity has no English label'
    line_name = members[str(candidate['StationID'])]
    if isinstance(line_name, dict):
        if (line_name.get('Zh_tw') != candidate['StationName']['Zh_tw']
                or line_name.get('En') != candidate['StationName']['En']):
            return None, 'official station and line bilingual labels disagree'
    elif normalize_name(line_name) != normalize_name(candidate['StationName']['Zh_tw']):
        return None, 'official station and line native labels disagree'
    return candidate, None


def build(package, source_data, manifest):
    output, unresolved, deferred = {}, [], []
    for line in package['lines']:
        system, official_lines = mapping(line)
        if system is None:
            deferred.extend(line['id'] + ':' + row[0] for row in line['stations'])
            continue
        stations, provenance = source_data[(system, 'station')]
        line_rows, identity = source_data[(system, 'stationOfLine')]
        members = {}
        for official_line in line_rows:
            if official_line['LineID'] in official_lines:
                for member in official_line['Stations']:
                    members[str(member['StationID'])] = member['StationName']
        for row in line['stations']:
            key = line['id'] + ':' + row[0]
            official, reason = match_station(row, stations, members)
            if official is None:
                unresolved.append({'country': 'tw', 'lineId': line['id'], 'stationCode': row[0],
                                   'operator': line['operator'], 'name': row[1], 'reason': reason})
                continue
            names = official['StationName']
            evidence = {'operator': line['operator'], 'officialStationId': official['StationUID'],
                        'zh': names['Zh_tw'], 'en': names['En'], 'source': provenance['source'],
                        'identitySource': identity['source'], 'retrievedAt': provenance['retrievedAt'],
                        'sha256': provenance['sha256'], 'identitySha256': identity['sha256'],
                        'matchMethod': 'operator + official line station ID + bilingual native name + official position within 2km'}
            if official.get('SrcUpdateTime'):
                evidence['sourceUpdatedAt'] = official['SrcUpdateTime']
            output[key] = {'country': 'tw', 'lineId': line['id'], 'stationCode': row[0],
                           'operator': line['operator'], 'name': row[1], 'en': names['En'],
                           'source': provenance['source'], 'identityEvidence': [evidence]}
    return {'schema': 'station-english-evidence/1', 'countries': ['tw'],
            'retrievedAt': max(item['retrievedAt'] for item in manifest if 'retrievedAt' in item),
            'sources': manifest, 'byLineStation': dict(sorted(output.items())),
            'unresolved': unresolved,
            'coverage': {'verifiedLineStations': len(output), 'verifiedStationGroups': len({r['stationCode'] for r in output.values()}),
                         'unresolvedLineStations': len(unresolved), 'deferredAFRLineStations': len(deferred)},
            'deferred': {'reason': 'AFR operator station-page evidence is maintained separately in tw-station-english-afr-source.json',
                         'lineStations': sorted(deferred)}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, default=SOURCES)
    parser.add_argument('--package', type=Path, default=PACKAGE)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source_data, manifest = load_sources(args.source_dir)
    result = build(json.loads(args.package.read_text()), source_data, manifest)
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        if args.output.read_text() != encoded:
            raise SystemExit('Taiwan English evidence needs regeneration')
    else:
        args.output.write_text(encoded)
    print(json.dumps(result['coverage']))


if __name__ == '__main__':
    main()
