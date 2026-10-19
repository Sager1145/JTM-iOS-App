#!/usr/bin/env node
// One own-passenger display curve; physical geometry and mileage stay canonical.
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
const LINE='jp-WILLER\u3000TRAINS-宮津線',KEY='miyazu-yosano-display';
const EVIDENCE='scripts/railway/miyazu-yosano-display-evidence.json';
const network=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(p));
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const readEvidence=()=>read(path.join(ROOT,EVIDENCE));

function ownReference(e){
  const bytes=fs.readFileSync(path.resolve(REPO,e.source.path));
  assert.equal(createHash('sha256').update(bytes).digest('hex'),e.source.sha256,'Miyazu source bytes changed');
  const source=JSON.parse(bytes),full=source['way/32052922/full.json'].elements;
  const way=full.find(r=>r.type==='way'&&r.id===32052922);
  assert.equal(way.version,10);assert.equal(way.timestamp,'2023-02-28T14:26:49Z');
  assert.deepEqual([e.fragment.sourceWay.id,e.fragment.sourceWay.version,e.fragment.sourceWay.timestamp],[way.id,way.version,way.timestamp],'Miyazu own way guard changed');
  for(const [key,value]of Object.entries(e.fragment.sourceWay.tagsRequired))assert.equal(way.tags[key],value);
  assert.equal(way.tags.service,undefined,'Passenger reference became service track');
  const relations=source['way/32052922/relations.json'].elements;
  for(const [id,version,from,index]of [[6015174,45,'宮津',47],[19072502,3,'西舞鶴',117]]){
    const route=relations.find(r=>r.type==='relation'&&r.id===id);
    const frozen=id===6015174?e.fragment.sourceRoute:e.fragment.completePassengerRoute;
    assert.deepEqual([frozen.id,frozen.version,frozen.timestamp,frozen.tags],[route.id,route.version,route.timestamp,route.tags],'Miyazu passenger route evidence changed');
    assert.equal(frozen.ownWayMemberOrdinalZeroBased,index,'Miyazu passenger route ordinal changed');
    assert.equal(route.version,version);assert.equal(route.tags.type,'route');assert.equal(route.tags.route,'train');
    assert.equal(route.tags.from,from);assert.equal(route.tags.to,'豊岡');assert.equal(route.tags.operator,'京都丹後鉄道');
    assert.deepEqual(route.members.slice(index-1,index+2).map(r=>[r.type,r.ref,r.role]),
      [['way',32052917,''],['way',32052922,''],['way',1044465731,'']],'Own passenger route changed');
  }
  const nodes=new Map(full.filter(r=>r.type==='node').map(r=>[r.id,r]));
  const coordinates=way.nodes.map(id=>{const n=nodes.get(id);assert(Number.isInteger(n.version));return[n.lon,n.lat];});
  assert.deepEqual(coordinates,e.fragment.sourceWay.geometry,'Own source coordinates changed');
  return coordinates;
}

function proposedYosanoLine(e){
  assert.equal(e.format,'jtm-miyazu-yosano-display-v1');assert.equal(e.lineID,LINE);assert.equal(e.intervalIndex,9);
  const line=structuredClone(e.baselineLine),f=e.fragment,w=f.window;
  assert.equal(line.id,LINE);assert.equal(line.displayIntervalCoordinates,undefined);
  assert.deepEqual(line.stations.slice(9,11),f.stations);
  assert.deepEqual(f.stations.map(r=>r[0]),['004390','004291']);
  assert.deepEqual(line.segments[9],f.canonicalCompactRow);
  const old=network.decodeIntervals(line)[9];assert.deepEqual(old,f.oldDecodedInterval);
  assert.deepEqual([w.decodedStartIndex,w.decodedEndIndexInclusive],[3,9]);
  assert.deepEqual([old[2],old[10]],[w.before,w.after],'Miyazu outside guards changed');
  const chain=ownReference(e),projections=w.projectedBoundaries.map((b,i)=>{
    assert.equal(b.index,[3,9][i]);const p=projectPointOntoPolyline(old[b.index],chain);
    assert.deepEqual(p.point,b.point,'Miyazu projection changed');assert.equal(p.insertIndex,b.insertIndex,'Miyazu projection segment changed');
    assert(Math.abs(p.distanceM-b.distanceM)<1e-9,'Miyazu projection distance changed');return p;
  });
  const coordinates=[projections[0].point,...chain.slice(projections[0].insertIndex+1,projections[1].insertIndex+1),projections[1].point];
  assert.deepEqual(coordinates,w.replacementCoordinates);
  const interval=[...old.slice(0,3),...coordinates,...old.slice(10)];assert.deepEqual(interval,f.candidateDecodedInterval);
  line.displayIntervalCoordinates={9:interval};return line;
}

// The second local curve stays in this same Miyazu authority. Its connected
// passenger ways are frozen individually; there is no nearest-track resolver.
function proposedLine(e){
  const line=proposedYosanoLine(e),f=e.fragment15,w=f.window;
  assert.equal(f.lineID,LINE);assert.equal(f.intervalIndex,15);
  assert.deepEqual(line.stations.slice(15,17),f.stations);
  assert.deepEqual(f.stations.map(r=>r[0]),['004208','004231']);
  assert.deepEqual(line.segments[15],f.canonicalCompactRow);
  const old=network.decodeIntervals(line)[15];assert.deepEqual(old,f.oldDecodedInterval);
  assert.deepEqual([w.decodedStartIndex,w.decodedEndIndexInclusive],[3,28]);
  assert.deepEqual([old[2],old[29]],[w.before,w.after],'Miyazu15 outside guards changed');
  const ids=[32052885,1044465764,32052892,1044465765,491716768],versions=[9,2,11,1,6];
  assert.equal(f.sourceFiles.length,5);assert.equal(f.sourceWays.length,5);
  const chain=[];let lastNode=null;
  for(let i=0;i<ids.length;i++){
    const bytes=fs.readFileSync(path.resolve(REPO,f.sourceFiles[i].path));
    assert.equal(createHash('sha256').update(bytes).digest('hex'),f.sourceFiles[i].sha256,'Miyazu15 source bytes changed');
    const full=JSON.parse(bytes).elements,way=full.find(r=>r.type==='way'&&r.id===ids[i]),frozen=f.sourceWays[i];
    assert(way,'Miyazu15 own way missing');
    assert.deepEqual([way.id,way.version,way.timestamp],[frozen.id,frozen.version,frozen.timestamp],'Miyazu15 source version changed');
    assert.equal(way.version,versions[i]);assert.deepEqual(way.nodes,frozen.nodes,'Miyazu15 source node proof changed');
    assert.deepEqual(way.tags,frozen.tags,'Miyazu15 source tags changed');
    for(const[k,v]of Object.entries({railway:'rail',usage:'main',operator:'京都丹後鉄道','KSJ2:LIN':'宮津線',gauge:'1067'}))assert.equal(way.tags[k],v);
    assert.equal(way.tags.service,undefined,'Miyazu15 passenger source became service track');
    if(i)assert.equal(way.nodes[0],lastNode,'Miyazu15 passenger node chain disconnected');
    lastNode=way.nodes.at(-1);
    const nodes=new Map(full.filter(r=>r.type==='node').map(r=>[r.id,r]));
    const coordinates=way.nodes.map(id=>{const n=nodes.get(id);assert(Number.isInteger(n.version));return[n.lon,n.lat];});
    assert.deepEqual(coordinates,frozen.coordinates,'Miyazu15 source coordinates changed');
    if(i)assert.deepEqual(chain.at(-1),coordinates[0],'Miyazu15 passenger coordinates disconnected');
    chain.push(...coordinates.slice(i?1:0));
  }
  const relations=read(path.resolve(REPO,e.source.path))['way/32052922/relations.json'].elements;
  assert.equal(f.passengerRoutes.length,4);
  for(const[id,version,index,reverse]of[[6015174,45,134,false],[19072502,3,204,false],[12030454,13,76,true],[19072511,3,81,true]]){
    const route=relations.find(r=>r.type==='relation'&&r.id===id),frozen=f.passengerRoutes.find(r=>r.id===id);
    assert.equal(route.version,version);assert.equal(route.tags.type,'route');assert.equal(route.tags.route,'train');
    assert.deepEqual([frozen.version,frozen.timestamp,frozen.tags,frozen.firstMemberOrdinalZeroBased],[route.version,route.timestamp,route.tags,index],'Miyazu15 passenger route changed');
    const members=route.members.slice(index,index+5);
    assert.deepEqual(members,frozen.members,'Miyazu15 passenger membership changed');
    assert.deepEqual(members.map(r=>[r.type,r.ref,r.role]),(reverse?[...ids].reverse():ids).map(id=>['way',id,'']),'Miyazu15 passenger chain changed');
  }
  const projections=w.projectedBoundaries.map((b,i)=>{
    assert.equal(b.index,[3,28][i]);const p=projectPointOntoPolyline(old[b.index],chain);
    assert.deepEqual(p.point,b.point,'Miyazu15 projection changed');assert.equal(p.insertIndex,b.insertIndex,'Miyazu15 projection segment changed');
    assert(Math.abs(p.distanceM-b.distanceM)<1e-9,'Miyazu15 projection distance changed');return p;
  });
  const coordinates=[projections[0].point,...chain.slice(projections[0].insertIndex+1,projections[1].insertIndex+1),projections[1].point];
  assert.deepEqual(coordinates,w.replacementCoordinates);
  const interval=[...old.slice(0,3),...coordinates,...old.slice(29)];assert.deepEqual(interval,f.candidateDecodedInterval);
  line.displayIntervalCoordinates[15]=interval;return line;
}

export function repairPackage(input,e=readEvidence()){
  const proposed=proposedLine(e),indices=input.lines.flatMap((r,i)=>r.id===LINE?[i]:[]);assert.equal(indices.length,1);
  const acceptedYosano={...proposed,displayIntervalCoordinates:{9:proposed.displayIntervalCoordinates[9]}};
  assert([e.baselineLine,acceptedYosano,proposed].some(line=>equal(input.lines[indices[0]],line)),'Miyazu baseline changed');
  assert.match(input.geometrySource?.license||'',/OpenStreetMap.*ODbL/i);
  const acceptedYosanoProvenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,intervalIndex:9,
    way:[32052922,10],passengerRoutes:[[6015174,45],[19072502,3]],guards:[2,10],displayWindow:[3,9],
    policy:e.policy,research:e.research,evidence:'app/'+EVIDENCE,
    script:'app/scripts/railway/repair-miyazu-yosano-display.mjs',physicalTopologyChanged:false};
  const provenance={...acceptedYosanoProvenance,interval15:{status:e.fragment15.status,wayVersions:e.fragment15.sourceWays.map(w=>[w.id,w.version]),passengerRoutes:e.fragment15.passengerRoutes.map(r=>[r.id,r.version]),guards:[2,29],displayWindow:[3,28],research:e.fragment15.research,limits:e.fragment15.limits}};
  const previous=input.geometrySource.manualOverrides?.[KEY];
  assert(previous===undefined||equal(previous,acceptedYosanoProvenance)||equal(previous,provenance),'Miyazu provenance changed');
  const result=structuredClone(input);result.lines[indices[0]]=proposed;
  result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;return result;
}

export function repairParts(pkg,input,e=readEvidence()){
  const line=pkg.lines.find(r=>r.id===LINE);assert.deepEqual(line,proposedLine(e));
  // The native plain-range decoder applies the same display interval override.
  const displayed={...line,segments:line.segments.map((s,i)=>line.displayIntervalCoordinates[i]?[s[0],0,line.displayIntervalCoordinates[i]]:s)};
  const rows=partRowsForLine(line,network.displayPartsForLine(line),{stations:line.stations,intervals:network.decodeIntervals(displayed)},null);
  assert.deepEqual(rows,[e.candidate15NativeRow],'Miyazu native ruler changed');
  const current=(input.partsByRegion?.jp||[]).filter(r=>r[0]===LINE);
  assert([e.baselineNativeRow,e.candidateNativeRow,e.candidate15NativeRow].some(row=>equal(current,[row])),'Miyazu native baseline changed');
  for(const key of ['byRegion','followsByRegion','familyWindowsByRegion']){
    const own=(input[key]?.jp||[]).filter(r=>r[0]===LINE||key==='followsByRegion'&&r[4]===LINE);
    assert.deepEqual(own,e.baselineReferences[key],'Miyazu reference changed: '+key);
  }
  assert.deepEqual((input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE)),
    e.baselineReferences.loopsByRegion,'Miyazu reference changed: loopsByRegion');
  assert.deepEqual((input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#')),
    e.baselineReferences.reversedLoopParts,'Miyazu reference changed: reversedLoopParts');
  for(const key of ['strokeExcludedByRegion','chainBoundariesByRegion'])
    assert.deepEqual((input[key]?.jp||[]).filter(r=>r[0]===LINE),e.baselineReferences[key],'Miyazu reference changed: '+key);
  const hubs=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));
  assert.deepEqual(hubs,e.baselineReferences.hubMembers,'Miyazu hub reference changed');
  const result=structuredClone(input);result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows[0]:r);return result;
}

function main(args){
  const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;
  assert(candidate||equal(args,['--apply']),'Use --candidate-root /private/tmp/<dir> or --apply');
  if(candidate)assert(candidate.startsWith('/private/tmp/'));
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(ROOT,p),before:fs.readFileSync(path.join(ROOT,p),'utf8')}]));
  const evidencePath=path.join(ROOT,EVIDENCE),evidenceBytes=fs.readFileSync(evidencePath,'utf8'),e=JSON.parse(evidenceBytes);
  const sourcePath=path.resolve(REPO,e.source.path),sourceBytes=fs.readFileSync(sourcePath,'utf8');
  const own15Sources=e.fragment15.sourceFiles.map(s=>({path:path.resolve(REPO,s.path),before:fs.readFileSync(path.resolve(REPO,s.path),'utf8')}));
  const rawSourcePath=path.join(ROOT,'data/rail-sections.json'),rawSourceBytes=fs.readFileSync(rawSourcePath,'utf8');
  const rawFeatures=JSON.parse(rawSourceBytes).features;
  for(const f of[e.fragment,e.fragment15])assert.deepEqual(rawFeatures[f.sourceN02FeatureIndexZeroBased],f.sourceN02Feature,'Miyazu raw source changed');
  const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e);
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
  const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
  if(candidate){fs.mkdirSync(candidate,{recursive:true});for(const[k,v]of Object.entries(outputs))fs.writeFileSync(path.join(candidate,path.basename(snapshots[k].path)),v);}
  else applyPreparedWrites(Object.entries(outputs).filter(([k,v])=>v!==snapshots[k].before).map(([k,after])=>({...snapshots[k],after})),
    [...Object.values(snapshots),{path:evidencePath,before:evidenceBytes},{path:sourcePath,before:sourceBytes},{path:rawSourcePath,before:rawSourceBytes},...own15Sources]);
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',lineID:LINE,intervalIndices:[9,15],nativePoints:e.candidate15NativeRow[4],nativeMetres:e.candidate15NativeRow[5],physicalTopologyChanged:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
