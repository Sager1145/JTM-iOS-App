#!/usr/bin/env python3
"""Four source-pinned Sep30 Sazanami trains from Soga observed inventory."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/"app/data/train-service-history"
DAY,UNTIL="2026-09-30","2026-10-01"
SUFFIX="sazanami1-2-4-5-20260930"
PINNED = [{'candidate_id': 'jr-east-sazanami1-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'sazanami',
  'service_name': 'さざなみ',
  'jr_scope': 'jr',
  'public_number': '1',
  'train_number': '1001M',
  'trip_id': 'jr-east.sazanami.1.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-sazanami1-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/049701.html',
  'source_sha256': '1a9ed299547f5689d4c8a2a218a56313661abc5c8d9b3a10c1ce84ff456fa3ed',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['東京', None, '17:30'],
            ['蘇我', '18:03', '18:04'],
            ['五井', '18:11', '18:11'],
            ['姉ケ崎', '18:16', '18:16'],
            ['木更津', '18:28', '18:29'],
            ['君津', '18:36', None]],
  'printed_platforms': {'東京': '京１', '蘇我': '５', '姉ケ崎': '１', '木更津': '３', '君津': '３'},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '平日運転',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; no unprinted '
                'vehicle assignment or number changes inferred.',
  'actual_dispatch': None},
 {'candidate_id': 'jr-east-sazanami2-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'sazanami',
  'service_name': 'さざなみ',
  'jr_scope': 'jr',
  'public_number': '2',
  'train_number': '1002M',
  'trip_id': 'jr-east.sazanami.2.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-sazanami2-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/049741.html',
  'source_sha256': 'ac6f0ae8f1d3700302b4476c77f5be310ad0ae16fdcb5f6577c15291b19341f3',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['君津', None, '05:52'],
            ['木更津', '05:58', '05:59'],
            ['姉ケ崎', '06:10', '06:10'],
            ['五井', '06:15', '06:15'],
            ['蘇我', '06:23', '06:24'],
            ['東京', '06:57', None]],
  'printed_platforms': {'君津': '３', '木更津': '１', '姉ケ崎': '３', '蘇我': '２', '東京': '京１'},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '平日運転',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; no unprinted '
                'vehicle assignment or number changes inferred.',
  'actual_dispatch': None},
 {'candidate_id': 'jr-east-sazanami4-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'sazanami',
  'service_name': 'さざなみ',
  'jr_scope': 'jr',
  'public_number': '4',
  'train_number': '1004M',
  'trip_id': 'jr-east.sazanami.4.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-sazanami4-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/075/076061.html',
  'source_sha256': 'a5c898302eea3577ae98021077257b6a91d35bc3216bbc2a5225ef526c5c59d1',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['木更津', None, '07:03'],
            ['姉ケ崎', '07:14', '07:14'],
            ['五井', '07:19', '07:20'],
            ['蘇我', '07:28', '07:29'],
            ['東京', '08:12', None]],
  'printed_platforms': {'木更津': '１', '姉ケ崎': '３', '蘇我': '２', '東京': '京１'},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '平日運転',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; no unprinted '
                'vehicle assignment or number changes inferred.',
  'actual_dispatch': None},
 {'candidate_id': 'jr-east-sazanami5-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'sazanami',
  'service_name': 'さざなみ',
  'jr_scope': 'jr',
  'public_number': '5',
  'train_number': '1005M',
  'trip_id': 'jr-east.sazanami.5.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-sazanami5-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/049721.html',
  'source_sha256': '59bbbcb6fdc2b6e8f199a5497a58407abe52a1992aa45c79b920162307c3c07f',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['東京', None, '19:30'],
            ['蘇我', '20:04', '20:05'],
            ['五井', '20:13', '20:14'],
            ['姉ケ崎', '20:18', '20:19'],
            ['木更津', '20:30', '20:30'],
            ['君津', '20:37', None]],
  'printed_platforms': {'東京': '京１', '蘇我': '５', '姉ケ崎': '１', '木更津': '３', '君津': '３'},
  'equipment': ['座席未指定券', '普通車全車指定席'],
  'printed_remarks': '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '平日運転',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; no unprinted '
                'vehicle assignment or number changes inferred.',
  'actual_dispatch': None}]

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
   codes={s[0] for line in package['lines'] for s in line['stations'] if s[1]=={'茅ケ崎':'茅ヶ崎','姉ケ崎':'姉ヶ崎'}.get(name,name) and line['operator'] in ['東日本旅客鉄道']}
   if name=='東京':codes &= {'003785' if c['service_id']=='sazanami' else '003766'}
   if len(codes)!=1:raise ValueError((name,codes))
   stations[name]='jp.n02.'+next(iter(codes))
  stationrows=[dict(station_id=sid,name_snapshot={'茅ケ崎':'茅ヶ崎','姉ケ崎':'姉ヶ崎'}.get(name,name),current_source_code=sid.removeprefix('jp.n02.'),rail_history_id=None,reference_kind='current_n02') for name,sid in stations.items() if sid not in known];known.update(stations.values())
  stops=[]
  for i,(name,a,d) in enumerate(c['stops'],1):
   call='origin' if i==1 else 'destination' if i==len(c['stops']) else 'passenger_stop'
   stops.append(dict(trip_id=tid,stop_sequence=i,station_id=stations[name],arrival_time=a,departure_time=d,day_offset=0,call_type=call,pickup_allowed=int(call!='destination'),dropoff_allowed=int(call!='origin'),platform=c['printed_platforms'].get(name),time_accuracy='minute',source_id=source))
  complete=[];facts=[];queue=[]
  for dim in ['identity','train_number','validity_calendar','origin_destination','stops','times','station_refs','formation','route_lines','operator']:
   status='unknown' if dim in ['route_lines','operator'] else 'partial' if dim=='formation' else 'verified';note=c['route_note'] if status=='unknown' else 'Direct exact-day timetable; formation records planned printed equipment only, actual dispatch unknown.'
   complete.append(dict(entity_type='trip',entity_id=tid,dimension=dim,status=status,confidence='low' if status=='unknown' else 'high',notes=note))
   if status=='verified':facts.append(dict(entity_type='trip',entity_id=tid,field_name=dim,source_id='jtm-current-station-directory' if dim=='station_refs' else source,page_or_locator='app/public/rail/jp-2025.json' if dim=='station_refs' else '2026年9月30日 td.ok; 時刻詳細',confidence='high',verification_status='verified'))
   else:queue.append(dict(research_id=tid+'.'+dim,entity_type='trip',entity_id=tid,missing_dimension=dim,status='open',notes=note))
  for field in ['all_reserved','green_car_available']:
   if c['formation'][field] is not None:facts.append(dict(entity_type='trip',entity_id=tid,field_name='formation.'+field,source_id=source,page_or_locator='設備: 普通車全車指定席' if field=='all_reserved' else '設備: グリーン車指定席',confidence='high',verification_status='verified'))
  outputs={
   f'normalized/station-identities-{SUFFIX}-{suffix}.jsonl':stationrows,
   f'normalized/timetable-versions-{suffix}.jsonl':[dict(timetable_version_id=vid,operator_scope='jr-east',effective_from=DAY,effective_until=UNTIL,edition_name='JR時刻表2026年10月号; exact September30',revision_type='source_snapshot',completeness='partial',source_ids=[source])],
   f'normalized/trips/{suffix}/seeds.jsonl':[dict(trip_id=tid,timetable_version_id=vid,service_id=c['service_id'],calendar_id=cid,train_number=c['train_number'],public_number=c['public_number'],origin_station_id=stations[c['stops'][0][0]],destination_station_id=stations[c['stops'][-1][0]],service_class='limited_express',notes=c['route_note'])],
   f'normalized/stop-times/{suffix}/seeds.jsonl':stops,
   f'normalized/calendars/{suffix}/seeds.jsonl':[dict(calendar_id=cid,valid_from=DAY,valid_until=UNTIL,holiday_policy='none',**{d:0 for d in ['monday','tuesday','wednesday','thursday','friday','saturday','sunday']})],
   f'normalized/calendar-exceptions/{suffix}/seeds.jsonl':[dict(calendar_id=cid,service_date=DAY,exception_type='add',reason='2026年9月30日 td.ok',source_id=source)],
   f'normalized/trip-formations/{suffix}/seeds.jsonl':[dict(c['formation'],formation_id=tid+'.formation.'+DAY,trip_id=tid,service_date=DAY,source_id=source,notes='Printed planned equipment; actual dispatch and car count unknown.')],
   f'normalized/fact-sources-{suffix}.jsonl':facts,
   f'normalized/fact-completeness-{suffix}.jsonl':complete,
   f'normalized/research-queue-{suffix}.jsonl':queue,
   f'sources/source-registry-{suffix}.jsonl':[dict(source_id=source,publisher='東日本旅客鉄道株式会社 / 株式会社交通新聞社',title=c['service_name']+c['public_number']+'号 停車駅一覧',source_type='official_train_timetable',url_or_locator=c['source_url'],issue='JR時刻表2026年10月号',publication_date=None,effective_date=DAY,accessed_at=DAY,license_status='no_reuse_grant_identified',redistribution_status='verification_only',automated_extraction_allowed=False,notes='September30 td.ok and complete printed calls/equipment inspected; source SHA256 '+c['source_sha256'])]}
  for path,rows in outputs.items():write(BASE/path,rows)
  print(c['service_name']+c['public_number'],len(stops),'calls')
if __name__=='__main__':main()
