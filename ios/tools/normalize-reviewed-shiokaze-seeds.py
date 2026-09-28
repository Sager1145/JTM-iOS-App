#!/usr/bin/env python3
"""Normalize visually reviewed endpoint facts; not a complete Shiokaze timetable."""
from collections import defaultdict
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'
SOURCE = 'jr-shikoku-west-shiokaze-obon-20260624'
DATES = ['2026-08-08', '2026-08-09', '2026-08-15', '2026-08-16']
# Page 2, both merged target-period cells apply to all twelve rows per direction.
DOWN = [('5','09:25','12:10'),('7','10:35','13:16'),('9','11:35','14:13'),
        ('11','12:35','15:17'),('13','13:35','16:16'),('15','14:35','17:24'),
        ('17','15:35','18:26'),('19','16:35','19:23'),('21','17:35','20:28'),
        ('23','18:35','21:34'),('25','19:35','22:35'),('27','20:39','23:34')]
UP = [('6','06:13','09:00'),('8','07:20','10:00'),('10','08:10','10:58'),
      ('12','09:15','12:11'),('14','10:21','13:11'),('16','11:23','14:11'),
      ('18','12:21','15:11'),('20','13:26','16:11'),('22','14:23','17:11'),
      ('24','15:28','18:11'),('26','16:27','19:11'),('28','17:37','20:12')]


def main():
    data = defaultdict(list)
    package = json.loads((ROOT / 'app/public/rail/jp-2025.json').read_text())
    station_ids = {}
    for name, operator in [('岡山','西日本旅客鉄道'),('松山','四国旅客鉄道')]:
        codes = {s[0] for line in package['lines'] if line['operator'] == operator
                 for s in line['stations'] if s[1] == name}
        if len(codes) != 1:
            raise ValueError(f'Ambiguous endpoint: {name}: {codes}')
        code = codes.pop()
        station_ids[name] = 'jp.n02.' + code
        data['station-identities'].append(dict(station_id=station_ids[name], name_snapshot=name,
            reference_kind='current_n02', current_source_code=code))
    data['services'].append(dict(service_id='shiokaze',canonical_name='しおかぜ',
        service_class='limited_express',historical_generation=1,jr_scope='through_jr',
        first_verified_date=DATES[0],last_verified_date=DATES[-1]))
    data['service-name-periods'].append(dict(service_id='shiokaze',name='しおかぜ',language='ja',
        valid_from=DATES[0],valid_until='2026-08-17',name_type='canonical',source_id=SOURCE))
    for direction, rows, origin, destination in [('down',DOWN,'岡山','松山'),('up',UP,'松山','岡山')]:
        for number, departure, arrival in rows:
            trip = f'jr-shikoku.shiokaze.{number}.2026-08-08'
            calendar = trip + '.calendar'
            version = trip + '.version'
            data['timetable-versions'].append(dict(timetable_version_id=version,operator_scope='jr-shikoku',
                effective_from=DATES[0],effective_until='2026-08-17',publication_date='2026-06-24',
                edition_name='Four explicitly announced Obon dates; endpoints only',
                revision_type='planned_exception',completeness='partial',source_ids=[SOURCE]))
            data['calendars'].append(dict(calendar_id=calendar,valid_from=DATES[0],valid_until='2026-08-17',
                holiday_policy='none',**{d:0 for d in ['monday','tuesday','wednesday','thursday','friday','saturday','sunday']}))
            data['calendar-exceptions'].extend(dict(calendar_id=calendar,service_date=day,
                exception_type='add',source_id=SOURCE,reason='Four dates explicitly stated on PDF pages 1 and 2') for day in DATES)
            data['trips'].append(dict(trip_id=trip,service_id='shiokaze',timetable_version_id=version,
                calendar_id=calendar,public_number=number,train_number=None,direction=direction,
                origin_station_id=station_ids[origin],destination_station_id=station_ids[destination],
                service_class='limited_express',notes='Endpoint-only announcement. Intermediate passenger calls, internal number and operator boundaries are not recorded.'))
            data['stop-times'].extend([
                dict(trip_id=trip,stop_sequence=1,station_id=station_ids[origin],departure_time=departure,
                     call_type='origin',pickup_allowed=1,dropoff_allowed=0,time_accuracy='minute',source_id=SOURCE),
                dict(trip_id=trip,stop_sequence=2,station_id=station_ids[destination],arrival_time=arrival,
                     call_type='destination',pickup_allowed=0,dropoff_allowed=1,time_accuracy='minute',source_id=SOURCE)])
            for dimension in ['identity','train_number','operator','validity_calendar','origin_destination',
                              'stops','times','route_lines','station_refs','provenance']:
                status = 'verified' if dimension in ['identity','validity_calendar','origin_destination','station_refs'] else 'partial' if dimension in ['stops','times','provenance'] else 'unknown'
                data['fact-completeness'].append(dict(entity_type='trip',entity_id=trip,dimension=dimension,
                    status=status,confidence='high' if status=='verified' else 'low',
                    notes='The announcement is not an all-stop timetable.'))
                if status == 'verified':
                    data['fact-sources'].append(dict(entity_type='trip',entity_id=trip,field_name=dimension,
                        source_id='jtm-current-station-directory' if dimension=='station_refs' else SOURCE,
                        page_or_locator='Shipped current station directory' if dimension=='station_refs' else 'PDF p.2, directional table; p.1 target dates',
                        confidence='high',verification_status='verified'))
                else:
                    data['research-queue'].append(dict(research_id=trip+'.'+dimension,entity_type='trip',entity_id=trip,
                        missing_dimension=dimension,status='open',notes='Obtain full original dated timetable and explicit operator/route evidence.'))
    for dimension in ['inventory','train_number','calendar','stops','times','route_lines','station_refs','provenance']:
        count = 0 if dimension in ['train_number','route_lines'] else 48 if dimension in ['stops','times','station_refs'] else 24
        data['coverage-declarations'].append(dict(
            coverage_id='jr-shikoku.2026.'+dimension+'.obon-endpoints',operator_scope='jr-shikoku',
            year=2026,dimension=dimension,status='partial' if count else 'missing',record_count=count,
            source_id=SOURCE,notes='24 endpoint-only templates for four announced dates; not a full-year inventory.'))
    for entity, rows in data.items():
        folder = 'normalized/' + entity + '/reviewed-shiokaze' if entity in ['trips','stop-times','calendars','calendar-exceptions'] else 'normalized'
        filename = 'seeds.jsonl' if folder.endswith('reviewed-shiokaze') else entity+'-shiokaze.jsonl'
        path = BASE / folder / filename
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(''.join(json.dumps(row,ensure_ascii=False,sort_keys=True)+'\n' for row in rows))
    print('Normalized 24 endpoint-only Shiokaze trips, 96 explicitly announced occurrences; full stops remain partial.')


if __name__ == '__main__':
    main()
