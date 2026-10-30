import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {repairPackage,repairParts,validateExternalReferences} from '../repair-kitto-miyazaki-display.mjs';
const net=createRequire(import.meta.url)('../../../public/rail-network.js');
const e=JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/repair-inputs/kitto-miyazaki-display-evidence.json',import.meta.url)));
const proposal=JSON.parse(fs.readFileSync(e.proposalPath));
const pkg={lines:[e.baselineLine,{id:'unrelated',stations:[],segments:[]}],geometrySource:{license:'OpenStreetMap ODbL',manualOverrides:{unrelated:{preserved:true}}}};
function distance(point,chain){
 // Local plane centred at the independent measured point, avoiding longitude-scale drift.
 const scale=111320*Math.cos(point[1]*Math.PI/180),project=p=>[(p[0]-point[0])*scale,(p[1]-point[1])*111320];
 let best=Infinity;
 for(let i=1;i<chain.length;i++){const a=project(chain[i-1]),b=project(chain[i]),dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,-(a[0]*dx+a[1]*dy)/(dx*dx+dy*dy||1)));best=Math.min(best,Math.hypot(a[0]+t*dx,a[1]+t*dy));}
 return best;
}
const inner=proposal.manualOwnRailSupports.filter(p=>p.commonView16Pixel[0]>-220&&p.commonView16Pixel[0]<939).map(p=>p.coordinate);

test('Kitto crossing follows the measured lower railway instead of retaining the north bulge',()=>{
 const baseline=Math.max(...inner.map(p=>distance(p,net.decodeIntervals(e.baselineLine)[6])));
 assert(baseline>10,'fixture no longer reproduces the observed crossing displacement');
 const result=repairPackage(pkg,e),line=result.lines[0],display=line.displayIntervalCoordinates?.[6]??net.decodeIntervals(line)[6];
 const error=Math.max(...inner.map(p=>distance(p,display)));
 assert(error<1.5,`bounded own-rail supports still displaced by ${error.toFixed(2)}m`);
 assert.deepEqual(display.slice(0,30),e.oldDecodedInterval.slice(0,30));assert.deepEqual(display.slice(-19),e.oldDecodedInterval.slice(42));
 assert.deepEqual(line.stations,e.baselineLine.stations);assert.deepEqual(line.segments,e.baselineLine.segments);
 assert.deepEqual(net.decodeIntervals(line),net.decodeIntervals(e.baselineLine));assert.deepEqual(result.lines[1],pkg.lines[1]);
 assert.deepEqual(result.geometrySource.manualOverrides.unrelated,{preserved:true});assert.deepEqual(repairPackage(result,e),result);
});

const laneInput=()=>Object.fromEntries(Object.entries(e.baselineRows).filter(([k])=>k!=='hubMembers').map(([k,v])=>[k,{jp:structuredClone(v)}]));
test('Kitto refreshes the native part ruler without inventing lanes or changing unrelated rows',()=>{
 const input=laneInput(),other=['unrelated',0,0,0,2,100,null,null,[]];
 input.partsByRegion.jp.push(other);input.byRegion.jp.push(['unrelated',0,0,100,0]);
 const result=repairParts(repairPackage(pkg,e),input,e);
 assert.deepEqual(result.partsByRegion.jp,[[e.lineID,0,0,15,808,61687,null,null,[]],other]);
 for(const key of Object.keys(input).filter(k=>k!=='partsByRegion'))assert.deepEqual(result[key],input[key]);
 assert.deepEqual(repairParts(repairPackage(pkg,e),result,e),result);
 for(const [key,row]of [['byRegion',[e.lineID,0,0,1,0]],['followsByRegion',['other',0,0,1,e.lineID,0,0,1]],['loopsByRegion',{lineIds:[e.lineID]}],['reversedLoopParts',e.lineID+'#0']]){
  const bad=laneInput();bad[key].jp.push(row);assert.throws(()=>repairParts(repairPackage(pkg,e),bad,e),/reference changed/);
 }
});

test('Kitto refuses stale native evidence, changed physical inputs, and new own external references',()=>{
 const changed=structuredClone(pkg);changed.lines[0].segments[6][0]+=1;
 assert.throws(()=>repairPackage(changed,e),/baseline changed/);
 for(const index of [0,2,9,10]){
  const bad=structuredClone(e);bad.sources[index].sha256='changed';assert.throws(()=>repairPackage(pkg,bad),/source bytes changed/);
 }
 const missing=structuredClone(e);missing.sources[0].path+='.missing';assert.throws(()=>repairPackage(pkg,missing),/evidence paths changed/);
 const guard=structuredClone(e);guard.fragment[0][1]+=.0001;assert.throws(()=>repairPackage(pkg,guard));
 validateExternalReferences(e.baselineExternalReferences,e);
 for(const key of Object.keys(e.baselineExternalReferences)){
  const bad=structuredClone(e.baselineExternalReferences);bad[key].push({unexpected:true});assert.throws(()=>validateExternalReferences(bad,e),/external reference changed/);
 }
});

test('Kitto cannot apply a reviewed crossing after its candidate native proof drifts',()=>{
 const bad=structuredClone(e);bad.nativeCandidateReview.sources[0].sha256='stale';
 assert.throws(()=>repairPackage(pkg,bad),/native review source bytes changed/);
 const line=structuredClone(e);line.nativeCandidateReview.reviewedOwnLineSha256='stale';
 assert.throws(()=>repairPackage(pkg,line),/native reviewed own line changed/);
 const render=structuredClone(e);render.nativeCandidateReview.wholeLineRenderDependency='stale';
 assert.throws(()=>repairPackage(pkg,render),/native reviewed render dependency changed/);
});
