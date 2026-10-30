import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {repairPackage,repairParts,validateExternalReferences} from '../repair-misumi-own-display.mjs';
const net=createRequire(import.meta.url)('../../../public/rail-network.js');
const e=JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/repair-inputs/misumi-own-display-evidence.json',import.meta.url)));
const pkg={lines:[e.baselineLine,{id:'unrelated',stations:[],segments:[]}],geometrySource:{license:'OpenStreetMap ODbL',manualOverrides:{unrelated:{preserved:true}}}};
const laneInput=()=>({...Object.fromEntries(Object.entries(e.baselineRows).filter(([k])=>k!=='hubMembers').map(([k,v])=>[k,{jp:structuredClone(v)}])),...Object.fromEntries(Object.entries(e.ownMaps).map(([k,v])=>[k,{jp:v===null?{}:{[e.lineID]:v}}]))});
function distance(p,chain){const sx=111320*Math.cos(p[1]*Math.PI/180),xy=q=>[(q[0]-p[0])*sx,(q[1]-p[1])*111320];let best=Infinity;for(let i=1;i<chain.length;i++){const a=xy(chain[i-1]),b=xy(chain[i]),dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,-(a[0]*dx+a[1]*dy)/(dx*dx+dy*dy||1)));best=Math.min(best,Math.hypot(a[0]+t*dx,a[1]+t*dy));}return best;}

test('Misumi places both station aliases on measured own rail, fits the guarded body and retains the outer tails exactly',()=>{
 for(const [id,p]of Object.entries(e.anchorCoordinates)){const old=e.baselineLine.stations.find(r=>r[0]===id).slice(2,4);assert(distance(p,[old,old])>10,'baseline no longer reproduces displaced station');}
 const old=net.decodeIntervals(e.baselineLine),witness=e.combinedFit.supportsInForwardOrder.find(s=>s.id==='join-manual-013').coordinate;
 assert(distance(witness,old[0])>15,'baseline no longer reproduces body displacement');
 const result=repairPackage(pkg,e),line=result.lines[0];assert.deepEqual(line.displayStationCoordinates,e.anchorCoordinates);
 assert.deepEqual(line.displayIntervalCoordinates,e.expectedIntervals);assert(distance(witness,line.displayIntervalCoordinates[0])<.01);
 assert.deepEqual(line.displayIntervalCoordinates[0].slice(0,8),old[0].slice(0,8));assert.deepEqual(line.displayIntervalCoordinates[2].slice(-30),old[2].slice(26));
 for(const [i,id]of [[0,'009852'],[1,'009849']]){assert.deepEqual(line.displayIntervalCoordinates[i].at(-1),e.anchorCoordinates[id]);assert.deepEqual(line.displayIntervalCoordinates[i+1][0],e.anchorCoordinates[id]);}
 const joined=[...line.displayIntervalCoordinates[0].slice(8),...line.displayIntervalCoordinates[1].slice(1),...line.displayIntervalCoordinates[2].slice(1,-30)];assert(joined.every((p,i)=>i===0||joined[i-1][0]>p[0]),'station repartition backtracks');
 for(const p of Object.values(e.anchorCoordinates))assert(net.displayPartsForLine(line).flat().some(q=>Math.abs(q[0]-p[0])<1e-10&&Math.abs(q[1]-p[1])<1e-10),'production grooming lost station alias');
 const physical=structuredClone(line);delete physical.displayStationCoordinates;delete physical.displayIntervalCoordinates;assert.deepEqual(physical,e.baselineLine);
 assert.deepEqual(net.decodeIntervals(line),old);assert.deepEqual(result.lines[1],pkg.lines[1]);assert.deepEqual(result.geometrySource.manualOverrides.unrelated,{preserved:true});assert.deepEqual(repairPackage(result,e),result);
});

test('Misumi refreshes the native point count and ruler while preserving absence of own lane/follow rows',()=>{
 const input=laneInput(),other=['unrelated',0,0,0,2,100,null,null,[]];input.partsByRegion.jp.push(other);input.byRegion.jp.push(['unrelated',0,0,100,-1]);
 const repaired=repairPackage(pkg,e),result=repairParts(repaired,input,e);assert.deepEqual(result.partsByRegion.jp,[[e.lineID,0,0,7,362,25609.4,null,null,[]],other]);
 for(const key of Object.keys(input).filter(k=>k!=='partsByRegion'))assert.deepEqual(result[key],input[key]);assert.deepEqual(repairParts(repaired,result,e),result);
 for(const[key,row]of [['byRegion',[e.lineID,0,0,1,-1]],['followsByRegion',['other',0,0,1,e.lineID,0,0,1]],['loopsByRegion',{lineIds:[e.lineID]}]]){const bad=laneInput();bad[key].jp.push(row);assert.throws(()=>repairParts(repaired,bad,e),/reference changed/);}
});

test('Misumi refuses stale proposal/native originals and altered physical data or coordinate authority',()=>{
 for(const selector of [s=>s.path.endsWith('/misumi-guarded-fit-20261020.json'),s=>s.path.includes('label-bend-z19')&&s.path.endsWith('/basemap.png')]){const bad=structuredClone(e);bad.sources.find(selector).sha256='changed';assert.throws(()=>repairPackage(pkg,bad),/source bytes changed/);}
 const missing=structuredClone(e);missing.sources=missing.sources.filter(s=>!(s.path.includes('label-bend-z19')&&s.path.endsWith('/view.json')));assert.throws(()=>repairPackage(pkg,missing),/evidence input set changed/);
 const wrong=structuredClone(e);wrong.combinedFit.coordinates[3][1]+=.001;assert.throws(()=>repairPackage(pkg,wrong),/fit authority changed/);
 const physical=structuredClone(pkg);physical.lines[0].segments[0][0]+=.01;assert.throws(()=>repairPackage(physical,e),/baseline changed/);
});

test('Misumi guards own source identity, external junction references and absent per-line native maps',()=>{
 validateExternalReferences(e.baselineExternalReferences,e);const refs=structuredClone(e.baselineExternalReferences);refs.junctions[0].stationCode='wrong';assert.throws(()=>validateExternalReferences(refs,e),/external reference changed/);
 const source=structuredClone(e);source.osmSource.elements[0].tags.name='wrong';assert.throws(()=>repairPackage(pkg,source),/source identity changed/);
 const bad=laneInput();bad.colorByRegion.jp[e.lineID]='#ff0000';assert.throws(()=>repairParts(repairPackage(pkg,e),bad,e),/reference changed/);
});

test('Misumi refuses stale accepted candidate proof and a mismatched reviewed own line or render dependency',()=>{
 const stale=structuredClone(e);stale.nativeCandidateReview.sources[0].sha256='changed';
 assert.throws(()=>repairPackage(pkg,stale),/native review source bytes changed/);
 const line=structuredClone(e);line.nativeCandidateReview.reviewedOwnLineSha256='changed';
 assert.throws(()=>repairPackage(pkg,line),/native reviewed own line changed/);
 const render=structuredClone(e);render.nativeCandidateReview.wholeLineRenderDependency='changed';
 assert.throws(()=>repairPackage(pkg,render),/native reviewed render dependency changed/);
});
