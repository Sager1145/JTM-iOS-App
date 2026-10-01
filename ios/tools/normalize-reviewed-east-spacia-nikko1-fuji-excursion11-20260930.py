#!/usr/bin/env python3
"""Exact Sep30 Spacia Nikko and Fuji Excursion, without inferred branch clocks."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/"app/data/train-service-history"
DAY,UNTIL="2026-09-30","2026-10-01"
SUFFIX="spacia-nikko1-fuji-excursion11-20260930"
PINNED = [{'candidate_id': 'jr-east-spacia-nikko1-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'spacia-nikko',
  'service_name': 'スペーシア日光',
  'jr_scope': 'through_jr',
  'public_number': '1',
  'train_number': '1091M',
  'trip_id': 'jr-east.spacia-nikko.1.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-spacia-nikko1-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/046931.html',
  'source_sha256': 'f657e4190c049a9d63a1095a290e787eedc6a749e1ad357ace04b4e2c04cc5fb',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['新宿', None, '09:34'],
            ['池袋', '09:39', '09:40'],
            ['浦和', '09:57', '09:58'],
            ['大宮', '10:03', '10:04'],
            ['栃木', '10:50', '10:51'],
            ['新鹿沼', '11:06', '11:06'],
            ['下今市', '11:22', '11:24'],
            ['東武日光', '11:31', None]],
  'printed_platforms': {'新宿': '５', '池袋': '３', '大宮': '１１'},
  'equipment': ['グリーン車指定席（４人用グリーン個室連結）', '普通車全車指定席'],
  'printed_remarks': '４人用グリーン個室料金は６３００円です １００系',
  'printed_operating_labels': None,
  'printed_coupling': None,
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': '100系',
                'car_count': None,
                'green_car_available': True,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; retain printed '
                'train number only.',
  'actual_dispatch': None,
  'green_compartment_note': 'Printed equipment specifies a four-person Green compartment; quantity '
                            'of compartments/car number not printed. This is compartment '
                            'occupancy, not total seating capacity.'},
 {'candidate_id': 'jr-east-fuji-excursion11-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'fuji-excursion',
  'service_name': '富士回遊',
  'jr_scope': 'through_jr',
  'public_number': '11',
  'train_number': '2111M',
  'trip_id': 'jr-east.fuji-excursion.11.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-fuji-excursion11-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/050/054801.html',
  'source_sha256': 'c162bff7234f8dc3c7283b0f2b399fbfdfcf24524b1a761839b99fc819db3627',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['新宿', None, None],
            ['立川', None, None],
            ['八王子', None, None],
            ['大月', None, '10:42'],
            ['都留文科大学前', '10:58', '10:59'],
            ['下吉田', '11:14', '11:14'],
            ['富士山', '11:19', '11:23'],
            ['富士急ハイランド', '11:25', '11:25'],
            ['河口湖', '11:28', None]],
  'printed_platforms': {},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '富士急行線内の特急料金は大月－富士山・河口湖間は６００円（こども４００円）です '
                     '〔富士回遊〕に富士急行線内のみご乗車の場合は、座席未指定券をご利用ください。座席の指定はできません。また、富士山－河口湖間の各駅相互間に限り、乗車券のみでご乗車になれます '
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '平日運転',
  'printed_coupling': '新宿－大月は3111Mに併結',
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
  'partial_timing_note': '2111M column has no clocks/platforms at 新宿・立川・八王子 and no '
                         'arrival/platform at 大月. Nulls retained; no Kaiji clocks copied. From 大月 '
                         'to 河口湖 only branch clocks are printed.',
  'reservation_note': 'Ordinary全車指定席 equipment label is retained; printed remark says Fujikyu-only '
                      'travel uses seat-unassigned ticket and cannot designate a seat, and 富士山–河口湖 '
                      'local journeys need only a fare ticket.'}]

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
   f'normalized/services-{suffix}.jsonl':[dict(service_id=c['service_id'],canonical_name=c['service_name'],service_class='limited_express',historical_generation=1,jr_scope=c['jr_scope'],first_verified_date=DAY,last_verified_date=DAY)],
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
  if c['service_id']=='fuji-excursion':
   kaiji='jr-east.kaiji.11.exact-2026-09-30'
   outputs[f'normalized/trip-relations/{suffix}/seeds.jsonl']=[dict(trip_id=tid,related_trip_id=kaiji,relation_type='couples_with',from_sequence=1,to_sequence=4,source_id=source),dict(trip_id=kaiji,related_trip_id=tid,relation_type='couples_with',from_sequence=1,to_sequence=4,source_id=source)]
  for path,rows in outputs.items():write(BASE/path,rows)
  print(c['service_name']+c['public_number'],len(stops),'calls')
if __name__=='__main__':main()
