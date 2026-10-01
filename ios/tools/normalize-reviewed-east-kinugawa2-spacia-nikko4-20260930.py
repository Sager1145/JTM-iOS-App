#!/usr/bin/env python3
"""Exact-day two reverse-direction Tobu through trains."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/"app/data/train-service-history"
DAY,UNTIL="2026-09-30","2026-10-01"
SUFFIX="kinugawa2-spacia-nikko4-20260930"
PINNED = [{'candidate_id': 'jr-east-kinugawa2-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'kinugawa',
  'service_name': 'きぬがわ',
  'jr_scope': 'through_jr',
  'public_number': '2',
  'train_number': '1082M',
  'trip_id': 'jr-east.kinugawa.2.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-kinugawa2-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/046951.html',
  'source_sha256': 'c105a121c17197a3b6bad0ea7375a173347bf618b19ed5d16a664b4c8c8ae475',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['鬼怒川温泉', None, '14:55'],
            ['東武ワールドスクウェア', '14:57', '14:58'],
            ['下今市', '15:19', '15:21'],
            ['新鹿沼', '15:37', '15:37'],
            ['栃木', '15:52', '15:53'],
            ['大宮', '16:37', '16:38'],
            ['浦和', '16:43', '16:44'],
            ['池袋', '17:02', '17:03'],
            ['新宿', '17:09', None]],
  'printed_platforms': {'大宮': '４', '池袋': '２', '新宿': '６'},
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
  'actual_dispatch': None,
  'printed_operating_labels': []},
 {'candidate_id': 'jr-east-spacia-nikko4-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'spacia-nikko',
  'service_name': 'スペーシア日光',
  'jr_scope': 'through_jr',
  'public_number': '4',
  'train_number': '1094M',
  'trip_id': 'jr-east.spacia-nikko.4.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-spacia-nikko4-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/085/087591.html',
  'source_sha256': 'cc88bc56b4e02736542f9fffd38093863d414139d5e9b583fc30328c33c8ab67',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['東武日光', None, '16:38'],
            ['下今市', '16:45', '16:46'],
            ['新鹿沼', '17:01', '17:02'],
            ['栃木', '17:17', '17:19'],
            ['大宮', '18:03', '18:04'],
            ['浦和', '18:10', '18:11'],
            ['池袋', '18:29', '18:30'],
            ['新宿', '18:35', None]],
  'printed_platforms': {'大宮': '４', '池袋': '２', '新宿': '６'},
  'equipment': ['グリーン車指定席（４人用グリーン個室連結）', '普通車全車指定席'],
  'printed_remarks': '４人用グリーン個室料金は６３００円です １００系',
  'printed_operating_labels': [],
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
                            'occupancy, not total seating capacity.'}]

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
   if c['formation'][field] is not None:facts.append(dict(entity_type='trip',entity_id=tid,field_name='formation.'+field,source_id=source,page_or_locator='設備: 普通車全車指定席' if field=='all_reserved' else ('備考: '+c['printed_remarks'] if field=='vehicle_series' else '設備: グリーン車指定席（４人用グリーン個室連結）'),confidence='high',verification_status='verified'))
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
  if c['service_id']=='fuji-excursion':
   kaiji='jr-east.kaiji.11.exact-2026-09-30'
   outputs[f'normalized/trip-relations/{suffix}/seeds.jsonl']=[dict(trip_id=tid,related_trip_id=kaiji,relation_type='couples_with',from_sequence=1,to_sequence=4,source_id=source),dict(trip_id=kaiji,related_trip_id=tid,relation_type='couples_with',from_sequence=1,to_sequence=4,source_id=source)]
  for path,rows in outputs.items():write(BASE/path,rows)
  print(c['service_name']+c['public_number'],len(stops),'calls')
if __name__=='__main__':main()
