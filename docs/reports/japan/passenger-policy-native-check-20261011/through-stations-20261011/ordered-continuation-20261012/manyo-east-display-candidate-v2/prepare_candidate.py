from PIL import Image,ImageDraw
import pathlib,json,math
base=pathlib.Path('/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012');out=pathlib.Path('/private/tmp/jtm-manyo-east-candidate');world=2**28
frames={n:json.loads((base/f'manyo-koshinokata-interval6-{n}-extraction-before/apple-map-extraction/analysis.json').read_text()) for n in ['first','middle','last']}
def unproject(n,p):
 a=frames[n];r=a['mapRect'];x=r['x']+p[0]*r['width']/a['width'];y=r['y']+p[1]*r['height']/a['height'];return [x/world*360-180,math.degrees(math.atan(math.sinh(math.pi*(1-2*y/world))))]
def project(n,c):
 a=frames[n];r=a['mapRect'];x=(c[0]+180)/360*world;y=(1-math.asinh(math.tan(math.radians(c[1])))/math.pi)/2*world;return [(x-r['x'])/r['width']*a['width'],(y-r['y'])/r['height']*a['height']]
# Manual visible physical-rail centre-band picks. Label/crossing gaps bridged from same identified rail tangents, never detector unsupported rows.
picks=[('first',[499.5,282]),('first',[600,306]),('first',[700,330]),('first',[800,354]),('first',[900,378]),('middle',[250,206]),('middle',[350,230]),('middle',[450,254]),('middle',[500,268]),('middle',[525,278]),('middle',[550,290]),('middle',[575,303]),('middle',[600,319]),('middle',[625,337]),('middle',[650,358]),('middle',[675,383]),('middle',[700,414]),('last',[447,305])]
coords=[unproject(n,p) for n,p in picks]
old=[]
for k in range(3):
 v=json.loads(pathlib.Path(f'/private/tmp/jtm-sapporo-yamahana-native/captures/000422/{k:06}/view.json').read_text());old.extend(v['sourceCoordinates'])
cos=math.cos(math.radians(36.7755));sx=111320*cos;sy=111320
def dist(a,b):return math.hypot((a[0]-b[0])*sx,(a[1]-b[1])*sy)
def segdist(p,a,b):
 x=(p[0]-a[0])*sx;y=(p[1]-a[1])*sy;u=(b[0]-a[0])*sx;v=(b[1]-a[1])*sy;t=max(0,min(1,(x*u+y*v)/(u*u+v*v))) if u*u+v*v else 0;return math.hypot(x-t*u,y-t*v)
maxmove=max(min(segdist(p,a,b) for line in old for a,b in zip(line,line[1:])) for p in coords)
obj={'format':'jtm-manual-display-candidate-v1','status':'candidate-awaiting-native-review-and-interval5-seam','lineID':'jp-万葉線-新湊港線','intervalIndex':6,'scope':'Display-only candidate; physical coordinates, topology and mileage unchanged. No production writes.','dependency':'96ea088dce99c2122d1bf85768b42afbc0a5eb44de6a18ee582f243029199dc1','coordinates':coords,'manualPicks':[{'frame':n,'pixel':p,'coordinate':c,'support':'manually identified physical black rail band; longitudinal terminal-platform midpoint for last pick'} for (n,p),c in zip(picks,coords)],'displayStations':[{'stationID':'001817','role':'shared #5/#6 start, must update #5 endpoint together','oldCoordinate':[137.10669,36.776285],'candidateCoordinate':coords[0],'moveMetres':dist([137.10669,36.776285],coords[0])},{'stationID':'001820','role':'terminal platform longitudinal midpoint intersect identified rail band; exclude ferry transverse block','oldCoordinate':[137.111935,36.774835],'candidateCoordinate':coords[-1],'moveMetres':dist([137.111935,36.774835],coords[-1])}],'maximumCandidateToOldSourcePolylineMetres':maxmove,'guards':['Candidate #6 may not be installed alone: #5 endpoint/001817 must match candidate start exactly.','No #5 interpolation authored until its actual rail imagery is reviewed.','Sparse manual polyline needs production smoothing/native overlay review before acceptance.','Apple black physical rail glyph is alignment reference; no road-center or ferry snap.','Detector supported/unsupported coordinates are not used to build this candidate.'],'sourceFrames':{n:{'mapRect':a['mapRect'],'width':a['width'],'height':a['height']} for n,a in frames.items()}}
(out/'candidate.json').write_text(json.dumps(obj,ensure_ascii=False,indent=2));geo={'type':'FeatureCollection','features':[{'type':'Feature','properties':{'lineID':obj['lineID'],'intervalIndex':6,'scope':'display-only manual candidate'},'geometry':{'type':'LineString','coordinates':coords}}]+[{'type':'Feature','properties':s,'geometry':{'type':'Point','coordinates':s['candidateCoordinate']}} for s in obj['displayStations']]};(out/'candidate.geojson').write_text(json.dumps(geo,ensure_ascii=False,indent=2))
for n in frames:
 im=Image.open(base/f'manyo-koshinokata-interval6-{n}-extraction-before/apple-map-extraction/basemap.png').convert('RGB');d=ImageDraw.Draw(im);ps=[project(n,c) for c in coords];d.line(ps,fill=(255,30,230),width=2)
 for i,p in enumerate(ps):
  if 0<=p[0]<999 and 0<=p[1]<654:d.ellipse((p[0]-3,p[1]-3,p[0]+3,p[1]+3),outline=(255,255,30),width=1);d.text((p[0]+5,p[1]-10),str(i),fill=(255,255,30))
 im.save(out/f'{n}-reprojection.png')
print(json.dumps({'candidate':str(out/'candidate.json'),'start':coords[0],'terminal':coords[-1],'maxNearestOldSourceMetres':maxmove,'stationMoves':obj['displayStations']},ensure_ascii=False))
