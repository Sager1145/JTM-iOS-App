#!/usr/bin/env python3
"""Four source-pinned Sep30 Shonan trains from Fujisawa observed inventory."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/"app/data/train-service-history"
DAY,UNTIL="2026-09-30","2026-10-01"
SUFFIX="shonan5-6-7-8-20260930"
PINNED = [{'candidate_id': 'jr-east-shonan5-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'shonan',
  'service_name': '湘南',
  'jr_scope': 'jr',
  'public_number': '5',
  'train_number': '3075M',
  'trip_id': 'jr-east.shonan.5.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-shonan5-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/095/098921.html',
  'source_sha256': '71c956a1709cde6714dc7d1565c9790543bab0252b1a29fbc097e360bba92b97',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['東京', None, '18:30'],
            ['品川', '18:38', '18:39'],
            ['大船', '19:08', '19:09'],
            ['藤沢', '19:13', '19:13'],
            ['辻堂', '19:17', '19:17'],
            ['茅ケ崎', '19:21', '19:21'],
            ['平塚', '19:26', None]],
  'printed_platforms': {'東京': '９', '品川': '１２', '大船': '３', '茅ケ崎': '６', '平塚': '３'},
  'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
  'printed_remarks': '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '平日運転',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': True,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; no unprinted '
                'vehicle assignment or number changes inferred.',
  'actual_dispatch': None},
 {'candidate_id': 'jr-east-shonan6-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'shonan',
  'service_name': '湘南',
  'jr_scope': 'jr',
  'public_number': '6',
  'train_number': '3076M',
  'trip_id': 'jr-east.shonan.6.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-shonan6-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/075/076081.html',
  'source_sha256': '7e5d41cddef699b11fdf7aa66fb78364eacc35eed3a0e240b228b6bacd101a05',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['小田原', None, '06:46'],
            ['茅ケ崎', '07:03', '07:04'],
            ['藤沢', '07:10', '07:11'],
            ['品川', '07:49', '07:50'],
            ['東京', '07:58', None]],
  'printed_platforms': {'小田原': '５', '茅ケ崎': '３', '品川': '８', '東京': '８'},
  'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
  'printed_remarks': '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '平日運転',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': True,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; no unprinted '
                'vehicle assignment or number changes inferred.',
  'actual_dispatch': None},
 {'candidate_id': 'jr-east-shonan7-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'shonan',
  'service_name': '湘南',
  'jr_scope': 'jr',
  'public_number': '7',
  'train_number': '3077M',
  'trip_id': 'jr-east.shonan.7.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-shonan7-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/065/068081.html',
  'source_sha256': '4442812cdaca4d135815592f7ba495d951f84b001c817dd49ce5f3a05ded7a04',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['東京', None, '19:00'],
            ['品川', '19:08', '19:09'],
            ['大船', '19:36', '19:36'],
            ['藤沢', '19:40', '19:41'],
            ['辻堂', '19:44', '19:45'],
            ['茅ケ崎', '19:48', '19:49'],
            ['平塚', '19:53', '19:54'],
            ['国府津', '20:03', '20:04'],
            ['小田原', '20:10', None]],
  'printed_platforms': {'東京': '９',
                        '品川': '１２',
                        '大船': '３',
                        '茅ケ崎': '６',
                        '平塚': '４',
                        '国府津': '１',
                        '小田原': '３'},
  'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
  'printed_remarks': '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '平日運転',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': True,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown; no unprinted '
                'vehicle assignment or number changes inferred.',
  'actual_dispatch': None},
 {'candidate_id': 'jr-east-shonan8-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'shonan',
  'service_name': '湘南',
  'jr_scope': 'jr',
  'public_number': '8',
  'train_number': '3078M',
  'trip_id': 'jr-east.shonan.8.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-shonan8-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/065/068201.html',
  'source_sha256': 'bc3025ef772ec7b894d9999497f448b3fe3300894188572dae51741602d96db2',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['小田原', None, '06:58'],
            ['茅ケ崎', '07:16', '07:17'],
            ['藤沢', '07:22', '07:23'],
            ['品川', '08:03', '08:04'],
            ['新橋', '08:09', '08:10'],
            ['東京', '08:13', None]],
  'printed_platforms': {'小田原': '４', '茅ケ崎': '３', '品川': '１３', '東京': '総３'},
  'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
  'printed_remarks': '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
  'printed_operating_labels': '平日運転',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': True,
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
