#!/usr/bin/env node
// One Apple-own-corridor display step; canonical geometry and stations stay exact.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {partRowsForLine} from './build-display-lanes.mjs';
import {refreshDependencyReferences,applyPreparedWrites,DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';
const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),REPO=path.dirname(ROOT);
const LINE='jp-わたらせ渓谷鐵道-わたらせ渓谷線',KEY='watarase-hanawa-step-display',EVIDENCE='scripts/railway/watarase-hanawa-step-display-evidence.json';
const network=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(p));
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function proposedLine(e){
  assert.equal(e.format,'jtm-watarase-hanawa-display-step-v1');assert.equal(e.lineID,LINE);assert.equal(e.baselineLine.id,LINE);
  for(const s of e.appleSources)assert.equal(createHash('sha256').update(fs.readFileSync(path.resolve(REPO,e.sourceRoot,s.file))).digest('hex'),s.sha256,'Hanawa Apple source bytes changed');
  for(const source of e.ownSources)assert.equal(createHash('sha256').update(fs.readFileSync(path.resolve(REPO,e.sourceRoot,source.file))).digest('hex'),source.sha256,'Hanawa own source bytes changed');
  for(const i of [0,1]){
    const view=read(path.resolve(REPO,e.sourceRoot,`detail-p${i}-view.json`));
    assert.deepEqual([view.lineID,view.intervalIndex,view.pointOrdinal,view.fromStationID,view.toStationID],[LINE,8,i,'002164','002161']);
  }
  const own=read(path.resolve(REPO,e.sourceRoot,'osm-way-24373800-full.json')).elements.find(x=>x.type==='way');
  const approach=read(path.resolve(REPO,e.sourceRoot,'osm-way-925516063-full.json')).elements.find(x=>x.type==='way');
  const route=read(path.resolve(REPO,e.sourceRoot,'osm-way-24373800-relations.json')).elements[0];
  assert.deepEqual([own.id,own.version,approach.id,approach.version,own.nodes.at(-1),approach.nodes.at(-1)],[24373800,8,925516063,3,264461333,264461333]);
  assert.deepEqual([route.id,route.version,route.tags.route],[1949287,42,'railway']);
  assert(route.members.some(m=>m.type==='way'&&m.ref===own.id)&&route.members.some(m=>m.type==='way'&&m.ref===approach.id));
  const line=structuredClone(e.baselineLine),old=network.decodeIntervals(line)[8];assert.deepEqual(old,e.oldDecodedInterval);
  assert.equal(e.removedIndex,5);assert.deepEqual(old[4],[139.30938,36.52174]);assert.deepEqual(old[5],[139.30941,36.52174]);assert.deepEqual(old[6],[139.30943,36.52175]);
  assert.deepEqual(e.retainedWindow.indices,[1,2,3,4,6,7,8]);assert.deepEqual(e.retainedWindow.coordinates,[1,2,3,4,6,7,8].map(i=>old[i]));
  assert.equal(e.rawFeature.index,269);assert.equal(e.rawFeature.feature.properties.N02_003,'わたらせ渓谷線');assert.equal(e.rawFeature.feature.properties.N02_004,'わたらせ渓谷鐵道');
  assert.deepEqual(e.rawFeature.feature.geometry.coordinates,old.slice(1,31));
  line.displayIntervalCoordinates={...line.displayIntervalCoordinates,8:old.filter((_,i)=>i!==5)};return line;
}
export function repairPackage(input,e=read(path.join(ROOT,EVIDENCE))){
  const proposed=proposedLine(e),indices=input.lines.flatMap((l,i)=>l.id===LINE?[i]:[]);assert.equal(indices.length,1);
  assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],proposed),'Hanawa baseline changed');
  assert.match(input.geometrySource.license,/OpenStreetMap.*ODbL/i);
  const provenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,intervalIndex:8,removedDisplayVertex:5,retainedGuards:[1,2,3,4,6,7,8],reference:'Apple labelled own Watarase corridor z19 points0/1; own OSM identity, no coordinate shift; A v2/v3 retained',policy:e.policy,evidence:'app/'+EVIDENCE,script:'app/scripts/railway/repair-watarase-hanawa-step-display.mjs',physicalTopologyChanged:false};
  const previous=input.geometrySource.manualOverrides?.[KEY];assert(previous===undefined||equal(previous,provenance),'Hanawa provenance changed');
  const result=structuredClone(input);result.lines[indices[0]]=proposed;result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;return result;
}
export function repairParts(pkg,input,e=read(path.join(ROOT,EVIDENCE))){
  const line=pkg.lines.find(l=>l.id===LINE);assert.deepEqual(line,proposedLine(e));
  // Native plain-range rows decode this same display interval, not the canonical step.
  const intervals=network.decodeIntervals(line);intervals[8]=line.displayIntervalCoordinates[8];
  const rows=partRowsForLine(line,network.displayPartsForLine(line),{stations:line.stations,intervals},null);
  assert.deepEqual(rows,e.candidateNativeRows,'Hanawa native ruler changed');assert.equal(rows.length,1);
  const lane=[[LINE,0,0,rows[0][5],e.baselineRows.byRegion[0][4]]];
  for(const key of ['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion']){
    const own=(input[key]?.jp||[]).filter(r=>r[0]===LINE||key==='followsByRegion'&&r[4]===LINE),expected=key==='partsByRegion'?rows:key==='byRegion'?lane:e.baselineRows[key];
    assert(equal(own,e.baselineRows[key])||equal(own,expected),'Hanawa reference changed: '+key);
  }
  assert.deepEqual((input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE)),e.baselineRows.loopsByRegion,'Hanawa reference changed: loopsByRegion');
  assert.deepEqual((input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#')),e.baselineRows.reversedLoopParts,'Hanawa reference changed: reversedLoopParts');
  const hubs=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));
  assert.deepEqual(hubs,e.baselineRows.hubMembers,'Hanawa hub reference changed');
  for(const[key,frozen]of Object.entries(e.ownMaps))assert.deepEqual(input[key]?.jp?.[LINE]??null,frozen,'Hanawa map reference changed');
  assert(!(input.excludedOperators||[]).includes(e.baselineLine.operator),'Hanawa excluded operator changed');assert(!(input.excludedLineIds||[]).includes(LINE),'Hanawa excluded line changed');
  const result=structuredClone(input);result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows[0]:r);result.byRegion.jp=result.byRegion.jp.map(r=>r[0]===LINE?lane[0]:r);return result;
}
function main(args){
  const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;assert(candidate||equal(args,['--apply']),'Use --candidate-root /private/tmp/<dir> or --apply');if(candidate)assert(candidate.startsWith('/private/tmp/'));
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(ROOT,p),before:fs.readFileSync(path.join(ROOT,p),'utf8')}]));
  const e=read(path.join(ROOT,EVIDENCE)),inputPaths=[path.join(ROOT,EVIDENCE),...[...e.appleSources,...e.ownSources].map(s=>path.resolve(REPO,e.sourceRoot,s.file)),path.join(ROOT,'data/rail-sections.json'),...e.externalPaths.map(p=>path.join(ROOT,p))];
  const sourceSnapshots=inputPaths.map(p=>({path:p,before:fs.readFileSync(p,'utf8')}));
  assert.deepEqual(read(path.join(ROOT,'data/rail-sections.json')).features[e.rawFeature.index],e.rawFeature.feature,'Hanawa raw N02 changed');
  const shared=read(path.join(ROOT,'public/rail/shared-corridors.json'));
  assert.deepEqual(shared.corridors.filter(r=>(r.lineIds||[]).includes(LINE)||(r.members||[]).some(m=>m.lineId===LINE)),e.baselineExternalDisplayReferences.corridors,'Hanawa shared corridor changed');
  assert.deepEqual(shared.displayLandlords.filter(r=>r.tenantLineId===LINE||r.landlordLineId===LINE||(r.tenantLineIds||[]).includes(LINE)||(r.landlordLineIds||[]).includes(LINE)),e.baselineExternalDisplayReferences.displayLandlords,'Hanawa display landlord changed');
  assert.deepEqual((shared.displayLanePolicy.excludedLineIds||[]).filter(id=>id===LINE),e.baselineExternalDisplayReferences.excludedLineIds,'Hanawa shared exclusion changed');
  assert.deepEqual(read(path.join(ROOT,'public/rail/display-releases.json')).releases.filter(r=>r.lineId===LINE),e.baselineExternalDisplayReferences.releases,'Hanawa display release changed');
  assert.deepEqual(read(path.join(ROOT,'data/physical-rail-junctions.json')).junctions.filter(r=>r.lineIDs?.includes(LINE)),e.baselineExternalDisplayReferences.junctions,'Hanawa junction changed');
  const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e);
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
  const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
  if(candidate){fs.mkdirSync(candidate,{recursive:true});for(const[k,after]of Object.entries(outputs))fs.writeFileSync(path.join(candidate,path.basename(snapshots[k].path)),after);}
  else applyPreparedWrites(Object.entries(outputs).filter(([k,v])=>v!==snapshots[k].before).map(([k,after])=>({...snapshots[k],after})),[...Object.values(snapshots),...sourceSnapshots]);
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',lineID:LINE,removedDisplayVertex:5,nativeRows:lanes.partsByRegion.jp.filter(r=>r[0]===LINE),physicalTopologyChanged:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
