#!/usr/bin/env node
import {assertAllowedCandidateDirectory} from './local-evidence-path.mjs';
// Bounded cartographic repair; physical topology and mileage stay canonical.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {partRowsForLine} from './build-display-lanes.mjs';
import {refreshDependencyReferences,applyPreparedWrites,DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';
const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),REPO=path.dirname(ROOT);
const LINE='jp-九州旅客鉄道-久大線',KEY='kyudai-kurume-display',EVIDENCE='scripts/railway/kyudai-kurume-display-evidence.json';
const network=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(p)),equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const evidence=()=>read(path.join(ROOT,EVIDENCE));
// Every reviewed original is both byte-checked and held as a before-write input.
function evidenceSources(e){return [...e.appleSources,...e.stationTrackRepair.sources,...e.nativeCandidateReview.candidatePairs.flatMap(pair=>pair.sources),...e.nativeCandidateReview.stationZ20Sources];}
function invert(pixel,view){
 const r=view.mapRect,s=view.snapshotProjection;assert(s&&s.displayScale===1&&view.camera.heading===0&&view.camera.pitch===0,'native projection witness missing');
 const x=r.x+r.width/2+(pixel[0]-s.centerXPoints)*s.mapPointsPerPointX,y=r.y+r.height/2+(pixel[1]-s.centerYPoints)*s.mapPointsPerPointY;
 return [x/268435456*360-180,Math.atan(Math.sinh(Math.PI*(1-2*y/268435456)))*180/Math.PI];
}
function measuredCoordinate(repair){
 const view=read(repair.sources[0].path);assert.equal(view.lineID,LINE);assert.equal(view.camera.zoom256,20);
 const samples=repair.railSamplesPixels,mx=samples.reduce((s,p)=>s+p[0],0)/samples.length,my=samples.reduce((s,p)=>s+p[1],0)/samples.length;
 const slope=samples.reduce((s,p)=>s+(p[0]-mx)*(p[1]-my),0)/samples.reduce((s,p)=>s+(p[0]-mx)**2,0),intercept=my-slope*mx;
 const midpoint=[0,1].map(i=>(repair.capPixels[0][i]+repair.capPixels[1][i])/2),x=(midpoint[0]+slope*(midpoint[1]-intercept))/(1+slope*slope);
 return invert([x,slope*x+intercept],view);
}
function proposedLine(e){
 assert.equal(e.format,'jtm-kyudai-kurume-display-v1');assert.equal(e.lineID,LINE);assert.equal(e.stationTrackRepair.stationID,'009398');
 for(const source of evidenceSources(e))assert.equal(hash(fs.readFileSync(source.path)),source.sha256,'Kyudai source bytes changed');
 const raw=read(path.resolve(REPO,e.n02Source.path));
 assert(e.n02Source.records.length>0,'Kyudai N02 source missing');
 for(const r of e.n02Source.records){assert.deepEqual(raw.features[r.index],r.feature,'Kyudai N02 source changed');assert.deepEqual([r.feature.properties.N02_003,r.feature.properties.N02_004],['久大線','九州旅客鉄道'],'Kyudai N02 identity changed');}
 const osm=read(e.osmSource.path);assert.equal(osm.fetchedAt,e.osmSource.fetchedAt,'Kyudai OSM source changed');
 for(const w of e.osmSource.elements){assert.deepEqual(osm.elements.find(x=>x.id===w.id),w,'Kyudai OSM source changed');assert.deepEqual([w.tags.name,w.tags.operator,w.tags.railway,w.tags.source],['JR久大線','九州旅客鉄道','rail','KSJ2'],'Kyudai OSM identity changed');}
 const station=e.stationTrackRepair.coordinate,measured=measuredCoordinate(e.stationTrackRepair);assert(measured.every((v,i)=>Math.abs(v-station[i])<1e-11),'Kyudai station own-rail projection changed');
 const supports=e.combinedFit.supports;assert.deepEqual(e.combinedFit.coordinates,supports.map(s=>s.coordinate),'Kyudai fit supports changed');
 for(const support of supports.filter(s=>s.role==='own-rail-support')){
  const view=read(support.viewPath);assert.equal(view.lineID,LINE);assert([32,33].includes(view.intervalIndex));
  const measured=invert(support.pixelPoints,view);assert(measured.every((v,i)=>Math.abs(v-support.coordinate[i])<1e-11),'Kyudai support projection changed');
 }
 const physical=network.decodeIntervals(e.baselineLine),chain=structuredClone(e.combinedFit.coordinates);
 assert.deepEqual(chain[0],physical[32][0],'Kyudai Mii guard changed');assert.deepEqual(chain.at(-1),physical[33].at(-1),'Kyudai Minami-Kurume guard changed');
 assert(chain.every((p,i)=>p.length===2&&p.every(Number.isFinite)&&(i===0||chain[i-1][0]>p[0])),'Kyudai combined support order reversed');
 // Insert at forward longitude/chainage. Western former #32 controls become #33.
 const split=chain.findIndex(p=>p[0]<station[0]);assert(split>0&&split<chain.length,'Kyudai station outside combined interval');chain.splice(split,0,structuredClone(station));
 assert(chain.every((p,i)=>i===0||chain[i-1][0]>p[0]),'Kyudai station repartition backtracks');
 const line=structuredClone(e.baselineLine);line.displayStationCoordinates={...line.displayStationCoordinates,'009398':structuredClone(station)};
 line.displayIntervalCoordinates={...line.displayIntervalCoordinates,32:chain.slice(0,split+1),33:chain.slice(split)};return line;
}
export function repairPackage(input,e=evidence()){
 const proposed=proposedLine(e),indices=input.lines.flatMap((l,i)=>l.id===LINE?[i]:[]);assert.equal(indices.length,1);
 assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],proposed),'Kyudai physical/display baseline changed');
 const result=structuredClone(input),provenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,stationID:'009398',intervalIndices:[32,33],policy:e.stationTrackRepair.policy,evidence:'app/'+EVIDENCE,script:'app/scripts/railway/repair-kyudai-kurume-display.mjs',physicalTopologyChanged:false};
 const previous=input.geometrySource.manualOverrides?.[KEY];assert(previous===undefined||equal(previous,provenance),'Kyudai provenance changed');
 result.lines[indices[0]]=proposed;result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;return result;
}
export function repairParts(pkg,input,e=evidence()){
 const line=pkg.lines.find(l=>l.id===LINE);assert.deepEqual(line,proposedLine(e));
 const stations=line.stations.map(row=>line.displayStationCoordinates?.[row[0]]?[row[0],row[1],...line.displayStationCoordinates[row[0]],...row.slice(4)]:row),intervals=network.decodeIntervals({...line,stations});
 for(const [i,points]of Object.entries(line.displayIntervalCoordinates))intervals[Number(i)]=points;
 const rows=partRowsForLine(line,network.displayPartsForLine(line),{stations,intervals},null);assert.equal(rows.length,1);assert.equal(e.baselineRows.partsByRegion.length,1);
 // This line owns one full-part lane. Its end follows the rebuilt display ruler.
 assert.deepEqual(e.baselineRows.byRegion,[[LINE,0,0,e.baselineRows.partsByRegion[0][5],-1]],'Kyudai whole-part lane reference changed');
 const laneRows=[[LINE,0,0,rows[0][5],-1]];
 for(const key of ['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion']){
  const own=(input[key]?.jp||[]).filter(r=>r[0]===LINE||key==='followsByRegion'&&r[4]===LINE);assert(equal(own,e.baselineRows[key])||key==='partsByRegion'&&equal(own,rows)||key==='byRegion'&&equal(own,laneRows),'Kyudai reference changed: '+key);
 }
 assert.deepEqual((input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE)),e.baselineRows.loopsByRegion,'Kyudai loop reference changed');
 assert.deepEqual((input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#')),e.baselineRows.reversedLoopParts,'Kyudai reversed reference changed');
 const hubs=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));assert.deepEqual(hubs,e.baselineRows.hubMembers,'Kyudai hub reference changed');
 for(const [key,frozen]of Object.entries(e.ownMaps))assert.deepEqual(input[key]?.jp?.[LINE]??null,frozen,'Kyudai map reference changed: '+key);
 assert(!(input.excludedOperators||[]).includes(e.baselineLine.operator)&&!(input.excludedLineIds||[]).includes(LINE),'Kyudai excluded reference changed');
 const result=structuredClone(input);result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows[0]:r);result.byRegion.jp=result.byRegion.jp.map(r=>r[0]===LINE?laneRows[0]:r);return result;
}
export function validateExternalReferences(actual,e=evidence()){assert.deepEqual(actual,e.baselineExternalDisplayReferences,'Kyudai external reference changed');}
function main(args){
 const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;
 assert(candidate||equal(args,['--apply']),'Use --candidate-root <repo>/railway-evidence/local/candidates/<directory> or --apply');if(candidate)assertAllowedCandidateDirectory(candidate);
 const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS},snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(ROOT,p),before:fs.readFileSync(path.join(ROOT,p))}])),e=evidence();
 const inputPaths=[path.join(ROOT,EVIDENCE),...evidenceSources(e).map(s=>s.path),path.resolve(REPO,e.n02Source.path),e.osmSource.path,...e.externalPaths.map(p=>path.join(ROOT,p))],inputs=inputPaths.map(p=>({path:p,before:fs.readFileSync(p)}));
 const shared=read(path.join(ROOT,'public/rail/shared-corridors.json'));validateExternalReferences({corridors:shared.corridors.filter(r=>(r.lineIds||[]).includes(LINE)||(r.members||[]).some(m=>m.lineId===LINE)),displayLandlords:shared.displayLandlords.filter(r=>r.tenantLineId===LINE||r.landlordLineId===LINE||(r.tenantLineIds||[]).includes(LINE)||(r.landlordLineIds||[]).includes(LINE)),excludedLineIds:(shared.displayLanePolicy.excludedLineIds||[]).filter(id=>id===LINE),releases:read(path.join(ROOT,'public/rail/display-releases.json')).releases.filter(r=>r.lineId===LINE),junctions:read(path.join(ROOT,'data/physical-rail-junctions.json')).junctions.filter(r=>r.lineIDs?.includes(LINE))},e);
 const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e),deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
 const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
 if(candidate){
  fs.mkdirSync(candidate,{recursive:true});assertAllowedCandidateDirectory(candidate);
  const writes=Object.entries(outputs).map(([k,after])=>{const destination=path.join(candidate,path.basename(snapshots[k].path));assert(!fs.existsSync(destination)||!fs.lstatSync(destination).isSymbolicLink(),'Candidate symlink');if(!fs.existsSync(destination))fs.writeFileSync(destination,'');return {path:destination,before:fs.readFileSync(destination),after:Buffer.from(after)};});
  applyPreparedWrites(writes,[...Object.values(snapshots),...inputs,...writes.map(({path,before})=>({path,before}))]);
 }else{
  const writes=Object.entries(outputs).map(([k,after])=>({...snapshots[k],after:Buffer.from(after)}));
  applyPreparedWrites(writes,[...Object.values(snapshots),...inputs]);
 }
 console.log(JSON.stringify({mode:candidate?'candidate':'applied',candidateRoot:candidate,lineID:LINE,intervalCounts:[pkg.lines.find(l=>l.id===LINE).displayIntervalCoordinates[32].length,pkg.lines.find(l=>l.id===LINE).displayIntervalCoordinates[33].length],physicalTopologyChanged:false,nativeAcceptance:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
