#!/usr/bin/env python3
"""Reviewed 2013 JR Central summer endpoints; never infer full stops or routes."""
from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SOURCE = 'jr-central-summer-20130517'

def days(month, *values):
    result = []
    for value in values:
        bounds = value if isinstance(value, tuple) else (value, value)
        result.extend(f'2013-{month:02}-{d:02}' for d in range(bounds[0], bounds[1]+1))
    return result

SHINANO_81 = days(7,13,15,20,21,27,28)+days(8,(2,4),(9,18),24,25)
SHINANO_84 = days(9,14,16,21,23)
SHINANO_85 = days(7,13,15,20,21,27,28)+days(8,(1,5),(9,18),24,25)
SHINANO_82 = days(9,14,16,21,23)
ROWS = [
 ('shinano','しなの','81','名古屋','08:28','白馬','12:02',SHINANO_81,3),
 ('shinano','しなの','84','白馬','14:53','名古屋','18:48',SHINANO_84,3),
 ('shinano','しなの','85','名古屋','10:29','松本','12:54',SHINANO_85,3),
 ('shinano','しなの','82','松本','15:00','名古屋','17:25',SHINANO_82,3),
 ('hida','ひだ','81','名古屋','10:18','高山','12:56',days(7,13)+days(8,(10,14))+days(9,14,15,21,22),3),
 ('hida','ひだ','82','高山','17:39','名古屋','20:02',days(7,13,15)+days(8,(10,16))+days(9,(14,16),(21,23)),3),
 ('hida','ひだ','83','名古屋','13:39','高山','16:14',days(7,15)+days(8,15,16)+days(9,16,23),3),
 ('hida','ひだ','61','名古屋','06:16','高山','09:10',days(7,6)+days(8,3)+days(9,7),3),
 ('nanki','南紀','81','名古屋','08:51','紀伊勝浦','12:48',days(7,13)+days(8,(9,18))+days(9,14,21),4),
 ('nanki','南紀','82','紀伊勝浦','13:41','名古屋','17:44',days(8,(9,18)),4),
 ('nanki','南紀','83','名古屋','16:42','紀伊勝浦','20:30',days(7,14,15,20,21,27,28)+days(8,(3,18),24,25)+days(9,15,16,22,23),4),
 ('nanki','南紀','84','紀伊勝浦','14:27','名古屋','18:26',days(7,(13,15),20,21,27,28)+days(8,(3,16),24,25)+days(9,(14,16),(21,23)),4),
]
OVERRIDE_DATES = days(8,2,9,(12,16))


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(r,ensure_ascii=False,sort_keys=True)+'\n' for r in rows))


def main():
    data = defaultdict(list)
    as_of = json.loads((BASE/'manifest.json').read_text())['as_of_date']
    package = json.loads((ROOT/'app/public/rail/jp-2025.json').read_text())
    existing_stations = {r['station_id'] for p in (BASE/'normalized').glob('station-identities*.jsonl')
                         if p.name != 'station-identities-central-2013.jsonl'
                         for line in p.read_text().splitlines() if line for r in [json.loads(line)]}
    existing_services = {r['service_id'] for p in (BASE/'normalized').glob('services*.jsonl')
                         if p.name != 'services-central-2013.jsonl'
                         for line in p.read_text().splitlines() if line for r in [json.loads(line)]}
    stations = {}
    for name, op in [('名古屋','東海旅客鉄道'),('白馬','東日本旅客鉄道'),('松本','東日本旅客鉄道'),
                     ('高山','東海旅客鉄道'),('紀伊勝浦','西日本旅客鉄道')]:
        codes={s[0] for l in package['lines'] if l['operator']==op for s in l['stations'] if s[1]==name}
        if len(codes)!=1: raise ValueError(f'Ambiguous current lookup {name}: {codes}')
        code=codes.pop(); stations[name]='jp.n02.'+code
        if stations[name] not in existing_stations:
            data['station-identities'].append(dict(station_id=stations[name],name_snapshot=name,
                reference_kind='current_n02',current_source_code=code))
    for service in ['hida','nanki']:
        selected=[r for r in ROWS if r[0]==service]
        dates=sorted(d for r in selected for d in r[7] if d<=as_of)
        if service not in existing_services:
            data['services'].append(dict(service_id=service,canonical_name=selected[0][1],service_class='limited_express',
                historical_generation=1,jr_scope='through_jr' if service=='nanki' else 'jr',
                first_verified_date=dates[0],last_verified_date=dates[-1]))
    for service, name in [('shinano','しなの'),('hida','ひだ'),('nanki','南紀')]:
        data['service-name-periods'].append(dict(service_id=service,name=name,language='ja',
            valid_from='2013-07-01',valid_until='2013-10-01',name_type='display',source_id=SOURCE))
        data['service-name-periods'].append(dict(service_id=service,name='ワイドビュー'+name,language='ja',
            valid_from='2013-07-01',valid_until='2013-10-01',name_type='branding',source_id=SOURCE))
    for service,name,number,origin,dep,destination,arr,operating,page in ROWS:
        operating=sorted(d for d in operating if d<=as_of)
        if not operating: continue
        trip=f'jr-central.{service}.{number}.2013-summer';cal=trip+'.calendar';version=trip+'.version'
        start=operating[0];until=(date.fromisoformat(operating[-1])+timedelta(days=1)).isoformat()
        data['timetable-versions'].append(dict(timetable_version_id=version,operator_scope='jr-central',
            effective_from=start,effective_until=until,publication_date='2013-05-17',
            edition_name='2013 summer planned temporary endpoints',revision_type='planned_exception',completeness='partial',source_ids=[SOURCE]))
        data['calendars'].append(dict(calendar_id=cal,valid_from=start,valid_until=until,holiday_policy='none',
            **{d:0 for d in ['monday','tuesday','wednesday','thursday','friday','saturday','sunday']}))
        data['calendar-exceptions'].extend(dict(calendar_id=cal,service_date=d,exception_type='add',
            reason='Dates explicitly listed in the announcement; no weekday inference',source_id=SOURCE) for d in operating)
        data['trips'].append(dict(trip_id=trip,service_id=service,timetable_version_id=version,calendar_id=cal,
            public_number=number,train_number=None,origin_station_id=stations[origin],destination_station_id=stations[destination],
            service_class='limited_express',notes='Published planned endpoint schedule only. Current directory lookup is not proof of 2013 station identity; intermediate calls and physical route unverified.'))
        data['stop-times'].extend([
            dict(trip_id=trip,stop_sequence=1,station_id=stations[origin],departure_time=dep,call_type='origin',pickup_allowed=1,dropoff_allowed=0,time_accuracy='minute',source_id=SOURCE),
            dict(trip_id=trip,stop_sequence=2,station_id=stations[destination],arrival_time=arr,call_type='destination',pickup_allowed=0,dropoff_allowed=1,time_accuracy='minute',source_id=SOURCE)])
        if service=='shinano' and number=='81':
            data['trip-stop-time-overrides'].extend(dict(trip_id=trip,service_date=d,stop_sequence=1,
                departure_override='08:25',source_id=SOURCE) for d in OVERRIDE_DATES if d in operating)
        for dimension in ['identity','train_number','operator','validity_calendar','origin_destination','stops','times','route_lines','station_refs','provenance']:
            status='verified' if dimension in ['identity','validity_calendar','origin_destination'] else 'unknown' if dimension in ['train_number','operator','route_lines'] else 'partial'
            data['fact-completeness'].append(dict(entity_type='trip',entity_id=trip,dimension=dimension,status=status,
                confidence='high' if status=='verified' else 'low',notes='Current station source codes do not verify 2013 identity or route. Only announced endpoint times and explicit dates are transcribed.'))
            if status!='unknown':
                data['fact-sources'].append(dict(entity_type='trip',entity_id=trip,field_name=dimension,
                    source_id='jtm-current-station-directory' if dimension=='station_refs' else SOURCE,
                    page_or_locator='Current lookup only; historical correspondence unverified' if dimension=='station_refs' else f'PDF physical page {page}; table and Shinano 81 departure footnote',
                    confidence='high' if status=='verified' else 'low',verification_status=status))
            if status!='verified':
                data['research-queue'].append(dict(research_id=trip+'.'+dimension,entity_type='trip',entity_id=trip,
                    missing_dimension=dimension,status='open',notes='Obtain full dated 2013 timetable, operator boundaries and historical station/line identity.'))
    for dimension in ['inventory','train_number','calendar','stops','times','route_lines','station_refs','provenance']:
        count=0 if dimension in ['train_number','route_lines'] else 24 if dimension in ['stops','times','station_refs'] else 12
        data['coverage-declarations'].append(dict(coverage_id='jr-central.2013.'+dimension+'.summer-endpoints',operator_scope='jr-central',year=2013,
            dimension=dimension,status='partial' if count else 'missing',record_count=count,source_id=SOURCE,
            notes='12 selected temporary endpoint templates; 165 row-supported scheduled occurrences. Not the 2013 inventory or all-stop timetable.'))
    nested={'trips','stop-times','calendars','calendar-exceptions','trip-stop-time-overrides'}
    for entity,rows in data.items():
        path=BASE/f'normalized/{entity}/reviewed-central-2013/seeds.jsonl' if entity in nested else BASE/f'normalized/{entity}-central-2013.jsonl'
        write(path,rows)
    print(f"Central 2013: {len(data['trips'])} templates, {len(data['calendar-exceptions'])} occurrences, {len(data['trip-stop-time-overrides'])} overrides")

if __name__=='__main__':main()
