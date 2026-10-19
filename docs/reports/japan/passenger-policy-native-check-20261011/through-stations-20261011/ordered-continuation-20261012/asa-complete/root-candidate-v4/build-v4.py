from pathlib import Path
import json,math,numpy as np
from PIL import Image,ImageDraw
b=Path('/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/asa-complete');o=b/'root-candidate-v4';o.mkdir(exist_ok=True);d=json.loads((b/'root-body-trace-v3/candidate-all-20-intervals-v3.json').read_text());v=json.loads((b/'stations-supplemental-20261014/04-009193-caps-z20/view.json').read_text());c=v['camera'];W=268435456
mk=lambda q:np.array([W*(q[0]+180)/360,W*(1-math.log(math.tan(math.pi/4+q[1]*math.pi/360))/math.pi)/2]);ll=lambda p:[float(p[0]/W*360-180),math.degrees(math.atan(math.sinh(math.pi*(1-2*p[1]/W))))]
def project(p,ps):
 best=None;s=0
 for i,(a,z) in enumerate(zip(ps,ps[1:])):
  den=np.dot(z-a,z-a);t=max(0,min(1,np.dot(p-a,z-a)/den)) if den else 0;q=a+t*(z-a);distance=np.linalg.norm(p-q);length=np.linalg.norm(z-a)
  if best is None or distance<best[0]:best=(distance,i,t,q,s+t*length)
  s+=length
 return best
path=[]
for r in d['intervals']:path.extend([mk(q) for q in (r['coordinates'] if not path else r['coordinates'][1:])])
parent=json.loads((b/'repair-chat-asa/all-intervals-and-aliases.json').read_text());original=[]
for item in parent['intervals']:original.extend([mk(q) for q in (item['coordinates'] if not original else item['coordinates'][1:])])
inside=[]
for j,q in enumerate(original):
 pixel=(q-np.array([c['rectX'],c['rectY']]))/c['mapPointsPerPoint']
 if 0<pixel[0]<999 and 0<pixel[1]<654:inside.append(j)
assert inside;rail=original[max(0,inside[0]-1):inside[-1]+2]
mid=np.array([c['rectX']+509.25*c['mapPointsPerPoint'],c['rectY']+310.75*c['mapPointsPerPoint']]);p=project(mid,rail);alias=ll(p[3]);rail.insert(p[1]+1,p[3]);lo=project(rail[0],path)[1]+1;hi=project(rail[-1],path)[1]+1;assert lo<hi;path=path[:lo]+rail+path[hi:];d['displayStationCoordinates']['009193']=alias
markers=[]
for row in d['allStationRows']:
 a=d['displayStationCoordinates'][row['stationID']];p=project(mk(a),path);assert p[0]<0.02;(markers.append((p[4],p[1],a)))
assert all(a[0]<z[0] for a,z in zip(markers,markers[1:]));intervals=[]
for i,(a,z) in enumerate(zip(markers,markers[1:])):
 coords=[a[2]]+[ll(q) for q in path[a[1]+1:z[1]+1]]+[z[2]];clean=[]
 for q in coords:
  if not clean or np.linalg.norm(mk(q)-mk(clean[-1]))>1e-5:clean.append(q)
 intervals.append({**d['intervals'][i],'coordinates':clean})
d['intervals']=intervals;d['status']='root-candidate-v4-physical-track-identity-reviewed-native-pending';d['nativeAcceptance']=False
for w in d['rootStationWitnesses']:
 if w.get('id')=='009193':w.update({'rail':[list((q-np.array([c['rectX'],c['rectY']]))/c['mapPointsPerPoint']) for q in rail],'alias':alias,'normalAliasPixel':[(mk(alias)[j]-[c['rectX'],c['rectY']][j])/c['mapPointsPerPoint'] for j in [0,1]],'basis':'own station rectangle midpoint projected to the physical rail reviewed in native dark basemap; regional aerial is qualitative context (URL-only calibration withdrawn); reject the distinct label/schematic S curve'})
d['withdrawnInterpretations']=['V2 Yoshikawa labelled S curve mistaken for physical rail','V2 interval10 large departure claim: raw basemap also contains the matching physical curved railway; not established failure']
(o/'candidate-all-20-intervals-v4.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
im=Image.open(b/'stations-supplemental-20261014/04-009193-caps-z20/basemap.png').convert('RGB');dr=ImageDraw.Draw(im)
px=lambda q:tuple((mk(q)-np.array([c['rectX'],c['rectY']]))/c['mapPointsPerPoint'])
for r in intervals[3:5]:dr.line([px(q) for q in r['coordinates']],fill=(200,0,140),width=2)
x,y=px(alias);dr.ellipse((x-5,y-5,x+5,y+5),outline=(0,160,30),width=2);im.save(o/'yoshikawa-physical-rail-v4.png');print('V4: restored physically evidenced gentle Yoshikawa rail;21 exact aliases;20 complete intervals;no native acceptance')
