#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../../../../../..');
const sourceDir = path.join(root, 'docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/shinagawa/sources');
const osmPath = path.join(sourceDir, 'osm-bounded-rail-ways.json');
const packagePath = path.join(root, 'app/public/rail/jp-2025.json');
const gsiSouth = path.join(sourceDir, 'gsi-2019-south-strip.png');
const gsiWest = path.join(sourceDir, 'gsi-2019-west-curve.png');
const outputPath = path.join(here, 'candidate-evidence.json');
const geojsonPath = path.join(here, 'candidate.geojson');
const acceptedYamanoteSha = '70034a46ac8e455787d9c1b94b44e98bb92ebd3bc0bc2a635b9c359290de2a00';

const sha = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const stableSha = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const osm = JSON.parse(fs.readFileSync(osmPath));
const pkg = JSON.parse(fs.readFileSync(packagePath));
const ways = new Map(osm.elements.map(row => [row.id, row]));
const point = row => [row.lon, row.lat];
const equal = (a, b) => a[0] === b[0] && a[1] === b[1];
const metres = (a, b) => Math.hypot((b[0]-a[0])*111320*Math.cos((a[1]+b[1])*Math.PI/360), (b[1]-a[1])*111320);

function chain(spec) {
  const out = [];
  for (const [id, reverse = false] of spec) {
    const row = ways.get(id);
    if (!row) throw new Error(`missing retained way ${id}`);
    let points = row.geometry.map(point);
    if (reverse) points.reverse();
    if (out.length && !equal(out.at(-1), points[0])) throw new Error(`non-contiguous way ${id}`);
    out.push(...points.slice(out.length ? 1 : 0));
  }
  return out;
}

function ruler(points) {
  const m = [0];
  for (let i=1; i<points.length; i++) m.push(m.at(-1)+metres(points[i-1], points[i]));
  return m;
}

function interpolate(points, distance) {
  const m = ruler(points);
  if (distance <= 0) return points[0];
  if (distance >= m.at(-1)) return points.at(-1);
  let i = 1;
  while (m[i] < distance) i++;
  const t = (distance-m[i-1])/(m[i]-m[i-1]);
  return [points[i-1][0]+t*(points[i][0]-points[i-1][0]), points[i-1][1]+t*(points[i][1]-points[i-1][1])];
}

function sliceBetweenLatitudes(points, northLat, southLat) {
  const crosses = lat => {
    for (let i=1; i<points.length; i++) {
      const a=points[i-1], b=points[i];
      if ((a[1]-lat)*(b[1]-lat) <= 0 && a[1] !== b[1]) {
        const t=(lat-a[1])/(b[1]-a[1]);
        return { index:i, p:[a[0]+t*(b[0]-a[0]),lat] };
      }
    }
    throw new Error(`latitude ${lat} absent from chain`);
  };
  const n=crosses(northLat), s=crosses(southLat);
  if (s.index < n.index) throw new Error('chain is not north-to-south');
  return [n.p, ...points.slice(n.index, s.index), s.p];
}

function centre(a, b, step=10) {
  const ma=ruler(a).at(-1), mb=ruler(b).at(-1), count=Math.ceil(Math.max(ma,mb)/step);
  return Array.from({length:count+1}, (_,i) => {
    const pa=interpolate(a,ma*i/count), pb=interpolate(b,mb*i/count);
    return [(pa[0]+pb[0])/2,(pa[1]+pb[1])/2];
  });
}

function localVector(a, b) {
  const latitude=(a[1]+b[1])/2;
  return [(b[0]-a[0])*111320*Math.cos(latitude*Math.PI/180),(b[1]-a[1])*111320];
}

function unitVector(v) {
  const length=Math.hypot(...v);
  return v.map(x=>x/length);
}

function quinticNormalTaper(points, stationAnchor, length=200, step=10) {
  const measures=ruler(points), total=measures.at(-1);
  if (total < length) throw new Error(`pair centre is shorter than ${length}m taper`);
  const delta=[stationAnchor[0]-points[0][0],stationAnchor[1]-points[0][1]];
  const sampled=[];
  for (let distance=0; distance<=length; distance+=step) {
    const raw=interpolate(points,distance), t=distance/length;
    const smoothstep=6*t**5-15*t**4+10*t**3;
    const weight=1-smoothstep;
    sampled.push([raw[0]+delta[0]*weight,raw[1]+delta[1]*weight]);
  }
  const unchanged=points.filter((_,i)=>measures[i]>length);
  const tapered=[...sampled,...unchanged];
  const rawAtEnd=interpolate(points,length);
  const tangent=unitVector(localVector(points[0],interpolate(points,10)));
  const normal=[-tangent[1],tangent[0]];
  const displacement=localVector(points[0],stationAnchor);
  const dot=(a,b)=>a[0]*b[0]+a[1]*b[1];
  const startTangent=unitVector(localVector(tapered[0],tapered[1]));
  const endTangent=unitVector(localVector(sampled.at(-2),sampled.at(-1)));
  const latitudeWarpMax=Math.max(...sampled.map((p,i)=>Math.abs(p[1]-interpolate(points,i*step)[1])*111320));
  if (!equal(tapered[0],stationAnchor)) throw new Error('Tokaido taper lost exact station anchor');
  if (!equal(sampled.at(-1),rawAtEnd)) throw new Error('Tokaido taper did not return exactly to pair centre');
  if (latitudeWarpMax !== 0) throw new Error('Tokaido connector introduced north/south latitude warp');
  return {points:tapered,diagnostics:{lengthMeters:length,sampleStepMeters:step,rawPairStart:points[0],stationAnchor,rawDisplacementMeters:metres(points[0],stationAnchor),normalDisplacementMeters:dot(displacement,normal),tangentialResidualMeters:dot(displacement,tangent),rawInitialTangentEastNorth:tangent,candidateFirstTangentEastNorth:startTangent,candidateLastTaperTangentEastNorth:endTangent,transverseResidualAtEndMeters:metres(sampled.at(-1),rawAtEnd),latitudeWarpMaxMeters:latitudeWarpMax,formula:'raw(s) + (stationAnchor - raw(0)) * (1 - (6t^5 - 15t^4 + 10t^3)), t=s/200'}};
}

function cubicGap(from, fromPrevious, to, toNext, step=10) {
  const chord=metres(from,to), count=Math.max(2,Math.ceil(chord/step));
  const unit=(a,b)=>{const dx=b[0]-a[0],dy=b[1]-a[1],n=Math.hypot(dx,dy);return [dx/n,dy/n]};
  const u=unit(fromPrevious,from), v=unit(toNext,to); // v points backwards from target
  const scale=chord/111320/3;
  const c1=[from[0]+u[0]*scale/Math.cos(from[1]*Math.PI/180),from[1]+u[1]*scale];
  const c2=[to[0]+v[0]*scale/Math.cos(to[1]*Math.PI/180),to[1]+v[1]*scale];
  return Array.from({length:count+1},(_,i)=>{const t=i/count,q=1-t;return [q*q*q*from[0]+3*q*q*t*c1[0]+3*q*t*t*c2[0]+t*t*t*to[0],q*q*q*from[1]+3*q*q*t*c1[1]+3*q*t*t*c2[1]+t*t*t*to[1]]});
}

function decodedInterval(line, index) {
  const row=line.segments[index], previous=index ? line.stations[index].slice(2,4) : null;
  const p=(row[1] && previous ? [previous] : []).concat(row[2].map(x=>[...x]));
  p[0]=line.stations[index].slice(2,4); p[p.length-1]=line.stations[index+1].slice(2,4);
  return p;
}

const yamaAIds = [[854519240],[781158785],[211240840],[115686505],[115686491]];
const yamaBIds = [[854519241,true],[781158786,true],[22562304,true],[115686481,true],[115686503,true]];
const tokaAIds = [[585431457,true],[781158784,true],[781158607,true],[74254986,true],[74255018,true],[34282203,true]];
const tokaBIds = [[1527862968],[210532076],[1527862967]];
for (const [id] of [...yamaAIds,...yamaBIds,...tokaAIds,...tokaBIds]) {
  const tags=ways.get(id)?.tags || {};
  if (tags.railway !== 'rail' || tags.operator !== '東日本旅客鉄道' || tags.usage !== 'main' || tags.service)
    throw new Error(`way ${id} lost reviewed JR-East main-track identity`);
}
const yamaA=chain(yamaAIds), yamaB=chain(yamaBIds), tokaA=chain(tokaAIds), tokaB=chain(tokaBIds);
const yamaLine=pkg.lines.find(x=>x.id==='jp-東日本旅客鉄道-山手線');
const tokaLine=pkg.lines.find(x=>x.id==='jp-東日本旅客鉄道-東海道線');
const yamaBase=decodedInterval(yamaLine,0), tokaBase=decodedInterval(tokaLine,6);

const yamaPairedA=sliceBetweenLatitudes(yamaA,35.628135,35.6169392);
const yamaPairedB=sliceBetweenLatitudes(yamaB,35.628135,35.6169392);
const yamaCentre=centre(yamaPairedA,yamaPairedB);
const yamaSouthSeam=[139.73149,35.617];
const yamaSeamIndex=yamaBase.findIndex(p=>equal(p,yamaSouthSeam));
const yamaGap=cubicGap(yamaCentre.at(-1),yamaCentre.at(-2),yamaSouthSeam,yamaBase[yamaSeamIndex+1]);
const yamaCandidate=[yamaBase[0],...yamaCentre.slice(1),...yamaGap.slice(1),...yamaBase.slice(yamaSeamIndex+1)];
if (stableSha(yamaCandidate) !== acceptedYamanoteSha) throw new Error('accepted Yamanote candidate changed');

const tokaPairedA=sliceBetweenLatitudes(tokaA,35.628135,35.626058);
const tokaPairedB=sliceBetweenLatitudes(tokaB,35.628135,35.626058);
const tokaCentre=centre(tokaPairedA,tokaPairedB);
const tokaTaper=quinticNormalTaper(tokaCentre,tokaBase[0]);
const tokaSingle=sliceBetweenLatitudes(tokaA,35.626058,35.6163321);
const tokaSouthSeam=[139.73632,35.61564];
const tokaSeamIndex=tokaBase.findIndex(p=>equal(p,tokaSouthSeam));
const tokaGap=cubicGap(tokaSingle.at(-1),tokaSingle.at(-2),tokaSouthSeam,tokaBase[tokaSeamIndex+1]);
const tokaCandidate=[...tokaTaper.points,...tokaSingle.slice(1),...tokaGap.slice(1),...tokaBase.slice(tokaSeamIndex+1)];

const wayRecord = ids => ids.map(([id,reverse=false]) => ({id,reverse,tags:ways.get(id).tags}));
const output={
  format:'jtm-shinagawa-fork-display-candidate-v1', status:'candidate-only-needs-apple-full-interval-review', generatedAt:'2026-10-12', crs:'WGS84 longitude latitude',
  warning:'OSM/GSI identify exposed passenger tracks but are not surveyed positional truth. Interpolated and retained-baseline windows are explicit and cannot be promoted without native Apple full-interval review.',
  frozenInputs:{osm:{path:path.relative(root,osmPath),sha256:sha(osmPath),fetchedAt:osm.fetchedAt,endpoint:osm.endpoint},gsi2019South:{path:path.relative(root,gsiSouth),sha256:sha(gsiSouth),tileOrigin:[18,232825,103271],dimensions:[768,2304]},gsi2019West:{path:path.relative(root,gsiWest),sha256:sha(gsiWest),tileOrigin:[18,232822,103280],dimensions:[1536,1280]},targetRows:{[yamaLine.id]:stableSha(yamaLine),[tokaLine.id]:stableSha(tokaLine)}},
  immutableScope:['physical station rows','segments and kilometres','line IDs and direction','jp-東日本旅客鉄道-総武線-3 independent platforms13–15 centre','大崎支線 two-south/one-station/one-north display policy'],
  candidates:[
    {lineId:yamaLine.id,intervalIndex:0,from:'品川',to:'大崎',directionalWays:{a:wayRecord(yamaAIds),b:wayRecord(yamaBIds)},identifiedPairBounds:{northLatitude:35.628135,southLatitude:35.6169392},stationEndWindow:{stationAnchor:yamaBase[0],identifiedPairCentre:yamaCentre[0],gapMeters:metres(yamaBase[0],yamaCentre[0]),policy:'display endpoint connector only; physical station unchanged'},pairCentrePoints:yamaCentre,fullCandidatePoints:yamaCandidate,unresolvedWindow:{from:yamaCentre.at(-1),to:yamaSouthSeam,method:'cubic tangent interpolation to retained Yamanote/Osaki stem',reason:'retained bounded OSM selection ends before Osaki; no extra rail was inferred',requiresAppleReview:true},retainedOsakiStem:yamaBase.slice(yamaSeamIndex),osakiAdaptation:['大崎支線 displayStationStem currently follows Yamanote from [139.7295,35.6183] through [139.72888,35.61912] to [139.728245,35.619945]. Recompute its Yamanote ruler measures only if Apple accepts this candidate; keep the coordinates unless native comparison rejects them.']},
    {lineId:tokaLine.id,intervalIndex:6,from:'品川',to:'大井町',directionalWays:{a:wayRecord(tokaAIds),b:wayRecord(tokaBIds)},identifiedPairBounds:{northLatitude:35.628135,southLatitude:35.626058},stationEndWindow:{stationAnchor:tokaBase[0],identifiedPairCentre:tokaCentre[0],gapMeters:metres(tokaBase[0],tokaCentre[0]),policy:'200m quintic normal-displacement taper from exact display station anchor to identified pair centre; physical station unchanged',taper:tokaTaper.diagnostics},pairCentrePoints:tokaCentre,fullCandidatePoints:tokaCandidate,candidateGuards:{exactStationAnchor:equal(tokaCandidate[0],tokaBase[0]),exactPairCentreAtTaperEnd:tokaTaper.diagnostics.transverseResidualAtEndMeters===0,noNorthSouthLatitudeWarp:tokaTaper.diagnostics.latitudeWarpMaxMeters===0,unchangedSouthEndpoint:equal(tokaCandidate.at(-1),tokaBase.at(-1)),acceptedYamanoteSha256:acceptedYamanoteSha},unresolvedWindows:[{from:tokaCentre.at(-1),to:tokaSingle.at(-1),method:'identified JR-East Tokaido direction A only',reason:'retained bounded evidence has no second JR-East Tokaido direction south of 35.626058',requiresAppleReview:true},{from:tokaSingle.at(-1),to:tokaSouthSeam,method:'cubic tangent interpolation to retained Tokaido interval tail',requiresAppleReview:true}],excludedContinuation:{wayId:749385266,reason:'tagged operator 東海旅客鉄道; rejected as the missing JR-East directional mate'}}
  ],
  replayPlan:['verify all frozen hashes','rebuild the four explicit chains and exact seams','sample paired chains monotonically at <=10m and midpoint them','apply only the documented 200m Tokaido north station normal-displacement taper','insert only the documented interpolation/baseline windows','emit candidate JSON and GeoJSON outside production','after Apple acceptance, rebuild only Yamanote #0 and Tokaido #6 target rows/native parts, then remap affected lane/follow measures by exact coordinate seams'],
  downstreamEffects:{lanes:['regenerate partsByRegion for Yamanote/Tokaido','remap Yamanote lane boundary m1250 by accepted seam coordinates','remap Tokaido lane window boundaries only where their coordinate falls inside changed geometry'],osaki:['recompute 大崎支線→Yamanote follow measures at [139.7295,35.6183] and station','do not alter 大崎支線 physical junctions or Sobu shared-tail follows']}
};
fs.writeFileSync(outputPath,JSON.stringify(output,null,2)+'\n');
const geojson={type:'FeatureCollection',name:'candidate-only-shinagawa-fork-display',features:[
  {type:'Feature',properties:{lineId:yamaLine.id,intervalIndex:0,status:'accepted-in-prior-Apple-review',pointsSha256:stableSha(yamaCandidate)},geometry:{type:'LineString',coordinates:yamaCandidate}},
  {type:'Feature',properties:{lineId:tokaLine.id,intervalIndex:6,status:'revised-north-connector-needs-Apple-review',taperLengthMeters:tokaTaper.diagnostics.lengthMeters,pointsSha256:stableSha(tokaCandidate)},geometry:{type:'LineString',coordinates:tokaCandidate}}
]};
fs.writeFileSync(geojsonPath,JSON.stringify(geojson,null,2)+'\n');
console.log(JSON.stringify({output:outputPath,geojson:geojsonPath,yamanotePoints:yamaCandidate.length,yamanoteSha256:stableSha(yamaCandidate),tokaidoPoints:tokaCandidate.length,tokaidoSha256:stableSha(tokaCandidate),tokaidoNorthTaper:tokaTaper.diagnostics,yamanoteGapMeters:metres(yamaCentre.at(-1),yamaSouthSeam),tokaidoPairEnd:tokaCentre.at(-1)},null,2));
