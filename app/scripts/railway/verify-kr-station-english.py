#!/usr/bin/env python3
"""Verify Korean memberships against retained official bilingual rows.

Offline deterministic rebuild. No package romanization or English values are proof.
Operator/line identities are scoped; nationwide native-name matching is prohibited.
Sources are raw anonymous data.go.kr downloads. XLSX is read with the stdlib.
"""
import argparse, collections, csv, hashlib, io, json, math, re, zipfile
from functools import lru_cache
from pathlib import Path
import xml.etree.ElementTree as ET
APP = Path(__file__).resolve().parents[2]
RAW = APP / 'data/station-english-sources/kr'
NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
OPERATOR_ALIASES = {'코레일': '한국철도공사', '서울시메트로9호선주식회사': '서울시메트로9호선', '부산김해경전철주식회사': '부산·김해경전철주식회사', '광주도시철도': '광주교통공사'}
# Explicit correspondence between display railways and official service lines.
# Physical lines that span more than one service are deliberately absent.
LINE_IDENTITIES = {
 'kr-gyeongbugosokseon': ('한국철도공사', ['경부선(고속)']),
 'kr-honamgosokseon': ('한국철도공사', ['호남선(고속)']),
 'kr-uisinseolseon': ('우이신설 도시철도', ['우이신설']),
 'kr-uijeongbugyeongjeoncheol': ('(주)우진메트로', ['의정부']),
 'kr-yongingyeongjeoncheol': ('용인에버라인운영(주)', ['에버라인']),
 'kr-bundangseon': ('한국철도공사', ['분당선', '수인분당']),
 'kr-suinseon': ('한국철도공사', ['수인선', '수인분당']),
 'kr-gyeongchunseon': ('한국철도공사', ['경춘']),
 'kr-gyeonguiseon': ('한국철도공사', ['경의중앙']),
 'kr-gyeonggangseon': ('한국철도공사', ['경강']),
 'kr-donghaeseon': ('한국철도공사', ['동해']),
 'kr-ilsanseon': ('한국철도공사', ['3호선']),
 'kr-gwacheonseon': ('한국철도공사', ['4호선']),
 'kr-ansanseon': ('한국철도공사', ['4호선']),
 'kr-incheongukjegonghangseon': ('공항철도주식회사', ['공항']),
 'kr-sinbundangseon': ('네오트랜스주식회사', ['신분당']),
 'kr-seohaeseon': ('한국철도공사', ['서해선']),
 'kr-3hoseon': ('서울교통공사', ['3호선']),
 'kr-4hoseon': ('서울교통공사', ['4호선']),
 'kr-busangimhaegyeongjeoncheol': ('부산·김해경전철주식회사', ['부산김해경전철']),
 'kr-seoul-jihacheol-9hoseon': ('서울시메트로9호선', ['9호선']),
}
for n in range(2,9):
 LINE_IDENTITIES[f'kr-seoul-jihacheol-{n}hoseon'] = ('서울교통공사', [f'{n}호선'])
for city, op, limit in [('busan', '부산교통공사',4),('daegu','대구교통공사',3),('daejeon','대전교통공사',1),('gwangju','광주교통공사',1),('incheon','인천교통공사',2)]:
 for n in range(1,limit+1):
  LINE_IDENTITIES[f'kr-{city}-dosicheoldo-{n}hoseon']=(op,[f'인천{n}호선' if city=='incheon' else f'{n}호선'])
for branch,service in [('macheonjiseon','5호선'),('hanamseon','5호선'),('seoul-jihacheol-2hoseon-sinjeongjiseon','2호선'),('seoul-jihacheol-2hoseon-seongsujiseon','2호선')]:
 LINE_IDENTITIES['kr-'+branch]=('서울교통공사',[service])

def clean(value):
 # OOXML escape is a carriage return, not part of the station name.
 return re.sub(r'\s+', ' ', str(value or '').replace('_x000D_', '\r')).strip()

@lru_cache(maxsize=None)
def base_name(value):
 return re.split(r'[（(]',clean(value),maxsplit=1)[0].strip()

def names_equal(package_name, official_name):
 p,o=base_name(package_name),base_name(official_name)
 return p==o or (o.endswith('역') and o[:-1]==p) or (p.endswith('역') and p[:-1]==o)

@lru_cache(maxsize=None)
def op_identity(value):
 return OPERATOR_ALIASES.get(clean(value),clean(value))

def xlsx_rows(path):
 with zipfile.ZipFile(path) as z:
  strings = [''.join(n.itertext()) for n in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('m:si',NS)] if 'xl/sharedStrings.xml' in z.namelist() else []
  result=[]
  for row in ET.fromstring(z.read('xl/worksheets/sheet1.xml')).findall('.//m:row',NS):
   cells={}
   for cell in row:
    col=0
    for char in re.sub('[0-9]','',cell.attrib['r']):col=col*26+ord(char)-64
    v=cell.find('m:v',NS)
    value=strings[int(v.text)] if cell.get('t')=='s' and v is not None else v.text if v is not None else ''.join(cell.itertext())
    cells[col-1]=clean(value)
   if cells:result.append([cells.get(i,'') for i in range(max(cells)+1)])
  return result

def source_rows(root=RAW):
 records=[];sources=[];positions=[]
 for mf in sorted(root.glob('*.metadata.json')):
  meta=json.loads(mf.read_text());path=root/meta['file'];raw=path.read_bytes()
  if hashlib.sha256(raw).hexdigest()!=meta['sha256']:raise ValueError(f'Source digest mismatch: {path}')
  sources.append(meta)
  if path.suffix=='.xlsx':
   rows=xlsx_rows(path)
   if not rows:continue
   for i,values in enumerate(rows[1:],2):
    row=dict(zip(rows[0],values));op=row.get('철도운영기관명',row.get('기관명'));line=row.get('선명',row.get('LN_NM'));name=row.get('역명');en=next((row[k] for k in ['역명(영문)','영어명','영역명'] if row.get(k)),None)
    if op and line and name and en:
     records.append(dict(operator=op,officialLine=line,name=name,en=en,officialStationCode=row.get('역번호') or None,source=meta['sourceURL'],identitySource=meta['sourceURL'],retrievedAt=meta['retrievedAt'],sha256=meta['sha256'],rawFile=meta['file'],sourceRow=i))
  elif path.suffix=='.csv':
   text=raw.decode(meta.get('encoding','utf-8-sig'));rows=list(csv.DictReader(io.StringIO(text)))
   if '.identity.' in path.name:
    for row in rows:
     op=row.get('철도운영기관명',row.get('철도운영기관'));line=row.get('선명');name=row.get('역명')
     if op and line and name and row.get('경도') and row.get('위도'):
      positions.append(dict(operator=op,officialLine=line,name=name,lon=float(row['경도']),lat=float(row['위도']),source=meta['sourceURL'],sha256=meta['sha256'],retrievedAt=meta['retrievedAt']))
   elif path.name=='15067652.csv':
    for i,row in enumerate(rows,2):
     if not row.get('역이름_영어'):continue
     for line in row.get('관련노선','').split(','):
      records.append(dict(operator='한국철도공사',officialLine=line,name=row['역이름'],en=row['역이름_영어'].strip(),officialStationCode=None,source=meta['sourceURL'],identitySource=meta['sourceURL'],retrievedAt=meta['retrievedAt'],sha256=meta['sha256'],rawFile=meta['file'],sourceRow=i,lon=float(row['경도좌표']),lat=float(row['위도좌표'])))
 return records,sources,positions

def distance_km(a,b):
 lat=math.radians((a[1]+b[1])/2);return math.hypot((a[0]-b[0])*111.32*math.cos(lat),(a[1]-b[1])*111.32)

def build(package,station_features,records,sources,positions):
 by_line={};unresolved=[]
 codes={(p['properties']['line_name'],p['properties']['operator'],p['properties']['n02_group_code']):p['properties']['n02_station_code'] for p in station_features['features']}
 for line in package['lines']:
  op=line['operator'];identity=LINE_IDENTITIES.get(line['id']);expected_lines=identity[1] if identity else [line['name']]
  for station in line['stations']:
   group,name,lon,lat=station[:4];key=line['id']+':'+group
   candidates=[r for r in records if op_identity(r['operator'])==op and r['officialLine'] in expected_lines and names_equal(name,r['name'])]
   accepted=[];reasons=[]
   for r in candidates:
    pos=[p for p in positions if op_identity(p['operator'])==op and p['officialLine']==r['officialLine'] and names_equal(name,p['name'])]
    if 'lon' in r:pos=[r]
    if pos and min(distance_km((lon,lat),(p['lon'],p['lat'])) for p in pos)>1.0:
     reasons.append('official-coordinate-disagrees-with-package');continue
    # Metropolitan-only 경강 table cannot establish high-speed 경강 stations;
    # 경의중앙 can establish 경의 names, but not unrelated 중앙 memberships.
    accepted.append(r)
   if not accepted:
    unresolved.append(dict(country='kr',lineId=line['id'],group=group,name=name,operator=op,stationCode=codes.get((line['name'],op,group)),reason=reasons[0] if reasons else ('official-operator-differs-from-package' if any(r['officialLine'] in expected_lines and names_equal(name,r['name']) for r in records) else 'no-official-operator-line-native-identity-match')));continue
   # Current bilingual name tables precede older station-code tables.
   accepted.sort(key=lambda r:(0 if Path(r['rawFile']).stem.startswith(('15064','15068')) else 1,r['source'],r['sourceRow']))
   primary=accepted[0];preferred=[r for r in accepted if (Path(r['rawFile']).stem.startswith(('15064','15068')))==(Path(primary['rawFile']).stem.startswith(('15064','15068')))]
   if len({r['en'] for r in preferred})>1:
    unresolved.append(dict(country='kr',lineId=line['id'],group=group,name=name,operator=op,stationCode=codes.get((line['name'],op,group)),reason='conflicting-official-english-rows',candidates=[dict(source=r['source'],name=r['name'],en=r['en']) for r in preferred]));continue
   evidence=[]
   for r in accepted:
    e={k:v for k,v in r.items() if k not in ['lon','lat']}
    pos=[p for p in positions if op_identity(p['operator'])==op and p['officialLine']==r['officialLine'] and names_equal(name,p['name'])]
    if 'lon' in r:pos=[r]
    e['matchMethod']='official-operator-line-native-name'+('-coordinate-within-1km' if pos else '-unique-scoped-row')
    if pos:
     nearest=min(pos,key=lambda p:distance_km((lon,lat),(p['lon'],p['lat'])))
     e['identitySource']=nearest['source'];e['identitySha256']=nearest['sha256']
     e['identityRetrievedAt']=nearest['retrievedAt']
     e['officialCoordinates']=[nearest['lon'],nearest['lat']]
     e['coordinateDistanceKm']=round(distance_km((lon,lat),(nearest['lon'],nearest['lat'])),6)
    evidence.append(e)
   aliases=sorted({r['name'] for r in accepted if r['name']!=name})
   by_line[key]=dict(country='kr',lineId=line['id'],stationCode=group,persistedStationCode=codes.get((line['name'],op,group)),operator=op,name=name,names=sorted({name,*aliases}),nameAliases=aliases,en=primary['en'],source=primary['source'],sourceURL=primary['source'],identityEvidence=evidence)
 return dict(schema='station-english-evidence/1',countries=['kr'],byLineStation=by_line,unresolved=unresolved,sources=sources,method='Official bilingual native identities scoped to operator and explicit line; parenthetical official qualifiers are recorded as aliases. No package English, generated code, flag or national name-only join establishes verification.',coverage=dict(totalMemberships=sum(len(l['stations']) for l in package['lines']),verifiedMemberships=len(by_line),unresolvedMemberships=len(unresolved),verifiedGroups=len({k.split(':',1)[1] for k in by_line}-{r['group'] for r in unresolved}),groupsWithVerifiedMembership=len({k.split(':',1)[1] for k in by_line})))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');ap.add_argument('--output',type=Path,default=APP/'data/station-english-verified-kr.json');args=ap.parse_args()
 records,sources,positions=source_rows();result=build(json.loads((APP/'public/rail/kr-2025.json').read_text()),json.loads((APP/'data/stations-kr.json').read_text()),records,sources,positions)
 rendered=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
 if args.check:
  if args.output.read_text()!=rendered:raise SystemExit('Korean station evidence is stale')
 else:args.output.write_text(rendered)
 print(json.dumps(result['coverage']))
if __name__=='__main__':main()
