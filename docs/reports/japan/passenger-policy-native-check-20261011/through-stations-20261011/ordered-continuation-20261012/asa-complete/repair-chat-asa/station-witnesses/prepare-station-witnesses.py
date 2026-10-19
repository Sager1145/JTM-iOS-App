import json,math
from pathlib import Path
from PIL import Image,ImageDraw
B=Path('/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/asa-complete');O=B/'repair-chat-asa/station-witnesses';W=268435456
# Literal identified own face caps; supports describe the actual rail band/group,
# not a pixel-colour ranking. Unknown faces are withheld explicitly.
D={
1:([[507,332],[579,355]],[[490,320],[540,335],[590,350]],'South own narrow face; separate Tosaden stop/line south excluded.'),
2:([[490,294],[550,309]],[[470,298.5],[530,311],[590,324]],'North own narrow face; label splits fill fragments, cap limits retained.'),
4:([[437,286],[490,344]],[[441,289],[465,321],[490,349]],'Clear lower own curved railway beside narrow west face; north attached rectangular bulb excluded.'),
5:([[395,335],[526,359]],[[400,320],[450,331],[500,341],[550,345],[600,349],[650,353.5],[700,358.5]],'South clear long own face; unequal north strip/label fragments disclosed, not averaged.'),
6:([[455,300],[531,319]],[[460,286],[500,297],[540,306]],'South narrow face excluding attached small south bulb and road55 north.'),
7:([[303,225],[558,387]],[[400,285.5],[450,316],[500,349.5],[550,382.5]],'Own island between two passenger rails; narrow interior light band, not outer railway casing. North building/access pieces excluded.'),
8:([[300,334],[411,337]],[[300,344],[350,347],[400,349],[450,350]],'North narrow face on LOWER actual paired railway; independent upper named single transit glyph explicitly rejected.'),
9:([[349,314],[449,326]],[[300,294],[500,321.5],[550,330.5]],'South identified narrow face beside LOWER actual paired physical rail; upper single transit glyph rejected as rail authority. North light strip is an alternative, not averaged.'),
10:([[453,326],[539,341]],[[400,309.5],[450,320.5],[550,342.5],[600,353.5]],'South narrow strip excluding small attached lower bulb; paired physical band, not upper named transit glyph.'),
11:([[456,343],[535,352]],[[450,321],[500,335],[550,342.5],[600,350]],'South identified narrow face on LOWER paired physical rail, excluding upper named single glyph.'),
12:([[404,343],[485,325]],[[400,354],[450,336],[500,316]],'North own narrow face; train label/buildings and south road55 excluded.'),
15:([[423,274],[499,307]],[[420,279],[460,300],[500,321.5],[600,375.5],[700,431],[780,479]],'North actual narrow longitudinal strip; attached two small roof rectangles excluded from endpoints.'),
16:([[482,337],[540,459]],[[500,327],[520,377],[536,425],[550,470]],'West actual long narrow face, east face506323→556452 disclosed; slightly unequal centres/curvature remain direction warning, no averaging.'),
17:([[324,286],[396,296]],[[300,292],[400,307],[500,322]],'North own short narrow face, long ordinary rail casing excluded.'),
18:([[438,328],[521,342]],[[400,301.5],[450,311],[550,329.5]],'South own narrow face; western roof/bulb excluded.'),
19:([[566,327],[644,337]],[[560,336],[600,342],[650,349]],'North clear own narrow bar; attached centre access rectangle excluded; south label fragments not merged for a count.'),
20:([[408,330],[486,402]],[[395,289],[425,319],[455,347],[474,363]],'Exclusive terminal own platform box: midpoint projected onto identified ending railway. Exclude roads/arrows/casing. Final line ends exactly at alias.'),
}
WARN={4:'Yoshikawa actual narrow strip connects a rectangular NW bulb and broad SE L-shaped fill. Original fine-grid shows prior endpoint490344 lies in broad attached fill rather than independently capped narrow face. Alias withheld, not guessed from connected component.',0:'Gomen multi-rail/unequal face allocation to Asa vsDosan is unresolved from saved station raw. Retain physical guard; no common code assignment or guessed alias. Own E→SE branch outside station is separately identified.',3:'Noichi upper/lower narrow strips join wide eastern station/building shapes; exact trueface caps vsattached fill remain unresolved. Do not adopt broad gray railway casing or aggregate connected fill.',13:'Aki General Hospital Front: no independently identified narrow bright own face in actual raw; blue station box/attached grey L-shaped building alone not a face.',14:'Aki multiple fan rails; south narrow face433349→539377 is visible, but own passenger track/group allocation among middle/lower fans needs continuation proof. Withhold a guessed nearest-rail normal.'}
pkg=json.loads(Path('/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/rail/jp-2025.json').read_text());line=next(x for x in pkg['lines'] if x['id']=='jp-土佐くろしお鉄道-阿佐線');rows=[]
def inv(v,p):r=v['mapRect'];s=v['camera']['mapPointsPerPoint'];x=r['x']+s*p[0];y=r['y']+s*p[1];return[x/W*360-180,math.degrees(math.atan(math.sinh(math.pi*(1-2*y/W))))]
def normal(mid,rail):
 # Project onto the actual local own-band polyline, not a global straight fit
 # which can flatten a curved platform group or shift its selected chainage.
 picks=[]
 for a,b in zip(rail,rail[1:]):
  d=[b[j]-a[j] for j in [0,1]];den=sum(v*v for v in d)
  f=max(0,min(1,sum((mid[j]-a[j])*d[j] for j in [0,1])/den));q=[a[j]+f*d[j] for j in [0,1]];picks.append((math.dist(q,mid),q))
 return min(picks,key=lambda x:x[0])[1]
for i,srow in enumerate(line['stations']):
 sid=srow[0];p=B/'stations-z18'/f'{i:02}-{sid}';v=json.loads((p/'view.json').read_text());im=Image.open(p/'basemap.png').convert('RGB');assert im.size==(999,654);d=ImageDraw.Draw(im);row={'stationIndex':i,'stationID':sid,'name':srow[1],'rawView':str(p/'view.json'),'dimensions':[999,654],'camera':v['camera'],'mapRect':v['mapRect'],'physicalCoordinate':srow[2:4],'nativeAcceptance':False}
 if i in WARN:row.update(status='WARNING-alias-withheld',displayCandidate=srow[2:4],warning=WARN[i],faceEndpoints=None,aliasPixel=[499.5,327]);d.text((5,5),f'{i} WARNING alias withheld; physical guard retained',fill='white')
 else:
  face,rails,basis=D[i];mid=[sum(p[j] for p in face)/2 for j in [0,1]];ap=normal(mid,rails);row.update(status='candidate-only-qualified',faceEndpoints=face,faceLongitudinalMidpoint=mid,railBandControls=rails,aliasPixel=ap,displayCandidate=inv(v,ap),basis=basis,precisionWarning='Manual cartographic support: approx2px normal/2px face caps; local rail/group centre and lane replay pending. Not surveyed/physical.',requiredCompleteIntervals=[j for j in [i-1,i] if 0<=j<20])
  if i in [5,7,9,16,19]:row['groupWarning']='Own co-track/platform-group allocation only; no individual operator/direction proof. Alternate/unequal own faces and label occlusions must remain visible in Root review.'
  d.line(face,fill=(255,150,0),width=2);d.line(rails,fill=(255,255,0),width=1)
  for q in face:
   x,y=q;d.ellipse((x-3,y-3,x+3,y+3),outline=(255,150,0),width=1)
  x,y=ap;d.ellipse((x-4,y-4,x+4,y+4),outline=(255,0,255),width=2);d.line([mid,ap],fill=(255,0,255),width=1)
  d.text((5,5),f'{i} orange own face / yellow rail band / magenta candidate normal',fill='white')
 im.save(O/f'{i:02}-{sid}-candidate-witness.png');rows.append(row)
(O/'station-candidates.json').write_text(json.dumps({'format':'jtm-asa-own-station-display-candidates-v1','status':'candidate-only-with-explicit-withheld-aliases','lineID':line['id'],'stations':rows,'limits':['Actual ownface caps identified manually in saved999x654 raws; connected fill mask used only as fragment-location aid, never platform identity.','Withheld face/rail assignments remain source physical guards pluswarnings, not correct anchors. Parent must not freeze warning connectors.','Both complete adjacent intervals need respective moved station joins; terminal20 has no outgoinginterval.']},ensure_ascii=False,indent=2)+'\n')
for r in rows:print(r['stationIndex'],r['name'],r['status'],r['aliasPixel'],r['displayCandidate'])
