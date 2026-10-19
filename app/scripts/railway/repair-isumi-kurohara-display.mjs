#!/usr/bin/env node
// One own passenger-reference curve; Isumi's bus substitution stays canonical.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {projectPointOntoPolyline} from './jp-manual-corrections/geo.mjs';
import {partRowsForLine} from './build-display-lanes.mjs';
import {refreshDependencyReferences,applyPreparedWrites,DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';
const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),REPO=path.dirname(ROOT);
const LINE='jp-いすみ鉄道-いすみ線',KEY='isumi-kurohara-display',EVIDENCE='scripts/railway/isumi-kurohara-display-evidence.json';
const network=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(p)),equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const readEvidence=()=>read(path.join(ROOT,EVIDENCE));

function ownChain(e){
  assert.equal(e.sourceFiles.length,4);assert.equal(e.sourceWays.length,3);
  const sources=e.sourceFiles.map(s=>{
    const bytes=fs.readFileSync(path.resolve(REPO,s.path));
    assert.equal(createHash('sha256').update(bytes).digest('hex'),s.sha256,'Isumi source bytes changed');
    return JSON.parse(bytes);
  });
  const ids=[1236719220,287004073,287004072],versions=[2,3,4],chain=[];let previous;
  for(let i=0;i<ids.length;i++){
    const full=sources[i].elements,way=full.find(r=>r.type==='way'&&r.id===ids[i]),frozen=e.sourceWays[i];
    assert(way,'Isumi own way missing');assert.equal(way.version,versions[i]);
    assert.deepEqual([way.id,way.version,way.timestamp,way.tags],[frozen.id,frozen.version,frozen.timestamp,frozen.tags],'Isumi own way changed');
    assert.deepEqual(way.nodes,frozen.nodes,'Isumi source node order changed');
    for(const[k,v]of Object.entries({railway:'rail',operator:'いすみ鉄道',name:'いすみ鉄道 いすみ線',gauge:'1067',usage:'branch',source:'Bing'}))assert.equal(way.tags[k],v);
    assert.equal(way.tags.service,undefined,'Isumi passenger source became service track');
    if(i)assert.equal(way.nodes[0],previous,'Isumi own node chain disconnected');
    const nodes=new Map(full.filter(r=>r.type==='node').map(r=>[r.id,r]));
    const records=way.nodes.map(id=>{const n=nodes.get(id);assert(Number.isInteger(n?.version),'Isumi source node missing');return n;});
    assert.deepEqual(records,frozen.nodeRecords,'Isumi source node records changed');
    const coords=records.map(n=>[n.lon,n.lat]);assert.deepEqual(coords,frozen.coordinates,'Isumi source coordinates changed');
    chain.push(...coords.slice(i?1:0));previous=way.nodes.at(-1);
  }
  assert.equal(e.passengerRoutes.length,2);
  for(const[id,version,index,reverse]of[[5748913,8,49,false],[16928972,3,22,true]]){
    const route=sources[3].elements.find(r=>r.type==='relation'&&r.id===id),frozen=e.passengerRoutes.find(r=>r.id===id);
    assert(route&&frozen,'Isumi own passenger route missing');assert.equal(route.version,version);
    assert.deepEqual([route.version,route.timestamp,route.tags],[frozen.version,frozen.timestamp,frozen.tags],'Isumi passenger route changed');
    assert.equal(route.tags.type,'route');assert.equal(route.tags.route,'train');assert.equal(route.tags.operator,'いすみ鉄道');
    assert.equal(route.tags.from,reverse?'上総中野':'大原');assert.equal(route.tags.to,reverse?'大原':'上総中野');
    assert.equal(frozen.firstMemberIndex,index,'Isumi passenger route ordinal changed');
    const members=route.members.slice(index,index+3);assert.deepEqual(members,frozen.members,'Isumi passenger membership changed');
    assert.deepEqual(members,(reverse?[...ids].reverse():ids).map(ref=>({type:'way',ref,role:''})),'Isumi passenger way chain changed');
  }
  assert.deepEqual(chain,e.fragment.sourceChainCoordinates,'Isumi frozen own chain changed');return chain;
}

function proposedLine(e){
  assert.equal(e.format,'jtm-isumi-kurohara-display-v1');assert.equal(e.lineID,LINE);assert.equal(e.intervalIndex,10);
  const line=structuredClone(e.baselineLine),f=e.fragment,w=f.window;
  assert.equal(line.id,LINE);assert.equal(line.displayIntervalCoordinates,undefined);
  assert.equal(line.serviceStatus,'substitute_bus');assert.deepEqual(line.serviceSpans,[[0,13,2]]);
  assert.deepEqual(line.stations.slice(10,12).map(r=>r[0]),['005236','005257']);
  assert.deepEqual(line.stations.slice(10,12),[f.fromStation,f.toStation]);
  assert.deepEqual(line.segments[10],f.physicalBaselineSegment);
  const old=network.decodeIntervals(line)[10];assert.deepEqual(old,f.oldDecodedCoordinates);
  assert.deepEqual(e.rawSourceFeature.properties,{N02_001:'12',N02_002:'5',N02_003:'いすみ線',N02_004:'いすみ鉄道'},'Isumi raw N02 identity changed');
  assert.equal(e.rawSourceFeature.geometry.type,'LineString');
  assert.deepEqual(e.rawSourceFeature.geometry.coordinates.toReversed(),old.slice(1,-1),'Isumi raw N02 controls changed');
  assert.equal(f.sourceFeatureIndex,66);assert.deepEqual(f.referenceWayChain,[1236719220,287004073,287004072]);
  assert.deepEqual([w.start,w.end],[13,34]);
  assert.deepEqual(w.outerGuards,{before:{index:12,coordinate:old[12]},after:{index:35,coordinate:old[35]}},'Isumi outside guards changed');
  assert.deepEqual(w.oldWindow,old.slice(13,35));
  const chain=ownChain(e),projections=[w.startProjection,w.endProjection].map((b,i)=>{
    assert.equal(b.index,[13,34][i]);assert.deepEqual(b.raw,old[b.index]);
    const p=projectPointOntoPolyline(old[b.index],chain);
    assert.deepEqual(p.point,b.point,'Isumi projection changed');assert.equal(p.insertIndex,b.insertIndex,'Isumi projection segment changed');
    assert(Math.abs(p.distanceM-b.distanceM)<1e-9,'Isumi projection distance changed');return p;
  });
  const fragment=[projections[0].point,...chain.slice(projections[0].insertIndex+1,projections[1].insertIndex+1),projections[1].point];
  assert.deepEqual(fragment,w.fragment,'Isumi fragment changed');
  const candidate=[...old.slice(0,13),...fragment,...old.slice(35)];assert.deepEqual(candidate,f.candidateDecodedCoordinates);
  line.displayIntervalCoordinates={10:candidate};return line;
}

export function repairPackage(input,e=readEvidence()){
  const proposed=proposedLine(e),indices=input.lines.flatMap((r,i)=>r.id===LINE?[i]:[]);assert.equal(indices.length,1);
  assert([e.baselineLine,proposed].some(line=>equal(input.lines[indices[0]],line)),'Isumi baseline changed');
  assert.match(input.geometrySource?.license||'',/OpenStreetMap.*ODbL/i);
  const provenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,intervalIndex:10,wayVersions:e.sourceWays.map(w=>[w.id,w.version]),passengerRoutes:e.passengerRoutes.map(r=>[r.id,r.version]),guards:[12,35],displayWindow:[13,34],policy:e.policy,research:e.research,evidence:'app/'+EVIDENCE,script:'app/scripts/railway/repair-isumi-kurohara-display.mjs',physicalTopologyChanged:false,serviceStatusPreserved:'substitute_bus'};
  const previous=input.geometrySource.manualOverrides?.[KEY];assert(previous===undefined||equal(previous,provenance),'Isumi provenance changed');
  const result=structuredClone(input);result.lines[indices[0]]=proposed;
  result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;return result;
}

function interfaceRows(line){
  const displayed={...line,segments:line.segments.map((s,i)=>line.displayIntervalCoordinates?.[i]?[s[0],0,line.displayIntervalCoordinates[i]]:s)};
  return partRowsForLine(line,network.displayPartsForLine(line),{stations:line.stations,intervals:network.decodeIntervals(displayed)},null);
}
export function repairParts(pkg,input,e=readEvidence()){
  const line=pkg.lines.find(r=>r.id===LINE);assert.deepEqual(line,proposedLine(e));
  assert.deepEqual(interfaceRows(e.baselineLine),e.baselineInterfaceRows,'Isumi baseline interface ruler changed');
  assert.deepEqual(interfaceRows(line),e.candidateInterfaceRows,'Isumi candidate interface ruler changed');
  // No chain is emitted for this service-split line by the native parts builder.
  // Do not turn the interface ruler into a new rendered native part.
  for(const key of['partsByRegion','byRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion'])
    assert.deepEqual((input[key]?.jp||[]).filter(r=>r[0]===LINE),e.baselineReferences[key],'Isumi reference changed: '+key);
  assert.deepEqual((input.followsByRegion?.jp||[]).filter(r=>r[0]===LINE||r[4]===LINE),e.baselineReferences.followsByRegion,'Isumi reference changed: followsByRegion');
  assert.deepEqual((input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE)),e.baselineReferences.loopsByRegion,'Isumi reference changed: loopsByRegion');
  assert.deepEqual((input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#')),e.baselineReferences.reversedLoopParts,'Isumi reference changed: reversedLoopParts');
  const hubs=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));
  assert.deepEqual(hubs,e.baselineReferences.hubMembers,'Isumi hub reference changed');return structuredClone(input);
}

export function assertExternalReferences(input,e=readEvidence()){
  const shared=input.sharedCorridors;
  assert.deepEqual((shared.corridors||[]).filter(r=>(r.lineIds||[]).includes(LINE)||(r.members||[]).some(m=>m.lineId===LINE)),e.externalReferences.sharedCorridors,'Isumi shared corridor reference changed');
  assert.deepEqual((shared.displayLandlords||[]).filter(r=>r.tenantLineId===LINE||r.landlordLineId===LINE||(r.tenantLineIds||[]).includes(LINE)||(r.landlordLineIds||[]).includes(LINE)),e.externalReferences.displayLandlords,'Isumi landlord reference changed');
  assert.deepEqual((input.releases.releases||[]).filter(r=>r.lineId===LINE),e.externalReferences.releases,'Isumi release reference changed');
  assert.deepEqual((input.junctions.junctions||[]).filter(r=>(r.lineIDs||[]).includes(LINE)),e.externalReferences.physicalJunctions,'Isumi physical junction reference changed');
}
function main(args){
  const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;
  assert(candidate||equal(args,['--apply']),'Use --candidate-root /private/tmp/<dir> or --apply');
  if(candidate)assert(candidate.startsWith('/private/tmp/'));
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(ROOT,p),before:fs.readFileSync(path.join(ROOT,p),'utf8')}]));
  const evidencePath=path.join(ROOT,EVIDENCE),evidenceBytes=fs.readFileSync(evidencePath,'utf8'),e=JSON.parse(evidenceBytes);
  const sources=e.sourceFiles.map(s=>({path:path.resolve(REPO,s.path),before:fs.readFileSync(path.resolve(REPO,s.path),'utf8')}));
  const rawPath=path.join(ROOT,'data/rail-sections.json'),rawBytes=fs.readFileSync(rawPath,'utf8');
  assert.deepEqual(JSON.parse(rawBytes).features[66],e.rawSourceFeature,'Isumi raw source changed');
  const externalPaths={sharedCorridors:'public/rail/shared-corridors.json',releases:'public/rail/display-releases.json',junctions:'data/physical-rail-junctions.json'};
  const external=Object.fromEntries(Object.entries(externalPaths).map(([k,p])=>[k,{path:path.join(ROOT,p),before:fs.readFileSync(path.join(ROOT,p),'utf8')}]));
  assertExternalReferences(Object.fromEntries(Object.entries(external).map(([k,s])=>[k,JSON.parse(s.before)])),e);
  const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e);
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
  const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
  if(candidate){fs.mkdirSync(candidate,{recursive:true});for(const[k,v]of Object.entries(outputs))fs.writeFileSync(path.join(candidate,path.basename(snapshots[k].path)),v);}
  else applyPreparedWrites(Object.entries(outputs).filter(([k,v])=>v!==snapshots[k].before).map(([k,after])=>({...snapshots[k],after})),[...Object.values(snapshots),{path:evidencePath,before:evidenceBytes},{path:rawPath,before:rawBytes},...sources,...Object.values(external)]);
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',lineID:LINE,intervalIndex:10,decodedControls:49,interfacePoints:e.candidateInterfaceRows[0][4],interfaceMetres:e.candidateInterfaceRows[0][5],continuousStrokeParts:0,strokeExclusionPreserved:'substitute_bus',physicalTopologyChanged:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
