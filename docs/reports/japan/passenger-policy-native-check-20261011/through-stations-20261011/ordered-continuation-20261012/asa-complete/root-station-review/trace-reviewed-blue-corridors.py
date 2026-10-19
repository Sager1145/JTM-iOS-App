"""Candidate tracing of the five manually identified Asa passenger corridors.

Reads original Apple snapshot pixels and their actual mapRects. Blue chroma
rejects grey roads/buildings and cyan water; directional continuity crosses
label halos. This produces proposals, never an automatic alignment verdict.
Platform/branch identity and station aliases remain explicit human inputs.
"""
from pathlib import Path
import json,math
import numpy as np
from PIL import Image,ImageFilter,ImageDraw
base=Path(__file__).resolve().parent.parent;out=base/'root-body-trace-v3';out.mkdir(exist_ok=True)
d=json.loads((base/'root-station-review/candidate-all-20-intervals-v2.json').read_text());views=json.loads((base/'native-candidate-v2/primary/capture-index.json').read_text());W=268435456
mk=lambda c:np.array([W*(c[0]+180)/360,W*(1-math.log(math.tan(math.pi/4+c[1]*math.pi/360))/math.pi)/2])
ll=lambda p:[float(p[0]/W*360-180),math.degrees(math.atan(math.sinh(math.pi*(1-2*p[1]/W))))]
receipts=[]
def simplify(p,tol):
 if len(p)<3:return p
 a,b=p[0],p[-1];v=b-a;den=np.dot(v,v);t=np.clip(((p-a)@v)/den,0,1) if den else np.zeros(len(p));dist=np.linalg.norm(p-(a+t[:,None]*v),axis=1);j=int(np.argmax(dist))
 if dist[j]<=tol:return np.array([a,b])
 return np.vstack([simplify(p[:j+1],tol)[:-1],simplify(p[j:],tol)])
for index in [7,8,9,10,11]:
 r=d['intervals'][index];src=np.array([mk(p) for p in r['coordinates']]);mpp=math.cos(math.radians(r['coordinates'][0][1]))*2*math.pi*6378137/W
 lengths=np.linalg.norm(np.diff(src,axis=0),axis=1);chain=np.r_[0,np.cumsum(lengths)];positions=np.linspace(0,chain[-1],max(3,int(chain[-1]*mpp/10)+1));points=np.column_stack([np.interp(positions,chain,src[:,k]) for k in [0,1]])
 tangent=np.gradient(points,axis=0);tangent/=np.linalg.norm(tangent,axis=1)[:,None];normal=np.column_stack([-tangent[:,1],tangent[:,0]])
 offsets=np.arange(-350,351,dtype=float);candidates=points[:,None,:]+normal[:,None,:]*offsets[None,:,None]/mpp;scores=np.zeros(candidates.shape[:2]);valid=np.zeros(scores.shape,dtype=bool)
 for row in [v for v in views if v['intervalIndex']==index]:
  c=row['camera'];im=Image.open(Path(row['folder'])/'basemap.png').convert('RGB');rgb=np.asarray(im).astype(np.int16);R,G,B=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
  mask=(B-G>45)&(G-R>4)&(G-R<90)&(B>170)&(R>40)
  thick=np.asarray(Image.fromarray((mask*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)))/255
  h,w=thick.shape;xx=(candidates[:,:,0]-c['rectX'])/c['mapPointsPerPoint'];yy=(candidates[:,:,1]-c['rectY'])/c['mapPointsPerPoint'];ok=(xx>=12)&(xx<w-12)&(yy>=12)&(yy<h-12)
  score=np.zeros_like(xx)
  # Longitudinal support, rather than nearest single blue pixel, rejects
  # isolated shields/letters. Labels can still require manual review.
  for along in [-6,-3,0,3,6]:
   x=np.rint(xx+tangent[:,None,0]*along/(mpp*c['mapPointsPerPoint'])).astype(int);y=np.rint(yy+tangent[:,None,1]*along/(mpp*c['mapPointsPerPoint'])).astype(int);score+=thick[np.clip(y,0,h-1),np.clip(x,0,w-1)]/5
  scores=np.maximum(scores,np.where(ok,score,0));valid|=ok
 cost=(1-scores)*6+np.abs(offsets)[None,:]*0.0008;cost[~valid]=50
 # Approved station/frame aliases are fixed; station shapes are never
 # inferred from chroma or averaged across unrelated platform families.
 edge=np.minimum(positions,positions[-1]-positions)*mpp;bound=np.minimum(350,edge*0.6);cost[np.abs(offsets)[None,:]>bound[:,None]]=1e8
 previous=cost[0].copy();backs=[];count=len(offsets)
 for i in range(1,len(points)):
  options=[]
  for delta in range(-12,13):
   old=np.full(count,1e9);start=max(0,delta);end=min(count,count+delta);old[start:end]=previous[start-delta:end-delta]+0.025*delta*delta;options.append(old)
  options=np.array(options);choice=np.argmin(options,axis=0);previous=cost[i]+options[choice,np.arange(count)];backs.append(np.arange(count)-(choice-12))
 chosen=np.zeros(len(points),dtype=int);chosen[-1]=int(np.argmin(previous))
 for i in range(len(points)-2,-1,-1):chosen[i]=backs[i][chosen[i+1]]
 selected=offsets[chosen];filtered=np.array([np.median(selected[max(0,i-2):min(len(selected),i+3)]) for i in range(len(selected))]);filtered[0]=filtered[-1]=0
 traced=points+normal*filtered[:,None]/mpp;traced=simplify(traced,1/mpp);coordinates=[ll(p) for p in traced];coordinates[0]=r['coordinates'][0];coordinates[-1]=r['coordinates'][-1];r['coordinates']=coordinates
 receipts.append({'intervalIndex':index,'sourceViews':len([v for v in views if v['intervalIndex']==index]),'sampleCount':len(points),'maximumProposedShiftMetres':float(np.max(np.abs(filtered))),'weakDirectionalSupportSamples':int(np.sum(scores[np.arange(len(points)),chosen]<0.4)),'coordinates':len(coordinates),'status':'proposal-only-manual-and-native-review-required'})
 # Reproject every complete original viewport for actual manual review.
 for row in [v for v in views if v['intervalIndex']==index]:
  c=row['camera'];im=Image.open(Path(row['folder'])/'basemap.png').convert('RGB');dr=ImageDraw.Draw(im)
  px=lambda p:tuple((mk(p)-np.array([c['rectX'],c['rectY']]))/c['mapPointsPerPoint'])
  dr.line([px(p) for p in coordinates],fill=(220,0,120),width=2);im.save(out/f"{index:02}-{row['pointOrdinal']:02}-proposal.png")
d['status']='root-body-trace-v3-proposal-native-acceptance-pending';d['nativeAcceptance']=False;d['rootBodyTraceReceipts']=receipts
(out/'candidate-all-20-intervals-v3.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');(out/'trace-receipts.json').write_text(json.dumps(receipts,ensure_ascii=False,indent=2)+'\n');print(json.dumps(receipts,ensure_ascii=False))
