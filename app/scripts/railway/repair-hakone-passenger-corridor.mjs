#!/usr/bin/env node
// Reviewed display-source repair; canonical graph, station IDs and mileage stay intact.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const same = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const distance = (a,b) => Math.hypot((b[0]-a[0])*111320*Math.cos((a[1]+b[1])*Math.PI/360),(b[1]-a[1])*111320);
const length = p => p.slice(1).reduce((s,b,i)=>s+distance(p[i],b),0);
function correctedLine(e, includeCartographicOverrides = true) {
  const line = structuredClone(e.baselineLine);
  line.displayStationCoordinates = { ...line.displayStationCoordinates, ...structuredClone(e.displayStationCoordinateOverrides || {}) };
  line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates, ...structuredClone(e.coordinates) };
  line.reversalTails = [...line.reversalTails, ...structuredClone(e.actualReversalTips)];
  line.displayReversalBranches = structuredClone(e.displayReversalBranches);
  if(includeCartographicOverrides) for(const [interval,review] of Object.entries(e.displayCartographicOverrides || {})) {
    const [first,last]=review.sourceWindow.indicesInclusive;
    const source=line.displayIntervalCoordinates[interval];
    line.displayIntervalCoordinates[interval]=[
      ...source.slice(0,first),...structuredClone(review.coordinates),...source.slice(last+1)
    ];
  }
  return line;
}
function distanceToPath(point,points) {
  const scale=Math.cos(point[1]*Math.PI/180);
  return Math.min(...points.slice(1).map((b,i)=>{
    const a=points[i],dx=(b[0]-a[0])*scale,dy=b[1]-a[1],x=(point[0]-a[0])*scale,y=point[1]-a[1];
    const t=Math.max(0,Math.min(1,(x*dx+y*dy)/(dx*dx+dy*dy || 1)));
    return Math.hypot(x-t*dx,y-t*dy)*111320;
  }));
}
function validateCartographicOverrides(e) {
  if(!e.displayCartographicOverrides) return;
  assert.deepEqual(Object.keys(e.displayCartographicOverrides),['6']);
  const review=e.displayCartographicOverrides[6],source=e.coordinates[6],points=review.coordinates;
  assert.equal(review.format,'jtm-hakone6-cartographic-display-v1');
  assert.equal(review.lineID,e.lineID); assert.equal(review.interval,6);
  assert.deepEqual(review.sourceWindow.indicesInclusive,[47,54]);
  assert.equal(review.sourceWindow.wayID,242460442);
  assert.deepEqual(review.sourceWindow.coordinates,source.slice(47,55));
  const way=e.ways.find(w=>w.id===242460442);
  assert.equal(way.tags.tunnel,'yes');
  assert.deepEqual(way.geometry.map(g=>[g.lon,g.lat]).toReversed(),source.slice(47,55));
  assert(e.chains[6].some(([id,direction])=>id===way.id && direction===-1));
  assert.deepEqual(points[0],source[47]); assert.deepEqual(points.at(-1),source[54]);
  assert(points.length>=10 && points.length<=40);
  assert(points.every(p=>p.length===2 && p.every(Number.isFinite)));
  assert(points.every((p,i)=>!i || p[0]<points[i-1][0]),'Reviewed tunnel leg must remain monotone without a new reversal');
  assert(points.every(p=>distanceToPath(p,source.slice(47,55))<12),'Cartographic supplement escaped reviewed source window');
  assert.deepEqual(review.nativeReference.mapScreenshotRect,[255,149,769,530]);
  assert.deepEqual(review.nativeReference.wgs84Bounds,[139.068351,35.234867,139.073710,35.237890]);
  const [west,south,east,north]=review.nativeReference.wgs84Bounds;
  const fromPixel=([x,y])=>[west+(x-255)/769*(east-west),north-(y-149)/530*(north-south)];
  for(const pixel of review.nativeReference.rawReferencePixels)
    assert(points.some(p=>distance(p,fromPixel(pixel))<0.001),'Native cartographic support lost');
  assert.deepEqual(points.at(-2),review.join.westGuardCoordinate);
  const guard=points.at(-2),outside=source[55],boundary=source[54];
  assert(Math.abs(distance(guard,boundary)-1)<0.001,'West tangent alias must be one metre');
  assert(Math.abs((guard[0]-boundary[0])*(boundary[1]-outside[1])-(guard[1]-boundary[1])*(boundary[0]-outside[0]))<1e-15);
}
export function repairPackage(input, e) {
  assert.equal(e.format,'jtm-hakone-passenger-corridor-v1');
  assert.deepEqual(Object.keys(e.coordinates), ['4','5','6','7','8','9']);
  if(e.displayStationCoordinateOverrides) {
    assert.deepEqual(Object.keys(e.displayStationCoordinateOverrides),['005269']);
    const p=e.displayStationCoordinateOverrides['005269'], review=e.stationRailReview;
    assert.equal(review.id,'005269');
    assert.deepEqual(p,review.displayCoordinate);
    assert.deepEqual(p,review.sourceProjection[1]);
    const [, , a,b,properties]=review.sourceProjection;
    assert.equal(properties.gsiLayer,'railway');
    assert.equal(properties.ftCode,2801);
    assert(Math.abs(distance(a,p)+distance(p,b)-distance(a,b))<0.001,'Station anchor must be on reviewed reference segment');
    assert(distance(p,e.baselineLine.stations[5].slice(2,4))<10);
    assert(distance(p,e.coordinates[5][1])<4,'Bounded station display alias');
  }
  const ways = new Map(e.ways.map(w=>[w.id,w]));
  for (const [interval,chain] of Object.entries(e.chains)) {
    let previous;
    const survey=[];
    for (const [id,direction] of chain) {
      const w = ways.get(id);
      assert(w && w.tags.railway === 'rail' && !w.tags.service);
      assert(['小田急箱根','箱根登山鉄道'].includes(w.tags.operator));
      assert(!['industrial','military','freight'].includes(w.tags.usage));
      assert(direction === 1 || direction === -1);
      assert(!(direction === -1 && w.tags.oneway === 'yes'));
      const nodes = direction === 1 ? w.nodes : w.nodes.toReversed();
      const points = w.geometry.map(g=>[g.lon,g.lat]);
      if(direction === -1) points.reverse();
      if(previous) {
        assert.equal(previous.node,nodes[0], 'Disconnected passenger switch nodes');
        assert.deepEqual(previous.point,points[0]);
      }
      survey.push(...points.slice(previous ? 1 : 0));
      previous = {node:nodes.at(-1),point:points.at(-1)};
    }
    const interior = interval === '5' ? e.coordinates[interval].slice(2,-1)
      : interval === '6' ? e.coordinates[interval].slice(1,-2) : e.coordinates[interval].slice(2,-2);
    assert(survey.some((p,index)=>same(p,interior[0]) && same(survey.slice(index,index+interior.length),interior)),
      'Reviewed display must retain contiguous ordered survey vertices');
  }
  for(const [i,points] of Object.entries(e.coordinates)) {
    const start = e.baselineLine.stations[+i], end = e.baselineLine.stations[+i+1];
    const anchor = s=>e.displayStationCoordinateOverrides?.[s[0]] || e.baselineLine.displayStationCoordinates?.[s[0]] || s.slice(2,4);
    assert.deepEqual(points[0],anchor(start)); assert.deepEqual(points.at(-1),anchor(end));
    for(const p of points.slice(1,-1)) {
      const onSurvey = e.ways.some(w=>w.geometry.some(g=>same(p,[g.lon,g.lat])));
      // Only the two bounded station-to-survey projections may be interpolated.
      assert(onSurvey || (+i!==6 && same(p,points[1])) || (+i!==5 && same(p,points.at(-2))));
    }
  }
  assert(distance(e.coordinates[5][0],e.coordinates[5][1])<7);
  assert(distance(e.coordinates[6].at(-2),e.coordinates[6].at(-1))<2);
  for(const [i,projection] of Object.entries(e.adjacentEndpointProjections)) {
    const points=e.coordinates[i];
    for(const [end,p] of Object.entries(projection)) {
      if(end!=='start' && end!=='end') continue;
      assert.deepEqual(end==='start' ? points[1] : points.at(-2),p.coordinate);
      assert(distance(p.coordinate,p.canonicalCoordinate)<p.boundedAliasMetres);
    }
  }
  for(const [before,after] of [[4,5],[6,7],[7,8],[8,9]])
    assert.deepEqual(e.coordinates[before].at(-2),e.coordinates[after][1], 'Survey station seam mismatch');
  // The independent native cartographic supplement is reviewed separately;
  // it cannot relax or replace the ordered OSM passenger graph proof above.
  validateCartographicOverrides(e);
  const pkg = structuredClone(input), index = pkg.lines.findIndex(l=>l.id===e.lineID);
  assert(index>=0);
  const repaired = correctedLine(e);
  assert(same(pkg.lines[index],e.baselineLine) || same(pkg.lines[index],e.previousReviewedLine) || same(pkg.lines[index],e.branchBaselineLine) || same(pkg.lines[index],e.stationBaselineLine) || same(pkg.lines[index],correctedLine(e,false)) || same(pkg.lines[index],repaired), 'Unreviewed line change');
  pkg.lines[index] = repaired;
  const parts = network.displayPartsForLine(repaired);
  assert.equal(parts.length,7);
  for(const tip of e.actualReversalTips) assert(parts.some(p=>p.some(v=>same(v,tip))), 'Surveyed reversal lost');
  for(const stem of e.displayReversalBranches) {
    assert.equal(parts.filter(p=>same(p,stem)).length,1,'Terminal stem must be drawn once');
    assert.equal(parts.filter(p=>same(p[0],stem[0])||same(p.at(-1),stem[0])).length,3,'Three fork legs must connect');
  }
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['hakone-passenger-corridor'] = {
    reviewedAt:e.date, source:e.source, intervals:[4,5,6,7,8,9], script:'app/scripts/railway/repair-hakone-passenger-corridor.mjs',
    evidence:'app/scripts/railway/hakone-passenger-corridor-evidence.json',
    passengerOnly:true, physicalTopologyChanged:false,
    ...(e.stationRailReview ? {stationDisplayReview:e.stationRailReview} : {}),
    ...(e.displayCartographicOverrides ? {displayCartographicReviews:e.displayCartographicOverrides} : {}),
    policy:'Node-connected passenger representative; preserves full switchback retraces. Unique timetable platform allocation is not certified.'
  };
  return pkg;
}
function measuredNativeDependencies(line,e) {
  const parts=network.displayPartsForLine(line);
  const displayLine={...line,stations:line.stations.map(s=>line.displayStationCoordinates?.[s[0]] ? [...s.slice(0,2),...line.displayStationCoordinates[s[0]],...s.slice(4)] : s),
    segments:line.segments.map((s,i)=>line.displayIntervalCoordinates?.[i] ? [s[0],0,line.displayIntervalCoordinates[i]] : s)};
  const rows=partRowsForLine(line,parts,{stations:displayLine.stations,intervals:network.decodeIntervals(displayLine)},null);
  return {...e.baselineNativeDependencies,
    partsByRegion:rows,
    byRegion:parts.map((p,i)=>[e.lineID,i,0,length(p),0.5]),
    // Old N02 overlaps ceased to exist. Reviewed terminal stems share exact surveyed forks.
    followsByRegion:[],
    chainBoundariesByRegion:[[e.lineID,1,3,"exact-shared-spur-main-legs"],[e.lineID,3,4,"exact-shared-spur-main-legs"],[e.lineID,4,6,"exact-shared-spur-main-legs"]]};
}
export function repairParts(pkg,input,e) {
  const result=structuredClone(input),line=pkg.lines.find(l=>l.id===e.lineID);
  const selected=measuredNativeDependencies(line,e);
  const beforeCartographic=measuredNativeDependencies(correctedLine(e,false),e);
  for(const [key,baseline] of Object.entries(e.baselineNativeDependencies)) {
    const current=input[key]?.jp || [], ours=current.filter(r=>JSON.stringify(r).includes(e.lineID));
    assert(same(ours,baseline)||same(ours,e.previousNativeDependencies[key])||same(ours,e.branchBaselineNativeDependencies[key])||same(ours,e.stationBaselineNativeDependencies?.[key])||same(ours,beforeCartographic[key])||same(ours,selected[key]), 'Unreviewed measured dependency: '+key);
    result[key].jp=current.filter(r=>!JSON.stringify(r).includes(e.lineID)).concat(selected[key]);
  }
  return result;
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const args=process.argv.slice(2), apply=same(args,['--apply']);
  assert(!args.length||apply,'Usage: repair-hakone-passenger-corridor.mjs [--apply]');
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',evidence:'scripts/railway/hakone-passenger-corridor-evidence.json',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([key,relative])=>{const file=path.join(ROOT,relative);return[key,{path:file,before:fs.readFileSync(file,'utf8')}];}));
  const read=k=>JSON.parse(snapshots[k].before),e=read('evidence'),pkg=repairPackage(read('package'),e),lanes=repairParts(pkg,read('lanes'),e);
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,read(k)])));
  if(apply) applyPreparedWrites([{...snapshots.package,after:JSON.stringify(pkg)},{...snapshots.lanes,after:JSON.stringify(lanes)+'\n'},
    ...Object.keys(DEPENDENCY_PATHS).map(k=>({...snapshots[k],after:JSON.stringify(deps[k],null,2)+'\n'}))],Object.values(snapshots));
  console.log(JSON.stringify({mode:apply?'applied':'candidate',intervalMetres:Object.values(e.coordinates).map(length),parts:lanes.partsByRegion.jp.filter(r=>r[0]===e.lineID).map(r=>r.slice(0,7))}));
}
