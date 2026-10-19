from pathlib import Path
import json, math
from PIL import Image,ImageDraw
import numpy as np
B=Path(__file__).resolve().parents[2]
O=Path(__file__).resolve().parent
CAPS=['002984','002985','002996','002997','002998','002999','003000','003001','003002','003003']
WORLD=268435456
line=next(l for l in json.loads(Path('app/public/rail/jp-2025.json').read_text())['lines'] if l['id']=='jp-土佐くろしお鉄道-阿佐線')
def world(p):
 lon,lat=p;return np.array([(lon+180)/360*WORLD,(1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*WORLD])
def geo(p):
 x,y=p;return [(x/WORLD*360)-180,math.degrees(math.atan(math.sinh(math.pi*(1-2*y/WORLD))))]
def xy(p,v):
 r=v['mapRect'];return (world(p)-[r['x'],r['y']])/v['camera']['mapPointsPerPoint']
def ll(p,v):
 r=v['mapRect'];return geo(np.array(p)*v['camera']['mapPointsPerPoint']+[r['x'],r['y']])
def source(i):
 s=line['segments'][i];return ([line['segments'][i-1][2][-1]] if s[1] and i else [])+s[2]
def views(i):return sorted((B/'native/primary/captures'/CAPS[i]).glob('*/view.json'))
def prep():
 for i in range(10):
  vs=views(i)
  for k in range(0,len(vs),4):
   out=Image.new('RGB',(2048,1600),'white')
   for slot,p in enumerate(vs[k:k+4]):
    im=Image.open(p.parent/'basemap.png').convert('RGB');d=ImageDraw.Draw(im);v=json.loads(p.read_text())
    pts=[tuple(xy(q,v))for q in source(i)];d.line(pts,fill=(215,20,75),width=1)
    for n,q in enumerate(pts):
     if 0<=q[0]<1024 and 0<=q[1]<768:d.text((q[0]+3,q[1]),str(n),fill=(190,0,45))
    x=slot%2*1024;y=slot//2*800;out.paste(im,(x,y+32));ImageDraw.Draw(out).text((x+8,y+7),f'interval {i} view {p.parent.name} source red (not alignment)',fill='black')
   out.save(O/f'original-i{i:02d}-{k:02d}.jpg',quality=95)
if __name__=='__main__':prep()

def fit():
 records=[]
 for i in range(10):
  vs=[(p,json.loads(p.read_text()),np.asarray(Image.open(p.parent/'basemap.png').convert('RGB')).astype(float))for p in views(i)]
  ps=np.array([world(q)for q in source(i)]); ds=np.linalg.norm(np.diff(ps,axis=0),axis=1); chain=np.r_[0,np.cumsum(ds)]
  stations=np.unique(np.r_[chain,np.arange(0,chain[-1],320)]) # about 40m supports + source corners
  samples=[]
  for s in stations:
   idx=min(np.searchsorted(chain,s,side='right')-1,len(ps)-2);idx=max(0,idx);t=(s-chain[idx])/ds[idx];q=ps[idx]*(1-t)+ps[idx+1]*t
   lo=max(0,s-200);hi=min(chain[-1],s+200)
   qa=np.array([np.interp(lo,chain,ps[:,a])for a in range(2)]);qb=np.array([np.interp(hi,chain,ps[:,a])for a in range(2)]);tangent=(qb-qa)/np.linalg.norm(qb-qa);normal=np.array([-tangent[1],tangent[0]])
   # Gomen multi-rail guard: no color ranking. First identifiable independent curve begins ~source vertex 3.
   if i==0 and s<=chain[3]:
    samples.append(dict(chain=s,world=q.tolist(),offset=0,status='provisional-retained-Gomen-guard',capture=None));continue
   opts=[]
   for p,v,im in vs:
    r=v['mapRect'];scale=v['camera']['mapPointsPerPoint'];pix=(q-[r['x'],r['y']])/scale
    if not(80<pix[0]<944 and 80<pix[1]<688):continue
    offsets=np.arange(-64,65,.5);along=np.arange(-30,31,2);cross=np.arange(-4,4.1,1)
    points=pix+offsets[:,None,None,None]*normal+along[None,:,None,None]*tangent+cross[None,None,:,None]*normal
    ix=np.rint(points[...,0]).astype(int);iy=np.rint(points[...,1]).astype(int);rgb=im[iy,ix];rr,gg,bb=rgb[...,0],rgb[...,1],rgb[...,2]
    # Blue/violet railway casing, excludes cyan hydrography; identity already set visually in corridor.
    mask=(bb-gg>30)&(gg-rr>3)&(gg-rr<55)&(bb-rr>38)&(rr>95)&(bb>215)
    profile=mask.mean(axis=(1,2));k=int(np.argmax(profile));peak=profile[k]
    # centroid over nearby coherent rail band, avoiding isolated label/badge peaks.
    if peak<.13:continue
    band=np.abs(offsets-offsets[k])<=4;weights=profile[band];off=float(np.sum(offsets[band]*weights)/sum(weights))
    margin=min(pix[0],1024-pix[0],pix[1],768-pix[1]);opts.append((peak,margin,off,p,v,pix))
   if not opts:
    samples.append(dict(chain=s,world=q.tolist(),offset=None,status='occluded-interpolate',capture=None));continue
   opts.sort(key=lambda a:(a[0],a[1]),reverse=True);peak,margin,off,p,v,pix=opts[0];actual=q+normal*off*v['camera']['mapPointsPerPoint']
   samples.append(dict(chain=s,world=actual.tolist(),sourceWorld=q.tolist(),normal=normal.tolist(),offset=off*v['camera']['mapPointsPerPoint'],rawOffsetPixels=off,status='identified-rail-band-candidate',capture=str(p.parent.relative_to(B)),rawPixel=xy(geo(actual),v).tolist(),camera=v['camera'],mapRect=v['mapRect'],supportScore=peak))
  # Missing support is bridged from neighbouring rail offsets, never pulled back to source.
  good=[n for n,x in enumerate(samples)if x['offset'] is not None]
  for n,x in enumerate(samples):
   if x['offset'] is None:
    idx=min(np.searchsorted(chain,x['chain'],side='right')-1,len(ps)-2);idx=max(0,idx)
    t=(x['chain']-chain[idx])/ds[idx];q=ps[idx]*(1-t)+ps[idx+1]*t;ta=(ps[min(idx+1,len(ps)-1)]-ps[idx]);ta/=np.linalg.norm(ta);normal=np.array([-ta[1],ta[0]])
    off=np.interp(x['chain'],[samples[g]['chain']for g in good],[samples[g]['offset']for g in good]);x['world']=(q+normal*off).tolist();x['offset']=float(off)
  # Reject isolated transverse spikes from cartographic labels; carry local supported tangent.
  for n in range(1,len(samples)-1):
   x=samples[n];pred=(samples[n-1]['offset']+samples[n+1]['offset'])/2
   if x['capture'] and abs(x['offset']-pred)>64 and samples[n+1]['chain']-samples[n-1]['chain']<900:
    x['rejectedOriginal']=dict(world=x['world'],offset=x['offset'],rawPixel=x['rawPixel']);x['offset']=pred;x['world']=(np.array(x['sourceWorld'])+np.array(x['normal'])*pred).tolist();x['status']='label-spike-replaced-by-neighbour-offset'
  coords=[geo(x['world'])for x in samples]
  # Endpoints are body-normal supports at old physical chainage, parent owns all frame aliases.
  records.append(dict(intervalIndex=i,fromStationID=line['stations'][i][0],toStationID=line['stations'][i+1][0],coordinates=coords,controls=samples,endpointStatus='provisional-body-support-at-physical-chainage; parent station frame/local joins pending',sourceCompleteCoordinates=source(i)))
  print(i,len(coords),len([x for x in samples if x['status']=='occluded-interpolate']))
 (O/'body-candidates.json').write_text(json.dumps(dict(format='Asa-body-candidate-v1',lineID=line['id'],scope='candidate only; no alias or native acceptance',intervals=records),ensure_ascii=False,indent=2))

def render():
 data=json.loads((O/'body-candidates.json').read_text())
 for row in data['intervals']:
  i=row['intervalIndex'];vs=views(i)
  for k in range(0,len(vs),4):
   out=Image.new('RGB',(2048,1600),'white')
   for slot,p in enumerate(vs[k:k+4]):
    v=json.loads(p.read_text());im=Image.open(p.parent/'basemap.png').convert('RGB');d=ImageDraw.Draw(im)
    pts=[tuple(xy(q,v))for q in row['coordinates']];d.line(pts,fill=(225,15,80),width=1)
    for n,pt in enumerate(pts):
     if 0<pt[0]<1024 and 0<pt[1]<768:
      if n%3==0:d.ellipse((pt[0]-2,pt[1]-2,pt[0]+2,pt[1]+2),outline=(170,0,50));d.text((pt[0]+3,pt[1]+3),str(n),fill=(180,0,45))
    (O/'reprojects').mkdir(exist_ok=True);im.save(O/'reprojects'/f'i{i:02d}-v{p.parent.name}.png')
    x=slot%2*1024;y=slot//2*800;out.paste(im,(x,y+32));ImageDraw.Draw(out).text((x+8,y+7),f'CANDIDATE interval {i} original view {p.parent.name}; provisional ends',fill='black')
   out.save(O/f'candidate-i{i:02d}-{k:02d}.jpg',quality=95)
if __name__=='__main__':fit();render()
