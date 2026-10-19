import json,math,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).parent;BASE=ROOT.parent
v3=json.loads((BASE/'proposal-wakai-nakamura-v3/candidate.json').read_text());kw=json.loads((BASE/'station-precise/kaina-z18/station-candidate-witness.json').read_text());hv=json.loads((BASE/'station-precise/kaina-z18/view.json').read_text())
defs=(BASE/'proposal-loop-v1/fit-proposal.py').read_text().split("print('Source support normal fit distances")[0].replace("CAP=Path('/private/tmp/jtm-yodo-complete-secondary-v1/captures/002693')","CAP=Path('/private/tmp/jtm-yodo-complete-primary-v1/captures/002969')").replace('for n in range(8,18):','for n in range(14):').replace("if 300<=common[0]<=480 and common[1]<420-(common[0]-320)*48/180-5:continue",'if False:continue')
defs=defs.replace('abs(d)*0.001','abs(d)*0.1').replace('for d in range(-60,61):','for d in range(-60,61):\n  if abs(d)>20:continue')
exec(defs)
pkg=json.loads(SRC.read_text());nk=next(x for x in pkg['lines'] if x['id']=='jp-土佐くろしお鉄道-中村線');source=[nk['segments'][1][2][-1]]+nk['segments'][2][2];pts=[project(q) for q in source];chain=[0]
for a,b in zip(pts,pts[1:]):chain.append(chain[-1]+math.dist(a,b))
scale=frames[6][0]['camera']['metresPerPoint']/8;values=[chain[4]];cur=chain[4]+25/scale
while cur<chain[-2]:values.append(cur);cur+=25/scale
values.append(chain[-2]);controls=[];missing=[]
for k,s in enumerate(values):
 i=next(i for i in range(len(pts)-1) if chain[i]<=s<=chain[i+1]);f=(s-chain[i])/(chain[i+1]-chain[i]);p=tuple(pts[i][j]+f*(pts[i+1][j]-pts[i][j]) for j in range(2));d=math.dist(pts[i],pts[i+1]);t=[(pts[i+1][j]-pts[i][j])/d for j in range(2)];q=fit(p,t)
 if not q:missing.append({'controlID':f'T{k:03}','sourceChainageMapPoints':s,'sourceBracket':[i,i+1]});continue
 q.update({'controlID':f'T{k:03}','sourceChainageMapPoints':s,'sourceBracket':[i,i+1]});controls.append(q)
# Trim final Naka1 fit supports before the independently picked north approach.
north=kw['northApproachCoordinates'];ymin=north[0][1];n1=[q for q in v3['nakamuraInterval1Coordinates'] if q[1]>ymin]+north
n2=kw['southApproachCoordinates']+[q['coordinate'] for q in controls]+[source[-1]]
assert n1[-1]==n2[0]==kw['candidateDisplayAlias'] and n2[-1]==source[-1]
def turns(coords):
 pp=[project(q) for q in coords];out=[]
 for i in range(1,len(pp)-1):
  a=[pp[i][j]-pp[i-1][j] for j in range(2)];b=[pp[i+1][j]-pp[i][j] for j in range(2)];den=math.hypot(*a)*math.hypot(*b)
  if den:out.append([i,math.degrees(math.acos(max(-1,min(1,sum(a[j]*b[j] for j in range(2))/den))))])
 return out
result={'status':'candidate-only-native-replay-required','nakamuraInterval1Coordinates':n1,'nakamuraInterval2Coordinates':n2,'kainaAlias':kw['candidateDisplayAlias'],'preciseWitnessPath':str(BASE/'station-precise/kaina-z18/station-candidate-witness.json'),'controls':controls,'unsupportedSamples':missing,'sourceCoordinates2':source,'sourcePhysicalPackageSha256':hashlib.sha256(SRC.read_bytes()).hexdigest(),'maximumTurns':{'interval1':max(turns(n1),key=lambda x:x[1]),'interval2':max(turns(n2),key=lambda x:x[1])},'turnsAbove30':{'interval1':[x for x in turns(n1) if x[1]>30],'interval2':[x for x in turns(n2) if x[1]>30]},'stationWarnings':kw['supportWarnings'],'outerIyokiGuard':source[-1]}
(ROOT/'candidate.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
for n,coords in [(1,n1),(2,n2)]:(ROOT/f'nakamura-interval-{n}-coordinates.json').write_text(json.dumps(coords,indent=2)+'\n')
for n,(v,raw) in frames.items():
 im=raw.copy();d=ImageDraw.Draw(im);px=lambda q:pixel(n,project(q));d.line([px(q) for q in source],fill=(230,30,30),width=2);d.line([px(q) for q in n2],fill=(10,150,30),width=2)
 for q in controls:
  x,y=px(q['coordinate'])
  if 0<=x<1024 and 0<=y<768:d.ellipse((x-1,y-1,x+1,y+1),fill='black')
  if 0<=x<1024 and 0<=y<768 and int(q['controlID'][1:])%10==0:d.text((x+3,y-12),q['controlID'],fill='black')
 d.rectangle((0,0,670,20),fill='white');d.text((3,3),f'Nakamura2 {n}: source red candidate green actual own-band controls black',fill='black');im.save(ROOT/f'reprojection-{n:02}.png')
for start in range(0,14,4):
 im=Image.new('RGB',(1024,800),'white')
 for n in range(start,min(14,start+4)):im.paste(Image.open(ROOT/f'reprojection-{n:02}.png').resize((512,384)),((n-start)%2*512,(n-start)//2*400))
 im.save(ROOT/f'candidate-contact-{start:02}.jpg')
r=hv['mapRect'];sc=hv['camera']['mapPointsPerPoint'];high=Image.open(BASE/'station-precise/kaina-z18/basemap.png').convert('RGB');d=ImageDraw.Draw(high)
def hpx(q):a,b=project(q);return((a-r['x'])/sc,(b-r['y'])/sc)
d.line([hpx(q) for q in n1],fill=(255,120,0),width=2);d.line([hpx(q) for q in n2],fill=(0,255,0),width=2);x,y=hpx(kw['candidateDisplayAlias']);d.ellipse((x-4,y-4,x+4,y+4),outline=(255,0,255),width=2);high.save(ROOT/'kaina-precise-seam.png')
print('n1',len(n1),'n2',len(n2),'controls',len(controls),'missing',len(missing),'turns',result['turnsAbove30'],'max',result['maximumTurns']);print('offsetrange',min(x['normalOffsetPixels'] for x in controls),max(x['normalOffsetPixels'] for x in controls))
