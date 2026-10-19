import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {repairPackage,repairParts} from '../repair-miyazu-yosano-display.mjs';
const network=createRequire(import.meta.url)('../../../public/rail-network.js');
const e=JSON.parse(fs.readFileSync(new URL('../miyazu-yosano-display-evidence.json',import.meta.url)));
const other={id:'unrelated',stations:[],segments:[],userChange:'retain'};
const pkg=()=>({lines:[e.baselineLine,other],geometrySource:{license:'OpenStreetMap ODbL',manualOverrides:{unrelated:{retain:true}}}});
const lanes=()=>({partsByRegion:{jp:[e.baselineNativeRow,['unrelated',0,0,0,2,100]]},byRegion:{jp:[['unrelated',0,0,100,0.5]]},followsByRegion:{jp:[]},familyWindowsByRegion:{jp:[]},hubReportByRegion:{jp:[]}});
test('Yosano dip uses own passenger curve while physical data and all outside controls stay exact',()=>{
 const before=pkg(),after=repairPackage(before),line=after.lines[0],old=e.fragment.oldDecodedInterval,candidate=line.displayIntervalCoordinates[9];
 assert.deepEqual(candidate,e.fragment.candidateDecodedInterval);
 assert.deepEqual(candidate.slice(0,3),old.slice(0,3));assert.deepEqual(candidate.slice(14),old.slice(10));
 assert.deepEqual(line.stations,e.baselineLine.stations);assert.deepEqual(line.segments,e.baselineLine.segments);
 assert.deepEqual(Object.keys(line.displayIntervalCoordinates),['9','15']);assert.deepEqual(after.lines[1],other);
 assert.deepEqual(after.geometrySource.manualOverrides.unrelated,{retain:true});assert.deepEqual(repairPackage(after),after);
 assert.deepEqual(before,pkg());
});
test('native plain part uses display intervals and changes only its actual count/ruler',()=>{
 const repaired=repairPackage(pkg()),before=lanes(),after=repairParts(repaired,before);
 assert.deepEqual(after.partsByRegion.jp[0],[e.lineID,0,0,17,1568,83936.6,null,null,[]]);
 assert.deepEqual(after.partsByRegion.jp[1],before.partsByRegion.jp[1]);
 for(const key of ['byRegion','followsByRegion','familyWindowsByRegion','hubReportByRegion'])assert.deepEqual(after[key],before[key]);
 const line=repaired.lines[0],displayed={...line,segments:line.segments.map((s,i)=>line.displayIntervalCoordinates[i]?[s[0],0,line.displayIntervalCoordinates[i]]:s)};
 const intervals=network.decodeIntervals(displayed),plain=[...intervals[0],...intervals.slice(1).flatMap(a=>a.slice(1))];
 assert.deepEqual(plain,network.displayPartsForLine(line)[0]);assert.deepEqual(repairParts(repaired,after),after);
});
test('changed physical baseline, archive bytes, projected guards and own measured dependencies are rejected',()=>{
 const changed=pkg();changed.lines[0]=structuredClone(changed.lines[0]);changed.lines[0].segments[9][0]+=0.1;
 assert.throws(()=>repairPackage(changed),/baseline/);
 const badSource=structuredClone(e);badSource.source.sha256='0'.repeat(64);assert.throws(()=>repairPackage(pkg(),badSource),/source bytes/);
 const badRoute=structuredClone(e);badRoute.fragment.sourceRoute.version+=1;assert.throws(()=>repairPackage(pkg(),badRoute),/passenger route/);
 const badGuard=structuredClone(e);badGuard.fragment.window.projectedBoundaries[0].point[1]+=0.00001;assert.throws(()=>repairPackage(pkg(),badGuard),/projection/);
 const stale=lanes();stale.followsByRegion.jp.push(['other',0,0,100,e.lineID,0,100,200]);assert.throws(()=>repairParts(repairPackage(pkg()),stale),/follows/);
 for(const [key,value]of [['loopsByRegion',{id:'new-loop',lineIds:[e.lineID]}],['reversedLoopParts',e.lineID+'#0'],['strokeExcludedByRegion',[e.lineID,'new-exclusion']],['chainBoundariesByRegion',[e.lineID,0,1,'new-boundary']]]){
  const changed=lanes();changed[key]={jp:[value]};assert.throws(()=>repairParts(repairPackage(pkg()),changed),new RegExp(key));
 }
 const hub=lanes();hub.hubReportByRegion.jp.push({hubId:'new',members:[{lineId:e.lineID,partIndex:0,from:100,to:200}]});assert.throws(()=>repairParts(repairPackage(pkg()),hub),/hub/);
});
test('Kabutoyama source upgrade preserves accepted Yosano and replaces only its own frozen passenger window',()=>{
 const baseline=repairPackage(pkg());delete baseline.lines[0].displayIntervalCoordinates[15];delete baseline.geometrySource.manualOverrides['miyazu-yosano-display'].interval15;
 const before=structuredClone(baseline),upgraded=repairPackage(baseline),line=upgraded.lines[0],f=e.fragment15;
 assert.deepEqual(line.displayIntervalCoordinates[15],f.candidateDecodedInterval);
 assert.deepEqual(line.displayIntervalCoordinates[9],e.fragment.candidateDecodedInterval);
 assert.deepEqual(line.displayIntervalCoordinates[15].slice(0,3),f.oldDecodedInterval.slice(0,3));
 assert.deepEqual(line.displayIntervalCoordinates[15].slice(28),f.oldDecodedInterval.slice(29));
 assert.deepEqual(line.stations,e.baselineLine.stations);assert.deepEqual(line.segments,e.baselineLine.segments);
 assert.deepEqual(repairPackage(upgraded),upgraded);assert.deepEqual(baseline,before);
 assert.equal(line.segments[15][0],2.326);
 assert(!line.displayIntervalCoordinates[15].some(p=>p[0]===134.91253&&p[1]===35.60474),'old south-bow control must be removed from display only');
 const currentParts=lanes();currentParts.partsByRegion.jp[0]=e.candidateNativeRow;
 const newParts=repairParts(upgraded,currentParts);
 assert.deepEqual(newParts.partsByRegion.jp[0],e.candidate15NativeRow);
 assert.deepEqual(newParts.partsByRegion.jp[1],currentParts.partsByRegion.jp[1]);
 function turn(a,b,c){const k=Math.cos(b[1]*Math.PI/180),u=[(b[0]-a[0])*k,b[1]-a[1]],v=[(c[0]-b[0])*k,c[1]-b[1]];return Math.acos(Math.max(-1,Math.min(1,(u[0]*v[0]+u[1]*v[1])/Math.hypot(...u)/Math.hypot(...v))))*180/Math.PI;}
 const curve=line.displayIntervalCoordinates[15];assert(turn(curve[2],curve[3],curve[4])<2.59);
 assert(turn(curve[26],curve[27],curve[28])<3.64);

 const badRoute=structuredClone(e);badRoute.fragment15.passengerRoutes[0].members[2].ref+=1;
 assert.throws(()=>repairPackage(pkg(),badRoute),/passenger/);
 const badNode=structuredClone(e);badNode.fragment15.sourceWays[1].nodes[0]+=1;
 assert.throws(()=>repairPackage(pkg(),badNode),/node/);
 const badBytes=structuredClone(e);badBytes.fragment15.sourceFiles[0].sha256='0'.repeat(64);
 assert.throws(()=>repairPackage(pkg(),badBytes),/source bytes/);
 const badBoundary=structuredClone(e);badBoundary.fragment15.window.after[0]+=0.00001;
 assert.throws(()=>repairPackage(pkg(),badBoundary),/outside guards/);
});
