"""Candidate-only exact-camera reprojection. Never operates apps or production inputs."""
import json,math,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
OUT=Path(__file__).resolve().parent
BASE=OUT.parent
W=268435456
LID='jp-土佐くろしお鉄道-中村線'
def read(p):return json.loads((BASE/p).read_text())
def project(q):return [W*(q[0]+180)/360,W*(1-math.asinh(math.tan(math.radians(q[1])))/math.pi)/2]
def inverse(x,y):return [x/W*360-180,math.degrees(math.atan(math.sinh(math.pi*(1-2*y/W))))]
def px(v,q):r=v['mapRect'];s=v['camera']['mapPointsPerPoint'];a,b=project(q);return [(a-r['x'])/s,(b-r['y'])/s]
def from_px(v,q):r=v['mapRect'];s=v['camera']['mapPointsPerPoint'];return inverse(r['x']+s*q[0],r['y']+s*q[1])
def save(name,x):(OUT/name).write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
inputs=['proposal-own-bodies-v2/nakamura00-coordinates.json','proposal-kaina-tail-v4/nakamura-interval-1-coordinates.json','proposal-kaina-tail-v4/nakamura-interval-2-coordinates.json','proposal-outer-bodies-v2/naka3-coordinates.json']
coords=[read(p) for p in inputs]
# The old full Naka3 fitter kept physical interpolation when <=2px from own rail.
# Use its actual own-band pixel witnesses directly in this uncomplicated named
# corridor, rather than treating source agreement as Apple alignment.
naka3w=read('proposal-outer-bodies-v2/naka3-pixel-controls.json')
naka3literal=[]
for q in naka3w['controls']:
 v=read(f"native-outer-adjacent-baseline/primary/captures/002970/{q['view']:06}/view.json")
 literal=from_px(v,q['ownPixel'])
 naka3literal.append(literal)
 q['originalStoredCoordinate']=q.pop('coordinates')
 q['literalPixelCoordinate']=literal
 q['basis']='Actual identified Nakamura thin blue railway; literal ownPixel inverse of named original view camera. Preserved original-fit gaps require native replay.'
coords[3]=[coords[3][0]]+naka3literal+[coords[3][-1]]

naka0view=read('native/primary/captures/002963/000000/view.json')
# Actual selected west continuation: right line remains a separate fan rail until
# its later convergence. Label pixels falsely pulled earlier body controls3..8.
naka0corrected_pixels=[[505.7,459],[506.2,485],[506.5,510],[506.3,535],[505.5,560],[505.0,585]]
naka0rejected=[{'index':i,'coordinate':coords[0][i],'pixel':px(naka0view,coords[0][i])} for i in range(3,9)]
coords[0][3:9]=[from_px(naka0view,p) for p in naka0corrected_pixels]
iyoki=read('stations-all-z18/guard-iyoki-009579/view.json')
alias=[133.0983224428835,33.10458511013298]
# Independently corrected literal rail picks: prior witness used x502/497/493 at
# y328/422/516; actual raw centre is about503/498/494. Preserve approved alias
# within disclosed 1.5px tolerance rather than silently change Root's point.
north_pixels=[[518.5,40],[515.5,100],[514,130],[511,180],[510.3,200],[504,320],[500.5,380]]
south_pixels=[[496.2,460],[494.2,500],[492.5,540],[491.7,570],[490.7,600]]
north=[from_px(iyoki,p) for p in north_pixels]+[alias]
south=[alias]+[from_px(iyoki,p) for p in south_pixels]
coords[2]=[q for q in coords[2] if q[1]>north[0][1]]+north
coords[3]=south+[q for q in coords[3] if q[1]<south[-1][1]]
assert coords[0][-1]==coords[1][0]
assert coords[1][-1]==coords[2][0]
assert coords[2][-1]==coords[3][0]==alias
shared=read('proposal-wakai-nakamura-v3/candidate.json')['sharedCoordinates']
yodo=read('proposal-all-yodo-stations-v2/yodo00-coordinates.json')
assert coords[1][:len(shared)]==shared==yodo[:len(shared)]
def turns(a):
 p=[project(q) for q in a];result=[]
 for i in range(1,len(p)-1):
  u=[p[i][j]-p[i-1][j] for j in [0,1]];v=[p[i+1][j]-p[i][j] for j in [0,1]];d=math.hypot(*u)*math.hypot(*v)
  if d:result.append({'index':i,'degrees':math.degrees(math.acos(max(-1,min(1,sum(u[j]*v[j] for j in [0,1])/d))))})
 return result
warnings=[{'stationID':'009500','status':'WARNING','retainedGuard':coords[0][0],'reason':'Kubokawa multi unequal faces and Dosan/Nakamura individual rail assignment unresolved. Shared code is not assignment; no new alias. If guard moves, Dosan59 also required.'},{'stationID':'009586','status':'WARNING','retainedGuard':coords[3][-1],'reason':'TosaSaga short upper face versus lower building-connected L strip remains unresolved. Last connector to retained physical guard is provisional, not accepted aligned station geometry. No new alias; a confirmed move requires complete Nakamura4.'},{'stationID':'009579','status':'WARNING-precision','reason':'Approved alias uses earlier fitted normal497.532421.331; corrected literal rail near498.3421.3 differs by ~0.8px within1.5px declared normal tolerance. Road occludes y~220–299; inferred north continuation between actual rail flanks200 and320. Cartographic, not surveyed.'}]
checks=[]
for idx,a in enumerate(coords):
 t=turns(a);checks.append({'intervalIndex':idx,'count':len(a),'start':a[0],'end':a[-1],'maximumTurn':max(t,key=lambda x:x['degrees']),'turnsAbove30':[q for q in t if q['degrees']>30],'minimumEdgeMapPoints':min(math.dist(project(u),project(v)) for u,v in zip(a,a[1:]))})
 save(f'nakamura-{idx}-coordinates.json',a)
records=[]
roots=['native/primary/captures/002963','native/primary/captures/002964','native/primary/captures/002969','native-outer-adjacent-baseline/primary/captures/002970']
for idx,root in enumerate(roots):
 views=sorted((BASE/root).glob('*/view.json'),key=lambda p:json.loads(p.read_text())['pointOrdinal'])
 for vp in views:
  v=json.loads(vp.read_text());assert v['lineID']==LID and v['intervalIndex']==idx
  raw=Image.open(vp.parent/'basemap.png').convert('RGB');assert raw.size==(round(v['camera']['viewportWidthPoints']),round(v['camera']['viewportHeightPoints']))
  im=raw.copy();d=ImageDraw.Draw(im);source=v['sourceCoordinates'][0]
  d.line([px(v,q) for q in source],fill=(220,40,40),width=1)
  d.line([px(v,q) for q in coords[idx]],fill=(0,130,20),width=1)
  for q in [coords[idx][0],coords[idx][-1]]:
   x,y=px(v,q);d.ellipse((x-3,y-3,x+3,y+3),outline=(240,0,220),width=1)
  n=v['pointOrdinal'];name=f'nakamura-{idx}-view-{n:02}.png';im.save(OUT/name)
  records.append({'intervalIndex':idx,'viewOrdinal':n,'rawView':str(vp),'rawBasemap':str(vp.parent/'basemap.png'),'dimensions':list(raw.size),'camera':v['camera'],'mapRect':v['mapRect'],'candidateReprojection':name,'status':'candidate-overlay-not-native-replay'})
 for kind in ['raw','candidate']:
  for start in range(0,len(views),4):
   sheet=Image.new('RGB',(1024,820),'white');d=ImageDraw.Draw(sheet)
   for n,vp in enumerate(views[start:start+4],start):
    img=Image.open(vp.parent/'basemap.png' if kind=='raw' else OUT/f'nakamura-{idx}-view-{n:02}.png');j=n-start;xx=j%2*512;yy=j//2*410
    sheet.paste(img.resize((512,384)),(xx,yy+20));d.text((xx+3,yy+3),f'Nakamura{idx} {kind} view{n}',fill='black')
   sheet.save(OUT/f'nakamura-{idx}-{kind}-contact-{start:02}.jpg')
# Exact highzoom seam witnesses include both sides and selected alias.
for name,viewpath,items,station in [('iyoki','stations-all-z18/guard-iyoki-009579/view.json',[(2,coords[2]),(3,coords[3])],alias),('wakai','station-precise/wakai-z18/view.json',[(0,coords[0]),(1,coords[1])],coords[1][0]),('kaina','station-precise/kaina-z18/view.json',[(1,coords[1]),(2,coords[2])],coords[2][0])]:
 v=read(viewpath);im=Image.open(BASE/Path(viewpath).parent/'basemap.png').convert('RGB');d=ImageDraw.Draw(im)
 for k,(idx,a) in enumerate(items):d.line([px(v,q) for q in a],fill=[(240,100,0),(0,200,70)][k],width=1)
 x,y=px(v,station);d.ellipse((x-3,y-3,x+3,y+3),outline=(255,0,255),width=1)
 im.save(OUT/f'{name}-seam-reprojection.png')
 if name=='iyoki':
  for p in north_pixels+south_pixels:
   x,y=p;d.ellipse((x-1,y-1,x+1,y+1),outline=(255,255,0))
  im.save(OUT/'iyoki-controls-reprojection.png')
receipt={'format':'jtm-nakamura-display-candidate-v1','status':'candidate-only-root-native-testing-pending','lineID':LID,'inputs':[{ 'path':str(BASE/p),'sha256':hashlib.sha256((BASE/p).read_bytes()).hexdigest()} for p in inputs],'intervals':[{'lineID':LID,'intervalIndex':i,'coordinates':a} for i,a in enumerate(coords)],'checks':checks,'sharedWakai':{'exactPrefixPoints':len(shared),'firstThree':shared[:3],'fork':read('proposal-wakai-nakamura-v3/candidate.json')['cartographicFork'],'policy':'Unchanged exact complete shared stem; diverging own continuations retain source direction, no physical graph change.'},'naka3Body':{'literalControls':naka3w['controls'],'gaps':naka3w['gaps'],'policy':'Literal ownPixel inverse per actual raw camera, including formerly retained source within2px; uncomplicated uniquely identified Nakamura rail. No road/river labels accepted as own identity.'},'naka0Correction':{'rawView':str(BASE/'native/primary/captures/002963/000000/view.json'),'rejected':naka0rejected,'acceptedPixels':naka0corrected_pixels,'supportedFlanks':[[506,450],[506.3,535],[505.5,560],[505.0,585],[504,610]],'warning':'459-520 own west railway hidden by Nakamura label; interpolated own continuation, not text or competing east fan. Kubokawa rail assignment warning remains.'},'iyokiWitness':{'rawView':str(BASE/'stations-all-z18/guard-iyoki-009579/view.json'),'dimensions':[999,654],'faceEndpoints':[[515,328],[508,516]],'faceMidpoint':[511.5,422],'approvedAlias':alias,'approvedAliasPixel':px(iyoki,alias),'correctedRailPicks':[[503,328],[498.3,421.3],[494,516]],'northApproachPixels':north_pixels,'southApproachPixels':south_pixels,'northApproachCoordinates':north,'southApproachCoordinates':south,'roadOcclusionY':[220,299]},'warnings':warnings,'reprojections':records,'preserved':'Physical IDs, stations, km, segments, routing and production files untouched. Candidate interval indices refer to existing owners.','acceptance':False}
save('candidate.json',receipt)
print(json.dumps(checks,ensure_ascii=False,indent=2))
