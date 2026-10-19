import importlib.util,json, numpy as np
from pathlib import Path
p=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('body',p/'body-fit.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
# Explicit visual own-physical-band guides, not selection by blue persistence.
# 7 follows the lower paired physical railway as it separates from upper transit at coast.
# 8 begins lower paired; after Wajiki curve it becomes upper paired, crossing the stylized transit stroke.
# 9 remains upper paired above most labels.
GUIDES={
7:[(8,520,378),(8,570,396),(8,620,424),(8,670,434),(8,720,441),(8,780,445),(8,850,449),(10,300,386),(10,500,391),(10,700,394),(10,820,402),(12,300,386),(12,450,394),(12,600,398),(12,800,403),(12,1000,408)],
8:[(0,100,378),(0,300,386),(0,500,395),(0,700,400),(0,900,406),(2,200,402),(2,300,404),(2,350,403),(2,400,399),(2,450,391),(2,500,377),(2,550,360),(2,600,340),(2,650,324),(2,700,312),(2,750,306),(2,800,303),(2,850,302),(2,900,303),(3,450,352),(3,550,357),(3,650,362),(3,750,371),(3,850,380),(3,950,390),(4,600,383),(4,700,396),(4,800,407)],
9:[(0,100,322),(0,200,336),(0,300,349),(0,400,362),(0,500,376),(0,650,400),(0,800,418),(0,950,440),(3,200,344),(3,400,370),(3,600,392),(3,750,422),(3,900,453),(5,300,344),(5,400,362),(5,500,382),(5,650,408)]}

def nearest(q,ps,chain):
 best=None
 for k,(a,b)in enumerate(zip(ps,ps[1:])):
  d=b-a;t=np.clip(np.dot(q-a,d)/np.dot(d,d),0,1);r=a+t*d;dist=np.linalg.norm(q-r)
  if best is None or dist<best[0]:best=(dist,chain[k]+t*(chain[k+1]-chain[k]),r,k)
 return best

def update():
 j=json.loads((p/'body-candidates.json').read_text())
 if not(p/'rejected-first-fit.json').exists():(p/'rejected-first-fit.json').write_text(json.dumps(j,ensure_ascii=False,indent=2))
 for i,guide in GUIDES.items():
  row=j['intervals'][i];ps=np.array([m.world(q)for q in m.source(i)]);chain=np.r_[0,np.cumsum(np.linalg.norm(np.diff(ps,axis=0),axis=1))]
  picks=[]
  for view,x,y in guide:
   vp=m.views(i)[view];v=json.loads(vp.read_text());ll=m.ll([x,y],v);q=m.world(ll);dist,s,r,k=nearest(q,ps,chain)
   if (s<1 or s>chain[-1]-1) and dist>400:continue
   tangent=ps[k+1]-ps[k];tangent/=np.linalg.norm(tangent);normal=np.array([-tangent[1],tangent[0]]);off=np.dot(q-r,normal)
   picks.append(dict(chain=float(s),coordinate=ll,rawPixel=[x,y],offset=float(off),capture=str(vp.parent.relative_to(m.B)),camera=v['camera'],mapRect=v['mapRect'],status='manual-identified-paired-physical-band-guide',pixelUncertainty=2))
  picks.sort(key=lambda x:x['chain']);unique=[]
  for x in picks:
   if unique and x['chain']-unique[-1]['chain']<80:continue
   unique.append(x)
  picks=unique;row['manualPhysicalBandControls']=picks
  # Interpolation is explicit; exact pixel witnesses are in manualPhysicalBandControls.
  fn=lambda s: np.interp(s,[x['chain']for x in picks],[x['offset']for x in picks])
  start=picks[0]['chain']
  for n,c in enumerate(row['controls']):
   s=c['chain']
   if i==7 and s<start:continue
   k=min(np.searchsorted(chain,s,side='right')-1,len(ps)-2);k=max(0,k);t=(s-chain[k])/(chain[k+1]-chain[k]);r=ps[k]*(1-t)+ps[k+1]*t
   tangent=ps[k+1]-ps[k];tangent/=np.linalg.norm(tangent);normal=np.array([-tangent[1],tangent[0]])
   bounded=np.clip(s,picks[0]['chain'],picks[-1]['chain']);off=float(fn(bounded));q=r+normal*off
   c['rejectedPreManualCoordinate']=row['coordinates'][n];c['world']=q.tolist();c['offset']=off;c['status']='interpolated-between-manual-paired-band-controls';c['capture']=None;c.pop('rawPixel',None);row['coordinates'][n]=m.geo(q)
  row['physicalBandWarning']='Upper/lower named transit and physical railway cross; manual own paired band controls own this body. Station endpoints remain parent-owned.'
 (p/'body-candidates.json').write_text(json.dumps(j,ensure_ascii=False,indent=2));m.render()
if __name__=='__main__':update()
