#!/usr/bin/env python3
"""Verify Fukuoka memberships against retained visible native list and reviewed numbered map.

No network, package mutation, package romanization, or generated readings are used.
The English map has outlined text; map-labels-reviewed.json is a human-readable
transcription reviewed against the retained PDF rendering/JPG on 2026-10-01.
"""
import argparse, hashlib, html, json, re
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
ROOT = APP / 'data/station-english-sources/jp-fukuoka'
PACKAGE=APP/'public/rail/jp-2025.json'
OPERATOR = '福岡市'
LINES = {'k': 'jp-福岡市-1号線(空港線)', 'h': 'jp-福岡市-2号線(箱崎線)', 'n': 'jp-福岡市-3号線(七隈線)'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def parse_native(source):
    # Strip comments before examining visible native names/number classes.
    source = re.sub(r'<!--.*?-->', '', source, flags=re.S)
    result = {}
    for symbol, line_id in LINES.items():
        match = re.search(r'<div class="content_area area_'+symbol+r'">(.*?)</ul>', source, re.S)
        if not match:
            raise ValueError('Missing visible line list '+symbol)
        rows = re.findall(r'<li class="([khn]\d{2})"><a href="([^"]+)"><b[^>]*>(.*?)</b>', match[1], re.S)
        result[line_id] = []
        for number, href, native in rows:
            # Current native site represents transfer Hakata as K11 in the
            # Nanakuma list. Current EN map explicitly prints K11/N18 together.
            number = 'N18' if symbol == 'n' and number == 'k11' else number.upper()
            native = html.unescape(re.sub('<[^>]+>', '', native)).strip()
            result[line_id].append({'stationNumber': number, 'name': native, 'stationPage': 'https://subway.city.fukuoka.lg.jp/'+href})
    expected = {LINES['k']:13, LINES['h']:7, LINES['n']:18}
    if {key:len(rows) for key,rows in result.items()} != expected:
        raise ValueError('Incomplete native line inventory')
    return result

def build(package_path=PACKAGE, root=ROOT):
    metadata = json.loads((root/'sources.json').read_text())
    for filename, row in metadata.items():
        if digest(root/filename) != row['sha256']:
            raise ValueError('Retained source digest mismatch: '+filename)
    reviewed = json.loads((root/'map-labels-reviewed.json').read_text())
    if reviewed['sourceSha256'] != metadata['route-map.pdf']['sha256']:
        raise ValueError('Reviewed map digest mismatch')
    labels = reviewed['byStationNumber']
    native = parse_native((root/'home-ja.html').read_text())
    package = json.loads(package_path.read_text())
    output = {'schema':'station-english-evidence/1','countries':['jp'],
              'packageVersion':package['version'],'sources':metadata,
              'byLineStation':{},'unresolved':[]}
    for line in package['lines']:
        if line['operator'] != OPERATOR:
            continue
        if line['id'] not in native:
            raise ValueError('Unknown Fukuoka line')
        by_name = {row['name']:row for row in native[line['id']]}
        if len(by_name) != len(native[line['id']]):
            raise ValueError('Ambiguous native name within operator line')
        for station in line['stations']:
            group, name = station[:2]
            key = line['id']+':'+group
            if name not in by_name:
                output['unresolved'].append({'country':'jp','lineId':line['id'],'stationCode':group,'name':name,'reason':'No exact native identity on retained visible operator line list'})
                continue
            identity = by_name[name]
            number = identity['stationNumber']
            if number not in labels:
                raise ValueError('Unreviewed official station number')
            en = labels[number]
            evidence = {'operator':OPERATOR,'officialStationId':number,'stationNumber':number,
                'officialLineName':{'K':'Airport Line','H':'Hakozaki Line','N':'Nanakuma Line'}[number[0]],
                'name':name,'en':en,'source':metadata['route-map.pdf']['url'],
                'identitySource':metadata['home-ja.html']['url'],'stationPage':identity['stationPage'],
                'sha256':metadata['route-map.pdf']['sha256'],'retrievedAt':metadata['route-map.pdf']['retrievedAt'],
                'identitySha256':metadata['home-ja.html']['sha256'],'identityRetrievedAt':metadata['home-ja.html']['retrievedAt'],
                'matchMethod':'Exact operator and native name within current visible line list, paired to reviewed current official English map by station number',
                'sourceLocator':'English PDF page 1 numbered label '+number+'; Japanese home visible content_area area_'+number[0].lower(),
                'transformation':'Map label line-wrap joined with spaces; printed hyphen preserved; no transliteration'}
            if number=='H04':
                title = metadata['maidashi-title.jpg']
                evidence.update(source=title['url'], sha256=title['sha256'], retrievedAt=title['retrievedAt'],
                    sourceLocator='Current official bilingual station title image: H04 / 馬出九大病院前 / Maidashi-Kyudaibyoinmae',
                    matchMethod='Exact operator/native identity and station number on current bilingual title image, corroborated by current numbered English route map',
                    transformation='none', corroboratingSource=metadata['route-map.pdf']['url'],
                    corroboratingSha256=metadata['route-map.pdf']['sha256'])
                source = title['url']
            else:
                source = metadata['route-map.pdf']['url']
            if number=='N18':
                evidence['transferIdentityNote']='Native Nanakuma list links 博多 using class k11; current English map prints the shared Hakata marker K11/N18.'
            output['byLineStation'][key]={'country':'jp','lineId':line['id'],'stationCode':group,
                'operator':OPERATOR,'name':name,'en':en,'source':source,'identityEvidence':[evidence]}
    expected_memberships = sum(len(line['stations']) for line in package['lines'] if line['operator']==OPERATOR)
    if expected_memberships != len(output['byLineStation'])+len(output['unresolved']):
        raise ValueError('Missing scoped membership')
    return output

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--package',type=Path,default=PACKAGE);parser.add_argument('--check',action='store_true');parser.add_argument('--output',type=Path,default=APP/'data/station-english-verified-jp-fukuoka.json');args=parser.parse_args()
    result=build(args.package)
    rendered=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if args.check:
        if args.output.read_text()!=rendered: raise ValueError('Fukuoka evidence stale')
    else: args.output.write_text(rendered)
    print(json.dumps({'verifiedMemberships':len(result['byLineStation']),'groups':len({row['stationCode'] for row in result['byLineStation'].values()}),'unresolved':len(result['unresolved'])}))
