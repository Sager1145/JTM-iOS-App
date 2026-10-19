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
const LINE='jp-一畑電車-北松江線',KEY='ichibata-kitamatsue-display',EVIDENCE='scripts/railway/ichibata-kitamatsue-display-evidence.json';
const network=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(p));
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function proposedLine(e){
  assert.equal(e.format,'jtm-ichibata-kitamatsue-display-v1');assert.equal(e.lineID,LINE);assert.equal(e.baselineLine.id,LINE);
  for(const s of e.appleSources)assert.equal(createHash('sha256').update(fs.readFileSync(path.resolve(REPO,e.sourceRoot,s.file))).digest('hex'),s.sha256,'Kitamatsue Apple source bytes changed');
  for(const source of e.ownSources)assert.equal(createHash('sha256').update(fs.readFileSync(path.resolve(REPO,e.sourceRoot,source.file))).digest('hex'),source.sha256,'Kitamatsue own source bytes changed');
  for(const i of [3,4]){
    const view=read(path.resolve(REPO,e.sourceRoot,`detail-p${i}-view.json`));
    assert.deepEqual([view.lineID,view.intervalIndex,view.pointOrdinal,view.fromStationID,view.toStationID],[LINE,6,i,'004610','004630']);
  }
  const own=read(path.resolve(REPO,e.sourceRoot,'osm-way-30414280-full.json')).elements.find(x=>x.type==='way');
  assert.deepEqual([own.id,own.version,own.tags.operator,own.tags.passenger_lines],[30414280,8,'一畑電車','1']);
  const relations=read(path.resolve(REPO,e.sourceRoot,'osm-way-30414280-relations.json')).elements;
  for(const[id,version,route]of[[1950436,22,'railway'],[11989798,9,'train'],[11996016,3,'train']]){
    const r=relations.find(x=>x.id===id);assert.deepEqual([r.version,r.tags.route],[version,route]);assert(r.members.some(m=>m.type==='way'&&m.ref===own.id));
  }
  const line=structuredClone(e.baselineLine),old=network.decodeIntervals(line)[6];assert.deepEqual(old,e.oldDecodedInterval);
  assert.deepEqual(e.removedIndices,[15,17,19]);assert.deepEqual([15,17,19].map(i=>old[i]),[[132.92675,35.47012],[132.92665,35.47007],[132.92657,35.47004]]);
  assert.deepEqual(e.retainedWindow.indices,[12,13,14,16,18,20,21,22]);assert.deepEqual(e.retainedWindow.coordinates,[12,13,14,16,18,20,21,22].map(i=>old[i]));
  assert.equal(e.rawFeature.index,700);assert.equal(e.rawFeature.feature.properties.N02_003,'北松江線');assert.equal(e.rawFeature.feature.properties.N02_004,'一畑電車');
  assert.deepEqual(e.rawFeature.feature.geometry.coordinates.slice().reverse(),old.slice(1,60));
  line.displayIntervalCoordinates={...line.displayIntervalCoordinates,6:old.filter((_,i)=>![15,17,19].includes(i))};return line;
}
export function repairPackage(input,e=read(path.join(ROOT,EVIDENCE))){
  const proposed=proposedLine(e),indices=input.lines.flatMap((l,i)=>l.id===LINE?[i]:[]);assert.equal(indices.length,1);
  assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],proposed),'Kitamatsue baseline changed');
  assert.match(input.geometrySource.license,/OpenStreetMap.*ODbL/i);
  const provenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,intervalIndex:6,removedDisplayVertices:[15,17,19],retainedGuards:[12,13,14,16,18,20,21,22],reference:'Apple labelled own Kitamatsue z19 points3/4; own passenger chain; no corridor shift',policy:e.policy,evidence:'app/'+EVIDENCE,script:'app/scripts/railway/repair-ichibata-kitamatsue-display.mjs',physicalTopologyChanged:false};
  const previous=input.geometrySource.manualOverrides?.[KEY];assert(previous===undefined||equal(previous,provenance),'Kitamatsue provenance changed');
  const result=structuredClone(input);result.lines[indices[0]]=proposed;result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;return result;
}
export function repairParts(pkg,input,e=read(path.join(ROOT,EVIDENCE))){
  const line=pkg.lines.find(l=>l.id===LINE);assert.deepEqual(line,proposedLine(e));
  // Native plain-range rows decode this same display interval, not the canonical step.
  const intervals=network.decodeIntervals(line);intervals[6]=line.displayIntervalCoordinates[6];
  const rows=partRowsForLine(line,network.displayPartsForLine(line),{stations:line.stations,intervals},null);
  assert.deepEqual(rows,e.candidateNativeRows,'Kitamatsue native ruler changed');assert.equal(rows.length,2);
  assert.deepEqual(rows[1],e.baselineRows.partsByRegion[1],'Kitamatsue west arm changed');
  // The sole known follow is on the exact retained suffix of part0; part1 is unchanged.
  // Use the native equirectangular metre formula for only the three removed legs.
  const distance=(a,b)=>Math.hypot((b[0]-a[0])*111320*Math.cos((a[1]+b[1])*Math.PI/360),(b[1]-a[1])*111320);
  const old=e.oldDecodedInterval;let delta=0;
  for(const i of [15,17,19])delta+=distance(old[i-1],old[i+1])-distance(old[i-1],old[i])-distance(old[i],old[i+1]);
  assert.equal(delta,e.nativeLengthDelta);
  const before=e.baselineRows.partsByRegion[0][7],after=rows[0][7];
  assert.deepEqual(after,before.filter(c=>![15,17,19].some(i=>equal(c,old[i]))),'Kitamatsue native changed beyond the three steps');
  const guard=before.findIndex(c=>equal(c,old[20]));assert(guard>0);
  let guardMeasure=0;for(let i=1;i<=guard;i++)guardMeasure+=distance(before[i-1],before[i]);
  assert.deepEqual(e.baselineRows.followsByRegion,[[LINE,0,16150,16321.235570460749,LINE,1,150,0]]);
  assert(16150>guardMeasure,'Kitamatsue follow enters the changed window');
  const follows=[[LINE,0,16150+delta,16321.235570460749+delta,LINE,1,150,0]];
  assert.deepEqual(follows,e.candidateFollowRows);
  for(const key of ['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion']){
    const own=(input[key]?.jp||[]).filter(r=>r[0]===LINE||key==='followsByRegion'&&r[4]===LINE),expected=key==='partsByRegion'?rows:key==='followsByRegion'?follows:e.baselineRows[key];
    assert(equal(own,e.baselineRows[key])||equal(own,expected),'Kitamatsue reference changed: '+key);
  }
  assert.deepEqual((input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE)),e.baselineRows.loopsByRegion,'Kitamatsue reference changed: loopsByRegion');
  assert.deepEqual((input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#')),e.baselineRows.reversedLoopParts,'Kitamatsue reference changed: reversedLoopParts');
  const hubs=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));
  assert.deepEqual(hubs,e.baselineRows.hubMembers,'Kitamatsue hub reference changed');
  for(const[key,frozen]of Object.entries(e.ownMaps))assert.deepEqual(input[key]?.jp?.[LINE]??null,frozen,'Kitamatsue map reference changed');
  assert(!(input.excludedOperators||[]).includes(e.baselineLine.operator),'Kitamatsue excluded operator changed');assert(!(input.excludedLineIds||[]).includes(LINE),'Kitamatsue excluded line changed');
  const result=structuredClone(input);result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows.find(row=>row[1]===r[1]):r);
  result.followsByRegion.jp=result.followsByRegion.jp.map(r=>equal(r,e.baselineRows.followsByRegion[0])||equal(r,follows[0])?follows[0]:r);return result;
}
function main(args){
  const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;assert(candidate||equal(args,['--apply']),'Use --candidate-root /private/tmp/<dir> or --apply');if(candidate)assert(candidate.startsWith('/private/tmp/'));
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(ROOT,p),before:fs.readFileSync(path.join(ROOT,p),'utf8')}]));
  const e=read(path.join(ROOT,EVIDENCE)),inputPaths=[path.join(ROOT,EVIDENCE),...[...e.appleSources,...e.ownSources].map(s=>path.resolve(REPO,e.sourceRoot,s.file)),path.join(ROOT,'data/rail-sections.json'),...e.externalPaths.map(p=>path.join(ROOT,p))];
  const sourceSnapshots=inputPaths.map(p=>({path:p,before:fs.readFileSync(p,'utf8')}));
  assert.deepEqual(read(path.join(ROOT,'data/rail-sections.json')).features[e.rawFeature.index],e.rawFeature.feature,'Kitamatsue raw N02 changed');
  const shared=read(path.join(ROOT,'public/rail/shared-corridors.json'));
  assert.deepEqual(shared.corridors.filter(r=>(r.lineIds||[]).includes(LINE)||(r.members||[]).some(m=>m.lineId===LINE)),e.baselineExternalDisplayReferences.corridors,'Kitamatsue shared corridor changed');
  assert.deepEqual(shared.displayLandlords.filter(r=>r.tenantLineId===LINE||r.landlordLineId===LINE||(r.tenantLineIds||[]).includes(LINE)||(r.landlordLineIds||[]).includes(LINE)),e.baselineExternalDisplayReferences.displayLandlords,'Kitamatsue display landlord changed');
  assert.deepEqual((shared.displayLanePolicy.excludedLineIds||[]).filter(id=>id===LINE),e.baselineExternalDisplayReferences.excludedLineIds,'Kitamatsue shared exclusion changed');
  assert.deepEqual(read(path.join(ROOT,'public/rail/display-releases.json')).releases.filter(r=>r.lineId===LINE),e.baselineExternalDisplayReferences.releases,'Kitamatsue display release changed');
  assert.deepEqual(read(path.join(ROOT,'data/physical-rail-junctions.json')).junctions.filter(r=>r.lineIDs?.includes(LINE)),e.baselineExternalDisplayReferences.junctions,'Kitamatsue junction changed');
  const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e);
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
  const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
  if(candidate){fs.mkdirSync(candidate,{recursive:true});for(const[k,after]of Object.entries(outputs))fs.writeFileSync(path.join(candidate,path.basename(snapshots[k].path)),after);}
  else applyPreparedWrites(Object.entries(outputs).filter(([k,v])=>v!==snapshots[k].before).map(([k,after])=>({...snapshots[k],after})),[...Object.values(snapshots),...sourceSnapshots]);
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',lineID:LINE,removedDisplayVertices:[15,17,19],nativeRows:lanes.partsByRegion.jp.filter(r=>r[0]===LINE),physicalTopologyChanged:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
