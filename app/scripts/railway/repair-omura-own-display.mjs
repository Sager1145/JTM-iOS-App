#!/usr/bin/env node
// Evidence-bound own-graphic repair. Physical topology and source kilometre rows stay canonical.
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
const LINE='jp-九州旅客鉄道-大村線',KEY='omura-own-display',PROPOSAL=path.join(EV,'proposals/omura-huis-ten-bosch-haenosaki-20261020');
export const EVIDENCE_PATH=path.join(EV,'repair-inputs/omura-own-display-evidence.json');
const net=createRequire(import.meta.url)('../../public/rail-network.js'),read=p=>JSON.parse(fs.readFileSync(p)),hash=b=>createHash('sha256').update(b).digest('hex'),equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b),near=(a,b,t=1e-10)=>a.length===b.length&&a.every((v,i)=>Math.abs(v-b[i])<t);
const evidence=()=>read(EVIDENCE_PATH),world=([lon,lat])=>[(lon+180)/360*268435456,(1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)/2*268435456];
const ROW_KEYS=['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion'];
const GROUPS=[['omura-huis-ten-bosch-haenosaki-z19-detail-20261020',[[0,40],[1,0],[1,1],[1,2],[1,3],[1,4],[1,5],[1,6],[1,7],[2,1]]],['omura-station-track-identity-imagery-z19-20261020',[[0,40],[1,7],[2,1]]],['omura-station-caps-z20-wide-detail-20261020',[[0,0],[0,8]]],['omura-station-outer-guard-context-z19-20261020',[[0,38],[0,39],[1,2],[1,3]]],['omura-station-approach-fit-context-z19-20261020',[[0,22],[0,23],[0,24],[0,26],[0,28],[0,30],[0,32],[0,34],[0,36],[1,4],[1,6],[1,8],[1,10],[1,12]]]];
const proposalPaths=()=>['complete-bounded-pixel-proposal','compact-source-freeze','source-identity','measured-station-anchors','station-identity-update','refined-body-supports','approach-pixel-supports','outer-guard-candidates','collar-extra-pixel-supports'].map(n=>path.join(PROPOSAL,n+'.json'));
const codePaths=()=>['app/public/rail-network.js','app/scripts/railway/build-display-lanes.mjs','app/scripts/railway/repair-three-reversal-extents.mjs','app/scripts/railway/local-evidence-path.mjs','ios/RailKit/Sources/RailCore/Data/CompactPackage.swift'].map(p=>path.join(REPO,p));
function expectedViews(){return GROUPS.flatMap(([session,slots])=>slots.map(([i,n])=>path.join(EV,'diagnostics/sessions',session,'alignment/captures',String(i).padStart(6,'0'),String(n).padStart(6,'0'),'view.json')));}
function invert(pixel,v){
 const r=v.mapRect,s=v.snapshotProjection;assert(s&&s.displayScale===1&&v.camera.heading===0&&v.camera.pitch===0,'Omura projection changed');
 const x=r.x+r.width/2+(pixel[0]-s.centerXPoints)*s.mapPointsPerPointX,y=r.y+r.height/2+(pixel[1]-s.centerYPoints)*s.mapPointsPerPointY;
 return [x/268435456*360-180,Math.atan(Math.sinh(Math.PI*(1-2*y/268435456)))*180/Math.PI];
}
function validateSources(e){
 assert.deepEqual(e.proposalPaths,proposalPaths(),'Omura evidence input set changed');const views=expectedViews();assert.deepEqual(e.viewWitnesses.map(v=>v.path),views,'Omura evidence view set changed');
 const paths=[...proposalPaths(),...views.flatMap(v=>['basemap.png','smooth.png','view.json'].map(f=>path.join(path.dirname(v),f)))].sort();assert.deepEqual(e.sources.map(s=>s.path),paths,'Omura evidence input set changed');
 for(const s of e.sources)assert.equal(hash(fs.readFileSync(s.path)),s.sha256,'Omura source bytes changed: '+s.path);
 assert.deepEqual(e.inputCodeSources.map(s=>s.path),codePaths(),'Omura input code set changed');for(const s of e.inputCodeSources)assert.equal(hash(fs.readFileSync(s.path)),s.sha256,'Omura input code bytes changed');
 for(const w of e.viewWitnesses){
  const v=read(w.path);assert.deepEqual([v.lineID,v.intervalIndex,v.pointOrdinal,v.fromStationID,v.toStationID],[LINE,w.intervalIndex,w.pointOrdinal,e.baselineLine.stations[w.intervalIndex][0],e.baselineLine.stations[w.intervalIndex+1][0]],'Omura native source identity changed');
  assert.deepEqual(v.snapshotProjection,w.snapshotProjection,'Omura projection changed');assert.deepEqual(v.captureSettings,w.captureSettings,'Omura capture settings changed');assert.equal(v.renderContract,w.renderContract,'Omura render contract changed');assert.equal(v.wholeLineRenderDependency,w.wholeLineRenderDependency,'Omura render dependency changed');
  const wide=w.path.includes('caps-z20-wide'),basis=wide?1:2;assert(v.camera.heading===0&&v.camera.pitch===0&&v.snapshotProjection.displayScale===1&&Math.abs(v.snapshotProjection.mapPointsPerPointX-basis)<1e-8&&Math.abs(v.snapshotProjection.mapPointsPerPointY-basis)<1e-8,'Omura projection changed');
 }
 const identity=read(path.join(PROPOSAL,'source-identity.json'));assert.deepEqual(e.sourceIdentity,identity,'Omura source identity changed');
 assert.deepEqual(identity.northToSouthMainWayIDs,[24461686,733698880,24461677,558513477,558513478,24461671,24461655,916599754,916599755,24461684]);assert.deepEqual(identity.excludedSidingWayIDs,[733698881,916599756]);
 const osm=read(identity.osmSourcePath),sections=read(identity.n02SourcePath);assert.equal(osm.fetchedAt,identity.fetchedAt,'Omura source identity changed');
 for(const w of [...identity.mainWays,...identity.excludedSidings]){assert.deepEqual(osm.elements.find(x=>x.id===w.id),w,'Omura source identity changed');assert.deepEqual([w.tags.name,w.tags.operator,w.tags.railway,w.tags.source],['JR大村線','九州旅客鉄道','rail','KSJ2'],'Omura source identity changed');assert.equal(w.tags.service,identity.excludedSidingWayIDs.includes(w.id)?'siding':undefined,'Omura source identity changed');}
 for(const r of identity.n02Records){assert.deepEqual(sections.features[r.featureIndex],r.feature,'Omura source identity changed');assert.deepEqual([r.feature.properties.N02_003,r.feature.properties.N02_004],['大村線','九州旅客鉄道'],'Omura source identity changed');}
}
function proposedLine(e){
 assert.equal(e.format,'jtm-omura-own-display-evidence-v1');assert.equal(e.lineID,LINE);validateSources(e);
 const p=read(path.join(PROPOSAL,'complete-bounded-pixel-proposal.json')),frozen=read(path.join(PROPOSAL,'compact-source-freeze.json')),anchors=read(path.join(PROPOSAL,'measured-station-anchors.json'));
 assert.deepEqual(e.baselineLine,frozen.compactLine,'Omura baseline changed');assert.equal(hash(JSON.stringify(e.baselineLine)),e.baselineOwnLineSha256,'Omura baseline changed');
 assert.deepEqual(e.combinedFit,p.combinedFit,'Omura fit authority changed');assert.equal(hash(JSON.stringify(p.combinedFit)),e.proposalAuthoritySha256,'Omura fit authority changed');
 const chain=e.combinedFit.coordinates,ordered=e.combinedFit.supportsInForwardOrder;assert.equal(chain.length,105);assert.deepEqual(chain,ordered.map(s=>s.coordinate),'Omura forward authority changed');assert(chain.every(q=>q.length===2&&q.every(Number.isFinite)),'Omura invalid support');
 // Forward order is frozen image authority. The real coast reverses longitude.
 assert.deepEqual(e.combinedFit.stationSplitIndices,{'009583':51,'009584':78});assert.deepEqual(e.baselineLine.stations.slice(0,4).map(s=>s[0]),['009568','009583','009584','009596']);
 const viewSet=new Set(expectedViews());for(const s of ordered){assert(viewSet.has(s.viewPath),'Omura support lacks immutable native witness');const v=read(s.viewPath);assert(near(invert(s.pixel,v),s.coordinate),'Omura support projection changed: '+s.id);}
 const aliases={};for(const s of anchors.stations){
  const v=read(s.viewPath),pts=s.manuallyIdentifiedTickedOwnRailPointsPixels,mx=pts.reduce((a,p)=>a+p[0],0)/pts.length,my=pts.reduce((a,p)=>a+p[1],0)/pts.length;
  const slope=pts.reduce((a,p)=>a+(p[0]-mx)*(p[1]-my),0)/pts.reduce((a,p)=>a+(p[0]-mx)**2,0),intercept=my-slope*mx;
  const caps=s.wholePassengerLongitudinalCapLineWitnessesPixels.map(line=>[0,1].map(k=>(line[0][k]+line[1][k])/2)),mid=[0,1].map(k=>(caps[0][k]+caps[1][k])/2),x=(mid[0]+slope*(mid[1]-intercept))/(1+slope*slope),pixel=[x,slope*x+intercept];
  assert(near(pixel,s.normalProjectedMidpointPixels)&&near(invert(pixel,v),s.proposedDisplayCoordinate),'Omura station cap derivation changed');aliases[s.stationID]=s.proposedDisplayCoordinate;
 }
 assert.deepEqual(aliases,e.anchorCoordinates,'Omura station authority changed');assert.deepEqual(Object.keys(aliases),['009583','009584']);assert.deepEqual(chain[51],aliases['009583']);assert.deepEqual(chain[78],aliases['009584']);
 const old=net.decodeIntervals(e.baselineLine);assert.deepEqual(old.slice(0,3).map(p=>p.length),[83,20,87]);
 for(const [n,g]of e.guards.entries()){
  const interval=n===0?0:2,index=n===0?41:15,authority=p.guards[n===0?'north':'south'];assert.equal(g.intervalIndex,interval);assert.deepEqual(g.refinedGuard,authority.refinedGuard,'Omura guard authority changed');assert.deepEqual(g.literalTrace,authority.literalTrace,'Omura literal guard authority changed');assert.equal(g.viewPath,authority.viewPath,'Omura guard view changed');assert.equal(g.refinedGuard.oldEdgeIndex,index);
  const t=g.refinedGuard.edgeT,[a,b]=old[interval].slice(index,index+2).map(world),q=world(g.refinedGuard.coordinate);assert(t>0&&t<1&&q.every((v,k)=>Math.abs(v-(a[k]+t*(b[k]-a[k])))<1e-5),'Omura guard left unchanged old edge');
  const v=read(g.viewPath);assert(near(invert(g.refinedGuard.pixel,v),g.refinedGuard.coordinate),'Omura guard projection changed');const ne=g.nativeDisplayEdge,saved=v.renderedDisplay[ne.partIndex].slice(ne.edgeIndex,ne.edgeIndex+2);assert.deepEqual(saved,ne.coordinates,'Omura saved native edge changed');assert(saved.every((p,i)=>near(p,old[interval][index+i])),'Omura guard native/source edge changed');
  assert(g.literalTrace.pixels.length>=35&&g.literalTrace.maxAxisResidualPixels<3&&g.refinedGuard.distanceToCurrentSmoothedCurvePixels<2&&g.refinedGuard.currentSmoothedTangentMismatchDegrees<7,'Omura guard lacks literal/smoothed witness');
 }
 assert.deepEqual([chain[0],chain.at(-1)],e.guards.map(g=>g.refinedGuard.coordinate));
 const intervals={0:[...old[0].slice(0,42),...chain.slice(0,52)],1:chain.slice(51,79),2:[...chain.slice(78),...old[2].slice(16)]};assert.deepEqual(intervals,e.expectedIntervals,'Omura retained outer tails changed');
 assert.equal(e.status,'bounded-own-rail-fit-and-two-station-display-repair; whole-line-open','Omura bounded provenance status changed');const line={...structuredClone(e.baselineLine),displayStationCoordinates:aliases,displayIntervalCoordinates:intervals};validateNativeCandidate(line,e);return line;
}
function validateNativeCandidate(line,e){
 const review=e.nativeCandidateReview;assert(review&&review.sources?.length===39,'Omura native candidate review missing');
 assert.equal(hash(JSON.stringify(line)),review.reviewedOwnLineSha256,'Omura native reviewed own line changed');
 const groups=[['omura-own-candidate-v2-complete-intervals0-2-20261020',[[0,12,0],[0,13,0],[0,14,0],[1,0,1],[1,1,1],[1,2,1],[1,3,1]],8],['omura-own-candidate-v2-station-caps-z20-wide-20261020',[[0,0,1],[1,0,2]],1],['omura-own-candidate-v2-changed-collar-z19-20261020',[[0,40,0],[0,41,0],[1,0,1],[1,1,1]],2]];
 const dependencies=['eb426be469674e4a50b0ef2b345970c48785151a297c18984da28f59cab53f19','329be417aa974f4ed291b64650d8ac1e768c01dd67a00197a9e59e11ab025802','30084e5f3ee82072612b05331bafbb50706977eb49587ccdc303aeb3894af2e1'];
 const views=groups.flatMap(([session,slots,basis])=>slots.map(([slot,n,i])=>({path:path.join(EV,'diagnostics/sessions',session,'alignment/captures',String(slot).padStart(6,'0'),String(n).padStart(6,'0'),'view.json'),i,n,basis})));
 assert.deepEqual(review.sources.map(s=>s.path),views.flatMap(v=>['basemap.png','smooth.png','view.json'].map(f=>path.join(path.dirname(v.path),f))),'Omura native review paths changed');
 for(const source of review.sources)assert.equal(hash(fs.readFileSync(source.path)),source.sha256,'Omura native review source bytes changed');
 assert.deepEqual(review.groups.map(g=>g.session),groups.map(g=>g[0]),'Omura native review groups changed');
 const witnesses=review.groups.flatMap(g=>g.views);assert.deepEqual(witnesses.map(w=>w.path),views.map(w=>w.path),'Omura native review witness set changed');
 for(const [n,w]of views.entries()){const v=read(w.path),frozen=witnesses[n],groupIndex=groups.findIndex(g=>w.path.includes('/'+g[0]+'/'));assert.equal(v.wholeLineRenderDependency,dependencies[groupIndex],'Omura native reviewed render dependency changed');assert.equal(v.wholeLineRenderDependency,frozen.wholeLineRenderDependency,'Omura native reviewed render dependency changed');assert.equal(v.renderContract,frozen.renderContract,'Omura native reviewed render contract changed');assert.deepEqual(v.snapshotProjection,frozen.snapshotProjection,'Omura native reviewed projection changed');assert.deepEqual([v.lineID,v.intervalIndex,v.fromStationID,v.toStationID,v.pointOrdinal],[LINE,w.i,line.stations[w.i][0],line.stations[w.i+1][0],w.n],'Omura native reviewed identity changed');assert(v.camera.heading===0&&v.camera.pitch===0&&v.snapshotProjection.displayScale===1&&Math.abs(v.snapshotProjection.mapPointsPerPointX-w.basis)<1e-8&&Math.abs(v.snapshotProjection.mapPointsPerPointY-w.basis)<1e-8,'Omura native reviewed projection changed');}
}
export function repairPackage(input,e=evidence()){
 const proposed=proposedLine(e),indices=input.lines.flatMap((l,i)=>l.id===LINE?[i]:[]);assert.equal(indices.length,1);assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],proposed),'Omura baseline changed');assert.match(input.geometrySource.license,/OpenStreetMap.*ODbL/i);
 const provenance={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,stationIDs:['009583','009584'],intervalIndices:[0,1,2],policy:e.policy,evidence:path.relative(REPO,EVIDENCE_PATH),script:'app/scripts/railway/repair-omura-own-display.mjs',physicalTopologyChanged:false,wholeLineAccepted:false};
 const previous=input.geometrySource.manualOverrides?.[KEY];assert(previous===undefined||equal(previous,provenance),'Omura provenance changed');const result=structuredClone(input);result.lines[indices[0]]=proposed;result.geometrySource.manualOverrides??={};result.geometrySource.manualOverrides[KEY]=provenance;return result;
}
export function ownReferences(input){
 const rows=Object.fromEntries(ROW_KEYS.map(k=>[k,(input[k]?.jp||[]).filter(r=>r[0]===LINE||k==='followsByRegion'&&r[4]===LINE)]));rows.loopsByRegion=(input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE));rows.reversedLoopParts=(input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#'));rows.hubMembers=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));return rows;
}
export function repairParts(pkg,input,e=evidence()){
 const line=pkg.lines.find(l=>l.id===LINE);assert.deepEqual(line,proposedLine(e));const stations=line.stations.map(r=>line.displayStationCoordinates[r[0]]?[...r.slice(0,2),...line.displayStationCoordinates[r[0]],...r.slice(4)]:r),intervals=net.decodeIntervals({...line,stations});Object.assign(intervals,line.displayIntervalCoordinates);
 const rows=partRowsForLine(line,net.displayPartsForLine(line),{stations,intervals},null);assert.deepEqual(rows,e.candidateNativeRows,'Omura native ruler changed');assert.equal(rows.length,1);const lane=[[LINE,0,0,rows[0][5],.5]];assert.deepEqual(lane,e.candidateLaneRows,'Omura lane ruler changed');assert.deepEqual(e.baselineRows.byRegion,[[LINE,0,0,47788.3,.5]],'Omura baseline lane changed');
 for(const[key,actual]of Object.entries(ownReferences(input))){const next=key==='partsByRegion'?rows:key==='byRegion'?lane:null;assert(equal(actual,e.baselineRows[key])||next&&equal(actual,next),'Omura reference changed: '+key);}
 assert.deepEqual(Object.keys(e.ownMaps),['colorByRegion','renderGroupByRegion','renderGroupPolicyByRegion'],'Omura own map scope changed');for(const[key,value]of Object.entries(e.ownMaps))assert.deepEqual(input[key]?.jp?.[LINE]??null,value,'Omura reference changed: '+key);assert(!(input.excludedOperators||[]).includes(line.operator)&&!(input.excludedLineIds||[]).includes(LINE),'Omura exclusion changed');const result=structuredClone(input);result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows[0]:r);result.byRegion.jp=result.byRegion.jp.map(r=>r[0]===LINE?lane[0]:r);return result;
}
export function validateExternalReferences(actual,e=evidence()){assert.deepEqual(actual,e.baselineExternalReferences,'Omura external reference changed');}
function externalReferences(shared,releases,junctions){return {corridors:shared.corridors.filter(r=>(r.lineIds||[]).includes(LINE)||(r.members||[]).some(m=>m.lineId===LINE)),displayLandlords:shared.displayLandlords.filter(r=>r.tenantLineId===LINE||r.landlordLineId===LINE||(r.tenantLineIds||[]).includes(LINE)||(r.landlordLineIds||[]).includes(LINE)),excludedLineIds:(shared.displayLanePolicy.excludedLineIds||[]).filter(id=>id===LINE),releases:releases.releases.filter(r=>r.lineId===LINE),junctions:junctions.junctions.filter(r=>r.lineIDs?.includes(LINE))};}
function main(args){
 const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;assert(candidate||equal(args,['--apply']),'Use --candidate-root <canonical local candidates directory> or --apply');if(candidate){assertAllowedCandidateDirectory(candidate);assert(candidate.startsWith(path.join(EV,'candidates')+path.sep),'Omura candidate must use canonical evidence tree');}
 const evidenceInput={path:EVIDENCE_PATH,before:fs.readFileSync(EVIDENCE_PATH)},e=JSON.parse(evidenceInput.before),paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
 const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(APP,p),before:fs.readFileSync(path.join(APP,p))}]));
 const inputs=[evidenceInput,...[...e.sources.map(s=>s.path),...e.nativeCandidateReview.sources.map(s=>s.path),...e.inputCodeSources.map(s=>s.path),e.sourceIdentity.osmSourcePath,e.sourceIdentity.n02SourcePath,...e.externalPaths.map(p=>path.join(APP,p))].map(p=>({path:p,before:fs.readFileSync(p)}))];
 const frozen=p=>JSON.parse(inputs.find(i=>i.path===path.join(APP,p)).before);validateExternalReferences(externalReferences(...e.externalPaths.map(frozen)),e);
 const load=k=>JSON.parse(snapshots[k].before),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e),deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
 const line=pkg.lines.find(l=>l.id===LINE),receipt={mode:candidate?'candidate':'applied',candidateRoot:candidate,lineID:LINE,ownLineSha256:hash(JSON.stringify(line)),intervalCounts:[0,1,2].map(i=>line.displayIntervalCoordinates[i].length),nativeRows:lanes.partsByRegion.jp.filter(r=>r[0]===LINE).map(r=>r.slice(0,7)),nativeLaneRows:lanes.byRegion.jp.filter(r=>r[0]===LINE),status:e.status,physicalTopologyChanged:false,newV2ViewPairsActuallyReviewed:13,newV2OriginalPNGsActuallyReviewed:26,nativeCandidateReview:'bounded native review complete; unchanged V1 bodies reused',mainFinalCheck:'pending separate Main review',applyAvailable:true,inputSnapshots:Object.values(snapshots).map(s=>({path:s.path,sha256:hash(s.before)})),immutableAuthorityFiles:e.sources.length};
 const outputs={...Object.fromEntries(Object.entries({package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))}).map(([k,after])=>[path.basename(snapshots[k].path),after])),'omura-candidate-receipt.json':JSON.stringify(receipt,null,2)+'\n'};
 let writes;
 if(candidate){fs.mkdirSync(candidate,{recursive:true});assertAllowedCandidateDirectory(candidate);writes=Object.entries(outputs).map(([name,after])=>{const destination=path.join(candidate,name);assert(!fs.existsSync(destination)||!fs.lstatSync(destination).isSymbolicLink(),'Omura candidate output cannot be symlink');if(!fs.existsSync(destination))fs.writeFileSync(destination,'');return {path:destination,before:fs.readFileSync(destination),after:Buffer.from(after)};});}
 else writes=Object.entries({package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))}).map(([k,after])=>({...snapshots[k],after:Buffer.from(after)}));
 applyPreparedWrites(writes,[...Object.values(snapshots),...inputs,...(candidate?writes.map(({path,before})=>({path,before})):[])]);console.log(JSON.stringify(receipt));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
