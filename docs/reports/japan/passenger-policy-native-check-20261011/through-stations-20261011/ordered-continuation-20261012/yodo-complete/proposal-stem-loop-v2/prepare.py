import json,math,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).parent
old=ROOT.parent/'proposal-loop-v1/fit-proposal.py'
defs=old.read_text().split("print('Source support normal fit distances")[0].replace('for n in range(8,18):','for n in range(18):')
exec(defs)
# The station endpoint is deliberately provisional pending the frame worker.
local_scale=frames[12][0]['camera']['metresPerPoint']/8
values=[chain[1]];cur=chain[1]+25/local_scale
while cur<chain[100]:values.append(cur);cur+=25/local_scale
values.append(chain[100]);controls=[];missing=[]
for k,s in enumerate(values):
 i=next(i for i in range(103) if chain[i]<=s<=chain[i+1]);f=(s-chain[i])/(chain[i+1]-chain[i]);point=tuple(pts[i][j]+f*(pts[i+1][j]-pts[i][j]) for j in range(2));d=math.dist(pts[i],pts[i+1]);t=[(pts[i+1][j]-pts[i][j])/d for j in range(2)];q=fit(point,t)
 if not q:missing.append({'controlID':f'S{k:03}','chainageMapPoints':s,'sourceBracket':[i,i+1]});continue
 q.update({'controlID':f'S{k:03}','sourceChainageMapPoints':s,'sourceBracket':[i,i+1]});controls.append(q)
# Exact visible cartographic convergence witness, not a physical switch edit.
v=frames[11][0];r=v['mapRect'];fp=[509,368];fork=inverse(r['x']+8*fp[0],r['y']+8*fp[1]);print('forkRGB',frames[11][1].getpixel(tuple(fp)))
# Partition by forward common raw projection, not camera sequence.
common=[q for q in controls if pixel(11,project(q['coordinate']))[0]>509]
west=[q for q in controls if pixel(11,project(q['coordinate']))[0]<509]
shared=[source[0]]+[q['coordinate'] for q in common]+[fork]
yodo=shared+[q['coordinate'] for q in west]+source[101:]
pkg=json.loads(SRC.read_text());nk=next(x for x in pkg['lines'] if x['id']=='jp-土佐くろしお鉄道-中村線');nsource=[nk['segments'][0][2][-1]]+nk['segments'][1][2];naka=shared+nsource[66:]
# literal shared geometry, monotonic source sampling, physical arrays unchanged
assert yodo[:len(shared)]==naka[:len(shared)] and yodo[0]==nsource[0] and yodo[-3:]==source[-3:]
for label,coords in [('Yodo',yodo),('Nakamura',naka)]:
 cp=[project(q) for q in coords];turns=[]
 for i in range(1,len(cp)-1):
  aa=(cp[i][0]-cp[i-1][0],cp[i][1]-cp[i-1][1]);bb=(cp[i+1][0]-cp[i][0],cp[i+1][1]-cp[i][1]);den=math.hypot(*aa)*math.hypot(*bb)
  if den:turns.append((i,math.degrees(math.acos(max(-1,min(1,(aa[0]*bb[0]+aa[1]*bb[1])/den))))))
 print(label,'points',len(coords),'maxturn',max(turns,key=lambda x:x[1]))
result={'status':'candidate-only-station-alias-provisional','sourcePackageSha256':hashlib.sha256(SRC.read_bytes()).hexdigest(),'stationAliasStatus':'Wakai source point retained ONLY provisionally; final original frame worker must replace shared first endpoint and Nakamura0 end together before freeze/replay acceptance.','sharedCoordinates':shared,'yodoInterval0Coordinates':yodo,'nakamuraInterval1Coordinates':naka,'yodoSourceCoordinates':source,'nakamuraSourceCoordinates':nsource,'controls':controls,'unsupportedSamples':missing,'forkCartographicWitness':{'viewOrdinal':11,'pixel':fp,'rgb':list(frames[11][1].getpixel(tuple(fp))),'coordinate':fork,'limit':'Approximate thin-band convergence; does not move physical source turnout or graph. Narrow merged-band extent is several pixels.'},'retainedNakamuraSuffixFromSourceIndex':66,'retainedYodoSuffixFromSourceIndex':101,'limits':['Complete Nakamura1 suffix remains source and unaccepted; complete owner replay required.','Short missing persistence spans connect actual neighbour own-band controls, never a nearby road.','Station aliases and final native measures remain pending.']}
(ROOT/'shared-stem-loop-candidate.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
(ROOT/'yodo-interval-0-coordinates.json').write_text(json.dumps(yodo,ensure_ascii=False,indent=2)+'\n');(ROOT/'nakamura-interval-1-coordinates.json').write_text(json.dumps(naka,ensure_ascii=False,indent=2)+'\n')
repro=[]
for n,(v,raw) in frames.items():
 im=raw.copy();draw=ImageDraw.Draw(im);r=v['mapRect'];px=lambda q:pixel(n,project(q));draw.line([px(q) for q in source],fill=(220,30,30),width=2);draw.line([px(q) for q in yodo],fill=(10,150,30),width=2);draw.line([px(q) for q in naka],fill=(180,0,200),width=1)
 marks=[]
 for q in controls:
  x,y=px(q['coordinate']);visible=0<=x<1024 and 0<=y<768;marks.append({'controlID':q['controlID'],'pixel':[x,y],'visible':visible,'offscreenSide':None if visible else ('left' if x<0 else 'right' if x>=1024 else 'top' if y<0 else 'bottom')})
  if visible:draw.ellipse((x-1,y-1,x+1,y+1),fill=(0,0,0))
  if visible and int(q['controlID'][1:])%12==0:draw.text((x+4,y-12),q['controlID'],fill='black')
 for label,q in [('Wakai-PROVISIONAL',source[0]),('cartographic-seam',fork),('Iejigawa-guard',source[-1])]:
  x,y=px(q)
  if 0<x<1024 and 0<y<768:draw.rectangle((x-3,y-3,x+3,y+3),outline='black',width=2);draw.text((x+5,y+3),label,fill='black')
 draw.rectangle((0,0,780,20),fill='white');draw.text((3,3),f'view{n} red=source green=Yodo magenta=Nakamura provisional shared stem; no acceptance',fill='black');im.save(ROOT/f'reprojection-{n:02}.png');repro.append({'viewOrdinal':n,'camera':v['camera'],'mapRect':r,'controlProjections':marks})
(ROOT/'reprojections.json').write_text(json.dumps(repro,ensure_ascii=False,indent=2)+'\n')
for j in range(0,18,3):
 im=Image.new('RGB',(1536,384),'white')
 for n in range(j,j+3):im.paste(Image.open(ROOT/f'reprojection-{n:02}.png').resize((512,384)),((n-j)*512,0))
 im.save(ROOT/f'contact-{j:02}.jpg')
print('controls',len(controls),'missing',len(missing),'shared',len(shared))
