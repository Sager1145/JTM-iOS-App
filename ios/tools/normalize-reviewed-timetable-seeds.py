#!/usr/bin/env python3
"""Promote explicitly reviewed small source candidates; never infer missing times/routes.

These records are partial evidence seeds, not an inventory baseline. The review
contract deliberately limits JR East HTML evidence to its displayed dates up to
AS_OF_DATE and leaves operator/route provenance unresolved.
"""
from datetime import date, timedelta
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
AS_OF = json.loads((BASE / 'manifest.json').read_text())['as_of_date']
ACCESSED_AT = '2026-09-27T19:36:14Z'


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(r, ensure_ascii=False, sort_keys=True)+'\n' for r in rows))


def main():
    entities = {k: [] for k in ['services', 'service-name-periods', 'timetable-versions',
                'station-identities', 'fact-sources', 'fact-completeness', 'research-queue']}
    trips, stops, calendars, exceptions, registry = [], [], [], [], []
    stations = {}
    package = json.loads((ROOT / 'app/public/rail/jp-2025.json').read_text())
    registry.append(dict(source_id='jtm-current-station-directory', publisher='JTM / MLIT N02',
        title='Shipped JP compact station directory', source_type='station_identity_directory',
        url_or_locator='app/public/rail/jp-2025.json', accessed_at=ACCESSED_AT,
        license_status='repository_source_terms', redistribution_status='existing_repository_resource',
        automated_extraction_allowed=True, notes='Attests current sourceCode only; not historical station validity or train routing.'))

    def add_trip(service, name, scope, number, internal, days, rows, source):
        days = sorted(d for d in days if d <= AS_OF)
        start, until = days[0], (date.fromisoformat(days[-1])+timedelta(days=1)).isoformat()
        trip_id = f'{scope}.{service}.{number}.{start}'
        version = trip_id + '.version'
        calendar = trip_id + '.calendar'
        entities['services'].append(dict(service_id=service, canonical_name=name,
            service_class='limited_express', historical_generation=1, first_verified_date=start,
            last_verified_date=days[-1], jr_scope='jr'))
        entities['service-name-periods'].append(dict(service_id=service, name=name, language='ja',
            valid_from=start, valid_until=until, name_type='display', source_id=source))
        entities['timetable-versions'].append(dict(timetable_version_id=version, operator_scope=scope,
            effective_from=start, effective_until=until, edition_name='Published source evidence window',
            revision_type='source_snapshot', completeness='partial', source_ids=[source]))
        calendars.append(dict(calendar_id=calendar, valid_from=start, valid_until=until,
            holiday_policy='none', **{d: 0 for d in ['monday','tuesday','wednesday','thursday','friday','saturday','sunday']}))
        exceptions.extend(dict(calendar_id=calendar, service_date=d, exception_type='add',
            reason='Explicit source operating date', source_id=source) for d in days)
        for row in rows:
            stations[row['station_id']] = row.pop('_station')
            stops.append(dict(trip_id=trip_id, day_offset=0, pickup_allowed=int(row['call_type'] != 'destination'),
                dropoff_allowed=int(row['call_type'] != 'origin'), time_accuracy='minute', source_id=source, **row))
        trips.append(dict(trip_id=trip_id, timetable_version_id=version, service_id=service,
            calendar_id=calendar, train_number=internal, public_number=number,
            origin_station_id=rows[0]['station_id'], destination_station_id=rows[-1]['station_id'],
            service_class='limited_express', notes='Partial seed: operator segments and route lines require independent source review.'))
        for dimension in ['identity','train_number','operator','validity_calendar','origin_destination','stops','times','route_lines','station_refs','provenance']:
            status = ('unknown' if dimension in ['operator','route_lines'] or dimension == 'train_number' and internal is None
                      else 'partial' if dimension == 'times' and scope in ['jr-hokkaido','jr-kyushu'] or dimension == 'provenance'
                      else 'verified')
            entities['fact-completeness'].append(dict(entity_type='trip', entity_id=trip_id,
                dimension=dimension, status=status, confidence='high' if status=='verified' else 'low'))
            if status == 'verified':
                entities['fact-sources'].append(dict(entity_type='trip', entity_id=trip_id,
                    field_name=dimension, source_id='jtm-current-station-directory' if dimension=='station_refs' else source,
                    page_or_locator='Shipped station directory' if dimension=='station_refs' else 'Published train table and calendar',
                    confidence='high', verification_status=status))
            else:
                entities['research-queue'].append(dict(research_id=trip_id+'.'+dimension, entity_type='trip',
                    entity_id=trip_id, missing_dimension=dimension, status='open',
                    notes='Require evidence; not filled from legacy patterns or present-day route connectivity.'))

    h = json.loads((BASE / 'candidates/jr-hokkaido-20260403-special.json').read_text())
    source = dict(h['source'], automated_extraction_allowed=False, accessed_at=ACCESSED_AT)
    registry.append(source)
    hstations = {s['station_id']: s for s in h['stations']}
    for t in h['trips']:
        rows = [dict(s, _station=hstations[s['station_id']]) for s in t['stop_times']]
        add_trip(t['service_id'], 'カムイ' if t['service_id']=='kamui' else 'ライラック', 'jr-hokkaido',
                 t['public_number'], None, t['operating_dates'], rows, source['source_id'])
    for filename, service, name, scope in [
        ('jr-central-shinano1-202609','shinano','しなの','jr-central'),
        ('jr-east-hitachi26-202609','hitachi','ひたち','jr-east')]:
        v = json.loads((BASE / ('candidates/'+filename+'.json')).read_text())
        sid = filename
        registry.append(dict(source_id=sid, publisher='東日本旅客鉄道 / 交通新聞社',
            title=v['public_name']+' 停車駅一覧', source_type='official_train_timetable',
            url_or_locator=v['source_url'], issue='JR時刻表2026年10月号', accessed_at=ACCESSED_AT,
            license_status='unknown', redistribution_status='unknown', automated_extraction_allowed=False,
            notes='Public timetable reviewed; redistribution authorization unresolved. Raw page not bundled.'))
        rows=[]
        for row in v['stop_times']:
            names = row['name_snapshot']
            codes={s[0] for l in package['lines'] for s in l['stations'] if s[1]==names
                   and l['operator'] in ['東海旅客鉄道','東日本旅客鉄道']}
            # Main Tokyo station group, not the distinct Keiyo platform family.
            if names == '東京': codes={'003766'}
            if len(codes) != 1: raise ValueError(f'Ambiguous station {names}: {codes}')
            code=next(iter(codes)); station_id='jp.n02.'+code
            station=dict(station_id=station_id, name_snapshot=names, reference_kind='current_n02',
                         current_source_code=code, rail_history_id=None)
            rows.append(dict(stop_sequence=row['stop_sequence'], station_id=station_id,
                arrival_time=row['arrival_time'], departure_time=row['departure_time'],
                call_type=row['call_type'], platform=row.get('platform'), _station=station))
        number=v['public_name'].split()[-1].removesuffix('号')
        add_trip(service,name,scope,number,v['train_number'],v['operating_dates'],rows,sid)
    yufuin = BASE / 'sources/candidates/jr-kyushu-yufuin-no-mori-20260314.json'
    if yufuin.exists():
        v=json.loads(yufuin.read_text())
        plan_source='jr-kyushu-yufuin-plan-20260919'
        registry.append(dict(source_id=plan_source,publisher='九州旅客鉄道株式会社',
            title='ゆふいんの森・ゆふ 9月19日〜30日の運行計画',
            source_type='official_planned_exception',url_or_locator='https://www.jrkyushu.co.jp/railway/index.html',
            accessed_at=ACCESSED_AT,effective_date='2026-09-19',license_status='unknown',
            redistribution_status='unknown',automated_extraction_allowed=False,
            notes='Explicitly states all Yufuin-no-Mori numbers 1–6 normally operate September 19–30. Snapshot capped at AS_OF_DATE.'))
        for t in v['trips']:
            rows=[]
            for i,(station_id,name,arrival,departure,call_type) in enumerate(t['displayed_times']):
                code=station_id.removeprefix('jp.n02.')
                if not any(s[0]==code and s[1]==name for l in package['lines'] for s in l['stations']):
                    raise ValueError(f'Unresolved Kyushu source station {name}/{code}')
                rows.append(dict(stop_sequence=i+1,station_id=station_id,arrival_time=arrival,
                    departure_time=departure,call_type=call_type,_station=dict(station_id=station_id,
                    name_snapshot=name,reference_kind='current_n02',current_source_code=code,rail_history_id=None)))
            add_trip('yufuin-no-mori','ゆふいんの森','jr-kyushu',t['public_number'],None,
                     [f'2026-09-{d:02}' for d in range(19,31)],rows,v['source_id'])
            trip_id=trips[-1]['trip_id']
            # Published stop times and the date-specific later plan have separate provenance.
            entities['timetable-versions'][-1]['source_ids'].append(plan_source)
            for fact in entities['fact-sources']:
                if fact['entity_id']==trip_id and fact['field_name']=='validity_calendar': fact['source_id']=plan_source
            for exception in exceptions:
                if exception['calendar_id']==trips[-1]['calendar_id']: exception['source_id']=plan_source
    entities['station-identities'] = sorted(stations.values(),key=lambda x:x['station_id'])
    for name, rows in entities.items():
        # Six numbered templates share one service identity and one dated name.
        unique={json.dumps(r,ensure_ascii=False,sort_keys=True):r for r in rows}
        write(BASE / f'normalized/{name}-root.jsonl',list(unique.values()))
    write(BASE / 'normalized/trips/reviewed-root/seeds.jsonl',trips)
    write(BASE / 'normalized/stop-times/reviewed-root/seeds.jsonl',stops)
    write(BASE / 'normalized/calendars/reviewed-root/seeds.jsonl',calendars)
    write(BASE / 'normalized/calendar-exceptions/reviewed-root/seeds.jsonl',exceptions)
    write(BASE / 'sources/source-registry-root.jsonl',registry)
    by_scope={}
    for trip in trips:
        scope=trip['trip_id'].split('.')[0]
        by_scope.setdefault(scope,[]).append(trip)
    coverage=[]
    for scope, scoped_trips in sorted(by_scope.items()):
        scoped_ids={t['trip_id'] for t in scoped_trips}
        scoped_stops=[s for s in stops if s['trip_id'] in scoped_ids]
        for dimension in ['inventory','train_number','calendar','stops','times','route_lines','station_refs','provenance']:
            count=(sum(bool(t.get('train_number')) for t in scoped_trips) if dimension=='train_number'
                   else 0 if dimension=='route_lines' else len(scoped_stops) if dimension in ['stops','times','station_refs']
                   else len(scoped_trips))
            coverage.append(dict(coverage_id=f'{scope}.2026.{dimension}.seed',operator_scope=scope,year=2026,
                dimension=dimension,status='partial' if count else 'missing',record_count=count,
                source_id=next(s['source_id'] for s in scoped_stops),
                notes='Only selected source/date windows; company-wide inventory denominator and full-year coverage are unknown.'))
    write(BASE / 'normalized/coverage-declarations-root.jsonl',coverage)
    print(f'Promoted {len(trips)} partial trips; {len(stops)} stops; {len(exceptions)} explicit occurrences')


if __name__ == '__main__': main()
