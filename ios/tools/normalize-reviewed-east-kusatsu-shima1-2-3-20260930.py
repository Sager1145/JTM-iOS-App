#!/usr/bin/env python3
"""Three source-pinned Sep30 Kusatsu-Shima trains from Nakanojo observed inventory."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/"app/data/train-service-history"
DAY,UNTIL="2026-09-30","2026-10-01"
SUFFIX="kusatsu-shima1-2-3-20260930"
PINNED = [{'candidate_id': 'jr-east-kusatsu-shima1-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'kusatsu-shima',
  'service_name': '草津・四万',
  'jr_scope': 'jr',
  'public_number': '1',
  'train_number': '3001M',
  'trip_id': 'jr-east.kusatsu-shima.1.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-kusatsu-shima1-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/047041.html',
  'source_sha256': '7a9e987db35d944e35049786ae95d6cadab2575e40ee789b6c7c398b3ce6e81b',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['上野', None, '10:00'],
            ['赤羽', '10:09', '10:10'],
            ['浦和', '10:18', '10:19'],
            ['大宮', '10:25', '10:26'],
            ['熊谷', '10:51', '10:51'],
            ['高崎', '11:18', '11:19'],
            ['新前橋', '11:25', '11:27'],
            ['渋川', '11:36', '11:37'],
            ['中之条', '11:57', '11:58'],
            ['長野原草津口', '12:18', None]],
  'printed_platforms': {'上野': '１４', '大宮': '８', '高崎': '２'},
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
  'actual_dispatch': None,
  'printed_operating_labels': []},
 {'candidate_id': 'jr-east-kusatsu-shima2-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'kusatsu-shima',
  'service_name': '草津・四万',
  'jr_scope': 'jr',
  'public_number': '2',
  'train_number': '3002M',
  'trip_id': 'jr-east.kusatsu-shima.2.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-kusatsu-shima2-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/047061.html',
  'source_sha256': '5e299047295bdc27565fe41dea4cb17f4deaf28e1885ebc3830b9493470d9d7a',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['長野原草津口', None, '13:07'],
            ['中之条', '13:28', '13:29'],
            ['渋川', '13:48', '13:49'],
            ['新前橋', '13:58', '13:59'],
            ['高崎', '14:05', '14:06'],
            ['熊谷', '14:33', '14:34'],
            ['大宮', '14:59', '15:00'],
            ['浦和', '15:06', '15:07'],
            ['赤羽', '15:15', '15:15'],
            ['上野', '15:26', None]],
  'printed_platforms': {'高崎': '７', '大宮': '６', '上野': '１６'},
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
  'actual_dispatch': None,
  'printed_operating_labels': []},
 {'candidate_id': 'jr-east-kusatsu-shima3-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'service_id': 'kusatsu-shima',
  'service_name': '草津・四万',
  'jr_scope': 'jr',
  'public_number': '3',
  'train_number': '3003M',
  'trip_id': 'jr-east.kusatsu-shima.3.exact-2026-09-30',
  'service_date': '2026-09-30',
  'source_id': 'jr-east-kusatsu-shima3-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/045/047051.html',
  'source_sha256': '3666da8ec010bd0519913d60b4e476274c707f55e2f0aa8dd7c7b865b1a5087d',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'stops': [['上野', None, '12:10'],
            ['赤羽', '12:18', '12:19'],
            ['浦和', '12:27', '12:28'],
            ['大宮', '12:34', '12:35'],
            ['熊谷', '13:01', '13:02'],
            ['高崎', '13:31', '13:33'],
            ['新前橋', '13:39', '13:40'],
            ['渋川', '13:50', '13:51'],
            ['中之条', '14:12', '14:13'],
            ['長野原草津口', '14:34', None]],
  'printed_platforms': {'上野': '１４', '大宮': '７', '高崎': '２'},
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
  'actual_dispatch': None,
  'printed_operating_labels': []}]

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
