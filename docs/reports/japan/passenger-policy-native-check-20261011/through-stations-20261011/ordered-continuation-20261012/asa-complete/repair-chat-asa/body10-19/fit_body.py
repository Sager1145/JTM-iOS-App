"""Candidate-only pixel controls/reprojection; no acceptance runner or production edits.
Manual seeds below use half-size sheet-local pixels; exported controls are literal full raw pixels.
"""
import json,math
from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np
B=Path(__file__).resolve().parents[2];O=Path(__file__).resolve().parent
W=268435456
# Each row: own-line visually identified seed polyline, in original raw /2 pixels.
SEEDS={
10:[[(160,177),(256,192),(350,207)],[(160,175),(256,188),(350,198)],[(160,185),(256,194),(300,207),(350,238)],[(160,149),(220,159),(256,173),(300,197),(350,237)],[(160,111),(220,145),(256,181),(290,224),(320,269),(350,293)],[(160,120),(190,161),(220,206),(256,261),(300,303),(350,326)],[(160,191),(205,221),(256,245),(300,263),(350,276)],[(160,162),(256,189),(350,205)],[(160,182),(256,193),(350,198)],[(160,179),(256,185),(350,185)],[(160,187),(256,184),(320,183),(350,185)],[(160,199),(256,212),(350,224)],[(160,185),(256,194),(350,211)]],
11:[[(160,179),(256,190),(350,208)],[(160,202),(256,222),(350,235)],[(160,220),(256,232),(350,244)],[(160,193),(256,205),(350,215)],[(160,241),(256,256),(350,278)],[(160,182),(256,198),(350,227)],[(160,166),(256,194),(350,211)],[(160,169),(256,189),(350,176)],[(160,208),(256,193),(350,150)]],
12:[[(160,208),(256,193),(350,150)],[(160,221),(256,190),(350,164)],[(160,214),(256,192),(350,169)]],
13:[[(160,214),(256,192),(350,169)],[(160,217),(256,194),(350,179)],[(160,183),(256,201),(350,220)],[(160,177),(256,206),(350,221)]],
14:[[(160,177),(256,206),(350,221)],[(160,183),(256,196),(350,229)],[(160,149),(220,166),(256,200),(300,243),(350,293)],[(160,98),(256,199),(350,299)],[(160,94),(256,196),(350,293)],[(160,94),(256,200),(350,304)],[(160,93),(256,195),(350,275)],[(160,126),(256,192),(350,243)],[(160,142),(256,192),(350,249)]],
15:[[(160,122),(256,170),(350,231)],[(160,130),(256,193),(350,275)],[(160,137),(256,207),(350,309)],[(180,110),(256,200),(326,304)],[(192,114),(250,207),(303,295)],[(196,82),(244,168),(285,246)],[(190,74),(244,173),(287,267)],[(230,100),(249,179),(250,264)],[(255,110),(251,196),(242,282)],[(290,105),(276,184),(263,270)],[(285,110),(280,193),(284,272)],[(215,100),(258,196),(319,284)],[(195,114),(249,196),(293,278)],[(210,108),(258,191),(280,275)]],
16:[[(210,108),(258,191),(280,275)],[(250,110),(257,196),(288,281)],[(203,96),(247,184),(306,256)],[(160,116),(220,162),(256,185),(350,241)],[(160,128),(256,190),(350,242)],[(160,153),(256,200),(350,223)],[(160,177),(256,191),(350,206)],[(160,174),(256,189),(350,204)]],
17:[[(160,172),(256,187),(350,202)],[(160,179),(256,193),(350,210)],[(160,175),(256,190),(350,205)],[(160,172),(256,187),(350,202)],[(160,178),(256,193),(350,208)],[(160,170),(256,185),(350,200)]],
18:[[(160,171),(256,185),(350,199)],[(160,172),(256,186),(350,199)],[(160,175),(256,182),(350,235)],[(160,114),(256,189),(297,270)],[(206,109),(252,191),(319,269)],[(160,97),(256,202),(320,275)],[(160,91),(256,198),(350,294),(375,306),(425,315)],[(160,162),(256,204),(350,219)],[(160,176),(256,192),(350,206)]],
19:[[(160,176),(256,192),(350,206)],[(160,177),(256,199),(350,246)],[(160,152),(256,207),(350,306)],[(160,120),(256,221),(294,261)],[(160,114),(212,168),(250,207)]],
}
def mp(c):
 lon,lat=c; return np.array([(lon/360+.5)*W,(.5-math.log(math.tan(math.pi/4+math.radians(lat)/2))/(2*math.pi))*W])
def geo(p): return [round((p[0]/W-.5)*360,9),round(math.degrees(2*math.atan(math.exp((.5-p[1]/W)*2*math.pi))-math.pi/2),9)]
def px(p,c): return (p-np.array([c['rectX'],c['rectY']]))/c['mapPointsPerPoint']
def world(p,c):return np.array(p)*c['mapPointsPerPoint']+np.array([c['rectX'],c['rectY']])
def project(p,src):
 best=(float('inf'),0)
 for j,(a,b) in enumerate(zip(src,src[1:])):
  v=b-a;t=max(0,min(1,float(np.dot(p-a,v)/np.dot(v,v))))
  dist=float(np.linalg.norm(p-a-v*t))
  if dist<best[0]:best=(dist,j+t)
 return best[1]
def snap(p,tangent,im):
 u=np.array(tangent,dtype=float);u/=np.linalg.norm(u);n=np.array([-u[1],u[0]])
 def blue(q):
  x,y=np.round(q).astype(int)
  if not (0<=x<1024 and 0<=y<768):return False
  r,g,b=map(int,im[y,x,:3]);return b>230 and r<180 and 110<g<210 and b-g>45
 hits=[]
 for t in np.arange(-18,18.01,.5):
  q=p+n*t
  if not blue(q):continue
  support=sum(any(blue(q+u*along+n*across)for across in [-1,0,1])for along in range(-18,19,3))/13
  if support>=.46:hits.append((support-.008*abs(t),t,support))
 if not hits:return p,'occluded-or-no-continuous-band'
 best=max(hits,key=lambda x:x[0]);near=[h[1]for h in hits if abs(h[1]-best[1])<1 and h[2]>=best[2]-.05]
 return p+n*(sum(near)/len(near)),'literal-blue-band'

def rdp(pts,eps):
 if len(pts)<3:return pts
 a,b=pts[0],pts[-1];v=b-a;den=np.dot(v,v)
 ds=[np.linalg.norm(p-a-v*max(0,min(1,np.dot(p-a,v)/den))) if den else np.linalg.norm(p-a)for p in pts[1:-1]]
 k=int(np.argmax(ds))+1
 if ds[k-1]>eps:return rdp(pts[:k+1],eps)[:-1]+rdp(pts[k:],eps)
 return [a,b]
D=json.load(open(B.parents[5]/'app/public/rail/jp-2025.json')) if False else json.load(open('app/public/rail/jp-2025.json'))
L=next(x for x in D['lines'] if x['id']=='jp-土佐くろしお鉄道-阿佐線')
outputs={};controls=[];cameras=[];panels=[]
for i,rows in SEEDS.items():
 cap=B/'native/primary/captures'/f'{2976+i:06d}'
 src=L['segments'][i][2];src=([L['segments'][i-1][2][-1]] if L['segments'][i][1] else [])+src;srcmp=[mp(p)for p in src]
 gathered=[]
 for vi,seeds in enumerate(rows):
  d=cap/f'{vi:06d}';v=json.load(open(d/'view.json'));c=v['camera'];a=np.array(Image.open(d/'basemap.png'))
  cameras.append({'intervalIndex':i,'capture':str(d.relative_to(B)),'camera':c,'mapRect':v['mapRect'],'size':[1024,768]})
  seeds=[np.array(p,dtype=float)*2 for p in seeds]
  for si,(p,q) in enumerate(zip(seeds,seeds[1:])):
   tangent=q-p;steps=max(1,math.ceil(np.linalg.norm(tangent)/24))
   for k in range(steps+1):
    rough=p+tangent*k/steps;pick,status=snap(rough,tangent,a);w=world(pick,c);order=project(w,srcmp)
    # Each camera contributes the central supported corridor. Overlaps are sorted geometrically, never capture order.
    if status=='literal-blue-band' and 0.001<order<len(srcmp)-1.001:
     gathered.append((order,w,i,vi,pick,status,rough))
  controls.append({'intervalIndex':i,'captureView':vi,'manualSeedRawPixels':[[float(x)for x in p]for p in seeds]})
 # Concrete cross-view false-pick repair, manually adjudicated in opened raw detail panels.
 if i in [10,13]:
  vi=4 if i==10 else 3;d=cap/f'{vi:06d}';c=json.load(open(d/'view.json'))['camera'];im=np.array(Image.open(d/'basemap.png'))
  bounds=(340,560) if i==10 else (400,540)
  gathered=[r for r in gathered if not(bounds[0]<=px(r[1],c)[0]<=bounds[1])]
  manual=[(370,248),(400,269),(430,291),(460,314),(490,339),(520,367),(550,399)] if i==10 else [(400,372),(440,382),(480,394),(520,406)]
  for j,pick0 in enumerate(manual):
   tangent=np.array(manual[min(j+1,len(manual)-1)])-np.array(manual[max(j-1,0)])
   # These interval-10 pixels are the lower branch's literal blue pixels.
   # A nearest-blue snap can jump back to the adjacent upper branch here.
   if i==10:pick=np.array(pick0,dtype=float);status='literal-lower-blue-band'
   else:pick,status=snap(np.array(pick0,dtype=float),tangent,im)
   w=world(pick,c);gathered.append((project(w,srcmp),w,i,vi,pick,status,np.array(pick0)))
 gathered.sort(key=lambda x:x[0]);selected=[]
 for rec in gathered:
  if not selected or np.linalg.norm(rec[1]-selected[-1][1])>100: selected.append(rec) # ~12.4m
 # Provisional own-band endpoint projections use source physical endpoint chainage, not a station-frame claim.
 for endpoint,vi,place in [(srcmp[0],0,0),(srcmp[-1],len(rows)-1,-1)]:
  d=cap/f'{vi:06d}';v=json.load(open(d/'view.json'));c=v['camera'];s=np.array(rows[vi])*2
  p=px(endpoint,c);best=None
  for x,y in zip(s,s[1:]):
   vv=y-x;t=np.dot(p-x,vv)/np.dot(vv,vv);q=x+vv*t;dist=np.linalg.norm(p-q)
   if best is None or dist<best[0]:best=(dist,q,vv)
  pick,status=snap(best[1],best[2],np.array(Image.open(d/'basemap.png')));rec=(0 if place==0 else len(srcmp)-1,world(pick,c),i,vi,pick,status,p)
  if place==0:selected.insert(0,rec)
  else:selected.append(rec)
 pts=rdp([r[1]for r in selected],10) # ~1.24m world tolerance; no whole-line spline
 # Remove only the three observed guard-adjacent duplicate corners, not a global edge threshold.
 if i in [11,15] and len(pts)>3 and np.linalg.norm(pts[-2]-pts[-1])<64:pts.pop(-2)
 if i==12 and len(pts)>3 and np.linalg.norm(pts[1]-pts[0])<64:pts.pop(1)
 # Aki's fan has a blue support east of the provisional station endpoint;
 # retaining it would reverse into the endpoint and imply a yard excursion.
 if i==13 and len(pts)>3 and pts[-2][0]>pts[-1][0]:pts.pop(-2)
 coords=[geo(p)for p in pts]
 outputs[str(i)]={'intervalIndex':i,'physicalKM':L['segments'][i][0],'continues':L['segments'][i][1],'coordinates':coords,'physicalEndpoints': [src[0],src[-1]],'endpointStatus':'provisional own-band projection; parent owns exact station-frame aliases/repartition','allocationWarning':'Views3–7: labelled upper diagonal and unlabelled coastward paired-rail continuation diverge/reconverge. Candidate follows lower physical continuation connected to own station frames; upper rejected as direct shape authority; allocation remains explicitly parent-adjudicated' if i==10 else None}
 for r in selected:controls.append({'intervalIndex':i,'captureView':r[3],'rawPixel':[round(float(x),3)for x in r[4]],'roughSeedPixel':[round(float(x),3)for x in r[6]],'status':r[5],'coordinate':geo(r[1]),'sourceOrderLocator':round(r[0],6)})
 for vi in range(len(rows)):
  d=cap/f'{vi:06d}';v=json.load(open(d/'view.json'));c=v['camera'];im=Image.open(d/'basemap.png').convert('RGB');draw=ImageDraw.Draw(im);p=[tuple(px(mp(q),c))for q in coords];draw.line(p,fill=(215,55,20),width=2)
  for r in selected:
   q=tuple(px(r[1],c));draw.ellipse((q[0]-2,q[1]-2,q[0]+2,q[1]+2),outline=(0,50,0))
  draw.text((10,8),f'PROPOSAL {i}/{vi:06d}; red candidate, green literal controls; endpoint guards provisional',fill='black')
  out=O/'reprojections'/f'{i:02d}-{vi:06d}.png';out.parent.mkdir(exist_ok=True);im.save(out);panels.append(str(out.relative_to(O)))
 for start in range(0,len(rows),4):
  sheet=Image.new('RGB',(1024,800),'white');dd=ImageDraw.Draw(sheet)
  for n,vi in enumerate(range(start,min(start+4,len(rows)))):
   im=Image.open(O/'reprojections'/f'{i:02d}-{vi:06d}.png').resize((512,384));x=n%2*512;y=n//2*400;sheet.paste(im,(x,y+16));dd.text((x+4,y+2),f'candidate {i} view{vi}',fill='black')
  sheet.save(O/f'candidate-{i}-{start//4}.png')
(O/'candidate-intervals10-19.json').write_text(json.dumps({'format':'asa-display-body-proposal-v2','lineID':L['id'],'invariants':'physical IDs, physical KM, routing source untouched','acceptance':'proposal only; no native acceptance or alignment counters','intervals':outputs},ensure_ascii=False,indent=2)+'\n')
(O/'literal-controls-and-cameras.json').write_text(json.dumps({'manualSeedsAndControls':controls,'rejectedSeedRegions':[
 {'intervalIndex':10,'captureViews':[3,4,5,6,7],'reason':'upper labelled blue branch and cross-branch snap positions are not selected shape authority; lower coastward blue continuation is selected'},
 {'intervalIndex':13,'captureViews':[2,3],'reason':'Aki upper yard fan and east-of-provisional-endpoint support are excluded from the representative body'}
 ],'originalCameras':cameras,'reprojections':panels},ensure_ascii=False,indent=2)+'\n')
print([(i,len(v['coordinates']))for i,v in outputs.items()])
