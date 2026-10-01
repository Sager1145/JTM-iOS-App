#!/usr/bin/env python3
"""Four exact-date Niigata departures; date-qualified Green equipment retained."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/"app/data/train-service-history"
DAY,UNTIL="2026-09-30","2026-10-01"
SUFFIX="inaho1-3-shirayuki2-4-20260930"
PINNED = [{'trip_id': 'jr-east.inaho.1.exact-2026-09-30',
  'service_id': 'inaho',
  'service_name': 'いなほ',
  'jr_scope': 'jr',
  'service_date': '2026-09-30',
  'public_number': '1',
  'train_number': '1M',
  'source_id': 'jr-east-inaho1-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/060/064001.html',
  'source_sha256': '5325bdf1f46d46eaf1ef17266760c95d10cffe3bb0618fd4a055db52fef71932',
  'source_locator': '2026年9月30日 td.ok; 印刷時刻/番線/設備/備考',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'printed_equipment': ['グリーン車指定席', '普通車一部指定席'],
  'printed_platforms': {'新潟': '５',
                        '新発田': '１',
                        '坂町': '３',
                        '村上': '３',
                        '余目': '２',
                        '酒田': '１',
                        '秋田': '３'},
  'printed_remarks': None,
  'stops': [['新潟', None, '08:23'],
            ['豊栄', '08:34', '08:35'],
            ['新発田', '08:44', '08:44'],
            ['中条', '08:53', '08:54'],
            ['坂町', '09:00', '09:00'],
            ['村上', '09:08', '09:09'],
            ['府屋', '09:38', '09:38'],
            ['あつみ温泉', '09:50', '09:51'],
            ['鶴岡', '10:13', '10:13'],
            ['余目', '10:23', '10:24'],
            ['酒田', '10:32', '10:34'],
            ['遊佐', '10:44', '10:44'],
            ['象潟', '11:04', '11:04'],
            ['仁賀保', '11:13', '11:13'],
            ['羽後本荘', '11:24', '11:24'],
            ['秋田', '11:57', None]],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': False,
                'green_car_available': True,
                'car_count': None,
                'vehicle_series': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route and operator segments are unknown.',
  'actual_dispatch': None,
  'candidate_id': 'jr-east-inaho1-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'printed_operating_labels': [],
  'train_number_segments': []},
 {'trip_id': 'jr-east.inaho.3.exact-2026-09-30',
  'service_id': 'inaho',
  'service_name': 'いなほ',
  'jr_scope': 'jr',
  'service_date': '2026-09-30',
  'public_number': '3',
  'train_number': '3M',
  'source_id': 'jr-east-inaho3-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/060/064011.html',
  'source_sha256': '2f20c2367485a6cd822ee20b12415ef9973afe1208db1abf5c5649bc43d6a680',
  'source_locator': '2026年9月30日 td.ok; 印刷時刻/番線/設備/備考',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'printed_equipment': ['普通車一部指定席'],
  'printed_platforms': {'新潟': '５', '新発田': '１', '坂町': '３', '村上': '３', '余目': '２', '酒田': '１'},
  'printed_remarks': '９月１８日～１０月１６・１９～２２日・１１月４～６・９・２１～２４・２８・２９日はグリーン車指定席連結',
  'stops': [['新潟', None, '10:50'],
            ['豊栄', '11:03', '11:04'],
            ['新発田', '11:13', '11:13'],
            ['中条', '11:22', '11:23'],
            ['坂町', '11:29', '11:30'],
            ['村上', '11:38', '11:38'],
            ['府屋', '12:08', '12:08'],
            ['あつみ温泉', '12:20', '12:21'],
            ['鶴岡', '12:43', '12:44'],
            ['余目', '12:54', '12:55'],
            ['酒田', '13:03', None]],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': False,
                'green_car_available': True,
                'car_count': None,
                'vehicle_series': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route and operator segments are unknown.',
  'actual_dispatch': None,
  'candidate_id': 'jr-east-inaho3-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'printed_operating_labels': [],
  'train_number_segments': [],
  'dated_green_evidence': {'valid_from': '2026-09-18',
                           'valid_through': '2026-10-16',
                           'printed_remark': '９月１８日～１０月１６・１９～２２日・１１月４～６・９・２１～２４・２８・２９日はグリーン車指定席連結',
                           'selected_date': '2026-09-30'}},
 {'trip_id': 'jr-east.shirayuki.2.exact-2026-09-30',
  'service_id': 'shirayuki',
  'service_name': 'しらゆき',
  'jr_scope': 'through_jr',
  'service_date': '2026-09-30',
  'public_number': '2',
  'train_number': '52M',
  'source_id': 'jr-east-shirayuki2-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/060/063961.html',
  'source_sha256': 'd3baf5e52cccfeee4a47442cfdeaf3ece2f0d7f622566e52f4ba651d21c2272c',
  'source_locator': '2026年9月30日 td.ok; 印刷時刻/番線/設備/備考',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'printed_equipment': ['普通車一部指定席'],
  'printed_platforms': {'新潟': '３', '新津': '２', '東三条': '３', '長岡': '４', '柏崎': '３', '直江津': '３'},
  'printed_remarks': 'えちごトキめき鉄道線内相互間のみの指定席特急券は発売いたしません',
  'stops': [['新潟', None, '07:35'],
            ['新津', '07:49', '07:50'],
            ['加茂', '08:03', '08:03'],
            ['東三条', '08:09', '08:10'],
            ['見附', '08:18', '08:18'],
            ['長岡', '08:27', '08:29'],
            ['柏崎', '08:54', '08:54'],
            ['柿崎', '09:09', '09:10'],
            ['直江津', '09:23', '09:25'],
            ['高田', '09:32', '09:33'],
            ['上越妙高', '09:39', '09:39'],
            ['新井', '09:46', None]],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': False,
                'green_car_available': None,
                'car_count': None,
                'vehicle_series': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route and operator segments are unknown. The printed '
                'ticketing remark is retained without converting it into an operator-segment '
                'claim.',
  'actual_dispatch': None,
  'candidate_id': 'jr-east-shirayuki2-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'printed_operating_labels': [],
  'train_number_segments': []},
 {'trip_id': 'jr-east.shirayuki.4.exact-2026-09-30',
  'service_id': 'shirayuki',
  'service_name': 'しらゆき',
  'jr_scope': 'through_jr',
  'service_date': '2026-09-30',
  'public_number': '4',
  'train_number': '54M',
  'source_id': 'jr-east-shirayuki4-20260930',
  'source_url': 'https://timetables.jreast.co.jp/2610/train/060/063971.html',
  'source_sha256': '07434d71f063cb5d3f91ae16f47d79fdcd4564cbe4d956905ef73a1fd2095b24',
  'source_locator': '2026年9月30日 td.ok; 印刷時刻/番線/設備/備考',
  'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
  'printed_equipment': ['普通車一部指定席'],
  'printed_platforms': {'新潟': '５', '新津': '２', '東三条': '３', '長岡': '４', '柏崎': '３', '直江津': '３'},
  'printed_remarks': 'えちごトキめき鉄道線内相互間のみの指定席特急券は発売いたしません',
  'stops': [['新潟', None, '10:23'],
            ['新津', '10:36', '10:37'],
            ['加茂', '10:49', '10:50'],
            ['東三条', '10:56', '10:57'],
            ['見附', '11:05', '11:06'],
            ['長岡', '11:16', '11:17'],
            ['柏崎', '11:42', '11:42'],
            ['柿崎', '11:57', '11:57'],
            ['直江津', '12:09', '12:11'],
            ['高田', '12:18', '12:18'],
            ['上越妙高', '12:24', None]],
  'formation': {'evidence_kind': 'planned',
                'all_reserved': False,
                'green_car_available': None,
                'car_count': None,
                'vehicle_series': None,
                'reserved_seat_capacity': None},
  'route_note': 'Exact dated ordered physical route and operator segments are unknown. The printed '
                'ticketing remark is retained without converting it into an operator-segment '
                'claim.',
  'actual_dispatch': None,
  'candidate_id': 'jr-east-shirayuki4-20260930',
  'canonical': False,
  'candidate_status': 'reviewed_official_html',
  'printed_operating_labels': [],
  'train_number_segments': []}]

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
   codes={s[0] for line in package['lines'] for s in line['stations'] if s[1]==name and line['operator'] in ['東日本旅客鉄道','えちごトキめき鉄道']}
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
  for field in ['all_reserved','green_car_available']:
   if c['formation'][field] is not None:facts.append(dict(entity_type='trip',entity_id=tid,field_name='formation.'+field,source_id=source,page_or_locator='設備: 普通車一部指定席' if field=='all_reserved' else ('備考: '+c['printed_remarks'] if c.get('dated_green_evidence') else '設備: グリーン車指定席'),confidence='high',verification_status='verified'))
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
