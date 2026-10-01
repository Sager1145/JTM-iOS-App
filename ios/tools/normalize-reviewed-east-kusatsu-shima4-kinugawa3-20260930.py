#!/usr/bin/env python3
"""Two exact-day new JR East families, source-pinned printed facts only."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/"app/data/train-service-history"
DAY,UNTIL="2026-09-30","2026-10-01"
SUFFIX="kusatsu-shima4-kinugawa3-20260930"
PINNED = [{'candidate_id': 'jr-east-kusatsu-shima4-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'kusatsu-shima',
  'service_name': '草津・四万',
  'jr_scope': 'jr',
  'public_number': '4',
  'train_number': '3004M',
  'trip_id': 'jr-east.kusatsu-shima.4.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-kusatsu-shima4-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/047071.html',
  'source_sha256': 'dbfa96de47bc0f8bc5e885a79e2becaa54a1168026cdb60af70dfad44d4ea4b2',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['長野原草津口', None, '15:43'],
            ['中之条', '16:05', '16:06'],
            ['渋川', '16:25', '16:26'],
            ['新前橋', '16:36', '16:38'],
            ['高崎', '16:44', '16:46'],
            ['熊谷', '17:15', '17:16'],
            ['大宮', '17:43', '17:44'],
            ['浦和', '17:50', '17:50'],
            ['赤羽', '17:58', '17:59'],
            ['上野', '18:09', None]],
  'printed_platforms': {'高崎': '７', '大宮': '６', '上野': '１４'},
  'equipment': ['普通車全車指定席'],
  'printed_remarks': None,
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': None,
                'car_count': None,
                'green_car_available': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown. Published '
                'whole-page train number retained; no unprinted Tobu number changes inferred.',
  'actual_dispatch': None},
 {'candidate_id': 'jr-east-kinugawa3-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'kinugawa',
  'service_name': 'きぬがわ',
  'jr_scope': 'through_jr',
  'public_number': '3',
  'train_number': '1083M',
  'trip_id': 'jr-east.kinugawa.3.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-kinugawa3-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/046941.html',
  'source_sha256': 'b0f3647eb88cf50e5550ced3c1c95697df38a2066d455584a035c9c32109bab8',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['新宿', None, '10:31'],
            ['池袋', '10:36', '10:37'],
            ['浦和', '10:54', '10:54'],
            ['大宮', '11:01', '11:02'],
            ['栃木', '11:44', '11:45'],
            ['新鹿沼', '12:00', '12:01'],
            ['下今市', '12:17', '12:18'],
            ['東武ワールドスクウェア', '12:33', '12:33'],
            ['鬼怒川温泉', '12:36', None]],
  'printed_platforms': {'新宿': '６', '池袋': '３', '大宮': '１１'},
  'equipment': ['普通車全車指定席'],
  'printed_remarks': '２５３系',
  'train_number_segments': [],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': True,
                'vehicle_series': '253系',
                'car_count': None,
                'green_car_available': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route/operator segments unknown. Published '
                'whole-page train number retained; no unprinted Tobu number changes inferred.',
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
   codes={s[0] for line in package['lines'] for s in line['stations'] if s[1]==name and line['operator'] in ['東日本旅客鉄道','東武鉄道']}
   if len(codes)!=1:raise ValueError((name,codes))
   stations[name]='jp.n02.'+next(iter(codes))
  stationrows=[dict(station_id=sid,name_snapshot=name,current_source_code=sid.removeprefix('jp.n02.'),rail_history_id=None,reference_kind='current_n02') for name,sid in stations.items() if sid not in known];known.update(stations.values())
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
  for field in ['all_reserved','vehicle_series']:
   if c['formation'][field] is not None:facts.append(dict(entity_type='trip',entity_id=tid,field_name='formation.'+field,source_id=source,page_or_locator='設備: 普通車全車指定席' if field=='all_reserved' else '備考: ２５３系',confidence='high',verification_status='verified'))
  outputs={
   f'normalized/services-{suffix}.jsonl':[dict(service_id=c['service_id'],canonical_name=c['service_name'],service_class='limited_express',historical_generation=1,jr_scope=c['jr_scope'],first_verified_date=DAY,last_verified_date=DAY)],
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
