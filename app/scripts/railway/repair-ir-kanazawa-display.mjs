#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const EVIDENCE = 'scripts/railway/ir-kanazawa-display-evidence.json';
const KEY = 'ir-kanazawa-display';
const LINE = 'jp-IRいしかわ鉄道-IRいしかわ鉄道線';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);

function ownChain(e) {
  const sourceRoot = path.resolve(REPO, e.sourceRoot);
  const identified = read(path.join(sourceRoot, 'identified-osm-live.json'));
  const continuation = read(path.join(sourceRoot, 'own-track2-continuation.json'));
  const relation = identified['834273931/relations.json'].elements.find(r => r.type === 'relation' && r.id === 4669038);
  assert.equal(relation.version, 26);
  let previousNode;
  const coordinates = [];
  for (const [id, version, full] of [[834273931,5,identified['834273931/full.json']], [394894111,7,continuation]]) {
    const way = full.elements.find(r => r.type === 'way' && r.id === id);
    assert.equal(way.version, version);
    for (const [key,value] of Object.entries(e.fragment.window.sourceTagsRequired)) assert.equal(way.tags[key],value);
    assert.equal(way.tags.railway, 'rail');
    assert.equal(way.tags.service, undefined);
    assert(relation.members.some(r => r.type === 'way' && r.ref === id));
    const nodes = new Map(full.elements.filter(r => r.type === 'node').map(r => [r.id,r]));
    const ordered = way.nodes.toReversed();
    if (previousNode !== undefined) assert.equal(ordered[0], previousNode, 'Own track chain disconnected');
    for (const nodeID of ordered.slice(previousNode === undefined ? 0 : 1)) {
      const node = nodes.get(nodeID);
      assert(Number.isInteger(node.version));
      coordinates.push([node.lon,node.lat]);
    }
    previousNode = ordered.at(-1);
  }
  return coordinates;
}

function proposedLine(e) {
  assert.equal(e.format, 'jtm-ir-kanazawa-display-v1');
  assert.equal(e.lineID, LINE);
  const line = structuredClone(e.baselineLine), f = e.fragment, w = f.window;
  assert.equal(line.id,e.lineID);
  assert.deepEqual(line.stations.slice(3,5).map(r=>r[0]), ['002076','002093']);
  assert.deepEqual(line.segments[3],f.canonicalCompactRowGuard);
  assert.deepEqual(network.decodeIntervals(line)[3],f.oldDecodedInterval);
  assert.deepEqual([w.decodedStartIndex,w.decodedEndIndexInclusive],[1,26]);
  const chain = ownChain(e);
  const projections = w.projectedBoundaries.map(b => {
    const p = projectPointOntoPolyline(f.oldDecodedInterval[b.index],chain);
    assert.deepEqual(p.point,b.point);
    assert.equal(p.insertIndex,b.insertIndex);
    assert(Math.abs(p.distanceM-b.distanceM)<1e-9);
    return p;
  });
  const replacement = [projections[0].point,...chain.slice(projections[0].insertIndex+1,projections[1].insertIndex+1),projections[1].point];
  assert.deepEqual(replacement,w.replacementCoordinates);
  const interval = [...f.oldDecodedInterval.slice(0,1),...replacement,...f.oldDecodedInterval.slice(27)];
  assert.deepEqual(interval,f.candidateDecodedInterval);
  line.displayIntervalCoordinates = {...line.displayIntervalCoordinates,3:interval};
  return line;
}

export function repairPackage(input,e=read(path.join(ROOT,EVIDENCE))) {
  const proposed = proposedLine(e), indices=input.lines.flatMap((r,i)=>r.id===e.lineID?[i]:[]);
  assert.equal(indices.length,1);
  assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],proposed),'IR baseline changed');
  assert.match(input.geometrySource.license,/OpenStreetMap.*ODbL/i);
  const result=structuredClone(input);
  result.lines[indices[0]]=proposed;
  result.geometrySource.manualOverrides ??= {};
  result.geometrySource.manualOverrides[KEY]={reviewedAt:e.reviewedAt,status:e.status,lineID:e.lineID,intervalIndex:3,
    ways:[[834273931,5],[394894111,7]],relation:[4669038,26],policy:e.policy,research:e.research,
    script:'app/scripts/railway/repair-ir-kanazawa-display.mjs',physicalTopologyChanged:false};
  return result;
}

export function repairParts(pkg,input,e=read(path.join(ROOT,EVIDENCE))) {
  const line=pkg.lines.find(r=>r.id===e.lineID);
  assert.deepEqual(line,proposedLine(e));
  const rows=partRowsForLine(line,network.displayPartsForLine(line));
  assert.deepEqual(rows.map(r=>[r[4],r[5]]),[[646,64396.1]]);
  const lane=[[e.lineID,0,0,64396.1,0.5]];
  for (const key of ['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion']) {
    const current=(input[key]?.jp||[]).filter(r=>r[0]===e.lineID || key==='followsByRegion'&&r[4]===e.lineID);
    const expected=key==='partsByRegion'?rows:key==='byRegion'?lane:[];
    assert(equal(current,e.baselineRows[key])||equal(current,expected),'IR measured reference changed: '+key);
  }
  assert.deepEqual((input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(e.lineID)),
    e.baselineRows.loopsByRegion,'IR measured reference changed: loopsByRegion');
  assert.deepEqual((input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(e.lineID+'#')),
    e.baselineRows.reversedLoopParts,'IR measured reference changed: reversedLoopParts');
  for (const key of ['strokeExcludedByRegion','chainBoundariesByRegion']) {
    assert.deepEqual((input[key]?.jp||[]).filter(r=>r[0]===e.lineID),e.baselineRows[key],'IR measured reference changed: '+key);
  }
  const hubMembers=(input.hubReportByRegion?.jp||[]).flatMap(hub=>(hub.members||[])
    .filter(member=>member.lineId===e.lineID).map(member=>({hubID:hub.hubId,member})));
  assert.deepEqual(hubMembers,e.baselineRows.hubReportByRegion,'IR measured hub reference changed');
  const result=structuredClone(input);
  result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===e.lineID?rows[0]:r);
  result.byRegion.jp=result.byRegion.jp.map(r=>r[0]===e.lineID?lane[0]:r);
  return result;
}

function main(args) {
  const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;
  assert(candidate||equal(args,['--apply']),'Use --candidate-root /private/tmp/<dir> or --apply');
  if(candidate) assert(candidate.startsWith('/private/tmp/'));
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([key,p])=>[key,{path:path.join(ROOT,p),before:fs.readFileSync(path.join(ROOT,p),'utf8')}]));
  const evidence=read(path.join(ROOT,EVIDENCE));
  const sourceSnapshots=[path.join(ROOT,EVIDENCE),...['identified-osm-live.json','own-track2-continuation.json'].map(p=>path.resolve(REPO,evidence.sourceRoot,p))]
    .map(p=>({path:p,before:fs.readFileSync(p,'utf8')}));
  const load=key=>JSON.parse(snapshots[key].before);
  const pkg=repairPackage(load('package')),lanes=repairParts(pkg,load('lanes'));
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
  const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
  if(candidate) {fs.mkdirSync(candidate,{recursive:true});for(const [k,after] of Object.entries(outputs))fs.writeFileSync(path.join(candidate,path.basename(snapshots[k].path)),after);}
  else applyPreparedWrites(Object.entries(outputs).filter(([k,v])=>v!==snapshots[k].before).map(([k,after])=>({...snapshots[k],after})),[...Object.values(snapshots),...sourceSnapshots]);
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',lineID:LINE,physicalTopologyChanged:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
