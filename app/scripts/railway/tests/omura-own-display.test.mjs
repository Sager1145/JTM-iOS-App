import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {repairPackage,repairParts,validateExternalReferences} from '../repair-omura-own-display.mjs';
const net=createRequire(import.meta.url)('../../../public/rail-network.js');
const e=JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/repair-inputs/omura-own-display-evidence.json',import.meta.url)));
const pkg=()=>({lines:[structuredClone(e.baselineLine),{id:'unrelated',stations:[],segments:[]}],geometrySource:{license:'OpenStreetMap ODbL',manualOverrides:{unrelated:{preserved:true}}}});
const laneInput=()=>({...Object.fromEntries(Object.entries(e.baselineRows).filter(([k])=>k!=='hubMembers').map(([k,v])=>[k,{jp:structuredClone(v)}])),...Object.fromEntries(Object.entries(e.ownMaps).map(([k,v])=>[k,{jp:v===null?{}:{[e.lineID]:v}}]))});
function distance(p,chain){const sx=111320*Math.cos(p[1]*Math.PI/180),xy=q=>[(q[0]-p[0])*sx,(q[1]-p[1])*111320];let best=Infinity;for(let i=1;i<chain.length;i++){const a=xy(chain[i-1]),b=xy(chain[i]),dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,-(a[0]*dx+a[1]*dy)/(dx*dx+dy*dy||1)));best=Math.min(best,Math.hypot(a[0]+t*dx,a[1]+t*dy));}return best;}

test('Omura removes the witnessed coastal displacement and centers both graphic station anchors without changing physical rows or outer tails',()=>{
 const input=pkg(),old=net.decodeIntervals(e.baselineLine),witness=e.combinedFit.supportsInForwardOrder.find(s=>s.id==='approach-i2-p6-1200-756').coordinate;
 assert(distance(witness,old[2])>12,'baseline no longer reproduces image-witnessed offset');
 const result=repairPackage(input,e),line=result.lines[0],shown=line.displayIntervalCoordinates?.[2]||old[2];
 assert(distance(witness,shown)<.1,'corrected own-rail display still displaced at the actual pixel witness');
 for(const[id,p]of [['009583',[129.7960667886532,33.09243293479382]],['009584',[129.80127384789716,33.08694118402072]]]){
  const prior=e.baselineLine.stations.find(r=>r[0]===id).slice(2,4);assert(distance(p,[prior,prior])>10);assert.deepEqual(line.displayStationCoordinates[id],p);
  const n=id==='009583'?0:1;assert.deepEqual(line.displayIntervalCoordinates[n].at(-1),p);assert.deepEqual(line.displayIntervalCoordinates[n+1][0],p);
  assert(net.displayPartsForLine(line).flat().some(q=>Math.abs(q[0]-p[0])<1e-10&&Math.abs(q[1]-p[1])<1e-10),'grooming lost station alias');
 }
 assert.deepEqual(line.displayIntervalCoordinates[0].slice(0,42),old[0].slice(0,42));assert.deepEqual(line.displayIntervalCoordinates[2].slice(-71),old[2].slice(16));
 const physical=structuredClone(line);delete physical.displayStationCoordinates;delete physical.displayIntervalCoordinates;assert.deepEqual(physical,e.baselineLine);assert.deepEqual(net.decodeIntervals(line),old);
 assert.deepEqual(result.lines[1],input.lines[1]);assert.deepEqual(result.geometrySource.manualOverrides.unrelated,{preserved:true});assert.deepEqual(input,pkg());assert.deepEqual(repairPackage(result,e),result);
 const authority=e.combinedFit.coordinates;assert(authority.some((p,i)=>i>0&&p[0]<authority[i-1][0])&&authority.some((p,i)=>i>0&&p[0]>authority[i-1][0]),'real coastal longitude reversal missing');
});

test('Omura refreshes its fallback native ruler and full-part lane extent while preserving lane0.5 and unrelated references',()=>{
 const input=laneInput(),other=['unrelated',0,0,0,2,100,null,null,[]];input.partsByRegion.jp.push(other);input.byRegion.jp.push(['unrelated',0,0,100,-1]);
 const result=repairParts(repairPackage(pkg(),e),input,e),row=result.partsByRegion.jp[0];assert.deepEqual(row.slice(0,7),[e.lineID,0,-1,-1,939,47794.7,'station-approach/groomed']);
 assert.deepEqual(result.byRegion.jp,[[e.lineID,0,0,47794.7,.5],['unrelated',0,0,100,-1]]);assert.deepEqual(result.partsByRegion.jp[1],other);
 for(const k of Object.keys(input).filter(k=>!['partsByRegion','byRegion'].includes(k)))assert.deepEqual(result[k],input[k]);assert.deepEqual(repairParts(repairPackage(pkg(),e),result,e),result);
 const stale=laneInput();stale.byRegion.jp[0][4]=-.5;assert.throws(()=>repairParts(repairPackage(pkg(),e),stale,e),/reference changed/);
 const follow=laneInput();follow.followsByRegion.jp.push(['unrelated',0,0,1,e.lineID,0,0,1]);assert.throws(()=>repairParts(repairPackage(pkg(),e),follow,e),/reference changed/);
});

test('Omura refuses stale originals, altered authority/projections, source identity and physical inputs',()=>{
 for(const select of [s=>s.path.endsWith('/complete-bounded-pixel-proposal.json'),s=>s.path.endsWith('/basemap.png')]){const bad=structuredClone(e);bad.sources.find(select).sha256='stale';assert.throws(()=>repairPackage(pkg(),bad),/source bytes changed/);}
 const wrong=structuredClone(e);wrong.combinedFit.coordinates[5][0]+=.001;assert.throws(()=>repairPackage(pkg(),wrong),/fit authority changed/);
 const source=structuredClone(e);source.sourceIdentity.mainWays[0].tags.service='siding';assert.throws(()=>repairPackage(pkg(),source),/source identity changed/);
 const camera=structuredClone(e);camera.viewWitnesses[0].snapshotProjection.mapPointsPerPointX=8;assert.throws(()=>repairPackage(pkg(),camera),/projection changed/);
 const input=pkg();input.lines[0].segments[0][0]+=.1;assert.throws(()=>repairPackage(input,e),/baseline changed/);
});

test('Omura preserves shared ownership and rejects missing or stale native candidate proof',()=>{
 validateExternalReferences(e.baselineExternalReferences,e);const bad=structuredClone(e.baselineExternalReferences);bad.junctions[0].stationCode='wrong';assert.throws(()=>validateExternalReferences(bad,e),/external reference changed/);
 const absent=structuredClone(e);delete absent.nativeCandidateReview;assert.throws(()=>repairPackage(pkg(),absent),/native candidate review missing/);
 const stale=structuredClone(e);stale.nativeCandidateReview.reviewedOwnLineSha256='stale';assert.throws(()=>repairPackage(pkg(),stale),/native reviewed own line changed/);
 const pixels=structuredClone(e);pixels.nativeCandidateReview.sources[0].sha256='stale';assert.throws(()=>repairPackage(pkg(),pixels),/native review source bytes changed/);
 const contract=structuredClone(e);contract.nativeCandidateReview.groups[0].views[0].wholeLineRenderDependency='stale';assert.throws(()=>repairPackage(pkg(),contract),/native reviewed render dependency changed/);
});

// The original candidate accidentally selected a broad platform bar through an occlusion.
test('Omura station collar stays on the independently witnessed straight own rail through the roof occlusion',()=>{
 const line=repairPackage(pkg(),e).lines[0],axis=[[129.7957523132896,33.09290413800899],[129.79646873131747,33.09183675044088]];
 const collar=[...line.displayIntervalCoordinates[0],...line.displayIntervalCoordinates[1]].filter(p=>p[1]<=axis[0][1]&&p[1]>=axis[1][1]);
 assert(collar.length>=4);
 for(const p of collar)assert(distance(p,axis)<1,'HTB collar detours onto the blue platform/roof bar instead of continuing on its own rail');
});
