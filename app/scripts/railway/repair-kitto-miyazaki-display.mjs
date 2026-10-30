#!/usr/bin/env node
// Bounded display candidate. Physical rows and unresolved outer offsets stay intact.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {assertAllowedCandidateDirectory} from './local-evidence-path.mjs';
import {partRowsForLine} from './build-display-lanes.mjs';
import {refreshDependencyReferences,applyPreparedWrites,DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';
const REPO=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..'),APP=path.join(REPO,'app');
const LINE='jp-九州旅客鉄道-吉都線',KEY='kitto-miyazaki-display';
export const EVIDENCE_PATH=path.join(REPO,'railway-evidence/local/repair-inputs/kitto-miyazaki-display-evidence.json');
const net=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(p));
const hash=b=>createHash('sha256').update(b).digest('hex');
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const ROW_KEYS=['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion'];
const evidence=()=>read(EVIDENCE_PATH);

function proposedLine(e){
 assert.equal(e.format,'jtm-kitto-miyazaki-display-evidence-v1');assert.equal(e.lineID,LINE);assert.equal(e.intervalIndex,6);
 assert.equal(e.sources.length,11,'Kitto native/proposal input set changed');
 const expectedPaths=[];
 for(const n of [16,17,18]){
  const directory=path.join(REPO,'railway-evidence/local/diagnostics/sessions/kitto-miyazaki-crossing-z19-detail-20261020/alignment/captures/000000',String(n).padStart(6,'0'));
  expectedPaths.push(...['basemap.png','smooth.png','view.json'].map(f=>path.join(directory,f)));
 }
 expectedPaths.push(e.proposalPath,e.sourceControlsPath);
 assert.deepEqual(e.sources.map(s=>s.path),expectedPaths,'Kitto evidence paths changed');
 for(const source of e.sources){
  assert.equal(hash(fs.readFileSync(source.path)),source.sha256,'Kitto source bytes changed: '+source.path);
  if(source.path.endsWith('/view.json')){
   const v=read(source.path);assert.deepEqual([v.lineID,v.intervalIndex,v.fromStationID,v.toStationID],[LINE,6,'009958','009955']);
   assert([16,17,18].includes(v.pointOrdinal));assert.equal(v.camera.heading,0);assert.equal(v.camera.pitch,0);
   assert(Math.abs(v.snapshotProjection.mapPointsPerPointX-2)<1e-8&&Math.abs(v.snapshotProjection.mapPointsPerPointY-2)<1e-8,'Kitto actual projection changed');
  }
 }
 const p=read(e.proposalPath),source=read(e.sourceControlsPath),old=net.decodeIntervals(e.baselineLine)[6];
 assert.equal(p.lineID,LINE);assert.equal(p.intervalIndex,6);assert.deepEqual(old,e.oldDecodedInterval);assert.deepEqual(old,source.decodedControls);
 assert.deepEqual(e.baselineLine.stations.slice(6,8),source.stationRows);assert.deepEqual(e.baselineLine.stations.slice(6,8).map(r=>r[0]),['009958','009955']);
 assert.equal(e.baselineLine.segments[6][0],4.598);assert.equal(e.baselineLine.segments[6][1],1);assert.equal(old.length,61);
 assert.deepEqual(e.baselineLine.segments[6][2],source.rawControls);assert.deepEqual(e.fragment,p.replacementOwnRailFragment);assert.equal(e.fragment.length,17);
 assert.deepEqual(p.changeDesign.replaceDecodedIndicesInclusive,[30,41]);assert.deepEqual(e.guardCoordinates,p.proposedGuards.map(g=>g.coordinate));
 assert.deepEqual([e.fragment[0],e.fragment.at(-1)],e.guardCoordinates,'Kitto fragment guards changed');
 const world=([lon,lat])=>[(lon+180)/360*268435456,(1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)/2*268435456];
 for(const [i,g]of p.proposedGuards.entries()){
  assert.deepEqual(g.oldDecodedEdge,i===0?[29,30]:[41,42]);assert(g.nearbyLiteralBlueGlyphPixels.length>0,'Kitto guard lacks actual pixel witness');
  const [a,b]=g.oldDecodedEdge.map(n=>world(old[n])),q=world(g.coordinate),t=g.oldEdgeFraction;
  assert(t>0&&t<1&&q.every((v,k)=>Math.abs(v-(a[k]+t*(b[k]-a[k])))<1e-5),'Kitto guard no longer lies on retained old edge');
 }
 const points=[...old.slice(0,30),...structuredClone(e.fragment),...old.slice(42)];
 assert.equal(points.length,66);assert(points.every(p=>p.length===2&&p.every(Number.isFinite)));
 assert.deepEqual(points,p.proposedDisplayIntervalCoordinates);assert.deepEqual([points[0],points.at(-1)],[old[0],old.at(-1)]);
 const line=structuredClone(e.baselineLine);line.displayIntervalCoordinates={...line.displayIntervalCoordinates,6:points};
 const review=e.nativeCandidateReview;
 assert(review&&review.sources.length===6,'Kitto native candidate review missing');
 const reviewRoot=path.join(REPO,'railway-evidence/local/diagnostics/sessions/kitto-miyazaki-candidate-join-z19-20261020/alignment/captures/000000');
 const reviewPaths=[16,18].flatMap(n=>['basemap.png','smooth.png','view.json'].map(f=>path.join(reviewRoot,String(n).padStart(6,'0'),f)));
 assert.deepEqual(review.sources.map(s=>s.path),reviewPaths,'Kitto native review paths changed');
 assert.equal(hash(JSON.stringify(line)),review.reviewedOwnLineSha256,'Kitto native reviewed own line changed');
 assert.equal(review.wholeLineRenderDependency,'0128c3d99c2c171a75e1be8bb96333692f5190614410f54188a5b6e8db6abe67','Kitto native reviewed render dependency changed');
 for(const source of review.sources){
  assert.equal(hash(fs.readFileSync(source.path)),source.sha256,'Kitto native review source bytes changed');
  if(source.path.endsWith('/view.json')){
   const v=read(source.path);
   assert.deepEqual([v.lineID,v.intervalIndex,v.fromStationID,v.toStationID],[LINE,6,'009958','009955']);
   assert([16,18].includes(v.pointOrdinal));assert.equal(v.wholeLineRenderDependency,review.wholeLineRenderDependency,'Kitto native reviewed render dependency changed');
   assert.equal(v.camera.heading,0);assert.equal(v.camera.pitch,0);
   assert(Math.abs(v.snapshotProjection.mapPointsPerPointX-2)<1e-8&&Math.abs(v.snapshotProjection.mapPointsPerPointY-2)<1e-8,'Kitto native reviewed projection changed');
  }
 }
 return line;
}

export function repairPackage(input,e=evidence()){
 const proposed=proposedLine(e),indices=input.lines.flatMap((l,i)=>l.id===LINE?[i]:[]);assert.equal(indices.length,1);
 assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],proposed),'Kitto baseline changed');
 assert.match(input.geometrySource.license,/OpenStreetMap.*ODbL/i);
 const provenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,intervalIndex:6,policy:e.policy,
  evidence:path.relative(REPO,EVIDENCE_PATH),script:'app/scripts/railway/repair-kitto-miyazaki-display.mjs',
  replacedDecodedControlIndices:[30,41],guardsOnOldEdges:[[29,30],[41,42]],physicalTopologyChanged:false,wholeIntervalAccepted:false,stationsAccepted:false};
 const previous=input.geometrySource.manualOverrides?.[KEY];assert(previous===undefined||equal(previous,provenance),'Kitto provenance changed');
 const result=structuredClone(input);result.lines[indices[0]]=proposed;result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;return result;
}

export function ownReferences(input){
 const rows=Object.fromEntries(ROW_KEYS.map(k=>[k,(input[k]?.jp||[]).filter(r=>r[0]===LINE||k==='followsByRegion'&&r[4]===LINE)]));
 rows.loopsByRegion=(input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE));
 rows.reversedLoopParts=(input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#'));
 rows.hubMembers=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));
 return rows;
}

export function repairParts(pkg,input,e=evidence()){
 const line=pkg.lines.find(l=>l.id===LINE);assert.deepEqual(line,proposedLine(e));
 const intervals=net.decodeIntervals(line);for(const [i,p]of Object.entries(line.displayIntervalCoordinates))intervals[Number(i)]=p;
 const rows=partRowsForLine(line,net.displayPartsForLine(line),{stations:line.stations,intervals},null);
 assert.deepEqual(rows,e.candidateNativeRows,'Kitto native ruler changed');assert.equal(rows.length,1);
 const refs=ownReferences(input);for(const [key,actual]of Object.entries(refs))assert(equal(actual,e.baselineRows[key])||key==='partsByRegion'&&equal(actual,rows),'Kitto reference changed: '+key);
 assert.deepEqual(e.baselineRows.byRegion,[],'Kitto baseline lane absence changed');
 for(const [key,value]of Object.entries(e.ownMaps))assert.deepEqual(input[key]?.jp?.[LINE]??null,value,'Kitto reference changed: '+key);
 assert(!(input.excludedOperators||[]).includes(line.operator)&&!(input.excludedLineIds||[]).includes(LINE),'Kitto exclusion changed');
 const result=structuredClone(input);result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows[0]:r);return result;
}

export function validateExternalReferences(actual,e=evidence()){
 assert.deepEqual(actual,e.baselineExternalReferences,'Kitto external reference changed');
}
function externalReferences(shared,releases,junctions){
 return {corridors:shared.corridors.filter(r=>(r.lineIds||[]).includes(LINE)||(r.members||[]).some(m=>m.lineId===LINE)),
  displayLandlords:shared.displayLandlords.filter(r=>r.tenantLineId===LINE||r.landlordLineId===LINE||(r.tenantLineIds||[]).includes(LINE)||(r.landlordLineIds||[]).includes(LINE)),
  excludedLineIds:(shared.displayLanePolicy.excludedLineIds||[]).filter(id=>id===LINE),releases:releases.releases.filter(r=>r.lineId===LINE),junctions:junctions.junctions.filter(r=>r.lineIDs?.includes(LINE))};
}
function main(args){
 const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;
 assert(candidate||equal(args,['--apply']),'Use --candidate-root <repo>/railway-evidence/local/candidates/<dir> or --apply');
 if(candidate){assertAllowedCandidateDirectory(candidate);const root=path.join(REPO,'railway-evidence/local/candidates');assert(candidate.startsWith(root+path.sep),'Kitto candidate must use canonical repository evidence tree');}
 const e=evidence(),paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
 const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(APP,p),before:fs.readFileSync(path.join(APP,p))}]));
 const inputs=[EVIDENCE_PATH,...e.sources.map(s=>s.path),...e.nativeCandidateReview.sources.map(s=>s.path),...e.externalPaths.map(p=>path.join(APP,p))].map(p=>({path:p,before:fs.readFileSync(p)}));
 const frozen=p=>JSON.parse(inputs.find(i=>i.path===path.join(APP,p)).before);
 validateExternalReferences(externalReferences(frozen(e.externalPaths[0]),frozen(e.externalPaths[1]),frozen(e.externalPaths[2])),e);
 const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e);
 const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
 const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
 let writes;
 if(candidate){
  fs.mkdirSync(candidate,{recursive:true});assertAllowedCandidateDirectory(candidate);
  writes=Object.entries(outputs).map(([k,after])=>{const destination=path.join(candidate,path.basename(snapshots[k].path));assert(!fs.existsSync(destination)||!fs.lstatSync(destination).isSymbolicLink(),'Candidate output cannot be symlink');if(!fs.existsSync(destination))fs.writeFileSync(destination,'');return {path:destination,before:fs.readFileSync(destination),after:Buffer.from(after)};});
 }else writes=Object.entries(outputs).map(([k,after])=>({...snapshots[k],after:Buffer.from(after)}));
 applyPreparedWrites(writes,[...Object.values(snapshots),...inputs,...(candidate?writes.map(({path,before})=>({path,before})):[])]);
 console.log(JSON.stringify({mode:candidate?'candidate':'applied',candidateRoot:candidate,lineID:LINE,intervalIndex:6,nativeRows:lanes.partsByRegion.jp.filter(r=>r[0]===LINE),physicalTopologyChanged:false,status:e.status}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
