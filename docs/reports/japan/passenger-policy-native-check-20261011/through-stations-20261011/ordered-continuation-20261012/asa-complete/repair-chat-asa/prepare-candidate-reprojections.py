import json,math,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
B=Path('/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/asa-complete');O=B/'repair-chat-asa';F=O/'station-integrated';F.mkdir(exist_ok=True);W=268435456
PR=lambda q:(W*(q[0]+180)/360,W*(1-math.asinh(math.tan(math.radians(q[1])))/math.pi)/2)
IN=lambda x,y:[x/W*360-180,math.degrees(math.atan(math.sinh(math.pi*(1-2*y/W))))]
def load(p):return json.loads(p.read_text())
def save(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
def inv(v,p):r=v['mapRect'];s=v['camera']['mapPointsPerPoint'];return IN(r['x']+s*p[0],r['y']+s*p[1])
def pixel(v,q):x,y=PR(q);r=v['mapRect'];s=v['camera']['mapPointsPerPoint'];return[(x-r['x'])/s,(y-r['y'])/s]
west=load(O/'body00-09/body-candidates.json');east=load(O/'body10-19/candidate-intervals10-19.json');body={x['intervalIndex']:x['coordinates'] for x in west['intervals']};body.update({int(k):x['coordinates'] for k,x in east['intervals'].items()});st=load(O/'station-witnesses/station-candidates.json')['stations'];pkg=load(Path('/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/rail/jp-2025.json'));line=next(x for x in pkg['lines'] if x['id']==west['lineID'])
chain=[];original_bounds=[]
for i in range(20):
 a=body[i];start=len(chain)
 for q in a:
  if chain and q==chain[-1]:continue
  chain.append(q)
 original_bounds.append([start,len(chain)-1])
pts=[PR(q) for q in chain];dist=[0]
for a,b in zip(pts,pts[1:]):dist.append(dist[-1]+math.dist(a,b))
def near(q,first,last):
 p=PR(q);hits=[]
 for i in range(max(0,first),min(len(pts)-1,last)):
  a,b=pts[i],pts[i+1];v=[b[j]-a[j] for j in [0,1]];den=sum(x*x for x in v)
  if not den:continue
  t=max(0,min(1,sum((p[j]-a[j])*v[j] for j in [0,1])/den));r=[a[j]+t*v[j] for j in [0,1]];hits.append((math.dist(p,r),dist[i]+t*math.sqrt(den),i,t))
 return min(hits,key=lambda h:h[0])
ops=[];markers=[];unknown=[]
for k,row in enumerate(st):
 if row['status'].startswith('WARNING'):
  if k==0:pos=dist[0]
  else:pos=dist[original_bounds[k-1][1]]
  markers.append({'stationIndex':k,'stationID':row['stationID'],'position':pos,'coordinate':chain[0] if k==0 else chain[original_bounds[k-1][1]],'status':'provisional-body-boundary-only-NOT-station-alias','warning':row['warning']});unknown.append(k);continue
 v=load(Path(row['rawView']));rail=row['railBandControls'];mid=row['aliasPixel'];controls=[{'pixel':p,'coordinate':inv(v,p),'role':'identified-own-rail-band'} for p in rail]+[{'pixel':mid,'coordinate':row['displayCandidate'],'role':'own-face-normal-alias'}]
 # Recorded controls already follow west/east or north/south passenger order.
 tangent=[rail[-1][j]-rail[0][j] for j in [0,1]]
 controls.sort(key=lambda c:sum(c['pixel'][j]*tangent[j] for j in [0,1]))
 if k==20:controls=[c for c in controls if sum((c['pixel'][j]-mid[j])*tangent[j] for j in [0,1])<=1e-7]
 lower=original_bounds[max(0,k-1)][0];upper=original_bounds[min(19,k)][1]+1
 # Drop invalid old Ioki guard from both owners; the correct own raw corridor
 # passes500321.5→716442, while old15head539265 is an unsupported84px excursion.
 if k==15:controls=[c for c in controls if c['pixel'][0]>=420]
 lo=near(controls[0]['coordinate'],lower,upper);hi=near(controls[-1]['coordinate'],lower,upper)
 if k==20:hi=(0,dist[-1],len(pts)-1,1)
 if k==15:
  # Include old14endpoint and false15head, then rejoin the witnessed lower band
  # at the first legal body15 continuation after it.
  hi=near(controls[-1]['coordinate'],original_bounds[15][0]+1,original_bounds[15][1]+1)
 assert hi[1]>lo[1],(k,lo,hi)
 ops.append({'stationIndex':k,'stationID':row['stationID'],'lo':lo[1],'hi':hi[1],'controls':controls,'startNearestMapPoints':lo[0],'endNearestMapPoints':hi[0],'oldRangeIndices':[lo[2],hi[2]],'rawView':row['rawView']})
 markers.append({'stationIndex':k,'stationID':row['stationID'],'position':near(row['displayCandidate'],lower,upper)[1],'coordinate':row['displayCandidate'],'status':'candidate-own-face-normal'})
for a,b in zip(ops,ops[1:]):assert a['hi']<b['lo'],('overlap',a['stationIndex'],b['stationIndex'])
# Rebuild single path without forced physical-guard hooks at unknown station faces.
path=[];index_by_station={};source_index=0
for op in ops:
 while source_index<len(chain) and dist[source_index]<op['lo']:
  path.append(chain[source_index]);source_index+=1
 while source_index<len(chain) and dist[source_index]<=op['hi']:source_index+=1
 for c in op['controls']:
  if path and path[-1]==c['coordinate']:continue
  path.append(c['coordinate'])
  if c['role']=='own-face-normal-alias':index_by_station[op['stationIndex']]=len(path)-1
while source_index<len(chain):path.append(chain[source_index]);source_index+=1
for marker in markers:
 k=marker['stationIndex']
 if k in index_by_station:continue
 # Keep existing own body boundary; no station midpoint is invented.
 hits=[(math.dist(PR(q),PR(marker['coordinate'])),i) for i,q in enumerate(path)];_,i=min(hits);index_by_station[k]=i;marker['coordinate']=path[i]
# Explicit source endpoint removals audited in full station images; no blanket angle filter.
removals=load(O/'local-join-removals.json')
for rejection in removals:
 q=rejection['coordinate']
 if q not in path:continue
 j=path.index(q)
 assert j not in index_by_station.values(),('would remove station boundary',rejection)
 path.pop(j)
 index_by_station={k:(n-1 if n>j else n) for k,n in index_by_station.items()}
assert sorted(index_by_station)==list(range(21))
assert all(index_by_station[i]<index_by_station[i+1] for i in range(20)),index_by_station
intervals=[]
for i in range(20):
 arr=path[index_by_station[i]:index_by_station[i+1]+1];intervals.append({'intervalIndex':i,'lineID':line['id'],'fromStationID':st[i]['stationID'],'toStationID':st[i+1]['stationID'],'coordinates':arr,'startStatus':markers[i]['status'],'endStatus':markers[i+1]['status']});save(F/f'asa-{i:02}-coordinates.json',arr)
assert intervals[-1]['coordinates'][-1]==st[-1]['displayCandidate']
views=[]
for d in sorted((B/'native/primary/captures').glob('*')):
 for vp in sorted(d.glob('*/view.json')):
  v=load(vp);i=v['intervalIndex'];raw=Image.open(vp.parent/'basemap.png').convert('RGB');assert raw.size==(round(v['camera']['viewportWidthPoints']),round(v['camera']['viewportHeightPoints']));im=raw.copy();dr=ImageDraw.Draw(im)
  dr.line([pixel(v,q) for q in intervals[i]['coordinates']],fill=(200,25,100),width=1)
  for q in [intervals[i]['coordinates'][0],intervals[i]['coordinates'][-1]]:
   x,y=pixel(v,q);dr.ellipse((x-3,y-3,x+3,y+3),outline=(255,0,255),width=1)
  n=v['pointOrdinal'];name=f'asa-{i:02}-view-{n:02}.png';im.save(F/name);views.append({'intervalIndex':i,'viewOrdinal':n,'rawView':str(vp),'dimensions':list(raw.size),'camera':v['camera'],'mapRect':v['mapRect'],'reprojection':name})
for k,row in enumerate(st):
 p=Path(row['rawView']);v=load(p);im=Image.open(p.parent/'basemap.png').convert('RGB');d=ImageDraw.Draw(im)
 for i in [k-1,k]:
  if 0<=i<20:d.line([pixel(v,q) for q in intervals[i]['coordinates']],fill=(0,200,100) if i==k else (255,120,0),width=1)
 if row['status'].startswith('WARNING'):d.text((5,5),'WARNING alias withheld; own body boundary is NOT accepted station midpoint',fill='white')
 else:
  x,y=row['aliasPixel'];d.ellipse((x-4,y-4,x+4,y+4),outline=(255,0,255),width=1)
 im.save(F/f'station-{k:02}-seam.png')
for i in range(20):
 records=sorted([r for r in views if r['intervalIndex']==i],key=lambda q:q['viewOrdinal'])
 for start in range(0,len(records),4):
  im=Image.new('RGB',(1024,820),'white');d=ImageDraw.Draw(im)
  for j,r in enumerate(records[start:start+4]):
   x=j%2*512;y=j//2*410;im.paste(Image.open(F/r['reprojection']).resize((512,384)),(x,y+20));d.text((x+2,y+3),f'Asa{i} view{r["viewOrdinal"]} candidate only',fill='black')
  im.save(F/f'asa-{i:02}-contact-{start:02}.jpg')
result={'format':'asa-display-candidate-with-withheld-faces-v1','status':'candidate-only-five-station-assignments-unresolved-NOT-freeze-input','lineID':line['id'],'intervals':intervals,'displayStationCoordinates':{r['stationID']:r['displayCandidate'] for r in st if not r['status'].startswith('WARNING')},'allStationRows':st,'withheldStationIndexes':unknown,'provisionalBodyBoundaryMarkers':markers,'integrationOperations':ops,'reprojections':views,'physicalInvariant':'Physical source stations/segments/km/routes unchanged; all writes candidate directory only.','inputs':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [O/'body00-09/body-candidates.json',O/'body10-19/candidate-intervals10-19.json',O/'station-witnesses/station-candidates.json']],'localJoinRemovals':removals,'nativeAcceptance':False,'limits':['Unknown five station boundary points are only existing own-body cuts; no old physical return-hook connector or guessed face aliases are inserted.','A complete final owner input requires explicit Gomen/Noichi/Yoshikawa/hospital-front/Aki face adjudication.','Root alone owns allthreeInspectors/Main tests; generated150views are not acceptance.']}
save(O/'all-intervals-and-aliases.json',result)
print('intervalcounts',[(x['intervalIndex'],len(x['coordinates'])) for x in intervals]);print('candidatealiases',len(result['displayStationCoordinates']),'withheld',unknown,'views',len(views))
