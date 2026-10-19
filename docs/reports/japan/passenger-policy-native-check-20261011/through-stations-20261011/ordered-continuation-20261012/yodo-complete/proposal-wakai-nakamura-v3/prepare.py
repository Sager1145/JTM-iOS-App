import json,math,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).parent
BASE=ROOT.parent
v2=json.loads((BASE/'proposal-stem-loop-v2/shared-stem-loop-candidate.json').read_text());wit=json.loads((BASE/'station-precise/station-candidate-witness.json').read_text())['wakai'];hv=json.loads((BASE/'station-precise/wakai-z18/view.json').read_text())
defs=(BASE/'proposal-loop-v1/fit-proposal.py').read_text().split("print('Source support normal fit distances")[0]
# Load the same bounded blue normal/persistence fitter with actual Nakamura1 frames.
defs=defs.replace("CAP=Path('/private/tmp/jtm-yodo-complete-secondary-v1/captures/002693')","CAP=Path('/private/tmp/jtm-yodo-complete-primary-v1/captures/002964')").replace('for n in range(8,18):','for n in range(29):')
# Remove lower-Yodo-specific competitor mask; replace with upper Nakamura branch discriminator below.
defs=defs.replace("if 300<=common[0]<=480 and common[1]<420-(common[0]-320)*48/180-5:continue", "if competitor_rejected(common):continue")
# This fit has different cameras, so common branch reference must be the exact Secondary view11.
defs=defs.replace("common=pixel(11,(rr['x']+8*hits[2][1],rr['y']+8*hits[2][2]))","cr=common_reference; common=((rr['x']+8*hits[2][1]-cr['x'])/8,(rr['y']+8*hits[2][2]-cr['y'])/8)")
common_reference=json.loads(Path('/private/tmp/jtm-yodo-complete-secondary-v1/captures/002693/000011/view.json').read_text())['mapRect']
def competitor_rejected(q):
 x,y=q;bounds=[(0,-140),(65,0),(100,230),(200,330),(300,366),(400,377),(509,368)]
 if not 300<=x<=509:return False
 a,b=next((a,b) for a,b in zip(bounds,bounds[1:]) if a[0]<=x<=b[0]);upper=a[1]+(x-a[0])*(b[1]-a[1])/(b[0]-a[0]);return y>upper+12
exec(defs)
source=v2['nakamuraSourceCoordinates'];pts=[project(q) for q in source];chain=[0]
for a,b in zip(pts,pts[1:]):chain.append(chain[-1]+math.dist(a,b))
scale=frames[14][0]['camera']['metresPerPoint']/8;values=[chain[66]];cur=chain[66]+25/scale
while cur<chain[-2]:values.append(cur);cur+=25/scale
values.append(chain[-2]);controls=[];missing=[]
for k,s in enumerate(values):
 i=next(i for i in range(len(pts)-1) if chain[i]<=s<=chain[i+1]);f=(s-chain[i])/(chain[i+1]-chain[i]);p=tuple(pts[i][j]+f*(pts[i+1][j]-pts[i][j]) for j in range(2));d=math.dist(pts[i],pts[i+1]);t=[(pts[i+1][j]-pts[i][j])/d for j in range(2)];q=fit(p,t)
 if not q:missing.append({'controlID':f'N{k:03}','sourceChainageMapPoints':s,'sourceBracket':[i,i+1]});continue
 q.update({'controlID':f'N{k:03}','sourceChainageMapPoints':s,'sourceBracket':[i,i+1]});controls.append(q)
# Explicit high-zoom actual own black rail support immediately south of the alias.
r=hv['mapRect'];sc=hv['camera']['mapPointsPerPoint'];localpix=[503,340];local=inverse(r['x']+sc*localpix[0],r['y']+sc*localpix[1]);alias=wit['candidateDisplayAlias']
shared=[alias,local]+v2['sharedCoordinates'][1:]
yodo=shared+v2['yodoInterval0Coordinates'][len(v2['sharedCoordinates']):]
naka=shared+[q['coordinate'] for q in controls]+[source[-1]]
assert yodo[:len(shared)]==naka[:len(shared)] and yodo[0]==alias and naka[-1]==source[-1]
def turns(coords):
 pp=[project(q) for q in coords];out=[]
 for i in range(1,len(pp)-1):
  a=[pp[i][j]-pp[i-1][j] for j in range(2)];b=[pp[i+1][j]-pp[i][j] for j in range(2)];den=math.hypot(*a)*math.hypot(*b)
  if den:out.append([i,math.degrees(math.acos(max(-1,min(1,sum(a[j]*b[j] for j in range(2))/den))))])
 return out
result={'status':'candidate-only-no-native-acceptance','wakaiAlias':alias,'wakaiWitnessPath':str(BASE/'station-precise/station-candidate-witness.json'),'localApproachWitness':{'rawView':str(BASE/'station-precise/wakai-z18/view.json'),'pixel':localpix,'coordinate':local,'note':'Explicit south own sleeper support already listed in precise frame witness; high-zoom black rail evidence.'},'sharedCoordinates':shared,'yodoInterval0Coordinates':yodo,'nakamuraInterval1Coordinates':naka,'nakamuraSourceCoordinates':source,'suffixControls':controls,'unsupportedSuffixSamples':missing,'cartographicFork':v2['forkCartographicWitness'],'turnsAbove30':{'yodo':[x for x in turns(yodo) if x[1]>30],'nakamura':[x for x in turns(naka) if x[1]>30]},'maximumTurn':{'yodo':max(turns(yodo),key=lambda x:x[1]),'nakamura':max(turns(naka),key=lambda x:x[1])},'limits':['Candidate only: precise alias is cartographic, not physical station coordinate.','Complete Nakamura0 approach and Kita/Yosan scope remain separately owned.','Blue glyph forest/tunnel geometry is not surveyed own rails; gaps disclosed.']}
(ROOT/'candidate.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');(ROOT/'yodo-interval-0-coordinates.json').write_text(json.dumps(yodo,indent=2)+'\n');(ROOT/'nakamura-interval-1-coordinates.json').write_text(json.dumps(naka,indent=2)+'\n')
# Exact-camera raw reprojections for ALL29 Nakamura frames plus precise Wakai.
projections=[]
for n,(v,raw) in frames.items():
 im=raw.copy();d=ImageDraw.Draw(im);px=lambda q:pixel(n,project(q));d.line([px(q) for q in source],fill=(230,30,30),width=2);d.line([px(q) for q in naka],fill=(10,150,30),width=2)
 marks=[]
 for q in controls:
  x,y=px(q['coordinate']);vis=0<=x<1024 and 0<=y<768;marks.append({'controlID':q['controlID'],'pixel':[x,y],'visible':vis})
  if vis:d.ellipse((x-1,y-1,x+1,y+1),fill='black')
  if vis and int(q['controlID'][1:])%12==0:d.text((x+3,y-12),q['controlID'],fill='black')
 d.rectangle((0,0,760,20),fill='white');d.text((3,3),f'Nakamura1 view{n}: red=source green=candidate black=exact suffix pixel controls',fill='black');im.save(ROOT/f'nakamura-reprojection-{n:02}.png');projections.append({'viewOrdinal':n,'camera':v['camera'],'mapRect':v['mapRect'],'controlProjections':marks})
(ROOT/'nakamura-reprojections.json').write_text(json.dumps(projections,indent=2)+'\n')
for start in range(0,29,4):
 im=Image.new('RGB',(1024,800),'white')
 for n in range(start,min(29,start+4)):im.paste(Image.open(ROOT/f'nakamura-reprojection-{n:02}.png').resize((512,384)),((n-start)%2*512,(n-start)//2*400))
 im.save(ROOT/f'candidate-contact-{start:02}.jpg')
high=Image.open(BASE/'station-precise/wakai-z18/basemap.png').convert('RGB');d=ImageDraw.Draw(high)
def hpx(q):a,b=project(q);return((a-r['x'])/sc,(b-r['y'])/sc)
d.line([hpx(q) for q in shared],fill=(0,255,0),width=2);x,y=hpx(alias);d.ellipse((x-4,y-4,x+4,y+4),outline=(255,0,255),width=2);d.text((x+8,y),'Wakai exact witness alias',fill='white');high.save(ROOT/'wakai-highzoom-reprojection.png')
print('suffixcontrols',len(controls),'missing',len(missing),'shared',len(shared),'yodo',len(yodo),'naka',len(naka),'turns',result['turnsAbove30'],'max',result['maximumTurn'])
