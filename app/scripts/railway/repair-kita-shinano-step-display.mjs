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
const LINE='jp-しなの鉄道-北しなの線',KEY='kita-shinano-step-display',EVIDENCE='scripts/railway/kita-shinano-step-display-evidence.json';
const network=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(p));
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function proposedLine(e){
  assert.equal(e.format,'jtm-kita-shinano-display-step-v1');assert.equal(e.lineID,LINE);assert.equal(e.baselineLine.id,LINE);
  for(const s of e.appleSources)assert.equal(createHash('sha256').update(fs.readFileSync(path.resolve(REPO,e.sourceRoot,s.file))).digest('hex'),s.sha256,'Kita-Shinano Apple source bytes changed');
  const view=read(path.resolve(REPO,e.sourceRoot,'apple-p14-view.json'));
  assert.deepEqual([view.lineID,view.intervalIndex,view.pointOrdinal,view.fromStationID,view.toStationID],[LINE,0,14,'001746','001788']);
  const line=structuredClone(e.baselineLine),old=network.decodeIntervals(line)[0];assert.deepEqual(old,e.oldDecodedInterval);
  assert.equal(e.removedIndex,69);assert.deepEqual(old[68],[138.18858,36.8364]);assert.deepEqual(old[69],[138.18864,36.83637]);
  assert.deepEqual(e.retainedWindow.indices,[66,67,68,70,71]);assert.deepEqual(e.retainedWindow.coordinates,[66,67,68,70,71].map(i=>old[i]));
  assert.equal(e.rawFeature.index,15085);assert.equal(e.rawFeature.feature.properties.N02_003,'北しなの線');assert.equal(e.rawFeature.feature.properties.N02_004,'しなの鉄道');
  assert.deepEqual(e.rawFeature.feature.geometry.coordinates.slice(66,70),old.slice(67,71));
  line.displayIntervalCoordinates={...line.displayIntervalCoordinates,0:old.filter((_,i)=>i!==69)};return line;
}
export function repairPackage(input,e=read(path.join(ROOT,EVIDENCE))){
  const proposed=proposedLine(e),indices=input.lines.flatMap((l,i)=>l.id===LINE?[i]:[]);assert.equal(indices.length,1);
  assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],proposed),'Kita-Shinano baseline changed');
  assert.match(input.geometrySource.license,/OpenStreetMap.*ODbL/i);
  const provenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,intervalIndex:0,removedDisplayVertex:69,retainedGuards:[66,67,68,70,71],reference:'Apple labelled own conventional corridor, historical point14 originals; no OSM coordinate shift',policy:e.policy,evidence:'app/'+EVIDENCE,script:'app/scripts/railway/repair-kita-shinano-step-display.mjs',physicalTopologyChanged:false};
  const previous=input.geometrySource.manualOverrides?.[KEY];assert(previous===undefined||equal(previous,provenance),'Kita-Shinano provenance changed');
  const result=structuredClone(input);result.lines[indices[0]]=proposed;result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;return result;
}
export function repairParts(pkg,input,e=read(path.join(ROOT,EVIDENCE))){
  const line=pkg.lines.find(l=>l.id===LINE);assert.deepEqual(line,proposedLine(e));
  // Native plain-range rows decode this same display interval, not the canonical step.
  const intervals=network.decodeIntervals(line);intervals[0]=line.displayIntervalCoordinates[0];
  const rows=partRowsForLine(line,network.displayPartsForLine(line),{stations:line.stations,intervals},null);
  assert.deepEqual(rows,e.candidateNativeRows,'Kita-Shinano native ruler changed');assert.equal(rows.length,1);
  const lane=[[LINE,0,0,rows[0][5],e.baselineRows.byRegion[0][4]]];
  for(const key of ['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion']){
    const own=(input[key]?.jp||[]).filter(r=>r[0]===LINE||key==='followsByRegion'&&r[4]===LINE),expected=key==='partsByRegion'?rows:key==='byRegion'?lane:e.baselineRows[key];
    assert(equal(own,e.baselineRows[key])||equal(own,expected),'Kita-Shinano reference changed: '+key);
  }
  assert.deepEqual((input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE)),e.baselineRows.loopsByRegion,'Kita-Shinano reference changed: loopsByRegion');
  assert.deepEqual((input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#')),e.baselineRows.reversedLoopParts,'Kita-Shinano reference changed: reversedLoopParts');
  const hubs=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));
  assert.deepEqual(hubs,e.baselineRows.hubMembers,'Kita-Shinano hub reference changed');
  for(const[key,frozen]of Object.entries(e.ownMaps))assert.deepEqual(input[key]?.jp?.[LINE]??null,frozen,'Kita-Shinano map reference changed');
  assert(!(input.excludedOperators||[]).includes(e.baselineLine.operator),'Kita-Shinano excluded operator changed');assert(!(input.excludedLineIds||[]).includes(LINE),'Kita-Shinano excluded line changed');
  const result=structuredClone(input);result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows[0]:r);result.byRegion.jp=result.byRegion.jp.map(r=>r[0]===LINE?lane[0]:r);return result;
}
function main(args){
  const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;assert(candidate||equal(args,['--apply']),'Use --candidate-root /private/tmp/<dir> or --apply');if(candidate)assert(candidate.startsWith('/private/tmp/'));
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(ROOT,p),before:fs.readFileSync(path.join(ROOT,p),'utf8')}]));
  const e=read(path.join(ROOT,EVIDENCE)),inputPaths=[path.join(ROOT,EVIDENCE),...e.appleSources.map(s=>path.resolve(REPO,e.sourceRoot,s.file)),path.join(ROOT,'data/rail-sections.json'),...e.externalPaths.map(p=>path.join(ROOT,p))];
  const sourceSnapshots=inputPaths.map(p=>({path:p,before:fs.readFileSync(p,'utf8')}));
  assert.deepEqual(read(path.join(ROOT,'data/rail-sections.json')).features[e.rawFeature.index],e.rawFeature.feature,'Kita-Shinano raw N02 changed');
  const shared=read(path.join(ROOT,'public/rail/shared-corridors.json'));
  assert.deepEqual(shared.corridors.filter(r=>(r.lineIds||[]).includes(LINE)||(r.members||[]).some(m=>m.lineId===LINE)),e.baselineExternalDisplayReferences.corridors,'Kita-Shinano shared corridor changed');
  assert.deepEqual(shared.displayLandlords.filter(r=>r.tenantLineId===LINE||r.landlordLineId===LINE||(r.tenantLineIds||[]).includes(LINE)||(r.landlordLineIds||[]).includes(LINE)),e.baselineExternalDisplayReferences.displayLandlords,'Kita-Shinano display landlord changed');
  assert.deepEqual((shared.displayLanePolicy.excludedLineIds||[]).filter(id=>id===LINE),e.baselineExternalDisplayReferences.excludedLineIds,'Kita-Shinano shared exclusion changed');
  assert.deepEqual(read(path.join(ROOT,'public/rail/display-releases.json')).releases.filter(r=>r.lineId===LINE),e.baselineExternalDisplayReferences.releases,'Kita-Shinano display release changed');
  assert.deepEqual(read(path.join(ROOT,'data/physical-rail-junctions.json')).junctions.filter(r=>r.lineIDs?.includes(LINE)),e.baselineExternalDisplayReferences.junctions,'Kita-Shinano junction changed');
  const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e);
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
  const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
  if(candidate){fs.mkdirSync(candidate,{recursive:true});for(const[k,after]of Object.entries(outputs))fs.writeFileSync(path.join(candidate,path.basename(snapshots[k].path)),after);}
  else applyPreparedWrites(Object.entries(outputs).filter(([k,v])=>v!==snapshots[k].before).map(([k,after])=>({...snapshots[k],after})),[...Object.values(snapshots),...sourceSnapshots]);
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',lineID:LINE,removedDisplayVertex:69,nativeRows:lanes.partsByRegion.jp.filter(r=>r[0]===LINE),physicalTopologyChanged:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
