from pathlib import Path
import json,math,copy
from PIL import Image,ImageDraw
base=Path('/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/asa-complete')
out=base/'root-station-review';out.mkdir(exist_ok=True);shots=base/'stations-supplemental-20261014'
d=json.loads((base/'repair-chat-asa/all-intervals-and-aliases.json').read_text());W=268435456
mk=lambda c:[W*(c[0]+180)/360,W*(1-math.log(math.tan(math.pi/4+c[1]*math.pi/360))/math.pi)/2]
def ll(p):return[p[0]/W*360-180,math.degrees(math.atan(math.sinh(math.pi*(1-2*p[1]/W))))]
def project(p,path):
 best=None;s=0
 for i,(a,b) in enumerate(zip(path,path[1:])):
  dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(length*length))) if length else 0;q=[a[0]+t*dx,a[1]+t*dy];dist=math.dist(q,p)
  if best is None or dist<best[0]:best=(dist,i,t,q,s+t*length)
  s+=length
 return best
specs=[
 {'i':0,'id':'009057','folder':'00-009057-face-z19','caps':[[198,467],[548,324]],'rail':[[260,462],[450,381],[650,296],[850,211],[950,168]],'basis':'own southern 0/1 platform; representative platform0 rail, official numbering plus regional east-branch continuity; no Dosan alias copied'},
 {'i':3,'id':'009112','folder':'03-009112-caps-z20','frame':[[274,148],[790,300],[722,514],[206,361]],'rail':[[200,257],[350,294],[499,331],[650,369],[850,419]],'basis':'own rectangular station frame longitudinal midpoint, normal to identified paired passenger rail group; user station-frame preference'},
 {'i':4,'id':'009193','folder':'04-009193-caps-z20','frame':[[330,176],[418,103],[689,445],[600,519]],'rail':[[330,104],[375,166],[410,228],[449,281],[510,319],[570,351],[611,396],[640,449],[677,515],[733,625]],'basis':'own main station rectangle excluding east facility polygon; actual labelled curving rail instead of straight cut through platform fill'},
 {'i':13,'id':'009242','folder':'13-009242-face-z19','frame':[[451,285],[618,244],[640,327],[473,372]],'rail':[[350,351],[500,315.5],[650,280],[750,256]],'basis':'own current Apple station rectangle on unique railway; older aerial confirms corridor only, does not prove post-construction platform caps'},
 {'i':14,'id':'009240','folder':'14-009240-face-z19','caps':[[366,381],[579,421]],'rail':[[100,305],[300,344],[500,383],[700,422],[900,460]],'basis':'own southern narrow passenger face, north-adjacent through passenger rail traced from west/east throat; yard and access building excluded'}]
path=[]
for item in d['intervals']:
 pts=item['coordinates'];assert not path or path[-1]==pts[0];path+=pts if not path else pts[1:]
whole=[mk(p) for p in path];witness=[]
for sp in specs:
 v=json.loads((shots/sp['folder']/'view.json').read_text());c=v['camera'];scale=c['mapPointsPerPoint']
 toMK=lambda p:[c['rectX']+p[0]*scale,c['rectY']+p[1]*scale]
 ps=sp.get('caps',sp.get('frame'));mid=[sum(p[j] for p in ps)/len(ps) for j in [0,1]];rail=[toMK(p) for p in sp['rail']];pr=project(toMK(mid),rail);alias=ll(pr[3]);insert=pr[1]+1;rail=rail[:insert]+[pr[3]]+rail[insert:]
 # Gomen terminal starts on the selected passenger representative and
 # follows its own east-going track into the observed Asa branch.
 if sp['i']==0:
  rail=rail[insert:]
  east=json.loads((shots/'00-009057-east-throat-z18'/'view.json').read_text())['camera']
  for x,y in [[120,346],[220,312],[300,297],[380,299],[440,311]]:rail.append([east['rectX']+x*east['mapPointsPerPoint'],east['rectY']+y*east['mapPointsPerPoint']])
  lo=0
 else:lo=project(rail[0],whole)[1]+1
 hi=project(rail[-1],whole)[1]+1
 assert lo<hi,(sp['i'],lo,hi)
 whole=whole[:lo]+rail+whole[hi:]
 d['displayStationCoordinates'][sp['id']]=alias
 witness.append({**sp,'view':str(shots/sp['folder']/'view.json'),'frameMidpointPixel':mid,'normalAliasPixel':[(pr[3][0]-c['rectX'])/scale,(pr[3][1]-c['rectY'])/scale],'alias':alias,'pickUncertaintyPixels':3,'status':'root-candidate-not-native-accepted'})
# Repartition the complete line at all line-scoped aliases, inserting each
# alias literally so both adjacent interval endpoints remain identical.
markers=[]
for row in d['allStationRows']:
 alias=d['displayStationCoordinates'][row['stationID']];pr=project(mk(alias),whole);assert pr[0]<0.02,(row['stationID'],pr[0]);markers.append((pr[4],pr[1],pr[2],mk(alias),alias))
assert all(a[0]<b[0] for a,b in zip(markers,markers[1:])), 'station order'
intervals=[]
for i,(a,b) in enumerate(zip(markers,markers[1:])):
 coords=[a[4]]+[ll(p) for p in whole[a[1]+1:b[1]+1]]+[b[4]]
 clean=[]
 for p in coords:
  if not clean or math.dist(mk(p),mk(clean[-1]))>1e-5:clean.append(p)
 intervals.append({**d['intervals'][i],'coordinates':clean})
d['intervals']=intervals;d['withheldStationIndexes']=[];d['status']='root-candidate-five-stations-reviewed-native-acceptance-pending';d['rootStationWitnesses']=witness;d['nativeAcceptance']=False
(out/'candidate-all-20-intervals-v2.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');(out/'five-station-witnesses.json').write_text(json.dumps(witness,ensure_ascii=False,indent=2)+'\n')
for sp in specs:
 v=json.loads((shots/sp['folder']/'view.json').read_text());c=v['camera'];im=Image.open(shots/sp['folder']/'basemap.png').convert('RGB');dr=ImageDraw.Draw(im)
 def px(coord):x,y=mk(coord);return[(x-c['rectX'])/c['mapPointsPerPoint'],(y-c['rectY'])/c['mapPointsPerPoint']]
 for item in intervals:
  if item['intervalIndex'] in [sp['i']-1,sp['i']]:dr.line([tuple(px(p)) for p in item['coordinates']],fill=(200,0,130),width=2)
 x,y=px(d['displayStationCoordinates'][sp['id']]);dr.ellipse((x-5,y-5,x+5,y+5),outline=(0,160,50),width=2)
 im.save(out/(sp['folder']+'-candidate-v2.png'))
print('20 full candidate intervals;21 aliases;5 root witnesses;physical data untouched;native pending')
