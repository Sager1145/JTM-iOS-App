#!/usr/bin/env node
// Bounded display repair between image-witnessed guards; physical rows stay canonical.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {assertAllowedCandidateDirectory} from './local-evidence-path.mjs';
import {partRowsForLine} from './build-display-lanes.mjs';
import {refreshDependencyReferences,applyPreparedWrites,DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';
const REPO=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..'),APP=path.join(REPO,'app'),EV=path.join(REPO,'railway-evidence/local');
const LINE='jp-九州旅客鉄道-三角線',KEY='misumi-own-display';
export const EVIDENCE_PATH=path.join(EV,'repair-inputs/misumi-own-display-evidence.json');
const net=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(p)),hash=b=>createHash('sha256').update(b).digest('hex'),equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const evidence=()=>read(EVIDENCE_PATH);
const ROW_KEYS=['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion'];
const world=([lon,lat])=>[(lon+180)/360*268435456,(1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)/2*268435456];
const near=(a,b,tolerance=1e-10)=>a.every((v,i)=>Math.abs(v-b[i])<tolerance);
function invert(pixel,v){
 const r=v.mapRect,s=v.snapshotProjection;
 assert(s&&s.displayScale===1&&v.camera.heading===0&&v.camera.pitch===0,'Misumi actual projection witness missing');
 const x=r.x+r.width/2+(pixel[0]-s.centerXPoints)*s.mapPointsPerPointX,y=r.y+r.height/2+(pixel[1]-s.centerYPoints)*s.mapPointsPerPointY;
 return [x/268435456*360-180,Math.atan(Math.sinh(Math.PI*(1-2*y/268435456)))*180/Math.PI];
}
function proposalInputs(e){
 const expected=['misumi-guarded-fit-20261020','misumi-core-manual-fit-20261020','misumi-station-anchors-20261020','misumi-core-join-assessment-20261020'].map(n=>path.join(EV,'proposals',n+'.json'));
 expected.push(path.join(EV,'legacy-tmp/jtm-misumi-midorikawa-sumiyoshi-proposal-20261020/proposal.json'),path.join(EV,'proposals/misumi-coastal-manual-20261020/proposal.json'));
 assert.deepEqual(e.proposalPaths,expected,'Misumi proposal paths changed');
 const [p,core,anchors]=expected.map(read),paths=new Set(expected),add=p=>paths.add(fs.realpathSync(p));
 const directory=d=>['view.json','basemap.png','smooth.png'].forEach(f=>add(path.join(d,f)));
 for(const s of p.combinedFit.supportsInForwardOrder){if(s.sourceDirectory)directory(s.sourceDirectory);if(s.viewPath)directory(path.dirname(s.viewPath));if(s.sourceImage)directory(path.dirname(s.sourceImage));}
 for(const s of [...p.newManualSupports,...core.manualSupports])directory(path.dirname(s.viewPath));
 for(const s of anchors.stations)directory(s.viewDirectory);
 directory(path.join(EV,'diagnostics/sessions/misumi-sumiyoshi-own-imagery-20261020/alignment/captures/000000/000055'));
 for(const s of p.sources)for(const file of s.paths)add(file);
 assert.deepEqual(e.sources.map(s=>s.path),[...paths].sort(),'Misumi evidence input set changed');
 for(const s of e.sources)assert.equal(hash(fs.readFileSync(s.path)),s.sha256,'Misumi source bytes changed: '+s.path);
 return {p,core,anchors};
}
function validateSourceIdentity(e){
 const n02=read(e.n02Source.path);assert.equal(e.n02Source.records.length,19,'Misumi N02 source identity changed');
 for(const r of e.n02Source.records){assert.deepEqual(n02.features[r.index],r.feature,'Misumi N02 source identity changed');assert.deepEqual([r.feature.properties.N02_003,r.feature.properties.N02_004],['三角線','九州旅客鉄道'],'Misumi N02 source identity changed');}
 const osm=read(e.osmSource.path);assert.equal(osm.fetchedAt,e.osmSource.fetchedAt,'Misumi OSM source identity changed');
 assert.deepEqual(e.osmSource.ownWayIDs,[24461245,416826274,416826275,1352412011,1352412010,24461250]);assert.equal(e.osmSource.excludedSidingWayID,857018550);
 assert.deepEqual(e.osmSource.elements.map(w=>w.id).sort((a,b)=>a-b),[...e.osmSource.ownWayIDs,857018550].sort((a,b)=>a-b),'Misumi OSM source identity changed');
 for(const w of e.osmSource.elements){assert.deepEqual(osm.elements.find(x=>x.id===w.id),w,'Misumi OSM source identity changed');assert.deepEqual([w.tags.name,w.tags.operator,w.tags.railway,w.tags.source],['JR三角線','九州旅客鉄道','rail','KSJ2'],'Misumi OSM source identity changed');assert.equal(w.tags.service,w.id===857018550?'siding':undefined,'Misumi own-main source identity changed');}
}
function proposedLine(e){
 assert.equal(e.format,'jtm-misumi-own-display-evidence-v1');assert.equal(e.lineID,LINE);
 const {p,core,anchors}=proposalInputs(e);validateSourceIdentity(e);
 assert.equal(p.lineID,LINE);assert.equal(p.combinedFit.continuous,true);assert.deepEqual(e.combinedFit,p.combinedFit,'Misumi fit authority changed');assert.deepEqual(e.guards,p.guards,'Misumi guard authority changed');
 const aliases={};
 for(const s of anchors.stations){
  const v=read(path.join(s.viewDirectory,'view.json'));assert.equal(v.lineID,LINE);
  const points=s.manuallyIdentifiedOwnRailPointsPixels,mx=points.reduce((a,q)=>a+q[0],0)/points.length,my=points.reduce((a,q)=>a+q[1],0)/points.length;
  const slope=points.reduce((a,q)=>a+(q[0]-mx)*(q[1]-my),0)/points.reduce((a,q)=>a+(q[0]-mx)**2,0),intercept=my-slope*mx;
  const mid=[0,1].map(k=>(s.manualWholeBlueStripLongitudinalCapsPixels[0][k]+s.manualWholeBlueStripLongitudinalCapsPixels[1][k])/2),x=(mid[0]+slope*(mid[1]-intercept))/(1+slope*slope);
  assert(near(invert([x,slope*x+intercept],v),s.proposedDisplayCoordinate),'Misumi station projection changed');aliases[s.stationID]=s.proposedDisplayCoordinate;
 }
 assert.deepEqual(aliases,e.anchorCoordinates,'Misumi station authority changed');assert.deepEqual(Object.keys(aliases),['009852','009849']);
 const manual=new Map([...p.newManualSupports,...core.manualSupports].map(s=>[s.id,s]));
 for(const s of p.combinedFit.supportsInForwardOrder){
  const sample=s.manualSupportID?manual.get(s.manualSupportID):s;
  if(sample.pixel&&(sample.viewPath||sample.sourceDirectory||sample.sourceImage)){
   const viewPath=sample.viewPath||path.join(sample.sourceDirectory||path.dirname(sample.sourceImage),'view.json'),v=read(viewPath);
   assert.equal(v.lineID,LINE);assert([0,1,2].includes(v.intervalIndex));assert(near(invert(sample.pixel,v),s.coordinate),'Misumi support projection changed: '+s.id);
  }
 }
 const old=net.decodeIntervals(e.baselineLine),chain=structuredClone(e.combinedFit.coordinates),split=e.combinedFit.stationSplitIndices;
 assert.equal(chain.length,107);assert.deepEqual(chain,e.combinedFit.supportsInForwardOrder.map(s=>s.coordinate));assert(chain.every((q,i)=>q.length===2&&q.every(Number.isFinite)&&(i===0||chain[i-1][0]>q[0])),'Misumi bounded fit backtracks');
 assert.deepEqual(split,{'009852':27,'009849':64});assert.deepEqual(chain[27],aliases['009852']);assert.deepEqual(chain[64],aliases['009849']);
 assert.deepEqual(e.baselineLine.stations.slice(0,4).map(s=>s[0]),['009850','009852','009849','009853']);assert.deepEqual(e.oldGuardEdgeIndices,{'0':7,'2':25});
 for(const g of e.guards){
  const index=e.oldGuardEdgeIndices[g.intervalIndex],edge=old[g.intervalIndex].slice(index,index+2),[a,b]=edge.map(world),q=world(g.coordinate),t=g.display.fractionInProjectedEdge;
  assert(edge.every((point,i)=>near(point,g.display.edgeCoordinates[i])),'Misumi old guard edge changed');assert(t>0&&t<1&&q.every((v,k)=>Math.abs(v-(a[k]+t*(b[k]-a[k])))<1e-5),'Misumi guard left old edge');
  const v=read(g.viewPath);assert.equal(v.lineID,LINE);assert.equal(v.intervalIndex,g.intervalIndex);assert(near(invert(g.display.pixel,v),g.coordinate));
  const saved=v.renderedDisplay[g.display.partIndex].slice(g.display.edgeIndexInSavedClippedPart,g.display.edgeIndexInSavedClippedPart+2);assert.deepEqual(saved,g.display.edgeCoordinates,'Misumi native guard edge changed');
  const smooth=v.renderedSmooth[g.smooth.partIndex].slice(g.smooth.edgeIndexInSavedClippedPart,g.smooth.edgeIndexInSavedClippedPart+2);assert.deepEqual(smooth,g.smooth.edgeCoordinates,'Misumi saved smooth witness changed');
  assert(g.actualOwnRailPixel?.length===2&&g.displayToOwnRailNormalResidualPixels<2&&g.smoothToOwnRailNormalResidualPixels<2,'Misumi guard lacks own-rail/smooth pixel witness');
 }
 assert.deepEqual([chain[0],chain.at(-1)],e.guards.map(g=>g.coordinate));
 const intervals={0:[...old[0].slice(0,8),...chain.slice(0,28)],1:chain.slice(27,65),2:[...chain.slice(64),...old[2].slice(26)]};
 assert.deepEqual(intervals,e.expectedIntervals,'Misumi retained outer tails or repartition changed');
 const line=structuredClone(e.baselineLine);line.displayStationCoordinates={...line.displayStationCoordinates,...aliases};line.displayIntervalCoordinates={...line.displayIntervalCoordinates,...intervals};
 const review=e.nativeCandidateReview;
 assert(review&&review.sources.length===15,'Misumi native candidate review missing');
 const root=path.join(EV,'diagnostics/sessions/misumi-own-candidate-join-stations-z19-detail-20261020/alignment/captures');
 const scope=[[0,5],[1,0],[1,27],[2,6],[2,20]];
 const expected=scope.flatMap(([i,n])=>['basemap.png','smooth.png','view.json'].map(f=>path.join(root,String(i).padStart(6,'0'),String(n).padStart(6,'0'),f)));
 assert.deepEqual(review.sources.map(s=>s.path),expected,'Misumi native review paths changed');
 assert.equal(hash(JSON.stringify(line)),review.reviewedOwnLineSha256,'Misumi native reviewed own line changed');
 assert.equal(review.wholeLineRenderDependency,'d4acfa1d5bb29d8a15c47b6a7a612c591c297f0ae397a7f0862037221dbb9c3c','Misumi native reviewed render dependency changed');
 for(const [index,source]of review.sources.entries()){
  assert.equal(hash(fs.readFileSync(source.path)),source.sha256,'Misumi native review source bytes changed');
  if(source.path.endsWith('/view.json')){
   const v=read(source.path),[i,n]=scope[Math.floor(index/3)],start=e.baselineLine.stations[i][0],end=e.baselineLine.stations[i+1][0];
   assert.deepEqual([v.lineID,v.intervalIndex,v.fromStationID,v.toStationID,v.pointOrdinal],[LINE,i,start,end,n],'Misumi native reviewed identity changed');
   assert.equal(v.wholeLineRenderDependency,review.wholeLineRenderDependency,'Misumi native reviewed render dependency changed');
   assert.equal(v.camera.heading,0);assert.equal(v.camera.pitch,0);assert.equal(v.snapshotProjection.displayScale,1);
   assert(Math.abs(v.snapshotProjection.mapPointsPerPointX-2)<1e-8&&Math.abs(v.snapshotProjection.mapPointsPerPointY-2)<1e-8,'Misumi native reviewed projection changed');
  }
 }
 assert.equal(e.status,'bounded-own-rail-fit-and-two-station-display-repair; whole-line-and-outer-stations-open','Misumi bounded provenance status changed');
 return line;
}
export function repairPackage(input,e=evidence()){
 const proposed=proposedLine(e),indices=input.lines.flatMap((l,i)=>l.id===LINE?[i]:[]);assert.equal(indices.length,1);assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],proposed),'Misumi baseline changed');assert.match(input.geometrySource.license,/OpenStreetMap.*ODbL/i);
 const provenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,stationIDs:['009852','009849'],intervalIndices:[0,1,2],policy:e.policy,evidence:path.relative(REPO,EVIDENCE_PATH),script:'app/scripts/railway/repair-misumi-own-display.mjs',physicalTopologyChanged:false,wholeIntervalsAccepted:false,outerStationsAccepted:false};
 const previous=input.geometrySource.manualOverrides?.[KEY];assert(previous===undefined||equal(previous,provenance),'Misumi provenance changed');const result=structuredClone(input);result.lines[indices[0]]=proposed;result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;return result;
}
export function ownReferences(input){
 const rows=Object.fromEntries(ROW_KEYS.map(k=>[k,(input[k]?.jp||[]).filter(r=>r[0]===LINE||k==='followsByRegion'&&r[4]===LINE)]));
 rows.loopsByRegion=(input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE));rows.reversedLoopParts=(input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#'));
 rows.hubMembers=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));return rows;
}
export function repairParts(pkg,input,e=evidence()){
 const line=pkg.lines.find(l=>l.id===LINE);assert.deepEqual(line,proposedLine(e));
 const stations=line.stations.map(r=>line.displayStationCoordinates?.[r[0]]?[...r.slice(0,2),...line.displayStationCoordinates[r[0]],...r.slice(4)]:r),intervals=net.decodeIntervals({...line,stations});for(const[i,p]of Object.entries(line.displayIntervalCoordinates))intervals[+i]=p;
 const rows=partRowsForLine(line,net.displayPartsForLine(line),{stations,intervals},null);assert.deepEqual(rows,e.candidateNativeRows,'Misumi native ruler changed');assert.equal(rows.length,1);
 for(const[key,actual]of Object.entries(ownReferences(input)))assert(equal(actual,e.baselineRows[key])||key==='partsByRegion'&&equal(actual,rows),'Misumi reference changed: '+key);
 assert.deepEqual(e.baselineRows.byRegion,[],'Misumi baseline lane absence changed');for(const[key,value]of Object.entries(e.ownMaps))assert.deepEqual(input[key]?.jp?.[LINE]??null,value,'Misumi reference changed: '+key);
 assert(!(input.excludedOperators||[]).includes(line.operator)&&!(input.excludedLineIds||[]).includes(LINE),'Misumi exclusion changed');const result=structuredClone(input);result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows[0]:r);return result;
}
export function validateExternalReferences(actual,e=evidence()){assert.deepEqual(actual,e.baselineExternalReferences,'Misumi external reference changed');}
function externalReferences(shared,releases,junctions){return {corridors:shared.corridors.filter(r=>(r.lineIds||[]).includes(LINE)||(r.members||[]).some(m=>m.lineId===LINE)),displayLandlords:shared.displayLandlords.filter(r=>r.tenantLineId===LINE||r.landlordLineId===LINE||(r.tenantLineIds||[]).includes(LINE)||(r.landlordLineIds||[]).includes(LINE)),excludedLineIds:(shared.displayLanePolicy.excludedLineIds||[]).filter(id=>id===LINE),releases:releases.releases.filter(r=>r.lineId===LINE),junctions:junctions.junctions.filter(r=>r.lineIDs?.includes(LINE))};}
function main(args){
 const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;
 assert(candidate||equal(args,['--apply']),'Use --candidate-root <repo>/railway-evidence/local/candidates/<dir> or --apply');
 if(candidate){assertAllowedCandidateDirectory(candidate);assert(candidate.startsWith(path.join(EV,'candidates')+path.sep),'Misumi candidate must use canonical repository evidence tree');}
 const evidenceInput={path:EVIDENCE_PATH,before:fs.readFileSync(EVIDENCE_PATH)},e=JSON.parse(evidenceInput.before),paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
 const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(APP,p),before:fs.readFileSync(path.join(APP,p))}]));
 const inputs=[evidenceInput,...[...e.sources.map(s=>s.path),...e.nativeCandidateReview.sources.map(s=>s.path),e.osmSource.path,e.n02Source.path,...e.externalPaths.map(p=>path.join(APP,p))].map(p=>({path:p,before:fs.readFileSync(p)}))];
 const frozen=p=>JSON.parse(inputs.find(i=>i.path===path.join(APP,p)).before);validateExternalReferences(externalReferences(...e.externalPaths.map(frozen)),e);
 const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e),deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
 const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
 let writes;
 if(candidate){
  fs.mkdirSync(candidate,{recursive:true});assertAllowedCandidateDirectory(candidate);writes=Object.entries(outputs).map(([k,after])=>{const destination=path.join(candidate,path.basename(snapshots[k].path));assert(!fs.existsSync(destination)||!fs.lstatSync(destination).isSymbolicLink(),'Candidate output cannot be symlink');if(!fs.existsSync(destination))fs.writeFileSync(destination,'');return {path:destination,before:fs.readFileSync(destination),after:Buffer.from(after)};});
 }else writes=Object.entries(outputs).map(([k,after])=>({...snapshots[k],after:Buffer.from(after)}));
 applyPreparedWrites(writes,[...Object.values(snapshots),...inputs,...(candidate?writes.map(({path,before})=>({path,before})):[])]);
 console.log(JSON.stringify({mode:candidate?'candidate':'applied',candidateRoot:candidate,lineID:LINE,intervalCounts:[0,1,2].map(i=>pkg.lines.find(l=>l.id===LINE).displayIntervalCoordinates[i].length),nativeRows:lanes.partsByRegion.jp.filter(r=>r[0]===LINE),physicalTopologyChanged:false,status:e.status,mainFinalCheck:'pending separate Main review'}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
