import json,math
from pathlib import Path
from PIL import Image,ImageDraw
B=Path('/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/yodo-complete');OUT=B/'proposal-own-bodies-v2';OUT.mkdir(exist_ok=True)
W=268435456
project=lambda q:(W*(q[0]+180)/360,W*(1-math.asinh(math.tan(math.radians(q[1])))/math.pi)/2)
inverse=lambda x,y:[x/W*360-180,math.degrees(math.atan(math.sinh(math.pi*(1-2*y/W))))]
def blue(rgb):r,g,b=rgb;return b-r>40 and b-g>20 and g-r>8 and g-r<.7*(b-r)
lines=json.load(open(B/'station-precise/assigned-interval-candidates.json'))['intervals'];assigned=next(i['coordinates'] for i in lines if '中村' in i['lineID'] and i['intervalIndex']==0)
source=json.load(open('/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/rail/jp-2025.json'))['lines']
inv=json.load(open('/private/tmp/yodo-shared-secondary-review/inventory.json'))
for name,lid,idx in [(f'yodo{i:02}','jp-四国旅客鉄道-予土線',i) for i in range(1,8)]:
 line=next(x for x in source if x['id']==lid)
 if name.startswith('yodo'):
  coords=list(line['segments'][idx][2]);coords=([line['segments'][idx-1][2][-1]]+coords if line['segments'][idx][1] else coords)
  paths=[Path(q['path']).parent for q in inv if q['itemID']==lid+'#'+str(idx)];tail=[]
 else:
  coords=assigned[:-7];tail=assigned[-7:];paths=[]
  for p in Path('/private/tmp/jtm-yodo-complete-primary-v1/captures').glob('*/*/view.json'):
   v=json.load(open(p))
   if v['lineID']==lid and v['intervalIndex']==0:paths.append(p.parent)
 frames=[]
 for p in paths:
  v=json.load(open(p/'view.json'));frames.append((v,Image.open(p/'basemap.png').convert('RGB'),p))
 frames.sort(key=lambda f:f[0]['pointOrdinal'])
 def pixel(v,p):r=v['mapRect'];sc=v['camera']['mapPointsPerPoint'];return((p[0]-r['x'])/sc,(p[1]-r['y'])/sc)
 def fit(p,t):
  options=[(math.dist(pixel(v,p),(512,384)),v,im,path) for v,im,path in frames if 50<pixel(v,p)[0]<974 and 50<pixel(v,p)[1]<718]
  if not options:return None
  _,v,im,path=min(options,key=lambda q:q[0]);x,y=pixel(v,p);norm=(-t[1],t[0]);best=[]
  bound={1:15,2:10,3:12,4:12,5:18,6:15,7:15}[idx]
  for d in range(-bound,bound+1):
   hits=[]
   for along in [-6,-3,0,3,6]:
    px=x+norm[0]*d+t[0]*along;py=y+norm[1]*d+t[1]*along;found=[]
    for dx in [-1,0,1]:
     for dy in [-1,0,1]:
      xx,yy=round(px)+dx,round(py)+dy
      if 0<=xx<1024 and 0<=yy<768 and blue(im.getpixel((xx,yy))):found.append((math.hypot(xx-px,yy-py),xx,yy))
    if found:hits.append(min(found))
   if len(hits)==5:
    # Actual reviewed yodo09 road381 badge at view2 x458,y341 is a competitor.
    if name=='yodo05' and ((v['pointOrdinal']==3 and 538<hits[2][1]<575 and 348<hits[2][2]<368) or (v['pointOrdinal']==5 and 496<hits[2][1]<534 and 397<hits[2][2]<421)):continue
    if name=='yodo09' and v['pointOrdinal']==2 and 440<hits[2][1]<480 and 325<hits[2][2]<360:continue
    best.append((sum(h[0] for h in hits)/5+abs(d)*.025,d,hits))
  if not best:return None
  _,d,h=min(best);xx,yy=h[2][1:];r=v['mapRect'];sc=v['camera']['mapPointsPerPoint']
  return{'coordinate':inverse(r['x']+sc*xx,r['y']+sc*yy),'pixel':[xx,yy],'normalOffsetPixels':d,'viewOrdinal':v['pointOrdinal'],'rawView':str(path/'view.json'),'rgb':list(im.getpixel((xx,yy))),'persistentWitnessPixels':[list(q[1:]) for q in h]}
 pts=[project(q) for q in coords];chain=[0]
 for a,b in zip(pts,pts[1:]):chain.append(chain[-1]+math.dist(a,b))
 scale=frames[0][0]['camera']['metresPerPoint']/frames[0][0]['camera']['mapPointsPerPoint'];values=set();step=25/scale;s=step
 while s<chain[-1]:values.add(s);s+=step
 controls=[];miss=[];candidate=[coords[0]]
 for s in sorted(values):
  if s==0 or s==chain[-1]:continue
  i=next(i for i in range(len(pts)-1) if chain[i]<=s<=chain[i+1] and chain[i+1]>chain[i]);f=(s-chain[i])/(chain[i+1]-chain[i]);p=tuple(pts[i][j]+f*(pts[i+1][j]-pts[i][j]) for j in [0,1]);d=math.dist(pts[i],pts[i+1]);t=[(pts[i+1][j]-pts[i][j])/d for j in [0,1]];q=fit(p,t)
  if q is None:
   miss.append({'chainageMapPoints':s,'sourceBracket':[i,i+1],'sourceInterpolatedCoordinate':inverse(*p),'handling':'Retained original source interpolation; no ownpixel fit claimed.'});candidate.append(inverse(*p));continue
  q.update({'controlID':f'{name}-C{len(controls):04}','sourceChainageMapPoints':s,'sourceBracket':[i,i+1],'sourceInterpolatedCoordinate':inverse(*p)})
  # Preserve existing original supports when their literal position already lies within2px of ownband.
  exact=next((k for k,c in enumerate(chain) if abs(c-s)<1e-5),None)
  if exact is not None and math.dist(project(q['coordinate']),pts[exact])/8<=2:q['coordinate']=coords[exact];q['preservedSourceIndex']=exact
  candidate.append(q['coordinate']);controls.append(q)
 candidate += [coords[-1]]+tail
 pp=[project(q) for q in candidate];turns=[]
 for k in range(1,len(pp)-1):
  a=[pp[k][j]-pp[k-1][j] for j in [0,1]];b=[pp[k+1][j]-pp[k][j] for j in [0,1]];den=math.hypot(*a)*math.hypot(*b)
  if den:turns.append([k,math.degrees(math.acos(max(-1,min(1,sum(a[j]*b[j] for j in [0,1])/den))))])
 result={'status':'provisional-candidate-only-station-guards-pending','lineID':lid,'intervalIndex':idx,'coordinates':candidate,'controls':controls,'unsupportedSamples':miss,'turnsAbove45':[t for t in turns if t[1]>45],'sourceCoordinates':coords+tail,'endpointGuards':{'start':candidate[0],'end':candidate[-1],'warning':'Preserved current guards pending Root highzoom station adjudication. Nakamura Wakai precise last7 retained.'},'limits':['Own thin-blue cartographic fit using exact raw cameras, not physical survey.','Normal search interval-specific bounds15/10/12/12/18/15/15px; five-point persistence; palette B-R>40, B-G>20, G-R>8, G-R<0.7*(B-R); road381 badges masked in Yodo5 views3 and5.','Missing witnesses retain source interpolation and disclose no own-pixel fit. Body is sampled at25m source chainage; physical source coordinates untouched. Current station guards are provisional and must be replaced by precise local witnesses.','Native smoothing/lane/Main replay pending.']}
 (OUT/(name+'-proposal.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');(OUT/(name+'-coordinates.json')).write_text(json.dumps(candidate,indent=2)+'\n')
 for v,im,p in frames:
  d=ImageDraw.Draw(im);d.line([pixel(v,project(q)) for q in coords+tail],fill=(220,20,20),width=2);d.line([pixel(v,project(q)) for q in candidate],fill=(10,150,30),width=2)
  for q in controls:
   x,y=pixel(v,project(q['coordinate']))
   if 0<=x<1024 and 0<=y<768:d.ellipse((x-1,y-1,x+1,y+1),fill='black')
  im.save(OUT/f'{name}-reprojection-{v["pointOrdinal"]:02}.png')
 print(name,'points',len(candidate),'controls',len(controls),'missing',len(miss),'turns45',len(result['turnsAbove45']),flush=True)
