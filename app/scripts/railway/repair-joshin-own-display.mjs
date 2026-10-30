#!/usr/bin/env node
import {assertAllowedCandidateDirectory} from './local-evidence-path.mjs';
// One bounded own Joshin display step; production apply requires a separate decision.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {partRowsForLine} from './build-display-lanes.mjs';
import {refreshDependencyReferences,applyPreparedWrites,DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';
const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),REPO=path.dirname(ROOT);
const LINE='jp-上信電鉄-上信線',KEY='joshin-own-display',EVIDENCE='scripts/railway/joshin-own-display-evidence.json';
const network=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(p));
const hash=value=>createHash('sha256').update(value).digest('hex');
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const sourcePath=p=>path.resolve(REPO,p);

function proposedLine(e,includeStation=true){
  assert.equal(e.format,'jtm-joshin-display-step-v1');assert.equal(e.lineID,LINE);assert.equal(e.baselineLine.id,LINE);
  assert.equal(e.appleSources.length,6);
  for(const source of e.appleSources){
    assert.equal(hash(fs.readFileSync(source.path)),source.sha256,'Joshin Apple source bytes changed');
    if(source.path.endsWith('/view.json')){
      const view=read(source.path);
      assert.deepEqual([view.lineID,view.intervalIndex,view.fromStationID,view.toStationID],[LINE,4,'002445','002452']);
      assert.equal(view.camera.zoom256,19);assert([0,1].includes(view.pointOrdinal));
    }
  }
  const raw=read(sourcePath(e.rawFeature.path)).features[e.rawFeature.index];
  assert.equal(e.rawFeature.index,6401);assert.equal(hash(JSON.stringify(raw)),e.rawFeature.sha256,'Joshin raw source feature changed');
  assert.deepEqual(raw.properties,{N02_001:'12',N02_002:'4',N02_003:'上信線',N02_004:'上信電鉄'});
  assert.deepEqual(e.rawFeature.coordinateIndices,[39,38,37]);
  assert.deepEqual(e.rawFeature.coordinates,[[139.02989,36.28422],[139.02993,36.28419],[139.02995,36.28419]]);
  assert.deepEqual([39,38,37].map(i=>raw.geometry.coordinates[i]),e.rawFeature.coordinates);
  for(const source of [e.osmSource,e.platformSource])assert.equal(hash(fs.readFileSync(sourcePath(source.path))),source.sha256,'Joshin local source bytes changed');
  const osm=read(sourcePath(e.osmSource.path));assert.equal(osm.fetchedAt,e.osmSource.fetchedAt);
  assert.deepEqual(e.osmSource.wayIds,[30414753,689274242,689274243]);
  const ways=osm.elements.filter(w=>e.osmSource.wayIds.includes(w.id));
  assert.equal(ways.length,3);assert.equal(hash(JSON.stringify(ways)),e.osmSource.selectedRecordsSha256,'Joshin selected source records changed');
  for(const w of ways)assert.deepEqual([w.tags.operator,w.tags.passenger_lines,w.tags.source,w.tags.railway],['上信電鉄','1','GSI/KIBAN 2500;NARO','rail']);
  const bridge=ways.find(w=>w.id===689274242);assert.equal(bridge.tags.bridge,'yes');
  assert.deepEqual(bridge.geometry,[{lat:36.2842241,lon:139.0299042},{lat:36.284199,lon:139.0299533}]);
  const line=structuredClone(e.baselineLine),old=network.decodeIntervals(line)[4];
  assert.deepEqual(old,e.oldDecodedInterval);assert.equal(e.removedIndex,3);
  assert.deepEqual(old.slice(2,5),e.rawFeature.coordinates);
  assert.deepEqual(e.retainedWindow.indices,[0,1,2,4,5,6]);
  assert.deepEqual(e.retainedWindow.coordinates,e.retainedWindow.indices.map(i=>old[i]));
  line.displayIntervalCoordinates={...line.displayIntervalCoordinates,4:old.filter((_,i)=>i!==3)};
  if(includeStation&&e.stationTrackRepair){
    const repair=e.stationTrackRepair;
    assert.equal(repair.format,'jtm-joshin-station-track-v1');assert.equal(repair.stationID,'002445');assert.equal(repair.lineID,LINE);
    assert.equal(repair.policy,'cartographic-blue-platform-strip-longitudinal-midpoint-normally-projected-to-identified-own-rail');
    assert(repair.sources.length>=4,'Joshin station native evidence missing');
    for(const source of repair.sources)assert.equal(hash(fs.readFileSync(source.path)),source.sha256,'Joshin station source bytes changed');
    const view=read(repair.sources[0].path),projection=view.snapshotProjection,rect=view.mapRect;
    assert.equal(view.fromStationID,'002445');assert.equal(view.lineID,LINE);assert.equal(view.intervalIndex,4);
    assert.equal(projection.displayScale,1);assert.equal(view.camera.heading,0);assert.equal(view.camera.pitch,0);
    const samples=repair.railSamplesPixels,mx=samples.reduce((s,p)=>s+p[0],0)/samples.length,my=samples.reduce((s,p)=>s+p[1],0)/samples.length;
    const slope=samples.reduce((s,p)=>s+(p[0]-mx)*(p[1]-my),0)/samples.reduce((s,p)=>s+(p[0]-mx)**2,0),intercept=my-slope*mx;
    const midpoint=[0,1].map(i=>(repair.capPixels[0][i]+repair.capPixels[1][i])/2);
    const px=(midpoint[0]+slope*(midpoint[1]-intercept))/(1+slope*slope),py=slope*px+intercept;
    const worldX=rect.x+rect.width/2+(px-projection.centerXPoints)*projection.mapPointsPerPointX;
    const worldY=rect.y+rect.height/2+(py-projection.centerYPoints)*projection.mapPointsPerPointY;
    const measured=[worldX/268435456*360-180,Math.atan(Math.sinh(Math.PI*(1-2*worldY/268435456)))*180/Math.PI];
    assert(measured.every((v,i)=>Math.abs(v-repair.coordinate[i])<1e-11),'Joshin station own-rail projection changed');
    const physical=network.decodeIntervals(e.baselineLine);
    for(const index of [3,4]){
      const points=repair.intervals[index];assert.equal(points.length,index===3?30:42);
      assert(points.every(p=>p.length===2&&p.every(Number.isFinite)),'Joshin station coordinate invalid');
      line.displayIntervalCoordinates[index]=structuredClone(points);
    }
    assert.deepEqual(repair.intervals[3][0],physical[3][0],'Joshin Negoya guard changed');
    assert.deepEqual(repair.intervals[4].slice(-2),old.slice(-2),'Joshin Yamana throat guards changed');
    assert.deepEqual(repair.intervals[3].at(-1),repair.coordinate);assert.deepEqual(repair.intervals[4][0],repair.coordinate);
    line.displayStationCoordinates={...line.displayStationCoordinates,[repair.stationID]:repair.coordinate};
  }
  return line;
}

export function repairPackage(input,e=read(path.join(ROOT,EVIDENCE))){
  const proposed=proposedLine(e),indices=input.lines.flatMap((line,i)=>line.id===LINE?[i]:[]);assert.equal(indices.length,1);
  assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],proposed)||e.stationTrackRepair&&equal(input.lines[indices[0]],proposedLine(e,false)),'Joshin baseline changed');
  assert.match(input.geometrySource.license,/OpenStreetMap.*ODbL/i);
  const provenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,intervalIndex:4,removedDisplayVertex:3,retainedGuards:[0,1,2,4,5,6],policy:e.policy,evidence:'app/'+EVIDENCE,script:'app/scripts/railway/repair-joshin-own-display.mjs',physicalTopologyChanged:false};
  const previous=input.geometrySource.manualOverrides?.[KEY];assert(previous===undefined||equal(previous,provenance),'Joshin provenance changed');
  const result=structuredClone(input);result.lines[indices[0]]=proposed;result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;
  if(e.stationTrackRepair){
    const stationProvenance={reviewedAt:e.reviewedAt,status:e.stationTrackRepair.status,lineID:LINE,stationID:'002445',intervalIndices:[3,4],policy:e.stationTrackRepair.policy,evidence:'app/'+EVIDENCE,script:'app/scripts/railway/repair-joshin-own-display.mjs',physicalTopologyChanged:false};
    const previousStation=input.geometrySource.manualOverrides?.[KEY+'-station-track'];assert(previousStation===undefined||equal(previousStation,stationProvenance),'Joshin station provenance changed');
    result.geometrySource.manualOverrides[KEY+'-station-track']=stationProvenance;
  }
  return result;
}

export function repairParts(pkg,input,e=read(path.join(ROOT,EVIDENCE))){
  const line=pkg.lines.find(l=>l.id===LINE);assert.deepEqual(line,proposedLine(e));
  const stations=line.stations.map(row=>line.displayStationCoordinates?.[row[0]]?[row[0],row[1],...line.displayStationCoordinates[row[0]],...row.slice(4)]:row);
  const intervals=network.decodeIntervals({...line,stations});
  for(const [index,points]of Object.entries(line.displayIntervalCoordinates))intervals[Number(index)]=points;
  const rows=partRowsForLine(line,network.displayPartsForLine(line),{stations,intervals},null);
  assert.deepEqual(rows,e.stationTrackRepair?.candidateNativeRows??e.candidateNativeRows,'Joshin native ruler changed');assert.equal(rows.length,1);
  assert.deepEqual(e.baselineRows.byRegion,[],'Joshin unexpectedly has a lane row');
  for(const key of ['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion']){
    const own=(input[key]?.jp||[]).filter(r=>r[0]===LINE||key==='followsByRegion'&&r[4]===LINE),expected=key==='partsByRegion'?rows:e.baselineRows[key];
    assert(equal(own,e.baselineRows[key])||equal(own,expected)||key==='partsByRegion'&&equal(own,e.candidateNativeRows),'Joshin reference changed: '+key);
  }
  assert.deepEqual((input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE)),e.baselineRows.loopsByRegion,'Joshin reference changed: loopsByRegion');
  assert.deepEqual((input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#')),e.baselineRows.reversedLoopParts,'Joshin reference changed: reversedLoopParts');
  const hubs=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));
  assert.deepEqual(hubs,e.baselineRows.hubMembers,'Joshin reference changed: hubs');
  for(const[key,frozen]of Object.entries(e.ownMaps))assert.deepEqual(input[key]?.jp?.[LINE]??null,frozen,'Joshin reference changed: '+key);
  assert(!(input.excludedOperators||[]).includes(e.baselineLine.operator),'Joshin reference changed: excluded operator');assert(!(input.excludedLineIds||[]).includes(LINE),'Joshin reference changed: excluded line');
  const result=structuredClone(input);result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows[0]:r);return result;
}

export function validateExternalReferences(actual,e=read(path.join(ROOT,EVIDENCE))){
  assert.deepEqual(actual,e.baselineExternalDisplayReferences,'Joshin external reference changed');
}

function main(args){
  const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;
  assert(candidate||equal(args,['--apply']),'Use --candidate-root <repo>/railway-evidence/local/candidates/<dir> or --apply');
  if(candidate)assertAllowedCandidateDirectory(candidate);
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(ROOT,p),before:fs.readFileSync(path.join(ROOT,p))}]));
  const e=read(path.join(ROOT,EVIDENCE));
  const inputPaths=[path.join(ROOT,EVIDENCE),...e.appleSources.map(s=>s.path),...(e.stationTrackRepair?.sources??[]).map(s=>s.path),sourcePath(e.rawFeature.path),sourcePath(e.osmSource.path),sourcePath(e.platformSource.path),...e.externalPaths.map(p=>path.join(ROOT,p))];
  const inputs=inputPaths.map(p=>({path:p,before:fs.readFileSync(p)}));
  const shared=read(path.join(ROOT,'public/rail/shared-corridors.json'));
  validateExternalReferences({
    corridors:shared.corridors.filter(r=>(r.lineIds||[]).includes(LINE)||(r.members||[]).some(m=>m.lineId===LINE)),
    displayLandlords:shared.displayLandlords.filter(r=>r.tenantLineId===LINE||r.landlordLineId===LINE||(r.tenantLineIds||[]).includes(LINE)||(r.landlordLineIds||[]).includes(LINE)),
    excludedLineIds:(shared.displayLanePolicy.excludedLineIds||[]).filter(id=>id===LINE),
    releases:read(path.join(ROOT,'public/rail/display-releases.json')).releases.filter(r=>r.lineId===LINE),
    junctions:read(path.join(ROOT,'data/physical-rail-junctions.json')).junctions.filter(r=>r.lineIDs?.includes(LINE))},e);
  const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e);
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
  const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
  if(candidate){
    fs.mkdirSync(candidate,{recursive:true});assertAllowedCandidateDirectory(candidate);
    const writes=Object.entries(outputs).map(([k,after])=>{
      const destination=path.join(candidate,path.basename(snapshots[k].path));
      assert(!fs.existsSync(destination)||!fs.lstatSync(destination).isSymbolicLink(),'Candidate output cannot be a symlink');
      if(!fs.existsSync(destination))fs.writeFileSync(destination,'');
      return {path:destination,before:fs.readFileSync(destination),after:Buffer.from(after)};
    });
    applyPreparedWrites(writes,[...Object.values(snapshots),...inputs,...writes.map(({path,before})=>({path,before}))]);
  }else{
    const writes=Object.entries(outputs).map(([k,after])=>({...snapshots[k],after:Buffer.from(after)}));
    applyPreparedWrites(writes,[...Object.values(snapshots),...inputs]);
  }
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',candidateRoot:candidate,lineID:LINE,intervalIndex:4,removedDisplayVertex:3,nativeRows:lanes.partsByRegion.jp.filter(r=>r[0]===LINE),physicalTopologyChanged:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
