#!/usr/bin/env python3
"""Capture the native macOS Apple Maps app; never opens a web map."""
import argparse
from functools import lru_cache
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import re
import numpy as np
import subprocess
import sys
import time
from PIL import Image, ImageChops, ImageStat

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
DEFAULT_OUT = REPO / 'outputs/apple-maps-rail'
REFERENCE_MPP = 250 / 87  # Approximate measured 0–250 m span in supplied reference.

class ScreenLockedError(RuntimeError):
    """Capture pauses for a manual unlock; never attempts to unlock the Mac."""

class TileCaptureError(RuntimeError):
    """A single tile cannot be validated; preserve it for retry, never classify it."""


def run(*args):
    try:
        p = subprocess.run([str(a) for a in args], text=True, capture_output=True, timeout=60)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f'Native command timed out: {args[0]}') from error
    if p.returncode:
        raise RuntimeError(p.stderr.strip() or p.stdout.strip() or f'{args[0]} failed ({p.returncode})')
    return p.stdout

def save_json(path, data):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    temp.replace(path)

@lru_cache(maxsize=1)
def rail_stations():
    from planner import _eligible
    stations=[]
    for country in ('us','ca'):
        for line in json.loads((REPO/f'app/public/rail/{country}-2025.json').read_text())['lines']:
            if _eligible(line):
                stations.extend((station[1],station[3],station[2]) for station in line.get('stations',[]) if len(station)>3)
    return stations


def camera_alignment(info, im, lat, lon, mpp):
    """Measure actual station icon displacement from the intended map center."""
    def station_key(name):
        name=re.sub(r'\s+(?:subway\s+|railway\s+)?station$','',name.strip(),flags=re.I)
        return re.sub(r'[^\w]','',name.casefold())
    by_name={}
    for name,slat,slon in rail_stations():
        if abs(slat-lat)<.12 and abs(slon-lon)<.16:
            by_name.setdefault(station_key(name),[]).append((slat,slon))
    bounds=info['window_bounds']; sx=im.width/bounds['Width'];sy=im.height/bounds['Height']
    matches={}
    for element in info['elements']:
        if element['id']!='VKPointFeature':continue
        # Neighborhood labels can share station names; transit icons include
        # route details after a comma, whereas those labels do not.
        if ',' not in element['description']:continue
        name=element['description'].split(',')[0].strip()
        options=by_name.get(station_key(name),[])
        if not options:continue
        slat,slon=min(options,key=lambda p:(p[0]-lat)**2+(p[1]-lon)**2)
        x,y,w,h=element['rect']
        observed_x=(x+w/2-bounds['X'])*sx
        observed_y=(y+h/2-bounds['Y'])*sy
        if not (0<observed_x<im.width and 0<observed_y<im.height):continue
        east=(slon-lon)*111320*math.cos(math.radians(lat))
        north=(slat-lat)*111320
        matches[name]=(observed_x-(im.width/2+east/mpp),observed_y-(im.height/2-north/mpp))
    if len(matches)<3:
        raise RuntimeError('Need at least three identified rail stations to verify native map centering. Probe Toronto at the default coordinate.')
    dx=statistics.median(v[0] for v in matches.values());dy=statistics.median(v[1] for v in matches.values())
    madx=statistics.median(abs(v[0]-dx) for v in matches.values());mady=statistics.median(abs(v[1]-dy) for v in matches.values())
    if max(madx,mady)>30:
        raise RuntimeError('Station coordinates disagree with native map projection; camera alignment is not verified.')
    return {'station_matches':len(matches),'residual_offset_pixels':[dx,dy],
            'median_absolute_deviation_pixels':[madx,mady],'station_names':sorted(matches)}


def corrected_coordinate(lat,lon,mpp,offset):
    return (lat-offset[1]*mpp/111320,
            lon+offset[0]*mpp/(111320*math.cos(math.radians(lat))))

class NativeMaps:
    def __init__(self, out):
        self.out = Path(out); self.out.mkdir(parents=True, exist_ok=True)
        self.helper = self.out / 'native-helper'
        source = HERE / 'native.swift'
        if not self.helper.exists() or self.helper.stat().st_mtime < source.stat().st_mtime:
            run('xcrun', 'swiftc', '-module-cache-path', self.out / 'module-cache', source, '-o', self.helper)
    def session(self):
        return json.loads(run(self.helper,'session'))
    def info(self):
        for attempt in range(3):
            if self.session()['locked']:raise ScreenLockedError('The Mac is locked. Unlock it manually to resume native Maps capture.')
            try:return json.loads(run(self.helper, 'info'))
            except RuntimeError as error:
                if 'No visible Maps window' not in str(error):raise
                if attempt==2:raise TileCaptureError('Native Maps window is not visible after reactivation') from error
                run('/usr/bin/osascript','-e','tell application id "com.apple.Maps" to activate')
                time.sleep(1)
    def press(self, name):
        run(self.helper, 'press', name)
    def open(self, lat, lon, zoom):
        if self.session()['locked']:raise ScreenLockedError('The Mac is locked. Unlock it manually to resume native Maps capture.')
        if not (-85 < lat < 85 and -180 <= lon <= 180 and 1 <= zoom <= 21):
            raise ValueError('Invalid map coordinate or zoom')
        # Explicit bundle ID forces the installed native Maps app, regardless of browser defaults.
        run('/usr/bin/open', '-b', 'com.apple.Maps', f'maps://?ll={lat:.7f},{lon:.7f}&z={zoom:.5f}&t=r')
        run('/usr/bin/osascript','-e','tell application id "com.apple.Maps" to activate')
    def prepare(self):
        info = self.info()
        if not info['screen_recording']:
            raise RuntimeError('Screen Recording access is required for the terminal running this script. Enable it in System Settings > Privacy & Security > Screen Recording and retry.')
        self.press('com.apple.menu.view')
        info = self.info()
        titles = {e['title'] for e in info['elements']}
        # These are idempotent actions: never toggle an already displayed scale off.
        for alternatives in [('Show Scale', '顯示縮放比例', '显示比例尺'), ('Hide Sidebar', '隱藏側邊欄', '隐藏边栏'), ('Face North', '朝向北方', '朝北')]:
            choice = next((x for x in alternatives if x in titles), None)
            if choice:
                self.press(choice)
                time.sleep(.25)
                self.press('com.apple.menu.view')
                titles = {e['title'] for e in self.info()['elements']}
        # Close menu via AXCancel (implemented by helper), without synthetic keystrokes.
        run(self.helper, 'cancel-menu')
    def snapshot(self, path):
        info = self.info()
        maps = [e for e in info['elements'] if 'VKMapTypeTransit' in e['value']]
        if maps and json.loads(maps[0]['value']).get('time') != 'Night':
            raise RuntimeError('The offline sorter requires dark Maps appearance. Switch to dark appearance, then rerun.')
        if not maps:
            raise RuntimeError('Native Maps is not in transit view; refusing to classify a different map style.')
        if any(e['id'] in ('HomeView','SearchHomeView') and e['rect'][2] > 100 and e['rect'][3] > 100 for e in info['elements']):
            raise RuntimeError('Maps search/sidebar overlay is visible. Hide it and rerun probe.')
        run('/usr/sbin/screencapture', '-x', '-o', '-l', info['window_id'], path)
        im = Image.open(path).convert('RGB')
        if min(im.size) < 300:
            raise RuntimeError('Maps window is too small')
        return info, im
    def settled(self, path, minimum=2.0, timeout=20.0):
        time.sleep(minimum)
        started = time.monotonic(); previous = None; stable = 0
        while time.monotonic() - started < timeout:
            info, im = self.snapshot(path)
            thumb = im.crop((100,100,im.width-100,im.height-100)).resize((160,90))
            # A stable blank/loading frame is not a valid map capture.
            texture = sum(ImageStat.Stat(thumb).stddev)
            if previous is not None:
                delta = sum(ImageStat.Stat(ImageChops.difference(previous,thumb)).mean) / 3
                stable = stable + 1 if delta < .65 and texture > .8 else 0
                # Forest and undeveloped land can contain only faint polygon
                # boundaries. Require a longer stable sequence for these views;
                # a uniform loading frame still has zero texture and is rejected.
                if stable >= (2 if texture > 3 else 6):
                    info['capture_validation']={'texture_score':round(texture,4),'stable_frames':stable}
                    return info, im
            previous = thumb
            time.sleep(.65)
        raise TileCaptureError('Maps did not finish rendering a textured, stable map within the timeout')
    def scale(self, im, tight=False):
        # Native Maps places its scale at top centre. OCR only this strip, enlarged
        # for reliable recognition; numbers are read with character-range boxes.
        box = ((int(im.width/2)-130,40,int(im.width/2)+130,80) if tight else (int(im.width*.39),25,int(im.width*.61),95))
        strip = im.crop(box)
        scale_path = self.out / 'scale-ocr.png'
        strip.resize((strip.width*4,strip.height*4)).save(scale_path)
        # Remove colored POI labels that can merge with scale numerals.
        pixels=np.asarray(strip.resize((strip.width*4,strip.height*4)).convert('RGB')).astype(float)
        maximum=pixels.max(2); minimum=pixels.min(2)
        text_mask=((maximum-minimum)<maximum*(.28 if tight else .18))&(maximum>(165 if tight else 140))
        if tight:
            strip.resize((strip.width*6,strip.height*6)).save(scale_path)
        else:
            Image.fromarray(np.where(text_mask,255,0).astype('uint8')).save(scale_path)
        lines = json.loads(run(self.helper, 'ocr', scale_path))
        text=' '.join(line['text'] for line in lines)
        if re.search(r'\b(ft|feet|mi|mile|km)\b|英尺|英里|公里',text,re.I):
            raise RuntimeError('Scale is not in metres; switch Maps to metric units before capture')
        words = [w for line in lines for w in line.get('words', [])]
        numbers=[]
        for w in words:
            try: value=float(w['text'])
            except ValueError: continue
            x,y,width,height=w['box']
            if value not in (0,25,50,75,100,125,150,200,250,300,375,500,750,1000): continue
            if height*strip.height > 24: continue
            numbers.append((value,(x+width/2)*strip.width,(y+height/2)*strip.height))
        # The scale is translucent, so OCR can merge its last number with the
        # unit. Measure its FIRST filled segment against the numeral above the
        # segment end. This works even when the final number/unit merges.
        raw=np.asarray(im.convert('RGB')).astype(float)
        left=int(im.width/2)-150; right=int(im.width/2)+150
        band=raw[65:70,left:right]; maximum=band.max(2); minimum=band.min(2)
        bar_mask=((maximum-minimum)<maximum*.65)&(minimum>95)&(maximum>120)
        bars=[]
        for row in bar_mask:
            start=None
            for x,active in enumerate([*row,False]):
                if active and start is None: start=x
                if not active and start is not None:
                    length=x-start
                    if 18<=length<=140:
                        absolute_end=left+x
                        for value,nx,ny in numbers:
                            if value>0 and abs(box[0]+nx-absolute_end)<6 and abs(box[1]+ny-56)<9:
                                bars.append(value/length)
                    start=None
        if bars:
            mpp=statistics.median(bars)
            if .3<mpp<20 and all(abs(x/mpp-1)<.08 for x in bars):
                return {'meters_per_pixel':mpp,'ocr':[x['text'] for x in lines],
                        'tick_candidates':numbers,'method':'OCR tick + measured scale segment'}
        candidates=[]
        for a in numbers:
            for b in numbers:
                if b[0]>a[0] and 15 < b[1]-a[1] < 180 and abs(a[2]-b[2])<5:
                    mpp=(b[0]-a[0])/(b[1]-a[1])
                    if .3<mpp<20: candidates.append(mpp)
        if not candidates:
            raise TileCaptureError('Cannot read metric scale ticks. Enable View > Show Scale, use metric units, and leave the Maps window unobstructed.')
        mpp=statistics.median(candidates)
        if any(abs(x/mpp-1)>.18 for x in candidates):
            raise TileCaptureError('Scale OCR produced inconsistent tick spacing; capture was not accepted')
        return {'meters_per_pixel':mpp,'ocr':[x['text'] for x in lines],'tick_candidates':numbers}

def calibrate(native, lat, lon, zoom, target, filename, offset=(0,0)):
    for attempt in range(6):
        request_lat,request_lon=corrected_coordinate(lat,lon,target,offset)
        native.open(request_lat,request_lon,zoom)
        info,im=native.settled(filename)
        try:
            scale=native.scale(im)
        except TileCaptureError:
            # Retry text recognition with a tighter mask before discarding a tile.
            scale=native.scale(im, tight=True)
        ratio=scale['meters_per_pixel']/target
        if abs(ratio-1)<.07:
            return zoom,info,im,scale
        zoom += math.log2(ratio)
    raise TileCaptureError('Native Maps zoom did not converge to the reference scale')

def capture_when_unlocked(native, tile, zoom, config, path, status):
    while True:
        try:
            return calibrate(native,tile['lat'],tile['lon'],zoom,config['target_meters_per_pixel'],path,
                             offset=config.get('coordinate_offset_pixels',(0,0)))
        except ScreenLockedError:
            status('paused_locked',tile['city'])
            print('Paused: unlock the Mac manually to resume.',flush=True)
            while native.session()['locked']:time.sleep(30)
            status('running',tile['city'])

def probe(args):
    native=NativeMaps(args.out)
    native.open(args.lat,args.lon,16.28)
    time.sleep(1)
    native.prepare()
    target=args.meters_per_pixel
    path=Path(args.out)/'probe-toronto.png'
    zoom,info,im,scale=calibrate(native,args.lat,args.lon,16.28,target,path)
    offset=camera_alignment(info,im,args.lat,args.lon,scale['meters_per_pixel'])['residual_offset_pixels']
    for attempt in range(3):
        zoom,info,im,scale=calibrate(native,args.lat,args.lon,zoom,target,path,offset=offset)
        alignment=camera_alignment(info,im,args.lat,args.lon,scale['meters_per_pixel'])
        residual=alignment['residual_offset_pixels']
        if max(abs(v) for v in residual)<20:break
        offset=[offset[0]+residual[0],offset[1]+residual[1]]
    else:raise RuntimeError('Native map center correction did not converge')
    config={'version':2,'coordinate_offset_pixels':offset,
            'coordinate_alignment_verified':True,'alignment_validation':alignment,'latitude':args.lat,'longitude':args.lon,'zoom':zoom,
            'target_meters_per_pixel':target,'measured_meters_per_pixel':scale['meters_per_pixel'],
            'image_size':list(im.size),'window_size':[info['window_bounds']['Width'],info['window_bounds']['Height']],
            'scale':scale,'created_at':time.strftime('%Y-%m-%dT%H:%M:%S%z'),
            'reference':'Supplied reference: 250 metres across approximately 87 image pixels',
            'inner_margin_px':100}
    save_json(Path(args.out)/'calibration.json',config)
    print(json.dumps(config,indent=2,ensure_ascii=False))
    print(f'Native probe saved: {path}')

def plan(args):
    from planner import plan_tiles
    calibration=json.loads((Path(args.out)/'calibration.json').read_text())
    catalog=json.loads((HERE/'cities.json').read_text())
    width,height=calibration['image_size']; mpp=calibration['target_meters_per_pixel']
    ids=args.cities.split(',') if args.cities else None
    tiles=plan_tiles(catalog['cities'],city_ids=ids,width_m=(width-200)*mpp,height_m=(height-200)*mpp,
                     overlap=args.overlap,mode=args.mode,
                     supplemental_dir=Path(args.out)/'network-cache',
                     rail_files=[REPO/'app/public/rail/us-2025.json',REPO/'app/public/rail/ca-2025.json'])
    payload={'version':2,'calibration':calibration,'mode':args.mode,'overlap':args.overlap,'tiles':tiles,
             'selected_city_ids':ids if ids is not None else [city['id'] for city in catalog['cities']],
             'coverage_note':'Metros scans curated metro boxes plus whole matched commuter corridors. Corridors is a faster inventory-only option. Catalog bounds still require review for geographic completeness.'}
    save_json(Path(args.out)/'plan.json',payload)
    counts={}
    for t in tiles: counts[t['city']]=counts.get(t['city'],0)+1
    print(json.dumps({'tiles':len(tiles),'city_counts':counts,'minimum_hours_at_4_seconds_per_tile':round(len(tiles)*4/3600,2),'plan':str(Path(args.out)/'plan.json')},indent=2))

def capture(args):
    from classify import classify_image
    out=Path(args.out).resolve()
    plan_data=json.loads((out/'plan.json').read_text()); config=plan_data['calibration']
    if not config.get('coordinate_alignment_verified') and not getattr(args,'one_per_city',False):
        raise RuntimeError('This plan predates native camera alignment verification. Run probe and plan before the full capture.')
    native=NativeMaps(out)
    lock=out/'capture.lock'
    try: fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    except FileExistsError: raise RuntimeError(f'Capture lock exists at {lock}. Check no other capture is running before removing a stale lock.')
    os.write(fd,str(os.getpid()).encode()); os.close(fd)
    try:
        for folder in ('rail','no_rail','pending'): (out/folder).mkdir(exist_ok=True)
        # Local rail station identities strengthen visual sorting without treating
        # route presence in the planner as proof of rail in the actual screenshot.
        stations=rail_stations()
        completed={}
        journal=out/'manifest.jsonl'
        if journal.exists():
            for line in journal.read_text().splitlines():
                try: row=json.loads(line)
                except json.JSONDecodeError: continue
                completed[row['id']]=row
        tiles=plan_data['tiles']
        if getattr(args,'one_per_city',False):
            grouped={}
            for tile in tiles:
                for city in tile.get('cities',[tile['city']]):
                    grouped.setdefault(city,[]).append(tile)
            # Prefer dense rail junctions for the native app readiness test.
            catalog={c['id']:c for c in json.loads((HERE/'cities.json').read_text())['cities']}
            representatives=[]
            for city,group in grouped.items():
                bounds=catalog[city]['bounds'][0]
                center_lat=(bounds[0]+bounds[2])/2;center_lon=(bounds[1]+bounds[3])/2
                local=[t for t in group if any(b[0]<=t['lat']<=b[2] and b[1]<=t['lon']<=b[3] for b in catalog[city]['bounds'])]
                representatives.append(max(local or group,key=lambda t:(len(t.get('rail_lines',[])),
                    -((t['lat']-center_lat)**2+(t['lon']-center_lon)**2))))
            tiles=representatives
        active_ids={hashlib.sha256(json.dumps({'tile':tile,'calibration':config},sort_keys=True).encode()).hexdigest()[:20] for tile in plan_data['tiles']}
        count=0; failures=[]; consecutive_failures=0; last_hash=None; started=time.time()
        def status(state,current=None):
            save_json(out/'status.json',{'state':state,'pid':os.getpid(),
                'started_at':started,'updated_at':time.time(),'planned_tiles':len(plan_data['tiles']),
                'selected_tiles':len(tiles),'completed_total':len(active_ids.intersection(completed)),'new_this_run':count,
                'failed_this_run':len(failures),'current_city':current,
                'elapsed_seconds':round(time.time()-started,1)})
        status('running')
        for tile in tiles:
            identity=hashlib.sha256(json.dumps({'tile':tile,'calibration':config},sort_keys=True).encode()).hexdigest()[:20]
            if identity in completed and (out/completed[identity]['file']).exists(): continue
            metadata=out/'metadata'/f'{identity}.json'
            if metadata.exists():
                recovered=json.loads(metadata.read_text())
                if (out/recovered['file']).exists():
                    with journal.open('a') as f: f.write(json.dumps(recovered,ensure_ascii=False)+'\n')
                    completed[identity]=recovered
                    continue
            if args.limit is not None and count>=args.limit: break
            zoom=config['zoom']+math.log2(math.cos(math.radians(tile['lat']))/math.cos(math.radians(config['latitude'])))
            path=out/'pending'/f'{tile["city"]}-{identity}.png'
            status('running',tile['city'])
            while native.session()['locked']:
                status('paused_locked',tile['city'])
                print('Paused: unlock the Mac manually to resume.',flush=True)
                time.sleep(30)
            for attempt in range(1,getattr(args,'retries',2)+2):
                try:
                    zoom,info,im,scale=capture_when_unlocked(native,tile,zoom,config,path,status)
                    break
                except TileCaptureError as error:
                    if attempt<=getattr(args,'retries',2):
                        print(f'Retrying {tile["city"]} {identity}: {error}',flush=True)
                        continue
                    failure={'id':identity,'tile':tile,'error':str(error),'attempts':attempt,'failed_at':time.time()}
                    failures.append(failure);consecutive_failures+=1
                    with (out/'failures.jsonl').open('a') as f:f.write(json.dumps(failure)+'\n')
                    print(f'FAILED {tile["city"]} {identity}: {error}',flush=True)
            else:
                status('running',tile['city'])
                if consecutive_failures>=5:
                    status('failed',tile['city'])
                    raise RuntimeError('Five consecutive tiles failed validation; stopped for inspection. Unvalidated images remain in pending/.')
                continue
            consecutive_failures=0
            if list(im.size)!=config['image_size']:
                raise RuntimeError('Maps window dimensions changed. Rerun probe and plan before continuing.')
            digest=hashlib.sha256(im.tobytes()).hexdigest()
            if digest==last_hash: raise RuntimeError('Two different map targets returned identical screenshots. Capture stopped to avoid silently saving stale frames.')
            last_hash=digest
            ax_descriptions=[e['description'] for e in info['elements'] if e['id']=='VKPointFeature']
            half_lat=im.height*scale['meters_per_pixel']/2/111320
            half_lon=im.width*scale['meters_per_pixel']/2/(111320*math.cos(math.radians(tile['lat'])))
            nearby_stations=sorted({name for name,lat,lon in stations if abs(lat-tile['lat'])<half_lat and abs(lon-tile['lon'])<half_lon})
            evidence={'ax_descriptions':ax_descriptions,'rail_lines':tile.get('rail_lines',[]),'known_rail_stations':nearby_stations}
            result=classify_image(path,evidence=evidence)
            destination=out/result['label']/path.name
            if destination.exists(): raise RuntimeError(f'Refusing to overwrite {destination}')
            row={'id':identity,'tile':tile,'file':str(destination.relative_to(out)),'classification':result,
                 'scale':scale,'render_validation':info.get('capture_validation',{}),'evidence':evidence,'zoom':zoom,'requested_coordinate':corrected_coordinate(tile['lat'],tile['lon'],config['target_meters_per_pixel'],config.get('coordinate_offset_pixels',(0,0))),'sha256':digest,'captured_at':time.strftime('%Y-%m-%dT%H:%M:%S%z')}
            save_json(metadata,row)
            path.replace(destination)
            with journal.open('a') as f: f.write(json.dumps(row,ensure_ascii=False)+'\n'); f.flush(); os.fsync(f.fileno())
            count+=1
            completed[identity]=row
            status('running',tile['city'])
            print(f'{count}: {tile["city"]} → {result["label"]} (review={result["needs_review"]})',flush=True)
        status('finished_with_failures' if failures else ('complete' if len(active_ids.intersection(completed))>=len(plan_data['tiles']) else 'batch_finished'))
        print(f'Captured {count} new images; {len(failures)} failed. Output: {out}')
        if failures:
            raise RuntimeError(f'{len(failures)} tiles failed validation; rerun capture to retry unsaved tiles.')
    except BaseException as error:
        if 'status' in locals():
            status('paused_locked' if isinstance(error,ScreenLockedError) else ('interrupted' if isinstance(error,KeyboardInterrupt) else 'failed'))
        raise
    finally:
        lock.unlink(missing_ok=True)

def resort(args):
    """Reclassify journaled captures while retaining original capture evidence."""
    from classify import classify_image
    out=Path(args.out).resolve()
    if (out/'capture.lock').exists():
        raise RuntimeError('Stop capture before resorting its images.')
    journal=out/'manifest.jsonl'
    rows={}
    for line in journal.read_text().splitlines():
        try: row=json.loads(line)
        except json.JSONDecodeError: continue
        rows[row['id']]=row
    counts={'rail':0,'no_rail':0,'moved':0,'missing':0}
    for identity,row in rows.items():
        source=out/row['file']
        if not source.exists():
            counts['missing']+=1
            continue
        result=classify_image(source,evidence=row.get('evidence',{}))
        destination=out/result['label']/source.name
        destination.parent.mkdir(parents=True,exist_ok=True)
        if destination!=source and destination.exists():
            raise RuntimeError(f'Refusing to overwrite {destination}')
        updated={**row,'file':str(destination.relative_to(out)),'classification':result,
                 'reclassified_at':time.strftime('%Y-%m-%dT%H:%M:%S%z')}
        save_json(out/'metadata'/f'{identity}.json',updated)
        if destination!=source:
            source.replace(destination)
            counts['moved']+=1
        with journal.open('a') as handle:
            handle.write(json.dumps(updated,ensure_ascii=False)+'\n')
            handle.flush();os.fsync(handle.fileno())
        counts[result['label']]+=1
    print(json.dumps(counts,indent=2))

def fetch(args):
    command=[sys.executable,str(HERE/'fetch_networks.py'),'--out',str(Path(args.out)/'network-cache')]
    for attempt in range(3):
        result=subprocess.run(command)
        if result.returncode==0:return
        if attempt==2:raise subprocess.CalledProcessError(result.returncode,command)
        print('Retrying missing network downloads in 30 seconds; successful caches are retained.',flush=True)
        time.sleep(30)

def audit_plan(args):
    subprocess.run([sys.executable,str(HERE/'audit_coverage.py'),'--plan',str(Path(args.out)/'plan.json'),
        '--network-cache',str(Path(args.out)/'network-cache'),'--output',str(Path(args.out)/'coverage-audit.json')],check=True)

def all_cities(args):
    """Run the complete workflow; a locked desktop waits for a manual unlock."""
    out=Path(args.out).resolve()
    out.mkdir(parents=True,exist_ok=True)
    lock=out/'workflow.lock'
    try: fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    except FileExistsError: raise RuntimeError(f'Workflow already locked at {lock}; check the recorded PID before starting another run.')
    os.write(fd,str(os.getpid()).encode());os.close(fd)
    def stage(name,error=None):
        save_json(out/'workflow-status.json',{'stage':name,'pid':os.getpid(),
            'updated_at':time.time(),'error':error})
        print(f'Workflow: {name}',flush=True)
    try:
        stage('fetching_networks');fetch(args)
        native=NativeMaps(out)
        while native.session()['locked']:
            stage('waiting_for_manual_unlock')
            time.sleep(30)
        path=out/'calibration.json'
        config=json.loads(path.read_text()) if path.exists() else {}
        if not config.get('coordinate_alignment_verified') or config.get('version',0)<2:
            stage('calibrating_native_maps')
            probe(argparse.Namespace(out=out,lat=43.6825,lon=-79.391,meters_per_pixel=REFERENCE_MPP))
        stage('planning_all_networks')
        plan(argparse.Namespace(out=out,cities=None,mode='metros',overlap=.2))
        stage('auditing_coverage');audit_plan(args)
        capture_args=argparse.Namespace(out=out,limit=None,retries=2,one_per_city=True)
        stage('testing_one_tile_per_metro');capture(capture_args)
        capture_args.one_per_city=False
        stage('capturing_all_tiles');capture(capture_args)
        stage('capture_complete')
    except BaseException as error:
        stage('interrupted' if isinstance(error,KeyboardInterrupt) else 'failed',str(error))
        raise
    finally:
        lock.unlink(missing_ok=True)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,default=DEFAULT_OUT)
    sub=p.add_subparsers(dest='command',required=True)
    q=sub.add_parser('probe',help='Probe native Maps and calibrate the reference scale')
    q.add_argument('--lat',type=float,default=43.6825);q.add_argument('--lon',type=float,default=-79.391)
    q.add_argument('--meters-per-pixel',type=float,default=REFERENCE_MPP)
    q.set_defaults(func=probe)
    q=sub.add_parser('plan',help='Build a resumable tile plan; does not drive Maps')
    q.add_argument('--cities',help='Comma-separated catalog IDs; default all')
    q.add_argument('--mode',choices=['metros','corridors','areas'],default='metros')
    q.add_argument('--overlap',type=float,default=.2);q.set_defaults(func=plan)
    q=sub.add_parser('capture',help='Capture planned tiles in native Maps and sort them')
    q.add_argument('--limit',type=int,help='Maximum NEW images in this run')
    q.add_argument('--one-per-city',action='store_true',help='Validate one representative planned screenshot in each metro')
    q.add_argument('--retries',type=int,default=2,help='Retries per tile before recording a validation failure')
    q.set_defaults(func=capture)
    q=sub.add_parser('fetch',help='Fetch supplemental full route geometries for all catalog metros')
    q.set_defaults(func=fetch)
    q=sub.add_parser('audit',help='Check area and complete line geometry coverage of the saved plan')
    q.set_defaults(func=audit_plan)
    q=sub.add_parser('resort',help='Reclassify existing journaled screenshots using their saved evidence')
    q.set_defaults(func=resort)
    q=sub.add_parser('all',help='Fetch, calibrate, plan, audit, test each metro, then capture every tile')
    q.set_defaults(func=all_cities)
    q=sub.add_parser('cities',help='List metro IDs and their rail systems')
    q.set_defaults(func=lambda a:print('\n'.join(c['id']+' — '+c['name']+': '+', '.join(c['systems']) for c in json.loads((HERE/'cities.json').read_text())['cities'])))
    args=p.parse_args()
    if getattr(args,'limit',None) is not None and args.limit<1: p.error('--limit must be positive')
    if getattr(args,'retries',0)<0: p.error('--retries must be nonnegative')
    if getattr(args,'meters_per_pixel',1)<=0: p.error('--meters-per-pixel must be positive')
    try: args.func(args)
    except KeyboardInterrupt: print('\nStopped. Rerun capture to resume.',file=sys.stderr);sys.exit(130)
    except (RuntimeError,ValueError,OSError,subprocess.CalledProcessError) as e: print(f'Error: {e}',file=sys.stderr);sys.exit(1)
if __name__=='__main__': main()
