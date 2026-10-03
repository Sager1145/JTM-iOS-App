#!/usr/bin/env python3
"""Rebuild reviewed service inventory; SQLite input is opened strictly read-only."""
import argparse, datetime, hashlib, json, sqlite3
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'ios/RailKit/Sources/RailCore/Resources/line-service-catalog.json'
OBSERVED = '2026-10-02'

def build():
    package = json.loads((ROOT / 'app/public/rail/jp-2025.json').read_text())
    lines = {l['id']:dict(lineID=l['id'],operatorName=l['operator'],lineName=l['name'],aliases=[],coverage='unknown',kinds=[],note='Service classes not yet researched; absence is not evidence of no service.') for l in package['lines']}
    def add(line_id, label, url, start=None, end=None, scope='', from_code=None, to_code=None):
        if line_id not in lines: raise ValueError(line_id)
        kind = dict(id=hashlib.sha256('|'.join([line_id,label,url,start or '',end or '',scope]).encode()).hexdigest()[:20],displayName=label,trainType=label,sourceURL=url,validFrom=start,validUntil=end,scope=scope,fromStationCode=from_code,toStationCode=to_code,observedOn=OBSERVED)
        line = lines[line_id]
        if kind not in line['kinds']: line['kinds'].append(kind)
        line['coverage']='partial'
        line['note']='Evidence covers the stated sections and dates only; service class inventory remains incomplete.'
    # Existing reviewed exact compact line references, without guessing line-name equivalence.
    database = ROOT / 'ios/RailKit/Sources/RailCore/Resources/train-service-timetable.sqlite'
    conn = sqlite3.connect(database.as_uri() + '?mode=ro', uri=True)
    query = '''SELECT DISTINCT s.current_n02_line_id,t.service_class,v.effective_from,v.effective_until,
        d.url_or_locator,s.line_name,s.from_station_id,s.to_station_id
        FROM trip_line_segments s JOIN trips t USING(trip_id)
        JOIN timetable_versions v USING(timetable_version_id)
        JOIN source_documents d ON d.source_id=s.source_id
        WHERE s.confidence='high' AND s.reference_kind='current_n02' '''
    for line_id,kind,start,end,url,name,origin,destination in conn.execute(query):
        label = {'limited_express':'特急','sleeper_limited_express':'寝台特急'}.get(kind)
        if line_id in lines and label and url.startswith('https://'):
            add(line_id,label,url,start,end,'Existing reviewed timetable line segment: '+name+' ('+origin+' → '+destination+')')
    conn.close()
    press = 'https://www.westjr.co.jp/press/article/items/251212_00_press_daiyakaisei_kinkiarea_1.pdf'
    main = 'jp-西日本旅客鉄道-東海道線'
    sanyo = 'jp-西日本旅客鉄道-山陽線'
    # Physical 東海道 includes the marketed 京都/神戸/琵琶湖 sections.
    lines[main]['aliases']=['琵琶湖線','JR京都線','JR神戸線']
    lines[sanyo]['aliases']=['JR神戸線']
    for label in ['快速','新快速']:
        add(main,label,press,'2026-03-14','2026-10-03','琵琶湖線・JR京都線・JR神戸線 米原–神戸; class may change to 普通 along the route','005075','007224')
    for label in ['普通','快速','新快速']:
        add(sanyo,label,press,'2026-03-14','2026-10-03','JR神戸線・山陽線 姫路–網干; does not cover western 山陽線','006509','006571')
    station = 'https://timetable.jr-odekake.net/station-timetable/2789011001?date=20260807'
    add(main,'普通',station,'2026-08-07','2026-08-08','JR京都線 observed eastbound station timetable; no historical extrapolation')
    # Source diagrams confirm labels without a published effective window. Such rows are
    # discoverable in an undated class picker but excluded from dated applicability.
    diagram='https://www.jr-odekake.net/station/pdf/teisya_07.pdf'
    for lid in ['jp-西日本旅客鉄道-北陸線','jp-西日本旅客鉄道-湖西線']:
        for label in ['普通','新快速']:
            add(lid,label,diagram,scope='Current official JR A/JR B stops diagram; effective date not published')
    # Access/airport rapid labels are segment-dependent; subway all-stop status is explicit.
    toei = next(l['id'] for l in package['lines'] if l['operator']=='東京都' and '浅草' in l['name'])
    for label in ['普通','アクセス特急','エアポート快特']:
        add(toei,label,'https://www.kotsu.metro.tokyo.jp/subway/timetable/asakusa/A18ND.html',scope='浅草→押上・京成/北総方面; アクセス特急 stops at every subway station')
    add(toei,'快特','https://www.kotsu.metro.tokyo.jp/subway/timetable/asakusa/A18SH.html',scope='浅草→泉岳寺・京急方面; subway portion stops at every station')
    # Explicit class labels researched independently of through-running topology.
    # The corridor catalog supplies reviewed physical identities and section anchors;
    # it does not by itself establish the classes below.
    corridors = {entry['id']: entry for entry in json.loads((ROOT / 'ios/RailKit/Sources/RailCore/Resources/japan-through-services.json').read_text())['patterns']}
    def reviewed_corridor(identity, labels, url, section_note, legs=None):
        corridor = corridors[identity]
        for leg in legs if legs is not None else corridor['legs']:
            identities = [leg['lineID']]
            if leg.get('reverseLineID'):
                identities.append(leg['reverseLineID'])
            for line_id in dict.fromkeys(identities):
                physical = next(line for line in package['lines'] if line['id'] == line_id)
                codes = {station[0] for station in physical['stations']}
                if leg['fromStationCode'] not in codes or leg['toStationCode'] not in codes:
                    raise ValueError('Curated service boundary not on physical line')
                entry = lines[line_id]
                for alias in [corridor['name'], corridor['serviceCode']]:
                    if alias not in entry['aliases']: entry['aliases'].append(alias)
                for label in labels:
                    scope = corridor['name'] + ': ' + section_note + ' [' + leg['fromStationCode'] + '–' + leg['toStationCode'] + ']'
                    add(line_id, label, url, scope=scope, from_code=leg['fromStationCode'], to_code=leg['toStationCode'])
                    entry['kinds'][-1]['observedOn'] = OBSERVED
    airport_legs = [dict(leg) for leg in corridors['hokkaido-airport-otaru']['legs']]
    airport_legs[0]['fromStationCode'] = '000227' # Sapporo; no special-rapid claim west to Otaru.
    reviewed_corridor('hokkaido-airport-otaru', ['普通','快速','特別快速','区間快速'],
        'https://www.jrhokkaido.co.jp/airport/index.html',
        'Official Airport stop guide explicitly labels all four classes; scoped Sapporo–New Chitose Airport. Effective interval not established.', airport_legs)
    reviewed_corridor('hokkaido-airport-otaru', ['快速'],
        'https://www.jrhokkaido.co.jp/airport/index.html',
        'Official Airport page identifies rapid Airport Otaru through service; no assertion of all classes to Otaru.')
    reviewed_corridor('seto-marine-liner', ['快速'],
        'https://www.jr-shikoku.co.jp/01_trainbus/vehicle-info/marine.html',
        'Official page explicitly names rapid Marine Liner Okayama–Takamatsu; complete class inventory and effective interval unknown.')
    reviewed_corridor('tohoku-joban-sendai', ['普通'],
        'https://timetables.jreast.co.jp/2610/timetable/tt1259/1259010.html',
        'October 2026 Haranomachi station timetable explicitly labels unmarked Sendai services 普通; no inferred other regional lines.')
    reviewed_corridor('tohoku-sendai-airport', ['普通'],
        'https://www.senat.co.jp/question',
        'Official FAQ explicitly identifies 普通列車 and its Sendai–Sendai Airport stop list; no effective-date guarantee.')
    # Shinjuku timetable explicitly lists 普通/快速/特別快速. Restrict all three to
    # the shared 大船–大宮 core; do not assign 特別快速 to the 宇都宮–逗子 branch.
    js_legs = [dict(leg) for leg in corridors['JS-utsunomiya-zushi']['legs'][:6]]
    js_legs[0]['fromStationCode'] = '002914' # Omiya
    reviewed_corridor('JS-utsunomiya-zushi', ['普通','快速','特別快速'],
        'https://timetables.jreast.co.jp/2610/timetable/tt0866/0866080.html',
        'October 2026 published Shinjuku class legend and reviewed JS core 大船–大宮. Class can change by segment; branches remain separately researched.', js_legs)
    # Tokyo JK source confirms both classes; reviewed corridor anchors bind them
    # to the operating system, not other Tohoku/Tokaido trains.
    reviewed_corridor('JK', ['普通','快速'],
        'https://timetables.jreast.co.jp/2610/timetable/tt1039/1039140.html',
        'October 2026 Tokyo JK timetable explicitly labels 普通 and 快速. 快速 designation applies to the operating system; actual skipped stops are confined to its central section.')
    reviewed_corridor('hanshin-sanyo', ['直通特急'],
        'https://www.sanyo-railway.co.jp/railway/express.html',
        'Official through express timetable explicitly covers Sanyo-Himeji–Hanshin Osaka-Umeda; no other class inferred.')
    # Two small manual factual excerpts, not a full reproduction of the timetable.
    by_name={s[1]:s[0] for l in package['lines'] for s in l['stations'] if l['operator']=='西日本旅客鉄道'}
    def stop(name,arrival,departure):
        def seconds(v):
            if v is None: return None
            h,m=map(int,v.split(':')); return h*3600+m*60
        return dict(stationCode=by_name[name],stationName=name,arrivalSeconds=seconds(arrival),departureSeconds=seconds(departure))
    def trip(number,kind,url,rows):
        return dict(id='jr-west-'+number+'-20261004-excerpt',trainNumber=number,trainType=kind,operatorName='西日本旅客鉄道',lineIDs=[main],serviceDates=['2026-10-04'],sourceURL=url,coverage='partial',note='Manual excerpt of published scheduled times for this date only; omitted stations and dates are unknown. Not an actual-operation report.',stops=[stop(*row) for row in rows])
    trips=[trip('102C','普通','https://timetable.jr-odekake.net/train-timetable/173421?date=20261004', [('大阪','06:10','06:12'),('新大阪','06:15','06:16')]),
           trip('3408M','新快速','https://timetable.jr-odekake.net/train-timetable/173041?date=20261004',[('大阪','07:28','07:30'),('新大阪','07:33','07:34'),('高槻','07:45','07:46'),('京都','07:59','08:00')])]
    for t in trips:
        add(main,t['trainType'],t['sourceURL'],'2026-10-04','2026-10-05','JR京都線 published trip excerpt 大阪–京都')
    return dict(schemaVersion=1,inventoryVersion=package['version'],observedOn=max([OBSERVED] + [kind['observedOn'] for line in lines.values() for kind in line['kinds']]),lines=list(lines.values()),trips=trips)

def merge_reviewed(artifact, overlay):
    """Merge explicit reviewed ODPT imports; never create unknown physical IDs."""
    if overlay.get('schemaVersion') != 1 or overlay.get('inventoryVersion') != artifact['inventoryVersion']:
        raise ValueError('Reviewed input schema/package version mismatch')
    registry = {line['lineID']: line for line in artifact['lines']}
    def date(value):
        if datetime.date.fromisoformat(value).isoformat() != value:
            raise ValueError('Invalid reviewed date')
        return value
    evidence_ids = {kind['id']: kind for line in artifact['lines'] for kind in line['kinds']}
    trip_ids = {trip['id'] for trip in artifact['trips']}
    for line in overlay['lines']:
        original = registry.get(line['lineID'])
        if original is None or original['operatorName'] != line['operatorName']:
            raise ValueError('Reviewed line/operator identity mismatch')
        if not line['kinds'] or line['coverage'] != 'partial':
            raise ValueError('Reviewed coverage requires evidence')
        for kind in line['kinds']:
            if not kind['sourceURL'].startswith('https://') or not kind['trainType'] or not kind['scope']:
                raise ValueError('Reviewed service provenance missing')
            start = date(kind['validFrom']) if kind.get('validFrom') else None
            end = date(kind['validUntil']) if kind.get('validUntil') else None
            if start and end and start >= end:
                raise ValueError('Invalid reviewed validity interval')
            date(kind['observedOn'])
            if kind['id'] in evidence_ids:
                if evidence_ids[kind['id']] != kind:
                    raise ValueError('Conflicting reviewed evidence identity')
            else:
                original['kinds'].append(kind)
                evidence_ids[kind['id']] = kind
        original['coverage'] = 'partial'
        original['note'] = 'Partial reviewed service inventory; imported dates and sections only.'
    for trip in overlay['trips']:
        if not trip['id'] or trip['id'] in trip_ids or not trip['sourceURL'].startswith('https://'):
            raise ValueError('Duplicate trip identity or missing provenance')
        if not trip['lineIDs'] or any(lid not in registry or registry[lid]['operatorName'] != trip['operatorName'] for lid in trip['lineIDs']):
            raise ValueError('Reviewed trip line/operator mismatch')
        if not trip['serviceDates'] or not all(date(day) for day in trip['serviceDates']):
            raise ValueError('Reviewed trip calendar missing')
        if trip['coverage'] != 'partial' or len(trip['stops']) < 2:
            raise ValueError('Reviewed timetable coverage invalid')
        previous = -1
        for stop in trip['stops']:
            times = [stop[key] for key in ['arrivalSeconds', 'departureSeconds'] if stop.get(key) is not None]
            if not times or any(not isinstance(value, int) or value < previous for value in times) or times != sorted(times):
                raise ValueError('Reviewed times are not chronological')
            previous = max(times)
        trip_ids.add(trip['id'])
        artifact['trips'].append(trip)
    artifact['observedOn'] = max(artifact.get('observedOn', ''), overlay.get('observedOn', ''))
    return artifact


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--reviewed-input', action='append', type=Path, default=[], help='Normalized reviewed overlay from import-odpt-line-services.py; repeatable')
    args=parser.parse_args()
    artifact=build()
    manifest_path = ROOT / 'app/data/conventional-timetable/manifest.json'
    reviewed = []
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        if manifest.get('schemaVersion') != 1:
            raise ValueError('Unsupported conventional timetable input manifest')
        reviewed = [ROOT / entry['path'] for entry in manifest['inputs']]
    for path in dict.fromkeys(path.resolve() for path in reviewed + args.reviewed_input):
        artifact=merge_reviewed(artifact,json.loads(path.read_text()))
    content=json.dumps(artifact,ensure_ascii=False,indent=2)+'\n'
    if args.check:
        if OUT.read_text()!=content: raise SystemExit('Service catalog is stale: rebuild with this script')
    else: OUT.write_text(content)
    print(f"{len(artifact['lines'])} lines; {sum(l['coverage']=='partial' for l in artifact['lines'])} partial; {len(artifact['trips'])} dated timetable excerpts")
if __name__=='__main__': main()
