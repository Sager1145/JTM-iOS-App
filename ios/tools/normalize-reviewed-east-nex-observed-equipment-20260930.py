#!/usr/bin/env python3
"""Stage only directly printed equipment; audit all observed NEX candidate calls."""
import json
from pathlib import Path
import train_timetable as timetable
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'app/data/train-service-history'
SUFFIX='reviewed-east-nex-observed-equipment-20260930'
CANDIDATE=BASE/'candidates/jr-east-nex-observed-equipment-20260930.json'

def write(path,rows):
 path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(''.join(json.dumps(x,ensure_ascii=False,sort_keys=True)+'\n' for x in rows))

def audit(data,c):
 trips={t['trip_id']:t for t in data['trips']}
 names={s['station_id']:s['name_snapshot'] for s in data['station_identities']}
 stops={};segments={}
 for s in data['stop_times']:stops.setdefault(s['trip_id'],[]).append(s)
 for s in data['trip_number_segments']:segments.setdefault(s['trip_id'],[]).append(s)
 mismatch=[];counts=dict(public_numbers=0,trips=0,stop_rows=0,printed_platforms=0,number_segments=0)
 for evidence in c['page_evidence']:
  n=evidence['public_number'];candidate=json.loads((BASE/f'candidates/jr-east-narita-express{n}-20260930.json').read_text());counts['public_numbers']+=1
  for t in candidate.get('trips',[candidate]):
   tid=t['trip_id'];counts['trips']+=1
   if trips[tid]['train_number']!=t['train_number']:mismatch.append([tid,'train_number'])
   actual=sorted(stops[tid],key=lambda s:s['stop_sequence'])
   if len(actual)!=len(t['stops']):mismatch.append([tid,'row_count'])
   for sequence,(printed,s) in enumerate(zip(t['stops'],actual),1):
    name,a,d=printed[:3];platform=printed[3] if len(printed)==5 else candidate['printed_platforms'].get(name)
    call=printed[4] if len(printed)==5 else ('origin' if sequence==1 else 'destination' if sequence==len(actual) else 'passenger_stop')
    expected=({'空港第２ビル':'空港第2ビル'}.get(name,name),a,d,platform,call,sequence)
    observed=(names[s['station_id']],s['arrival_time'],s['departure_time'],s.get('platform'),s['call_type'],s['stop_sequence'])
    if observed!=expected:mismatch.append([tid,sequence,expected,observed])
    counts['stop_rows']+=1;counts['printed_platforms']+=int(platform is not None)
   expected_segments=t.get('train_number_segments',[])
   actual_segments=[{k:v for k,v in s.items() if k!='trip_id'} for s in segments.get(tid,[])]
   if sorted(actual_segments,key=lambda s:s['from_sequence'])!=expected_segments:mismatch.append([tid,'number_segments',expected_segments,actual_segments])
   counts['number_segments']+=len(expected_segments)
 return dict(scope='All 54 observed public numbers; candidate-to-normalized parity, not an independent re-observation of every clock.',counts=counts,mismatches=mismatch)

def main():
 c=json.loads(CANDIDATE.read_text());data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE))
 result=audit(data,c)
 if result['mismatches']:raise ValueError(result)
 assert result['counts']['public_numbers']==54 and result['counts']['trips']==84
 sources={s['source_id']:s for s in data['source_documents']}
 facts=[];completeness=[]
 for e in c['page_evidence']:
  assert e['date_evidence']=={'month':'2026年9月','day':30,'cell_class':'ok'}
  assert sources[e['source_id']]['url_or_locator']==e['source_url']
  assert all('普通車全車指定席' in col and 'グリーン車指定席' in col for col in e['equipment_columns'])
 assert len(c['formations'])==82
 for f in c['formations']:
  assert f['evidence_kind']=='planned' and f['all_reserved'] is True and f['green_car_available'] is True
  assert all(f.get(k) is None for k in ['car_count','vehicle_series','reserved_seat_capacity'])
  for field,label in [('all_reserved','普通車全車指定席'),('green_car_available','グリーン車指定席')]:
   facts.append(dict(entity_type='trip',entity_id=f['trip_id'],field_name='formation.'+field,source_id=f['source_id'],page_or_locator='2026-09-30 td.ok; 設備: '+label,confidence='high',verification_status='verified'))
  completeness.append(dict(entity_type='trip',entity_id=f['trip_id'],dimension='formation',status='partial',confidence='high',notes='Direct planned reservation equipment; exact dated car count, vehicle assignment and actual dispatch unknown.'))
 write(BASE/f'normalized/trip-formations/{SUFFIX}/seeds.jsonl',c['formations'])
 write(BASE/f'normalized/fact-sources-{SUFFIX}.jsonl',facts)
 write(BASE/f'normalized/fact-completeness-{SUFFIX}.jsonl',completeness)
 (BASE/'audits/jr-east-nex-candidate-normalized-parity-20260930.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(result['counts']));print('82 planned reservation equipment overlays; 0 parity mismatches')
if __name__=='__main__':main()
