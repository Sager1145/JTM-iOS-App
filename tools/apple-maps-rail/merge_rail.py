#!/usr/bin/env python3
"""Assemble saved rail captures into geographic PNG/GeoTIFF mosaics and a viewer."""
import argparse
from collections import OrderedDict, defaultdict
from datetime import datetime
import json
import math
from pathlib import Path
import shutil
import time

import numpy as np
from PIL import Image
import tifffile

HERE=Path(__file__).resolve().parent
DEFAULT=HERE.parents[1]/'outputs/apple-maps-rail'
R=6378137.0

def mercator(lat,lon):
    return R*math.radians(lon),R*math.log(math.tan(math.pi/4+math.radians(lat)/2))

def frame(row,size,offset,margin=100):
    lat,lon=row.get('requested_coordinate',(row['tile']['lat'],row['tile']['lon']))
    mpp=float(row['scale']['meters_per_pixel'])/math.cos(math.radians(lat))
    x,y=mercator(lat,lon)
    # Requested coordinates are displaced by Maps' retained sidebar camera inset.
    x-=offset[0]*mpp;y+=offset[1]*mpp
    w,h=size;cw,ch=w-2*margin,h-2*margin
    return {'id':row['id'],'file':row['file'],'left':x-cw*mpp/2,'top':y+ch*mpp/2,
            'right':x+cw*mpp/2,'bottom':y-ch*mpp/2,'source_width':w,'source_height':h,
            'crop':{'left':margin,'top':margin,'width':cw,'height':ch},
            'inferred_request': 'requested_coordinate' not in row}

def layout(rows,source,offset,target_mpp):
    records=[]
    for row in rows:
        with Image.open(source/row['file']) as im:size=im.size
        records.append(frame(row,size,offset))
    ref_lat=sum(r['tile']['lat'] for r in rows)/len(rows)
    resolution=target_mpp/math.cos(math.radians(ref_lat))
    left=min(f['left'] for f in records);top=max(f['top'] for f in records)
    width=math.ceil((max(f['right'] for f in records)-left)/resolution)
    height=math.ceil((top-min(f['bottom'] for f in records))/resolution)
    for f in records:
        f.update(x=(f['left']-left)/resolution,y=(top-f['top'])/resolution,
                 width=(f['right']-f['left'])/resolution,height=(f['top']-f['bottom'])/resolution)
    return records,width,height,left,top,resolution

class Images:
    def __init__(self,source,limit=12):self.source=source;self.limit=limit;self.cache=OrderedDict()
    def get(self,node):
        key=node['file']
        if key in self.cache:self.cache.move_to_end(key);return self.cache[key]
        c=node['crop']
        with Image.open(self.source/key) as im:
            image=im.crop((c['left'],c['top'],c['left']+c['width'],c['top']+c['height'])).convert('RGBA')
        self.cache[key]=image
        if len(self.cache)>self.limit:
            _,old=self.cache.popitem(last=False);old.close()
        return image
    def close(self):
        for image in self.cache.values():image.close()
        self.cache.clear()

def preview(nodes,width,height,source,path,maximum=6000):
    factor=min(1,maximum/max(width,height))
    canvas=Image.new('RGBA',(max(1,math.ceil(width*factor)),max(1,math.ceil(height*factor))))
    for n in nodes:
        c=n['crop']
        with Image.open(source/n['file']) as im:
            cropped=im.crop((c['left'],c['top'],c['left']+c['width'],c['top']+c['height']))
            x0,y0=round(n['x']*factor),round(n['y']*factor)
            x1,y1=round((n['x']+n['width'])*factor),round((n['y']+n['height'])*factor)
            resized=cropped.resize((max(1,x1-x0),max(1,y1-y0)),Image.Resampling.LANCZOS).convert('RGBA')
            canvas.alpha_composite(resized,(x0,y0))
    canvas.save(path,compress_level=4)
    result=list(canvas.size);canvas.close();return result

def tile_index(nodes,tile=512):
    grid=defaultdict(list)
    for n in nodes:
        for row in range(max(0,math.floor(n['y']/tile)),math.ceil((n['y']+n['height'])/tile)):
            for col in range(max(0,math.floor(n['x']/tile)),math.ceil((n['x']+n['width'])/tile)):
                grid[row,col].append(n)
    return grid

def tiles(nodes,width,height,source,tile=512):
    grid=tile_index(nodes,tile);images=Images(source)
    empty=np.zeros((tile,tile,4),dtype=np.uint8)
    try:
        for row in range(math.ceil(height/tile)):
            for col in range(math.ceil(width/tile)):
                matches=grid.get((row,col),[])
                if not matches:yield empty;continue
                output=Image.new('RGBA',(tile,tile))
                for n in matches:
                    im=images.get(n);a=im.width/n['width'];b=im.height/n['height']
                    patch=im.transform((tile,tile),Image.Transform.AFFINE,
                        (a,0,(col*tile-n['x'])*a,0,b,(row*tile-n['y'])*b),
                        resample=Image.Resampling.BILINEAR)
                    output.alpha_composite(patch)
                yield np.asarray(output)
    finally:images.close()

def geotiff(nodes,width,height,left,top,resolution,source,path):
    tags=[(33550,'d',3,(resolution,resolution,0),False),
          (33922,'d',6,(0,0,0,left,top,0),False),
          (34735,'H',16,(1,1,0,3,1024,0,1,1,1025,0,1,1,3072,0,1,3857),False)]
    temporary=path.with_suffix('.tif.tmp')
    tifffile.imwrite(temporary,tiles(nodes,width,height,source),shape=(height,width,4),dtype=np.uint8,
        bigtiff=True,tile=(512,512),photometric='rgb',extrasamples=['unassalpha'],
        compression='deflate',compressionargs={'level':4},maxworkers=2,metadata=None,extratags=tags,
        description='Native Apple Maps rail screenshot mosaic. EPSG:3857; approximate screenshot georeferencing. Transparent pixels are missing captures.')
    temporary.replace(path)
    with tifffile.TiffFile(path) as tif:
        page=tif.pages[0]
        assert page.shape==(height,width,4) and page.is_tiled

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=DEFAULT)
    parser.add_argument('--out',type=Path)
    parser.add_argument('--cities',help='Optional comma-separated metro IDs')
    parser.add_argument('--preview-size',type=int,default=6000)
    parser.add_argument('--skip-tiff',action='store_true')
    args=parser.parse_args();source=args.source.resolve();out=(args.out or source/'merged').resolve()
    for folder in ('previews','full'):(out/folder).mkdir(parents=True,exist_ok=True)
    calibration=json.loads((source/'calibration.json').read_text())
    catalog={c['id']:c['name'] for c in json.loads((HERE/'cities.json').read_text())['cities']}
    journal={}
    for line in (source/'manifest.jsonl').read_text().splitlines():
        try:r=json.loads(line);journal[r['id']]=r
        except (ValueError,KeyError):continue
    rows=[r for r in journal.values() if r['file'].startswith('rail/') and (source/r['file']).exists()]
    known={str((source/r['file']).resolve()) for r in rows}
    unplaced=[str(p) for p in (source/'rail').glob('*.png') if str(p.resolve()) not in known]
    if unplaced:raise RuntimeError(f'{len(unplaced)} rail images lack capture coordinates; refusing to silently omit them')
    groups=defaultdict(list)
    for r in rows:groups[r['tile']['city']].append(r)
    chosen=set(args.cities.split(',')) if args.cities else set(groups)
    manifest={'created_at':datetime.now().astimezone().isoformat(),'image_count':0,'cities':[],
        'notes':['Only currently saved rail/ images are included. Blank areas have no saved rail screenshot.',
                 'Images are placed by recorded coordinates and measured scale, with the calibrated camera offset removed.',
                 'Geographic placement is approximate; map labels and small registration seams can differ between captures.',
                 'Overlapping newer captures cover older captures. Original screenshots are unchanged.'],
        'source':str(source),'legacy_inferred_coordinates':sum('requested_coordinate' not in r for r in rows)}
    started=time.time()
    for i,city in enumerate(sorted(chosen)):
        if city not in groups:raise ValueError(f'No rail images for {city}')
        records=sorted(groups[city],key=lambda r:(r['captured_at'],r['id']))
        nodes,w,h,left,top,res=layout(records,source,calibration['coordinate_offset_pixels'],calibration['target_meters_per_pixel'])
        print(f'[{i+1}/{len(chosen)}] {city}: {len(nodes)} images → {w} × {h}',flush=True)
        overview=out/'previews'/f'{city}.png'
        preview_size=preview(nodes,w,h,source,overview,args.preview_size)
        full=out/'full'/f'{city}.tif'
        if not args.skip_tiff:geotiff(nodes,w,h,left,top,res,source,full)
        for n in nodes:
            n['src']=Path(__import__('os').path.relpath(source/n['file'],out)).as_posix()
        item={'id':city,'name':catalog.get(city,city),'image_count':len(nodes),'width':w,'height':h,
              'overview':str(overview.relative_to(out)),'overview_size':preview_size,'images':nodes,
              'full_resolution':str(full.relative_to(out)) if not args.skip_tiff else None,
              'crs':'EPSG:3857','projected_meters_per_pixel':res,'upper_left':[left,top]}
        manifest['cities'].append(item);manifest['image_count']+=len(nodes)
        (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    shutil.copyfile(HERE/'mosaic-viewer.html',out/'index.html')
    print(json.dumps({'cities':len(manifest['cities']),'images':manifest['image_count'],'seconds':round(time.time()-started,1),'output':str(out)}),flush=True)

if __name__=='__main__':main()
