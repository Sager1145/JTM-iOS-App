#!/usr/bin/env python3
"""Offline regeneration from retained operator publications and reviewed transcripts.

All runtime paths derive from the app directory. Only the supplied output changes;
cohort scripts execute in a private working copy. The reviewed ledger defines the
available historical cohort, not a completeness requirement for future packages.
Requires pypdf for retained PDF text extraction. No network access is performed.
"""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile
APP = Path(__file__).resolve().parents[2]
BASE = APP / 'data/station-english-sources/next-official'
OUTPUT = APP / 'data/station-english-verified-next-official.json'
def load(path): return json.loads(path.read_text(encoding='utf-8'))
def encode(value): return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n'
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def retained():
    manifest=load(BASE/'retained-input-manifest.json')
    for name, sha in manifest['files'].items():
        p=BASE/name
        if not p.is_file() or digest(p)!=sha: raise ValueError('retained source/review/algorithm hash mismatch: '+name)
    registered=load(BASE/'cohorts.json')
    if set(registered)!=set(EXPECTED_COHORTS): raise ValueError('unknown/missing cohort registration')
    if any(registered[k]!=EXPECTED_COHORTS[k] for k in registered): raise ValueError('wrong cohort verifier registration')
    return registered
EXPECTED_COHORTS={'tobu':'build_and_validate.py','nagoya-sapporo':'build_and_validate.py','keio-odakyu':'build_and_validate.py','hanshin-sanyo-kobe':'build_and_validate.py','toyama':'verify.py','toyama-c21':'verify.py','hiroden-m18':'verify.py','hiroshima-tosaden':'verify.py','keikyu':'verify.py','korail':'verify_tail.py','kr-operators':'verify_tail.py','matsuura-kotoden':'verify_kotoden.py','nishitetsu-iyo':'verify.py'}
def validate_rows(rows, packages):
    current={}
    for country,pkg in packages.items():
        for line in pkg['lines']:
            for s in line['stations']:
                key=country+':'+line['id']+':'+s[0]
                if key in current: raise ValueError('duplicate current membership: '+key)
                current[key]=(line['operator'],s[1])
    seen=set()
    for key,row in rows.items():
        country=row['country'].lower();
        if country not in ('jp','kr'): raise ValueError('publication country outside JP/KR: '+country)
        code=row['stationCode']; identity=country+':'+row['lineId']+':'+code
        if key!=row['lineId']+':'+code or identity not in current: raise ValueError('unknown/miskeyed evidence membership: '+key)
        if identity in seen: raise ValueError('duplicate evidence membership: '+identity)
        seen.add(identity)
        if current[identity]!=(row['operator'],row['name']): raise ValueError('current operator/native identity mismatch: '+identity)
        if not row.get('en') or not row.get('identityEvidence'): raise ValueError('missing source English/identity proof: '+identity)
def regenerate():
    cohorts=retained(); scope=load(BASE/'package-scope.json')
    packages={c:load(APP/f'public/rail/{c}-2025.json') for c in ('jp','kr')}
    by={};sources=[];unresolved=[];counts={}
    with tempfile.TemporaryDirectory(prefix='jtm-official-source-') as tmp:
        app=(Path(tmp)/'repo/app').resolve(); base=app/'data/station-english-sources/next-official'
        shutil.copytree(BASE,base)
        (app/'scripts/railway').mkdir(parents=True)
        shutil.copy2(APP/'scripts/railway/verify-kr-station-english.py',app/'scripts/railway/verify-kr-station-english.py')
        shutil.copytree(APP/'data/station-english-sources/kr',app/'data/station-english-sources/kr')
        for c,pkg in packages.items():
            # Project only pre-reviewed memberships; new ones receive no evidence.
            projected={**pkg,'lines':[]}
            for l in pkg['lines']:
                old=scope[c].get(l['id'])
                if old is None: continue
                codes={s[0] for s in old['stations']}
                projected['lines'].append({**l,'stations':[s for s in l['stations'] if s[0] in codes]})
            p=app/f'public/rail/{c}-2025.json';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(encode(projected))
            if c == 'kr': shutil.copy2(APP/f'data/stations-{c}.json',app/f'data/stations-{c}.json')
        for cohort,script in cohorts.items():
            folder=base/cohort
            proc=subprocess.run([sys.executable,str(folder/script)],cwd=folder,text=True,capture_output=True,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
            if proc.returncode: raise ValueError(cohort+' source gate failed:\n'+proc.stderr[-4000:])
            evidence=[load(p) for p in folder.glob('station-english-*.json')]
            evidence=[e for e in evidence if e.get('schema')=='station-english-evidence/1']
            if len(evidence)!=1: raise ValueError(cohort+' missing/duplicate generated evidence output')
            e=evidence[0];counts[cohort]=len(e['byLineStation'])
            for key,row in e['byLineStation'].items():
                if key in by: raise ValueError('duplicate cohort evidence: '+key)
                by[key]=portable(row,app,cohort)
            sources += [portable(s,app,cohort) for s in e.get('sources',[])]
            unresolved += [portable(r,app,cohort) for r in e.get('unresolved',[])]
    validate_rows(by,packages)
    unresolved=[r for r in unresolved if r.get('lineId','')+':'+r.get('stationCode',r.get('groupCode',r.get('group',''))) not in by]
    return {'schema':'station-english-evidence/1','countries':['jp','kr'],'byLineStation':dict(sorted(by.items())),'sources':sources,'unresolved':unresolved,'coverage':{'verifiedMemberships':len(by),'verifiedStationGroups':len({(r['country'].lower(),r['stationCode']) for r in by.values()}),'byCohort':counts},'method':'Regenerated offline from retained raw operator publications and immutable manually reviewed transcripts; exact operator/physical-line/group/native identities and source coordinate constraints retained. New memberships outside reviewed scope remain pending.'}
def portable(value,app,cohort):
    if isinstance(value,list): return [portable(v,app,cohort) for v in value]
    if isinstance(value,dict):
        result={k:portable(v,app,cohort) for k,v in value.items()}
        if 'rawFile' in result and 'rawRoot' not in result: result['rawRoot']='data/station-english-sources/next-official/'+cohort
        # KR shared source rows publish their canonical app-relative retained paths.
        for k in ('rawFile','file'):
            if k in result and isinstance(result[k],str):
                f=result[k]
                if (APP/'data/station-english-sources/kr'/f).is_file():result['rawRoot']='data/station-english-sources/kr'
        return result
    if isinstance(value,str) and value.startswith(str(app)):
        return Path(value).relative_to(app).as_posix()
    return value
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');parser.add_argument('--output',type=Path,default=OUTPUT);args=parser.parse_args()
    result=regenerate();text=encode(result)
    if args.check:
        if not args.output.is_file() or args.output.read_text()!=text:raise SystemExit('next-official evidence is stale or absent')
    else:
        args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(text)
    print(json.dumps(result['coverage'],ensure_ascii=False))
if __name__=='__main__':main()
