#!/usr/bin/env node
// Outer station display stage preserving the strict earlier Otani curve repair.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { repairPackage as repairCurve } from './repair-keishin-display-curve.mjs';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(path.join(ROOT, p)));
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const same = (a,b) => a[0] === b[0] && a[1] === b[1];
function taperToRetainedBoundary(points, boundary, outside, transition) {
  assert.deepEqual([transition.metres, transition.sampleStepMetres, transition.boundaryTangentGuardMetres], [20, 2, 1]);
  const origin = points.at(-1), longitudeScale = 111320 * Math.cos(origin[1] * Math.PI / 180);
  const toXY = p => [(p[0] - origin[0]) * longitudeScale, (p[1] - origin[1]) * 111320];
  const fromXY = p => [origin[0] + p[0] / longitudeScale, origin[1] + p[1] / 111320];
  const xy = points.map(toXY), cumulative = [0];
  for (let i = 1; i < xy.length; i++) cumulative.push(cumulative.at(-1) + Math.hypot(xy[i][0] - xy[i - 1][0], xy[i][1] - xy[i - 1][1]));
  const total = cumulative.at(-1), start = total - transition.metres;
  assert(start > 0, 'Transition must stay inside the previously affected approach');
  const delta = toXY(boundary);
  assert(Math.hypot(...delta) < 14, 'Transition escaped the reviewed alias bound');
  const result = points.filter((_, i) => cumulative[i] < start).map(p => p.slice());
  const stations = new Set(cumulative.filter(m => m >= start && m < total - 1));
  for (let m = start; m < total - 1; m += transition.sampleStepMetres) stations.add(m);
  for (const metre of [...stations].sort((a, b) => a - b)) {
    let i = 0;
    while (cumulative[i + 1] < metre) i++;
    const fraction = (metre - cumulative[i]) / (cumulative[i + 1] - cumulative[i]);
    const t = (metre - start) / transition.metres;
    const weight = t * t * t * (10 + t * (-15 + 6 * t));
    result.push(fromXY([xy[i][0] + fraction * (xy[i + 1][0] - xy[i][0]) + delta[0] * weight,
      xy[i][1] + fraction * (xy[i + 1][1] - xy[i][1]) + delta[1] * weight]));
  }
  // Match the retained outside ray at the boundary, without an orthogonal step.
  const ray = toXY(outside).map((v, i) => v - delta[i]), magnitude = Math.hypot(...ray);
  result.push(fromXY(delta.map((v, i) => v - ray[i] / magnitude)), boundary.slice());
  return result;
}

function localProjection(point, points) {
  const sx = 111320 * Math.cos(point[1] * Math.PI / 180), sy = 111320;
  let best;
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[i], b = points[i + 1], dx = (b[0]-a[0])*sx, dy = (b[1]-a[1])*sy;
    const t = Math.max(0, Math.min(1, ((point[0]-a[0])*sx*dx + (point[1]-a[1])*sy*dy)/(dx*dx+dy*dy)));
    const coordinate = [a[0]+t*(b[0]-a[0]), a[1]+t*(b[1]-a[1])];
    const distanceMetres = Math.hypot((coordinate[0]-point[0])*sx, (coordinate[1]-point[1])*sy);
    if (!best || distanceMetres < best.distanceMetres) best = { coordinate, distanceMetres, segment:i };
  }
  return best;
}
function identifiedMean(e) {
  assert.equal(e.format, 'jtm-keishin-kamisakaemachi-display-v1');
  for (const w of e.ways) {
    const primary = JSON.parse(fs.readFileSync(path.join(REPO, e.sourceDirectory, `way-${w.id}-full.json`)));
    const actual = primary.elements.find(x => x.type === 'way');
    assert.deepEqual([actual.id, actual.version, actual.timestamp, actual.tags, actual.nodes],
      [w.id,w.version,w.timestamp,w.tags,w.nodes], 'Primary Keihan passenger graph changed');
    const nodes = new Map(primary.elements.filter(x => x.type === 'node').map(x => [x.id,x]));
    assert.deepEqual(actual.nodes.map(n => [nodes.get(n).lon,nodes.get(n).lat]),w.coordinates);
    assert.equal(w.tags.operator,'京阪電気鉄道'); assert.equal(w.tags.name,'京阪電気鉄道京津線');
    assert.equal(w.tags.gauge,'1435'); assert.equal(w.tags.passenger_lines,'2');
    assert.equal(w.tags.usage,'branch'); assert(!w.tags.service);
    assert.equal(w.tags.railway, 'rail');
    if ([80241107,518501759].includes(w.id)) assert.equal(w.tags.embedded,'pavement');
  }
  for (const c of e.sameTrackConnections) {
    const a=e.ways.find(w=>w.id===c.railWay), b=e.ways.find(w=>w.id===c.tramWay);
    const i=a.nodes.indexOf(c.sharedNode), j=b.nodes.indexOf(c.sharedNode);
    assert(i>=0 && j>=0 && same(a.coordinates[i],b.coordinates[j]),'Keihan same-track join changed');
  }
  const tracks=[30662150,518501760].map(id=>e.ways.find(w=>w.id===id));
  const latitudes=[...new Set([35.0030,35.0059,...tracks.flatMap(w=>w.coordinates.filter(p=>p[1]>=35.0030 && p[1]<=35.0059).map(p=>p[1]))])].sort((a,b)=>a-b);
  const atLatitude=(w,y)=>{
    for(let i=0;i<w.coordinates.length-1;i++) {
      const a=w.coordinates[i],b=w.coordinates[i+1];
      if(y>=Math.min(a[1],b[1])&&y<=Math.max(a[1],b[1])&&a[1]!==b[1]) return a[0]+(y-a[1])/(b[1]-a[1])*(b[0]-a[0]);
    }
    assert.fail('Paired mean outside identified rail legs');
  };
  const mean=latitudes.map(y=>[(atLatitude(tracks[0],y)+atLatitude(tracks[1],y))/2,y]);
  assert.deepEqual(mean,e.meanLocalCoordinates,'Reviewed paired mean changed');
  const p=localProjection(e.baselineLine.stations[5].slice(2,4),mean);
  assert.deepEqual(p.coordinate,e.displayAnchor); assert(p.distanceMetres<9);
  return mean;
}
export function repairPackage(input,e=read('scripts/railway/keishin-kamisakaemachi-display-evidence.json'),upstream=read('scripts/railway/keishin-display-curve-evidence.json')) {
  const mean=identifiedMean(e),baseline=structuredClone(e.baselineLine);
  // Run the original strict owner against its own frozen pre-station baseline.
  const replay=repairCurve({lines:[structuredClone(baseline)],geometrySource:{}},upstream);
  assert.deepEqual(replay.lines[0],baseline,'Earlier Keishin curve stage no longer reproduces baseline');
  assert.deepEqual(baseline.stations[5].slice(0,4),['005987','上栄町',135.86019,35.00518]);
  const physical=network.decodeIntervals(baseline),display4=baseline.displayIntervalCoordinates[4];
  const start=[135.86004,35.00486],end=[135.86048,35.00564];
  assert.deepEqual(physical[4][28],start); assert.deepEqual(physical[5][2],end);
  const a=localProjection(start,mean),s=localProjection(baseline.stations[5].slice(2,4),mean),b=localProjection(end,mean);
  assert(a.segment<s.segment && s.segment<b.segment && a.distanceMetres<5 && b.distanceMetres<4);
  const incoming=[a.coordinate,...mean.slice(a.segment+1,s.segment+1),e.displayAnchor];
  const outgoing=[e.displayAnchor,...mean.slice(s.segment+1,b.segment+1),b.coordinate];
  const i=display4.findIndex(p=>same(p,start)); assert(i>=0);
  const corrected=structuredClone(baseline);
  corrected.displayStationCoordinates={...baseline.displayStationCoordinates,[e.stationID]:e.displayAnchor.slice()};
  corrected.displayIntervalCoordinates={...baseline.displayIntervalCoordinates,
    4:[...display4.slice(0,i),...taperToRetainedBoundary(incoming.toReversed(),start,display4[i-1],e.transition).toReversed()],
    5:[...taperToRetainedBoundary(outgoing,end,physical[5][3],e.transition),...physical[5].slice(3)]};
  const current=input.lines.find(l=>l.id===e.lineID);
  assert(equal(current,baseline)||equal(current,corrected),'Unreviewed Keishin dependency changed');
  const pkg=structuredClone(input);pkg.lines[pkg.lines.findIndex(l=>l.id===e.lineID)]=corrected;
  pkg.geometrySource||={};pkg.geometrySource.manualOverrides||={};
  pkg.geometrySource.manualOverrides['keishin-kamisakaemachi-display']={reviewedAt:e.reviewedAt,lineID:e.lineID,stationID:e.stationID,
    script:'app/scripts/railway/repair-keishin-kamisakaemachi-display.mjs',evidence:'app/scripts/railway/keishin-kamisakaemachi-display-evidence.json',
    displayAnchor:e.displayAnchor,intervals:[4,5],bounds:{incoming:start,outgoing:end},transition:e.transition,
    passengerWays:e.ways.map(w=>({id:w.id,version:w.version,timestamp:w.timestamp})),physicalTopologyChanged:false,
    policy:'Paired identified Keihan passenger corridor; catalog projection is a display alias, not a surveyed platform centre.'};
  return pkg;
}
export function repairParts(pkg,input,e=read('scripts/railway/keishin-kamisakaemachi-display-evidence.json')) {
  const line=pkg.lines.find(l=>l.id===e.lineID),parts=network.displayPartsForLine(line);
  assert.equal(parts.length,1,'Keishin decomposition changed');
  const displayed={...line,stations:line.stations.map(s=>line.displayStationCoordinates?.[s[0]]?[...s.slice(0,2),...line.displayStationCoordinates[s[0]],...s.slice(4)]:s),
    segments:line.segments.map((s,i)=>line.displayIntervalCoordinates?.[i]?[s[0],0,line.displayIntervalCoordinates[i]]:s)};
  const rows=partRowsForLine(line,parts,{stations:displayed.stations,intervals:network.decodeIntervals(displayed)},null);
  assert(rows.every(r=>!r[8]?.length),'Unreviewed withheld measures');
  const cached=input.partsByRegion.jp.filter(r=>r[0]===e.lineID);
  assert(equal(cached,e.baselineNativeRows)||equal(cached,rows),'Keishin native part dependency changed');
  for(const [key,expected] of Object.entries(e.baselineMeasuredReferences)) assert.deepEqual((input[key]?.jp||[]).filter(r=>JSON.stringify(r).includes(e.lineID)),expected,'Keishin measured references changed: '+key);
  assert(!(input.reversedLoopParts?.jp||[]).some(r=>r.split('#')[0]===e.lineID));
  const lanes=structuredClone(input);lanes.partsByRegion.jp=lanes.partsByRegion.jp.map(r=>r[0]===e.lineID?rows[r[1]]:r);return lanes;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const args=process.argv.slice(2),apply=equal(args,['--apply']);assert(!args.length||apply,'Usage: repair-keishin-kamisakaemachi-display.mjs [--apply]');
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',evidence:'scripts/railway/keishin-kamisakaemachi-display-evidence.json',upstream:'scripts/railway/keishin-display-curve-evidence.json',shared:'public/rail/shared-corridors.json',script:'scripts/railway/repair-keishin-kamisakaemachi-display.mjs',priorScript:'scripts/railway/repair-keishin-display-curve.mjs',network:'public/rail-network.js',partsBuilder:'scripts/railway/build-display-lanes.mjs',dependencyHelper:'scripts/railway/repair-three-reversal-extents.mjs',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>{const file=path.join(ROOT,p);return[k,{path:file,before:fs.readFileSync(file,'utf8')}];}));
  const load=k=>JSON.parse(snapshots[k].before),e=load('evidence');
  assert(!JSON.stringify(load('shared')).includes(e.lineID),'Shared Keishin reference requires review');
  const pkg=repairPackage(load('package'),e,load('upstream')),lanes=repairParts(pkg,load('lanes'),e);
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
  if(apply)applyPreparedWrites([{...snapshots.package,after:JSON.stringify(pkg)},{...snapshots.lanes,after:JSON.stringify(lanes)+'\n'},...Object.keys(DEPENDENCY_PATHS).map(k=>({...snapshots[k],after:JSON.stringify(deps[k],null,2)+'\n'}))],Object.values(snapshots));
  console.log(JSON.stringify({mode:apply?'applied':'candidate',lineID:e.lineID,displayAnchor:e.displayAnchor,intervalPointCounts:[4,5].map(i=>pkg.lines.find(l=>l.id===e.lineID).displayIntervalCoordinates[i].length),physicalTopologyChanged:false}));
}
