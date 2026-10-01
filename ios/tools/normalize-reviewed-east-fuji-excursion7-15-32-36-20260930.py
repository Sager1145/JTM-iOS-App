#!/usr/bin/env python3
"""Four official Fuji Excursion branches, preserving shared-column blanks."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/"app/data/train-service-history"
DAY,UNTIL="2026-09-30","2026-10-01"
SUFFIX="fuji-excursion7-15-32-36-20260930"
PINNED = [{'candidate_id': 'jr-east-fuji-excursion7-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'fuji-excursion',
  'service_name': '富士回遊',
  'jr_scope': 'through_jr',
  'public_number': '7',
  'train_number': '2107M',
  'trip_id': 'jr-east.fuji-excursion.7.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-fuji-excursion7-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/050/054791.html',
  'source_sha256': 'd6c4d08a30291381123a11ee38de8888becca35a46c82e2af582ffea61f4c3de',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['新宿', None, None],
            ['立川', None, None],
            ['八王子', None, None],
            ['大月', None, '09:42'],
            ['都留文科大学前', '09:58', '09:58'],
            ['下吉田', '10:12', '10:13'],
            ['富士山', '10:18', '10:21'],
            ['富士急ハイランド', '10:23', '10:23'],
            ['河口湖', '10:26', None]],
  'printed_platforms': {},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '富士急行線内の特急料金は大月－富士山・河口湖間は６００円（こども４００円）です '
                     '〔富士回遊〕に富士急行線内のみご乗車の場合は、座席未指定券をご利用ください。座席の指定はできません。また、富士山－河口湖間の各駅相互間に限り、乗車券のみでご乗車になれます '
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '',
  'printed_coupling': '新宿－大月は3107Mに併結',
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
  'partial_timing_note': 'Only Fuji Excursion column clocks/platforms transcribed. Coupled Kaiji '
                         'clocks/platforms not copied; blank shared section remains null.',
  'reservation_note': 'Ordinary全車指定席 equipment label is retained; printed remark says Fujikyu-only '
                      'travel uses seat-unassigned ticket and cannot designate a seat, and 富士山–河口湖 '
                      'local journeys need only a fare ticket.',
  'coupling_relations': [{'trip_id': 'jr-east.fuji-excursion.7.exact-2026-09-30',
                          'related_trip_id': 'jr-east.kaiji.7.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 1,
                          'to_sequence': 4,
                          'source_id': 'jr-east-fuji-excursion7-20260930'},
                         {'trip_id': 'jr-east.kaiji.7.exact-2026-09-30',
                          'related_trip_id': 'jr-east.fuji-excursion.7.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 1,
                          'to_sequence': 4,
                          'source_id': 'jr-east-fuji-excursion7-20260930'}]},
 {'candidate_id': 'jr-east-fuji-excursion15-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'fuji-excursion',
  'service_name': '富士回遊',
  'jr_scope': 'through_jr',
  'public_number': '15',
  'train_number': '2115M',
  'trip_id': 'jr-east.fuji-excursion.15.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-fuji-excursion15-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/060/063481.html',
  'source_sha256': 'cc76641f5e38dc9ca244adc8f4e3a24e49a58042f43b9b9d33de34c0de79dc26',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['新宿', None, None],
            ['立川', None, None],
            ['八王子', None, None],
            ['大月', None, '11:36'],
            ['都留文科大学前', '11:55', '11:56'],
            ['下吉田', '12:11', '12:12'],
            ['富士山', '12:17', '12:19'],
            ['富士急ハイランド', '12:21', '12:22'],
            ['河口湖', '12:24', None]],
  'printed_platforms': {},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '富士急行線内の特急料金は大月－富士山・河口湖間は６００円（こども４００円）です '
                     '〔富士回遊〕に富士急行線内のみご乗車の場合は、座席未指定券をご利用ください。座席の指定はできません。また、富士山－河口湖間の各駅相互間に限り、乗車券のみでご乗車になれます '
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '',
  'printed_coupling': '新宿－大月は3115Mに併結',
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
  'partial_timing_note': 'Only Fuji Excursion column clocks/platforms transcribed. Coupled Kaiji '
                         'clocks/platforms not copied; blank shared section remains null.',
  'reservation_note': 'Ordinary全車指定席 equipment label is retained; printed remark says Fujikyu-only '
                      'travel uses seat-unassigned ticket and cannot designate a seat, and 富士山–河口湖 '
                      'local journeys need only a fare ticket.',
  'coupling_relations': [{'trip_id': 'jr-east.fuji-excursion.15.exact-2026-09-30',
                          'related_trip_id': 'jr-east.kaiji.15.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 1,
                          'to_sequence': 4,
                          'source_id': 'jr-east-fuji-excursion15-20260930'},
                         {'trip_id': 'jr-east.kaiji.15.exact-2026-09-30',
                          'related_trip_id': 'jr-east.fuji-excursion.15.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 1,
                          'to_sequence': 4,
                          'source_id': 'jr-east-fuji-excursion15-20260930'}]},
 {'candidate_id': 'jr-east-fuji-excursion32-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'fuji-excursion',
  'service_name': '富士回遊',
  'jr_scope': 'through_jr',
  'public_number': '32',
  'train_number': '2132M',
  'trip_id': 'jr-east.fuji-excursion.32.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-fuji-excursion32-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/060/063671.html',
  'source_sha256': '1402ddaf71b5a79e931f843b157295e2f80ab5654668c7ba582cf9d8179b0170',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['河口湖', None, '14:08'],
            ['富士急ハイランド', '14:11', '14:11'],
            ['富士山', '14:14', '14:16'],
            ['下吉田', '14:21', '14:21'],
            ['都留文科大学前', '14:36', '14:37'],
            ['大月', '14:56', None],
            ['八王子', None, None],
            ['立川', None, None],
            ['新宿', None, None]],
  'printed_platforms': {},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '富士急行線内の特急料金は河口湖・富士山－大月間は６００円（こども４００円）です '
                     '〔富士回遊〕に富士急行線内のみご乗車の場合は、座席未指定券をご利用ください。座席の指定はできません。また、河口湖－富士山間の各駅相互間に限り、乗車券のみでご乗車になれます '
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '',
  'printed_coupling': '大月－新宿は3132Mに併結',
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
  'partial_timing_note': 'Only Fuji Excursion column clocks/platforms transcribed. Coupled Kaiji '
                         'clocks/platforms not copied; blank shared section remains null.',
  'reservation_note': 'Ordinary全車指定席 equipment label is retained; printed remark says Fujikyu-only '
                      'travel uses seat-unassigned ticket and cannot designate a seat, and 富士山–河口湖 '
                      'local journeys need only a fare ticket.',
  'coupling_relations': [{'trip_id': 'jr-east.fuji-excursion.32.exact-2026-09-30',
                          'related_trip_id': 'jr-east.kaiji.32.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 6,
                          'to_sequence': 9,
                          'source_id': 'jr-east-fuji-excursion32-20260930'},
                         {'trip_id': 'jr-east.kaiji.32.exact-2026-09-30',
                          'related_trip_id': 'jr-east.fuji-excursion.32.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 5,
                          'to_sequence': 8,
                          'source_id': 'jr-east-fuji-excursion32-20260930'}]},
 {'candidate_id': 'jr-east-fuji-excursion36-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'fuji-excursion',
  'service_name': '富士回遊',
  'jr_scope': 'through_jr',
  'public_number': '36',
  'train_number': '2136M',
  'trip_id': 'jr-east.fuji-excursion.36.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-fuji-excursion36-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/060/063461.html',
  'source_sha256': 'ef09559fa05f344cd98f9f6efe2a5b126bc8d2b24781b700a650ca8f01593e1f',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['河口湖', None, '14:58'],
            ['富士急ハイランド', '15:01', '15:01'],
            ['富士山', '15:04', '15:06'],
            ['下吉田', '15:11', '15:12'],
            ['都留文科大学前', '15:26', '15:27'],
            ['大月', '15:48', None],
            ['八王子', None, None],
            ['立川', None, None],
            ['新宿', None, None]],
  'printed_platforms': {},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '富士急行線内の特急料金は河口湖・富士山－大月間は６００円（こども４００円）です '
                     '〔富士回遊〕に富士急行線内のみご乗車の場合は、座席未指定券をご利用ください。座席の指定はできません。また、河口湖－富士山間の各駅相互間に限り、乗車券のみでご乗車になれます '
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '',
  'printed_coupling': '大月－新宿は3136Mに併結',
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
  'partial_timing_note': 'Only Fuji Excursion column clocks/platforms transcribed. Coupled Kaiji '
                         'clocks/platforms not copied; blank shared section remains null.',
  'reservation_note': 'Ordinary全車指定席 equipment label is retained; printed remark says Fujikyu-only '
                      'travel uses seat-unassigned ticket and cannot designate a seat, and 富士山–河口湖 '
                      'local journeys need only a fare ticket.',
  'coupling_relations': [{'trip_id': 'jr-east.fuji-excursion.36.exact-2026-09-30',
                          'related_trip_id': 'jr-east.kaiji.36.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 6,
                          'to_sequence': 9,
                          'source_id': 'jr-east-fuji-excursion36-20260930'},
                         {'trip_id': 'jr-east.kaiji.36.exact-2026-09-30',
                          'related_trip_id': 'jr-east.fuji-excursion.36.exact-2026-09-30',
                          'relation_type': 'couples_with',
                          'from_sequence': 5,
                          'to_sequence': 8,
                          'source_id': 'jr-east-fuji-excursion36-20260930'}]}]

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
  outputs[f'normalized/trip-relations/{suffix}/seeds.jsonl']=c['coupling_relations']
  for path,rows in outputs.items():write(BASE/path,rows)
  print(c['service_name']+c['public_number'],len(stops),'calls')
if __name__=='__main__':main()
