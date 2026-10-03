#!/usr/bin/env python3
"""Rebuild scratch evidence from retained official PDF visual transcription.
No network, package English, or transliteration. Intended for review before integration.
"""
import argparse,csv,hashlib,json,re,unicodedata
from pathlib import Path
from collections import defaultdict,Counter
APP=Path(__file__).resolve().parents[2]
ROOT=APP/'data/station-english-sources/jp-shikoku'
PACKAGE=APP/'public/rail/jp-2025.json'
OPERATOR='四国旅客鉄道'
PREFIXES={'予土線':{'G'},'予讃線':{'Y','U','S'},'内子線':{'U'},'土讃線':{'D','K'},'徳島線':{'B'},'高徳線':{'T'},'鳴門線':{'N'},'牟岐線':{'M'},'本四備讃線':{'SET','Y'}}
LINES={'Y':'予讃線','U':'予讃線・内子線','S':'予讃線（伊予長浜経由）','D':'土讃線','K':'土讃線','G':'予土線','B':'徳島線','T':'高徳線','N':'鳴門線','M':'牟岐線','SET':'瀬戸大橋線'}
def norm(v):return unicodedata.normalize('NFKC',v).replace('ヶ','ケ').replace('ヵ','カ')
def sha(data):return hashlib.sha256(data).hexdigest()
def read_sources(root):
 manifest=json.loads((root/'raw/manifest.json').read_text())
 sources={}
 for m in manifest:
  raw=(root/'raw'/m['file']).read_bytes()
  if sha(raw)!=m['sha256']:raise ValueError('Source digest mismatch: '+m['file'])
  sources[m['file']]=dict(m,raw=raw)
 review=json.loads((root/'visual-review.json').read_text())
 if review['pdfSha256']!=sources['map.pdf']['sha256']:raise ValueError('Visual review PDF mismatch')
 trans=(root/'transcription.tsv').read_bytes()
 if sha(trans)!=review['transcriptionSha256']:raise ValueError('Unreviewed visual transcription change')
 rows=list(csv.DictReader(trans.decode().splitlines(),delimiter='\t'))
 if len({r['code'] for r in rows})!=len(rows):raise ValueError('Duplicate published route codes')
 for row in rows:
  row['prefix']=re.match(r'[A-Z]+',row['code'])[0]
  if row['prefix'] not in LINES:raise ValueError('Unknown published route')
  if not row['name'] or not row['en']:raise ValueError('Empty visual label')
 return manifest,sources,review,rows

def temporary_rows(sources):
 from pypdf import PdfReader
 import io
 ja=sources['number-ja.html']['raw'].decode();en=sources['number-en.html']['raw'].decode()
 if '津島ノ宮及び田井ノ浜の臨時2駅を除く' not in ja:raise ValueError('Native temporary station pair changed')
 match=re.search(r'excluding two temporary stations, ([A-Za-z]+) and ([A-Za-z]+)',en)
 if not match:raise ValueError('English temporary station pair changed')
 text=PdfReader(io.BytesIO(sources['summer2026-ja.pdf']['raw'])).pages[0].extract_text()
 text=re.sub(r'\s+','',text)
 result={}
 for (native,line),english in zip([('津島ノ宮','予讃線'),('田井ノ浜','牟岐線')],match.groups()):
  if line+'に「'+native+'駅」を臨時に開設' not in text:raise ValueError('Missing published temporary station line')
  result[native]={'name':native,'en':english,'officialLines':[line]}
 return result

def build(package=None,root=ROOT):
 raw_package=PACKAGE.read_bytes();package=package or json.loads(raw_package)
 manifest,sources,review,rows=read_sources(root);temps=temporary_rows(sources)
 groups=defaultdict(set)
 for line in package['lines']:
  if line['operator']==OPERATOR:
   for code,name,*_ in line['stations']:groups[norm(name)].add(code)
 records={};unresolved=[]
 for line in package['lines']:
  if line['operator']!=OPERATOR:continue
  for code,name,*_ in line['stations']:
   key=line['id']+':'+code
   if key in records:raise ValueError('Duplicate line/group membership')
   base={'country':'jp','lineId':line['id'],'stationCode':code,'operator':OPERATOR,'name':name}
   reason=None
   if len(groups[norm(name)])>1:reason='Native name occurs in multiple package groups; explicit additional identity required'
   allowed=PREFIXES.get(line['name'],set())
   if line['id'].endswith(('-2','-3')):allowed={'U'}
   candidates=[r for r in rows if norm(r['name'])==norm(name) and r['prefix'] in allowed]
   # Utazu is the map's Y09 junction with the published Seto-Ohashi line.
   if line['name']=='本四備讃線':candidates=[r for r in candidates if r['code'] in ('SET0','Y09')]
   english=set(r['en'] for r in candidates)
   if not reason and name in temps:
    t=temps[name]
    if line['name'] not in t['officialLines']:reason='Temporary station published line mismatch'
    else:
     meta=sources['number-en.html'];evidence=[]
     for f,role in [('number-en.html','published English pair'),('number-ja.html','published native pair'),('summer2026-ja.pdf','2026 published native route')]:
      m=sources[f];evidence.append({'name':name,'en':t['en'],'operator':OPERATOR,'officialLines':t['officialLines'],'source':m['source'],'rawFile':m['file'],'sha256':m['sha256'],'retrievedAt':m['retrievedAt'],'evidenceRole':role,'page':1 if f.endswith('.pdf') else None,'matchMethod':'operator_bilingual_numbering_same_temporary_station_pair_and_published_native_line'})
     records[key]={**base,'en':t['en'],'source':meta['source'],'sourceURL':meta['source'],'identityEvidence':evidence};continue
   if not reason and (not candidates or len(english)!=1):reason='No unambiguous visually reviewed bilingual label on the published route'
   if reason:unresolved.append({**base,'reason':reason});continue
   meta=sources['map.pdf']
   evidence={'name':name,'publishedNativeNames':sorted({r['name'] for r in candidates}),'en':next(iter(english)),'operator':OPERATOR,'source':meta['source'],'rawFile':meta['file'],'sha256':meta['sha256'],'retrievedAt':meta['retrievedAt'],'page':1,'officialLines':sorted({LINES[r['prefix']] for r in candidates}),'officialStationNumbers':[r['code'] for r in candidates if r['code']!='SET0'],'transcriptionFile':'transcription.tsv','transcriptionSha256':review['transcriptionSha256'],'matchMethod':'operator_bilingual_route_map_visually_reviewed_native_name_and_published_route_station_number'}
   if any(r['code']=='SET0' for r in candidates):evidence['matchMethod']='operator_bilingual_route_map_visually_reviewed_native_name_and_published_seto_ohashi_line';evidence['note']='Kojima is printed on the Seto-Ohashi line without a station number. SET0 is a local transcription locator, never a published station ID.'
   records[key]={**base,'en':next(iter(english)),'source':meta['source'],'sourceURL':meta['source'],'identityEvidence':[evidence]}
 return {'schema':'station-english-evidence/1','countries':['jp'],'packageVersion':package['version'],'packageSha256':sha(raw_package),'note':'Scratch candidate. Map English copied verbatim from retained current official 2025.5.1 bilingual map; source PDF has outlined text and requires retained reviewed visual transcription. Temporary station English comes from paired official numbering pages with 2026 route identity. No package English used. Native normalization is NFKC and small ケ/カ equivalence only.','sources':manifest,'byLineStation':dict(sorted(records.items())),'unresolved':unresolved,'coverage':{'verifiedMemberships':len(records),'unresolvedMemberships':len(unresolved),'groupsWithVerifiedMembership':len({r['stationCode'] for r in records.values()}),'unresolvedReasons':dict(Counter(r['reason'] for r in unresolved))}}
def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();b=build();s=json.dumps(b,ensure_ascii=False,indent=2)+'\n';out=APP/'data/station-english-verified-jp-shikoku.json'
 if a.check:
  if out.read_text()!=s:raise SystemExit('Scratch Shikoku candidate stale')
 else:out.write_text(s)
 print(json.dumps(b['coverage'],ensure_ascii=False))
if __name__=='__main__':main()
