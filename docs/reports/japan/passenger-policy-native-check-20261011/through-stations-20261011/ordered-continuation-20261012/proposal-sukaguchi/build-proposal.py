from pathlib import Path
import json, math
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
RAW = ROOT / 'tsushima-complete-native'
WORLD = 268435456
MAIN = 'jp-名古屋鉄道-名古屋本線'
TSUSH = 'jp-名古屋鉄道-津島線'

cameras = {}
def view(name):
    if name not in cameras:
        cameras[name] = json.loads((RAW / name / 'view.json').read_text())['camera']
    return cameras[name]

def world_pixel(name, p):
    c = view(name)
    return [c['rectX'] + p[0] * c['rectWidth'] / 999,
            c['rectY'] + p[1] * c['rectHeight'] / 654]

def geographic(p):
    return [p[0] / WORLD * 360 - 180,
            math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * p[1] / WORLD))))]

def geographic_world(p):
    return [(p[0] + 180) / 360 * WORLD,
            (1 - math.asinh(math.tan(math.radians(p[1]))) / math.pi) / 2 * WORLD]

def pixel(name, p):
    c = view(name)
    return [(p[0] - c['rectX']) / (c['rectWidth'] / 999),
            (p[1] - c['rectY']) / (c['rectHeight'] / 654)]

images = {}
def rgb(name, p):
    if name not in images:
        images[name] = Image.open(RAW / name / 'basemap.png').convert('RGB')
    return list(images[name].getpixel((round(p[0]), round(p[1]))))

controls = []
def add(item, name, p, kind='manually-identified-own-black-glyph', coordinate=None):
    w = world_pixel(name, p) if coordinate is None else geographic_world(coordinate)
    rec = {'item': item, 'capture': name, 'pixel': p, 'rgb': rgb(name, p),
           'coordinate': geographic(w) if coordinate is None else coordinate,
           'mapPoint': w, 'kind': kind}
    controls.append(rec)
    return rec

station = 'tsushima-sukaguchi-z18-before'
mid = 'meitetsu-main-17-view1-z18-before'
end = 'tsushima-sukaguchi-interval0-view6-z18-before'
aliases = {
    '005337': [136.84198711408624, 35.204625793777495],
    '005352': [136.84625120866804, 35.198706437899155],
    '005374': [136.85237591897993, 35.195456036607474],
    '005368': [136.82580403802893, 35.19600760468442],
}
add('tsushima0', station, [592,378], 'occluded-station-midpoint-normal-candidate', aliases['005352'])
for p in [[555,351],[410,251],[390,237],[380,232],[370,228],[360,223],
          [350,219],[340,214],[320,206],[300,197],[275,185],[200,159],[100,140]]:
    add('tsushima0', station, p)
for i, points in [(1,[[550,280],[800,233]]),(2,[[100,569],[150,543],[200,514],[250,481],[400,380],[500,313],[800,115]]),
                  (3,[[400,316],[450,313],[500,306],[520,303],[530,301],[540,299],[680,261],[690,258],[700,254],[750,233],[800,207],[850,175]]),(4,[[200,310],[500,303]]),
                  (5,[[350,316],[900,297]]),(6,[[700,312]])]:
    for p in points:
        add('tsushima0', f'tsushima-sukaguchi-interval0-view{i}-z18-before', p)
add('tsushima0', end, [490,315], 'root-supplied-own-frame-normal-alias', aliases['005368'])

add('main17', 'meitetsu-marunouchi-z18-before', [471,231],
    'label-masked-station-normal-candidate', aliases['005337'])
for p in [[418,100],[480,280],[487,300],[504,350],[521,400],[534,440],
          [542,460],[553,480],[562,500],[572,520],[586,540],[593,550],[600,560],[607,570]]:
    add('main17', mid, p)
for p in [[151,10],[159,20],[166,30],[173,40],[176,45],
          [275,147],[300,168],[340,198],[360,214],[370,221],[380,229],[410,251],[555,351]]:
    add('main17', station, p)
add('main17', station, [592,378], 'occluded-station-midpoint-normal-candidate', aliases['005352'])

add('main18', station, [592,378], 'occluded-station-midpoint-normal-candidate', aliases['005352'])
for p in [[630,404],[640,412]]:
    add('main18', station, p)
for p in [[200,122],[250,156],[350,224],[400,257],[450,291],[620,402],[650,419]]:
    add('main18', 'meitetsu-main-18-view1-z18-before', p)
for p in [[250,150],[300,182],[350,214],[400,246],[425,263],[450,279]]:
    add('main18', 'meitetsu-main-18-view2-z18-before', p)
add('main18', 'meitetsu-shinkawabashi-z18-before', [454,280],
    'label-masked-station-normal-candidate', aliases['005374'])

def seeds(item):
    return sorted([q for q in controls if q['item']==item], key=lambda q:q['mapPoint'][0])

def expected(pts, x):
    for a,b in zip(pts, pts[1:]):
        if a[0] <= x <= b[0] and b[0] > a[0]:
            t=(x-a[0])/(b[0]-a[0]); return a[1]+t*(b[1]-a[1])
    return None

def extend_columns(item, name, bands, radius=8):
    # Manual identity/label bands precede this local intensity query.
    pts=sorted([pixel(name,q['mapPoint']) for q in seeds(item)], key=lambda p:p[0])
    im=Image.open(RAW/name/'basemap.png').convert('RGB')
    for lo,hi in bands:
        for x in range(lo,hi+1,20):
            ey=expected(pts,x)
            if ey is None or not 8<ey<646: continue
            choices=[]
            for y in range(round(ey)-radius,round(ey)+radius+1):
                r,g,b=im.getpixel((x,y))
                if not(r<51 and g<70 and b<95 and b-r>15 and r<=.78*g and g<=.8*b): continue
                if (r,g,b) in [(46,52,64),(34,46,69)]: continue
                # Reject text outlines adjoining the light-blue letter fill.
                label=any((lambda v:v[0]>110 and v[1]>140 and v[2]>190)(im.getpixel((xx,yy)))
                          for xx in range(x-3,x+4) for yy in range(y-3,y+4))
                if label: continue
                choices.append((abs(y-ey)+sum((r,g,b))/300,y))
            if choices:
                _,y=min(choices)
                add(item,name,[x,y],'bounded-own-glyph-column-query-after-manual-identity')

extend_columns('tsushima0',station,[(110,330)],6)
for i,bands in [(1,[(120,240),(500,600),(790,910)]),
                (2,[(130,240),(400,580),(740,800)]),
                (3,[(280,520),(700,840)]),
                (4,[(150,270),(450,570),(750,810)]),
                (5,[(290,390),(570,670),(860,960)]),
                (6,[(670,770)])]:
    extend_columns('tsushima0',f'tsushima-sukaguchi-interval0-view{i}-z18-before',bands)
extend_columns('main18','meitetsu-main-18-view1-z18-before',[(220,440),(600,660)])
extend_columns('main18','meitetsu-main-18-view2-z18-before',[(260,440)])

def pchip(points, spacing=80):
    # Shape-preserving Hermite interpolation; no source vertices are retained as guards.
    xs=[p[0] for p in points];ys=[p[1] for p in points]
    hs=[b-a for a,b in zip(xs,xs[1:])]
    ds=[(b-a)/h for a,b,h in zip(ys,ys[1:],hs)]
    ms=[ds[0]]
    for i in range(1,len(xs)-1):
        a,b=ds[i-1],ds[i]
        if a*b<=0: ms.append(0)
        else:
            w1=2*hs[i]+hs[i-1];w2=hs[i]+2*hs[i-1]
            ms.append((w1+w2)/(w1/a+w2/b))
    ms.append(ds[-1]);out=[]
    for i,h in enumerate(hs):
        # Cap physical spacing also on steep Main northwest approach.
        count=max(1,math.ceil(math.hypot(h,ys[i+1]-ys[i])/spacing))
        for j in range(count):
            t=j/count;t2=t*t;t3=t2*t
            yy=(2*t3-3*t2+1)*ys[i]+(t3-2*t2+t)*h*ms[i]+(-2*t3+3*t2)*ys[i+1]+(t3-t2)*h*ms[i+1]
            out.append([xs[i]+h*t,yy])
    return out+[points[-1]]

def fit(item, lo, hi):
    selected=[]
    for q in seeds(item):
        x=q['mapPoint'][0]
        if not lo-0.01<=x<=hi+0.01: continue
        # Avoid tiny inter-capture jitter edges; manual/alias points win a close pair.
        if selected and x-selected[-1]['mapPoint'][0]<12:
            if 'candidate' in q['kind'] or 'alias' in q['kind'] or ('manually' in q['kind'] and 'query' in selected[-1]['kind']):
                selected[-1]=q
            continue
        selected.append(q)
    return pchip([q['mapPoint'] for q in selected]), selected

common=[world_pixel(station,[410,251]),world_pixel(station,[555,351]),geographic_world(aliases['005352'])]
ts_end=geographic_world(aliases['005368']);ma_start=geographic_world(aliases['005337']);ma_end=geographic_world(aliases['005374'])
tfit,tselected=fit('tsushima0',ts_end[0],common[0][0]);mfit,mselected=fit('main17',ma_start[0],common[0][0]);efit,eselected=fit('main18',common[-1][0],ma_end[0])
arrays={'tsushima0':list(reversed(common))+list(reversed(tfit[:-1])),
        'main17':mfit[:-1]+common,'main18':efit}
coords={k:[geographic(p) for p in v] for k,v in arrays.items()}
# Root-provided aliases retain exact decimals at all matching ends.
coords['tsushima0'][0]=aliases['005352'];coords['tsushima0'][-1]=aliases['005368']
coords['main17'][0]=aliases['005337'];coords['main17'][-1]=aliases['005352']
coords['main18'][0]=aliases['005352'];coords['main18'][-1]=aliases['005374']
assert coords['main17'][-3:]==list(reversed(coords['tsushima0'][:3]))

payload={'status':'PROPOSAL / ROOT REVIEW REQUIRED','format':'jtm-bounded-display-proposal-v1',
         'physicalSource':'Unchanged; these arrays are display-only candidates.',
         'displayStationCoordinates':aliases,
         'intervals':[{'lineID':TSUSH,'intervalIndex':0,'coordinates':coords['tsushima0']},
                      {'lineID':MAIN,'intervalIndex':17,'coordinates':coords['main17']},
                      {'lineID':MAIN,'intervalIndex':18,'coordinates':coords['main18']}],
         'commonSpanThreeCoordinates':coords['tsushima0'][:3],
         'warnings':['Sukaguchi midpoint rail is occluded by the transverse building; face identity is cartographic, not physical platform-number proof.',
                     'Label gaps use shape-preserving interpolation between own glyph supports, not source returns.',
                     'Local queries have pixel/sleeper/antialias uncertainty and require the attached full-view reprojection review.',
                     'No native final smoothing, lanes or runtime acceptance was measured.']}
(HERE/'candidate.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n')
(HERE/'control-provenance.json').write_text(json.dumps({'controls':controls,'fitControls':{'tsushima0':tselected,'main17':mselected,'main18':eselected},'interpolation':'Monotone piecewise cubic Hermite in mapPoints, maximum support sampling roughly20viewportpixels; shared station stem stays exactly three reverse-equal controls.'},ensure_ascii=False,indent=2)+'\n')
features=[{'type':'Feature','properties':{'lineID':i['lineID'],'intervalIndex':i['intervalIndex'],'status':'proposal-not-accepted'},'geometry':{'type':'LineString','coordinates':i['coordinates']}} for i in payload['intervals']]
(HERE/'candidate.geojson').write_text(json.dumps({'type':'FeatureCollection','features':features},ensure_ascii=False,indent=2)+'\n')

repros=HERE/'reprojections';repros.mkdir(exist_ok=True);records=[]
sets={'tsushima0':[station]+[f'tsushima-sukaguchi-interval0-view{i}-z18-before' for i in range(1,7)],
      'main17':['meitetsu-marunouchi-z18-before','meitetsu-main-17-view1-z18-before','meitetsu-main-17-view2-z18-before'],
      'main18':[f'meitetsu-main-18-view{i}-z18-before' for i in range(4)]}
for item,names in sets.items():
    for name in names:
        im=Image.open(RAW/name/'basemap.png').convert('RGB');draw=ImageDraw.Draw(im)
        pix=[pixel(name,p) for p in arrays[item]]
        draw.line([tuple(p) for p in pix],fill=(255,145,30),width=2)
        shown=[]
        for q in controls:
            if q['item']!=item:continue
            x,y=pixel(name,q['mapPoint'])
            if 0<=x<999 and 0<=y<654:
                draw.ellipse((x-2,y-2,x+2,y+2),outline=(40,240,240),width=1)
                shown.append({'originalCapture':q['capture'],'originalPixel':q['pixel'],'projectedPixel':[x,y],'kind':q['kind']})
        for code,coord in aliases.items():
            x,y=pixel(name,geographic_world(coord))
            if 0<=x<999 and 0<=y<654:
                draw.ellipse((x-5,y-5,x+5,y+5),outline=(255,255,80),width=2)
                draw.text((x+6,y-12),code,fill=(255,255,80))
        path=repros/f'{item}-{name}.png';im.save(path)
        records.append({'item':item,'capture':name,'output':str(path.relative_to(HERE)),'camera':view(name),'allCandidatePixels':pix,'visibleControls':shown,'status':'ROOT_REVIEW_PENDING'})
(HERE/'reprojection-manifest.json').write_text(json.dumps({'count':len(records),'records':records,'legend':'orangecandidatecentreline; cyanownsupport; yellowstationnormalcandidate. Originalrawunchanged. All14capturesretained:7Tsushima+3Main17+4Main18.'},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'counts':{k:len(v) for k,v in coords.items()},'controls':len(controls),'reprojections':len(records),'reverseSharedThree':True}))
