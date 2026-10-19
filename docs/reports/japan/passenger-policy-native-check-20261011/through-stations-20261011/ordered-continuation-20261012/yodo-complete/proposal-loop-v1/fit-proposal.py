import json,math,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).parent
CAP=Path('/private/tmp/jtm-yodo-complete-secondary-v1/captures/002693')
SRC=Path('app/public/rail/jp-2025.json')
LID='jp-四国旅客鉄道-予土線';W=268435456
line=next(x for x in json.loads(SRC.read_text())['lines'] if x['id']==LID);source=line['segments'][0][2]
def project(q):return (W*(q[0]+180)/360,W*(1-math.asinh(math.tan(math.radians(q[1])))/math.pi)/2)
def inverse(x,y):return [x/W*360-180,math.degrees(math.atan(math.sinh(math.pi*(1-2*y/W))))]
pts=[project(q) for q in source];chain=[0]
for a,b in zip(pts,pts[1:]):chain.append(chain[-1]+math.dist(a,b))
frames={}
for n in range(8,18):
 p=CAP/f'{n:06}';v=json.loads((p/'view.json').read_text());frames[n]=(v,Image.open(p/'basemap.png').convert('RGB'))
def pixel(n,p):r=frames[n][0]['mapRect'];return ((p[0]-r['x'])/8,(p[1]-r['y'])/8)
def blue(rgb):r,g,b=rgb;return b-r>70 and b-g>30 and g-r>20

def fit(p,t):
 options=[]
 for n in frames:
  x,y=pixel(n,p)
  if 80<x<944 and 80<y<688:options.append((math.hypot(x-512,y-384),n,x,y))
 if not options:return None
 _,n,x,y=min(options);im=frames[n][1];norm=(-t[1],t[0]); candidates=[]
 # Look only across the identified own Yodo band; competing Nakamura and water are excluded by identity/colour/persistence.
 for d in range(-60,61):
  hits=[]
  for along in [-6,-3,0,3,6]:
   px=x+norm[0]*d+t[0]*along;py=y+norm[1]*d+t[1]*along
   found=[]
   for dx in [-1,0,1]:
    for dy in [-1,0,1]:
     ix,iy=round(px)+dx,round(py)+dy
     if 0<=ix<1024 and 0<=iy<768 and blue(im.getpixel((ix,iy))):found.append((math.hypot(ix-px,iy-py),ix,iy))
   if found:hits.append(min(found))
  if len(hits)==5:
   # Manually identified exclusion between lower Yodo and upper Nakamura arcs
   # in common exact raw view11; colour alone cannot choose this shared-colour branch.
   rr=frames[n][0]['mapRect']; common=pixel(11,(rr['x']+8*hits[2][1],rr['y']+8*hits[2][2]))
   if 300<=common[0]<=480 and common[1]<420-(common[0]-320)*48/180-5:continue
   cost=sum(h[0] for h in hits)/5+abs(d)*0.001
   candidates.append((cost,d,hits))
 if not candidates:return None
 _,d,hits=min(candidates);ix,iy=hits[2][1:];r=frames[n][0]['mapRect'];q=inverse(r['x']+8*ix,r['y']+8*iy)
 return {'viewOrdinal':n,'pixel':[ix,iy],'rgb':list(im.getpixel((ix,iy))),'normalOffsetPixels':d,'coordinate':q,'sourcePixel':[x,y],'tangent':t,'persistentWitnessPixels':[[h[1],h[2]] for h in hits]}
print('Source support normal fit distances (guards included)')
for i in range(60,104):
 a=pts[max(0,i-1)];b=pts[min(103,i+1)];d=math.dist(a,b);f=fit(pts[i],[(b[0]-a[0])/d,(b[1]-a[1])/d]);print(i,None if f is None else (f['viewOrdinal'],f['normalOffsetPixels'],f['pixel']))
# Fit controls in common source chainage order, not overlapping camera order.
# 25 metres in this local WebMercator scale; include both modification boundaries.
start,end=chain[61],chain[100];local_scale=frames[12][0]['camera']['metresPerPoint']/8
values=[start];cur=start+25/local_scale
while cur<end:values.append(cur);cur+=25/local_scale
values.append(end)
controls=[];missing=[]
for k,s in enumerate(values):
 i=next(i for i in range(103) if chain[i]<=s<=chain[i+1]);t0=(s-chain[i])/(chain[i+1]-chain[i]);p=tuple(pts[i][j]+t0*(pts[i+1][j]-pts[i][j]) for j in range(2));d=math.dist(pts[i],pts[i+1]);t=[(pts[i+1][j]-pts[i][j])/d for j in range(2)]
 f=fit(p,t)
 if not f:
  missing.append({'chainageMapPoints':s,'sourceBracket':[i,i+1]});continue
 f.update({'controlID':f'C{k:03}','sourceBracket':[i,i+1],'sourceFraction':t0,'sourceChainageMapPoints':s,'sourceInterpolatedCoordinate':inverse(*p),'fitSide':'signed left normal of forward source tangent'})
 controls.append(f)
# A missing witness is never snapped to a road. Neighbouring own-band controls bridge only the short cartographic pixel gap.
coords=source[:61]+[f['coordinate'] for f in controls]+source[101:]
# Ordered input chainage plus physical forward triple checks expose cross-camera backtracks.
cp=[project(q) for q in coords];angles=[]
for i in range(1,len(cp)-1):
 a=tuple(cp[i][j]-cp[i-1][j] for j in range(2));b=tuple(cp[i+1][j]-cp[i][j] for j in range(2));den=math.hypot(*a)*math.hypot(*b)
 if den:angles.append((i,math.degrees(math.acos(max(-1,min(1,sum(a[j]*b[j] for j in range(2))/den))))))
assert all(turn<30 for idx,turn in angles if idx>=60), 'Observed candidate sharp turn/backtrack must be resolved'
# scope invariant equality; no station, physical, mileage or topology record is altered.
assert coords[:61]==source[:61] and coords[-3:]==source[-3:] and coords[0]==source[0] and coords[-1]==source[-1]
proposal={'status':'candidate-only-not-accepted','lineID':LID,'intervalIndex':0,'fromStationID':line['stations'][0][0],'toStationID':line['stations'][1][0],'physicalKilometresPreserved':line['segments'][0][0],'sourceSha256':hashlib.sha256(SRC.read_bytes()).hexdigest(),'sourceCoordinates':source,'coordinates':coords,'preservedSharedSourceIndices':[0,60],'replacedSourceIndices':[61,100],'preservedFarGuardSourceIndices':[101,103],'stationRows':line['stations'][:2],'controls':controls,'unsupportedSamples':missing,'manualBranchExclusion':{'commonRawView':11,'xRange':[300,480],'rejectedIfYBelow':'y < 420-(x-320)*48/180-5','reason':'Upper Nakamura arc overlaps normal search; lower Yodo arm independently followed in raw views10–12'},'maximumCandidateTurn':max(angles,key=lambda x:x[1]),'candidateModifiedTurnsAbove60Degrees':[x for x in angles if x[0]>=60 and x[1]>60],'palette':{'exampleRGB':[116,169,253],'predicate':'B-R>70 && B-G>30 && G-R>20','rejection':'Cyan stream, gray329 road and road lettering excluded; competing Nakamura arc excluded by identified forward corridor search.'},'fitAlgorithm':'Exact zero-heading/pitch raw mapRect WebMercator projection; normal search ±60 pixels; require thin-blue support at five longitudinal positions -6,-3,0,3,6px. Candidate actual central witness integer pixel inverted to WGS84. Source chainage ordered 25m controls. Short missing witness spans disclosed; not filled using roads.','limits':['Cartographic thin blue sleeper-marked own Yodo band; no surveyed forest/tunnel rail claim.','Source shared boundary index60 is preserved despite ~5px glyph separation; no other owner or fork change proposed.','No station aliases moved; station frames/endpoints retained.','Overlays are candidate raw controls, not native smoothing or production lane acceptance.']}
(ROOT/'interval-0-proposal.json').write_text(json.dumps(proposal,ensure_ascii=False,indent=2)+'\n');(ROOT/'interval-0-coordinates.json').write_text(json.dumps(coords,ensure_ascii=False,indent=2)+'\n')
# All current interval frames show literal source, candidate, controls, and retained guards.
repro=[]
for n in range(18):
 p=CAP/f'{n:06}';v=json.loads((p/'view.json').read_text());r=v['mapRect'];im=Image.open(p/'basemap.png').convert('RGB');draw=ImageDraw.Draw(im)
 def px(q):a,b=project(q);return ((a-r['x'])/8,(b-r['y'])/8)
 draw.line([px(q) for q in source],fill=(220,30,30),width=2);draw.line([px(q) for q in coords],fill=(15,150,30),width=2)
 allp=[]
 for f in controls:
  x,y=px(f['coordinate']);visible=0<=x<1024 and 0<=y<768;allp.append({'controlID':f['controlID'],'pixel':[x,y],'visible':visible,'offscreenSide':None if visible else ('left' if x<0 else 'right' if x>=1024 else 'top' if y<0 else 'bottom')})
  if visible:draw.ellipse((x-2,y-2,x+2,y+2),fill=(255,0,255))
  if visible and int(f['controlID'][1:])%8==0:draw.text((x+3,y-12),f['controlID'],fill=(100,0,110))
 guards=[]
 for si in [0,60,101,103]:
  x,y=px(source[si]);visible=0<=x<1024 and 0<=y<768;guards.append({'sourceIndex':si,'pixel':[x,y],'visible':visible})
  if visible:draw.rectangle((x-4,y-4,x+4,y+4),outline=(0,0,0),width=2);draw.text((x+5,y+3),f'G{si}',fill=(0,0,0))
 draw.rectangle((0,0,620,20),fill='white');draw.text((3,3),f'view{n}: red=literal source green=candidate magenta=controls black=retained guards',fill='black');im.save(ROOT/f'reprojection-{n:02}.png')
 repro.append({'viewOrdinal':n,'rawBasemap':str(p/'basemap.png'),'camera':v['camera'],'mapRect':r,'controls':allp,'guards':guards})
(ROOT/'reprojections.json').write_text(json.dumps(repro,ensure_ascii=False,indent=2)+'\n')
print('Candidate controls',len(controls),'missing',len(missing),'coords',len(coords),'modified sharpturns',proposal['candidateModifiedTurnsAbove60Degrees'])
