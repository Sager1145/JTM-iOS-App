#!/usr/bin/env python3
"""Regenerate eleven reviewed KR proofs offline from retained publications.
First-pass scope is reproduced from raw publications, never loaded from cached
English evidence. Retained coordinate blocks and mismatches remain unresolved.
"""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,sys,tempfile
APP=Path(__file__).resolve().parents[2]
ROOT=APP/'data/station-english-sources/next-official'
PACKET=ROOT/'kr-operators-second-pass'
OUTPUT=APP/'data/station-english-verified-kr-second-pass.json'
BASELINE=APP/'data/station-english-kr-second-pass-first-baseline.json'
REVIEW=APP/'data/station-english-kr-second-pass-review.json'
def load(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def text(v):return json.dumps(v,ensure_ascii=False,indent=2,sort_keys=True)+'\n'
def validate(result,package,features):
 members={};codes={}
 for line in package['lines']:
  for s in line['stations']:
   key=line['id']+':'+s[0]
   if key in members:raise ValueError('duplicate current membership')
   members[key]=(line['operator'],s[1],line['name'])
 for f in features['features']:
  p=f['properties'];codes[(p['line_name'],p['operator'],p['n02_group_code'])]=p['n02_station_code']
 for key,row in result['byLineStation'].items():
  if row['country']!='kr' or key!=row['lineId']+':'+row['stationCode'] or key not in members:raise ValueError('unknown/miskeyed/non-KR evidence')
  op,native,lineName=members[key]
  if (row['operator'],row['name'])!=(op,native):raise ValueError('current operator/native identity mismatch')
  if row['persistedStationCode']!=codes.get((lineName,op,row['stationCode'])):raise ValueError('current persisted station identity mismatch')
 if len(result['byLineStation'])!=11 or len(result['unresolved'])!=96:raise ValueError('reviewed cohort partition changed')
 if sum('coordinate-conflict' in r['category'] for r in result['unresolved'])!=19:raise ValueError('coordinate blocks changed')
def portable(v,app):
 if isinstance(v,list):return [portable(a,app)for a in v]
 if isinstance(v,dict):
  r={k:portable(a,app)for k,a in v.items()}
  for key in ('rawFile','file'):
   if key in r and isinstance(r[key],str):
    f=r[key]
    if f.startswith('data/'):
     r['rawRoot']=str(Path(f).parent);r[key]=Path(f).name
    elif (APP/'data/station-english-sources/kr'/f).is_file():r['rawRoot']='data/station-english-sources/kr'
    elif (PACKET/f).is_file():r['rawRoot']='data/station-english-sources/next-official/kr-operators-second-pass'
    elif (ROOT/'kr-operators'/f).is_file():r['rawRoot']='data/station-english-sources/next-official/kr-operators'
  return r
 if isinstance(v,str) and v.startswith(str(app)):return Path(v).relative_to(app).as_posix()
 return v
def regenerate(run_regressions=False):
 for name,h in load(PACKET/'retained-input-manifest.json')['files'].items():
  if sha(PACKET/name)!=h:raise ValueError('retained raw/review/algorithm hash mismatch: '+name)
 package=load(APP/'public/rail/kr-2025.json');features=load(APP/'data/stations-kr.json')
 with tempfile.TemporaryDirectory(prefix='jtm-kr-second-')as tmp:
  app=(Path(tmp)/'repo/app').resolve();root=app/'data/station-english-sources/next-official';root.mkdir(parents=True)
  for name in ('kr-operators','kr-operators-second-pass'):shutil.copytree(ROOT/name,root/name)
  (root/'reviewed-scope').mkdir()
  shutil.copy2(PACKET/'reviewed-scope.json',root/'reviewed-scope/integrated-coverage.json')
  shutil.copytree(APP/'data/station-english-sources/kr',app/'data/station-english-sources/kr')
  for rel in ('scripts/railway/verify-kr-station-english.py','public/rail/kr-2025.json','data/stations-kr.json'):
   p=app/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(APP/rel,p)
  second=root/'kr-operators-second-pass';first=root/'kr-operators'
  def run(p):
   proc=subprocess.run([sys.executable,str(p)],cwd=p.parent,text=True,capture_output=True,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
   if proc.returncode:raise ValueError(p.name+' failed:\n'+proc.stderr[-4000:])
  run(first/'verify_tail.py');baseline=(first/'station-english-evidence-delta.json').read_bytes()
  (first/'artifact-hashes.json').write_text(text({'station-english-evidence-delta.json':sha(first/'station-english-evidence-delta.json')}))
  if run_regressions:run(second/'test_delta.py')
  run(second/'verify_delta.py');result=portable(load(second/'station-english-evidence-delta.json'),app)
 validate(result,package,features)
 result['previousDeltaRawFile']=BASELINE.name;result['previousDeltaRawRoot']='data';result['checkpointRawFile']='reviewed-scope.json';result['checkpointRawRoot']='data/station-english-sources/next-official/kr-operators-second-pass'
 return result,baseline
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--check',action='store_true');ap.add_argument('--regressions',action='store_true');args=ap.parse_args();result,baseline=regenerate(args.regressions)
 review={'schema':'station-english-source-review/1','countries':['kr'],'coverage':result['coverage'],'unresolved':result['unresolved']}
 result={**result,'unresolved':[],'coverage':{'verifiedMemberships':11,'groupsWithVerifiedMembership':11,'unresolvedMemberships':0},'sourceReviewRawFile':REVIEW.name,'sourceReviewRawRoot':'data'}
 if args.check:
  if not OUTPUT.is_file() or OUTPUT.read_text()!=text(result) or not BASELINE.is_file() or BASELINE.read_bytes()!=baseline or not REVIEW.is_file() or REVIEW.read_text()!=text(review):raise SystemExit('KR second-pass evidence/baseline is stale or absent')
 else:
  OUTPUT.parent.mkdir(parents=True,exist_ok=True);OUTPUT.write_text(text(result));BASELINE.write_bytes(baseline);REVIEW.write_text(text(review))
 print(json.dumps(result['coverage']))
if __name__=='__main__':main()
