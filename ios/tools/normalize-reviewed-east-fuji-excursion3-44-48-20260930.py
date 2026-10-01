#!/usr/bin/env python3
"""Three official Fuji Excursion branches, preserving shared-column blanks."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/"app/data/train-service-history"
DAY,UNTIL="2026-09-30","2026-10-01"
SUFFIX="fuji-excursion3-44-48-20260930"
PINNED = [{'candidate_id': 'jr-east-fuji-excursion3-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'fuji-excursion',
  'service_name': '富士回遊',
  'jr_scope': 'through_jr',
  'public_number': '3',
  'train_number': '2103M',
  'trip_id': 'jr-east.fuji-excursion.3.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-fuji-excursion3-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/050/054761.html',
  'source_sha256': 'd9773e947cb306b624c44e719013758c9595f2baea3ec19d67608bf14c351fd1',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['千葉', None, None],
            ['船橋', None, None],
            ['錦糸町', None, None],
            ['新宿', None, None],
            ['立川', None, None],
            ['八王子', None, None],
            ['大月', None, '08:40'],
            ['都留文科大学前', '08:57', '08:57'],
            ['下吉田', '09:11', '09:13'],
            ['富士山', '09:18', '09:23'],
            ['富士急ハイランド', '09:25', '09:26'],
            ['河口湖', '09:28', None]],
  'printed_platforms': {},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '富士急行線内の特急料金は大月－富士山・河口湖間は６００円（こども４００円）です '
                     '〔富士回遊〕に富士急行線内のみご乗車の場合は、座席未指定券をご利用ください。座席の指定はできません。また、富士山－河口湖間の各駅相互間に限り、乗車券のみでご乗車になれます '
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '',
  'printed_coupling': '千葉－大月は5003Mに併結',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; retain printed '
                'train number only.',
  'actual_dispatch': None,
  'partial_timing_note': 'Only Fuji Excursion column clocks/platforms transcribed. Coupled '
                         'companion clocks/platforms not copied; blank shared section remains '
                         'null.',
  'reservation_note': 'Ordinary全車指定席 equipment label is retained; printed remark says Fujikyu-only '
                      'travel uses seat-unassigned ticket and cannot designate a seat, and 富士山–河口湖 '
                      'local journeys need only a fare ticket.',
  'coupling_relations': [{'trip_id': 'jr-east.fuji-excursion.3.exact-2026-09-30',
                          'related_trip_id': 'jr-east.azusa.3.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 1,
                          'to_sequence': 7,
                          'source_id': 'jr-east-fuji-excursion3-20260930'},
                         {'trip_id': 'jr-east.azusa.3.exact-2026-09-30',
                          'related_trip_id': 'jr-east.fuji-excursion.3.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 1,
                          'to_sequence': 7,
                          'source_id': 'jr-east-fuji-excursion3-20260930'}],
  'printed_coupled_service': 'あずさ 3号',
  'printed_coupled_number': '5003M'},
 {'candidate_id': 'jr-east-fuji-excursion44-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'fuji-excursion',
  'service_name': '富士回遊',
  'jr_scope': 'through_jr',
  'public_number': '44',
  'train_number': '2144M',
  'trip_id': 'jr-east.fuji-excursion.44.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-fuji-excursion44-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/060/063781.html',
  'source_sha256': '08e114f0f035bca147c868608964c2c5759cb06b91fdd3c051355a0cdca5dbb9',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['河口湖', None, '16:48'],
            ['富士急ハイランド', '16:51', '16:51'],
            ['富士山', '16:54', '16:56'],
            ['下吉田', '17:00', '17:01'],
            ['都留文科大学前', '17:16', '17:17'],
            ['大月', '17:35', None],
            ['八王子', None, None],
            ['立川', None, None],
            ['新宿', None, None]],
  'printed_platforms': {},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '富士急行線内の特急料金は河口湖・富士山－大月間は６００円（こども４００円）です '
                     '〔富士回遊〕に富士急行線内のみご乗車の場合は、座席未指定券をご利用ください。座席の指定はできません。また、河口湖－富士山間の各駅相互間に限り、乗車券のみでご乗車になれます '
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '',
  'printed_coupling': '大月－新宿は44Mに併結',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; retain printed '
                'train number only.',
  'actual_dispatch': None,
  'partial_timing_note': 'Only Fuji Excursion column clocks/platforms transcribed. Coupled '
                         'companion clocks/platforms not copied; blank shared section remains '
                         'null.',
  'reservation_note': 'Ordinary全車指定席 equipment label is retained; printed remark says Fujikyu-only '
                      'travel uses seat-unassigned ticket and cannot designate a seat, and 富士山–河口湖 '
                      'local journeys need only a fare ticket.',
  'coupling_relations': [{'trip_id': 'jr-east.fuji-excursion.44.exact-2026-09-30',
                          'related_trip_id': 'jr-east.azusa.44.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 6,
                          'to_sequence': 9,
                          'source_id': 'jr-east-fuji-excursion44-20260930'},
                         {'trip_id': 'jr-east.azusa.44.exact-2026-09-30',
                          'related_trip_id': 'jr-east.fuji-excursion.44.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 14,
                          'to_sequence': 17,
                          'source_id': 'jr-east-fuji-excursion44-20260930'}],
  'printed_coupled_service': 'あずさ 44号',
  'printed_coupled_number': '44M'},
 {'candidate_id': 'jr-east-fuji-excursion48-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'fuji-excursion',
  'service_name': '富士回遊',
  'jr_scope': 'through_jr',
  'public_number': '48',
  'train_number': '2148M',
  'trip_id': 'jr-east.fuji-excursion.48.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-fuji-excursion48-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/060/063471.html',
  'source_sha256': 'e4de9aba8615243e3ac96aaa1db1ac9a8d25b26c6d0dc0536ee88fed392bf8de',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['河口湖', None, '17:41'],
            ['富士急ハイランド', '17:43', '17:44'],
            ['富士山', '17:46', '17:49'],
            ['下吉田', '17:53', '17:54'],
            ['都留文科大学前', '18:10', '18:10'],
            ['大月', '18:28', None],
            ['八王子', None, None],
            ['立川', None, None],
            ['新宿', None, None]],
  'printed_platforms': {},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '富士急行線内の特急料金は河口湖・富士山－大月間は６００円（こども４００円）です '
                     '〔富士回遊〕に富士急行線内のみご乗車の場合は、座席未指定券をご利用ください。座席の指定はできません。また、河口湖－富士山間の各駅相互間に限り、乗車券のみでご乗車になれます '
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '',
  'printed_coupling': '大月－新宿は3148Mに併結',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; retain printed '
                'train number only.',
  'actual_dispatch': None,
  'partial_timing_note': 'Only Fuji Excursion column clocks/platforms transcribed. Coupled '
                         'companion clocks/platforms not copied; blank shared section remains '
                         'null.',
  'reservation_note': 'Ordinary全車指定席 equipment label is retained; printed remark says Fujikyu-only '
                      'travel uses seat-unassigned ticket and cannot designate a seat, and 富士山–河口湖 '
                      'local journeys need only a fare ticket.',
  'coupling_relations': [{'trip_id': 'jr-east.fuji-excursion.48.exact-2026-09-30',
                          'related_trip_id': 'jr-east.kaiji.48.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 6,
                          'to_sequence': 9,
                          'source_id': 'jr-east-fuji-excursion48-20260930'},
                         {'trip_id': 'jr-east.kaiji.48.exact-2026-09-30',
                          'related_trip_id': 'jr-east.fuji-excursion.48.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 5,
                          'to_sequence': 8,
                          'source_id': 'jr-east-fuji-excursion48-20260930'}],
  'printed_coupled_service': 'かいじ 48号',
  'printed_coupled_number': '3148M'}]

def write(path,rows):
 path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(''.join(json.dumps(r,ensure_ascii=False,sort_keys=True)+'\n' for r in rows))

def main():
 package=json.loads((ROOT/'app/public/rail/jp-2025.json').read_text())
 known={json.loads(line)['station_id'] for p in BASE.glob('normalized/station-identities*.jsonl') if SUFFIX not in p.name for line in p.read_text().splitlines() if line.strip()}
 for pinned in PINNED:
  c=json.loads((BASE/f"candidates/{pinned['candidate_id']}.json").read_text())
  if c!=pinned:raise ValueError('Source-pinned candidate changed')
  suffix='east-'+c['service_id']+c['public_number']+'-20260930';tid=c['trip_id'];source=c['source_id'];cid=tid+'.calendar';vid=tid+'.version';stations={}
  for name,_,_ in c['stops']:
   codes={s[0] for line in package['lines'] for s in line['stations'] if s[1]==name and line['operator'] in ['東日本旅客鉄道','東武鉄道','富士山麓電気鉄道']}
   if len(codes)!=1:raise ValueError((name,codes))
   stations[name]='jp.n02.'+next(iter(codes))
  stationrows=[dict(station_id=sid,name_snapshot=name,current_source_code=sid.removeprefix('jp.n02.'),rail_history_id=None,reference_kind='current_n02') for name,sid in stations.items() if sid not in known];known.update(stations.values())
  stops=[]
  for i,(name,a,d) in enumerate(c['stops'],1):
   call='origin' if i==1 else 'destination' if i==len(c['stops']) else 'passenger_stop'
   stops.append(dict(trip_id=tid,stop_sequence=i,station_id=stations[name],arrival_time=a,departure_time=d,day_offset=0,call_type=call,pickup_allowed=int(call!='destination'),dropoff_allowed=int(call!='origin'),platform=c['printed_platforms'].get(name),time_accuracy='minute',source_id=source))
  complete=[];facts=[];queue=[]
  for dim in ['identity','train_number','validity_calendar','origin_destination','stops','times','station_refs','formation','route_lines','operator']:
   status='unknown' if dim in ['route_lines','operator'] else 'partial' if dim=='formation' or (dim=='times' and c['service_id']=='fuji-excursion') else 'verified';note=c['route_note'] if status=='unknown' else 'Direct exact-day timetable; formation records planned printed equipment only, actual dispatch unknown.'
   if dim=='times' and c['service_id']=='fuji-excursion':note=c['partial_timing_note']
   complete.append(dict(entity_type='trip',entity_id=tid,dimension=dim,status=status,confidence='low' if status=='unknown' else 'high',notes=note))
   if status=='verified':facts.append(dict(entity_type='trip',entity_id=tid,field_name=dim,source_id='jtm-current-station-directory' if dim=='station_refs' else source,page_or_locator='app/public/rail/jp-2025.json' if dim=='station_refs' else '2026年9月30日 td.ok; 時刻詳細',confidence='high',verification_status='verified'))
   else:queue.append(dict(research_id=tid+'.'+dim,entity_type='trip',entity_id=tid,missing_dimension=dim,status='open',notes=note))
  for field in ['all_reserved','vehicle_series','green_car_available']:
   if c['formation'][field] is not None:facts.append(dict(entity_type='trip',entity_id=tid,field_name='formation.'+field,source_id=source,page_or_locator='設備: 普通車全車指定席' if field=='all_reserved' else ('備考: １００系' if field=='vehicle_series' else '設備: グリーン車指定席（４人用グリーン個室連結）'),confidence='high',verification_status='verified'))
  outputs={
   f'normalized/station-identities-{SUFFIX}-{suffix}.jsonl':stationrows,
   f'normalized/timetable-versions-{suffix}.jsonl':[dict(timetable_version_id=vid,operator_scope='jr-east',effective_from=DAY,effective_until=UNTIL,edition_name='JR時刻表2026年10月号; exact September30',revision_type='source_snapshot',completeness='partial',source_ids=[source])],
   f'normalized/trips/{suffix}/seeds.jsonl':[dict(trip_id=tid,timetable_version_id=vid,service_id=c['service_id'],calendar_id=cid,train_number=c['train_number'],public_number=c['public_number'],origin_station_id=stations[c['stops'][0][0]],destination_station_id=stations[c['stops'][-1][0]],service_class='limited_express',notes=c['route_note'])],
   f'normalized/stop-times/{suffix}/seeds.jsonl':stops,
   f'normalized/calendars/{suffix}/seeds.jsonl':[dict(calendar_id=cid,valid_from=DAY,valid_until=UNTIL,holiday_policy='none',**{d:0 for d in ['monday','tuesday','wednesday','thursday','friday','saturday','sunday']})],
   f'normalized/calendar-exceptions/{suffix}/seeds.jsonl':[dict(calendar_id=cid,service_date=DAY,exception_type='add',reason='2026年9月30日 td.ok',source_id=source)],
   f'normalized/trip-formations/{suffix}/seeds.jsonl':[dict(c['formation'],formation_id=tid+'.formation.'+DAY,trip_id=tid,service_date=DAY,source_id=source,notes='Printed planned equipment; actual dispatch and car count unknown. '+c.get('reservation_note',c.get('green_compartment_note','')))],
   f'normalized/fact-sources-{suffix}.jsonl':facts,
   f'normalized/fact-completeness-{suffix}.jsonl':complete,
   f'normalized/research-queue-{suffix}.jsonl':queue,
   f'sources/source-registry-{suffix}.jsonl':[dict(source_id=source,publisher='東日本旅客鉄道株式会社 / 株式会社交通新聞社',title=c['service_name']+c['public_number']+'号 停車駅一覧',source_type='official_train_timetable',url_or_locator=c['source_url'],issue='JR時刻表2026年10月号',publication_date=None,effective_date=DAY,accessed_at=DAY,license_status='no_reuse_grant_identified',redistribution_status='verification_only',automated_extraction_allowed=False,notes='September30 td.ok and complete printed calls/equipment inspected; source SHA256 '+c['source_sha256'])]}
  known_trips={json.loads(line)['trip_id'] for p in BASE.glob('normalized/trips/*/*.jsonl') for line in p.read_text().splitlines() if line.strip()}
  outputs[f'normalized/trip-relations/{suffix}/seeds.jsonl']=[r for r in c['coupling_relations'] if r['trip_id'] in known_trips | {tid} and r['related_trip_id'] in known_trips | {tid}]
  if len(outputs[f'normalized/trip-relations/{suffix}/seeds.jsonl']) != len(c['coupling_relations']):
   queue.append(dict(research_id=tid+'.coupling',entity_type='trip',entity_id=tid,missing_dimension='coupling',status='open',notes='Official printed coupling retained in candidate; companion trip not yet approved, so canonical relation deferred.'))
  for path,rows in outputs.items():write(BASE/path,rows)
  print(c['service_name']+c['public_number'],len(stops),'calls')
if __name__=='__main__':main()
