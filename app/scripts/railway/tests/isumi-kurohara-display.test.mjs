import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {partRowsForLine} from '../build-display-lanes.mjs';
import {repairPackage,repairParts,assertExternalReferences} from '../repair-isumi-kurohara-display.mjs';
const network=createRequire(import.meta.url)('../../../public/rail-network.js');
const e=JSON.parse(fs.readFileSync(new URL('../isumi-kurohara-display-evidence.json',import.meta.url)));
const other={id:'unrelated',stations:[],segments:[],userChange:'keep'};
const pkg=()=>({lines:[structuredClone(e.baselineLine),other],geometrySource:{license:'OpenStreetMap ODbL',manualOverrides:{unrelated:{keep:true}}}});
const lanes=()=>({partsByRegion:{jp:[['unrelated',0,0,0,2,100]]},byRegion:{jp:[]},followsByRegion:{jp:[]},familyWindowsByRegion:{jp:[]},hubReportByRegion:{jp:[]},strokeExcludedByRegion:{jp:[[e.lineID,'substitute_bus']]},releasedIntervalsByRegion:{}});
test('Kurohara replaces only the frozen own display curve and preserves physical bus-service records',()=>{
 const before=pkg(),after=repairPackage(before),line=after.lines[0],old=e.fragment.oldDecodedCoordinates,candidate=line.displayIntervalCoordinates?.[10];
 assert.deepEqual(candidate,e.fragment.candidateDecodedCoordinates);
 assert.deepEqual(candidate.slice(0,13),old.slice(0,13));assert.deepEqual(candidate.slice(39),old.slice(35));
 assert.deepEqual(Object.keys(line.displayIntervalCoordinates),['10']);
 const physical={...line};delete physical.displayIntervalCoordinates;assert.deepEqual(physical,e.baselineLine);
 assert.equal(line.serviceStatus,'substitute_bus');assert.deepEqual(line.serviceSpans,[[0,13,2]]);
 assert.deepEqual(after.lines[1],other);assert.deepEqual(after.geometrySource.manualOverrides.unrelated,{keep:true});
 assert.deepEqual(repairPackage(after),after);assert.deepEqual(before,pkg());
});
test('existing native interface consumes the display fragment while the real excluded rows remain absent',()=>{
 const repaired=repairPackage(pkg()),line=repaired.lines[0],before=lanes(),after=repairParts(repaired,before);
 assert.deepEqual(after,before);assert.deepEqual(repairParts(repaired,after),after);
 const displayed={...line,segments:line.segments.map((s,i)=>line.displayIntervalCoordinates?.[i]?[s[0],0,line.displayIntervalCoordinates[i]]:s)};
 const intervals=network.decodeIntervals(displayed),parts=network.displayPartsForLine(line);
 assert.deepEqual(intervals[10],e.fragment.candidateDecodedCoordinates);
 assert.deepEqual(parts[0],[...intervals[0],...intervals.slice(1).flatMap(a=>a.slice(1))]);
 assert.deepEqual(partRowsForLine(line,parts,{stations:line.stations,intervals},null),[[e.lineID,0,0,12,592,26937.3,null,null,[]]]);
 assert(!after.partsByRegion.jp.some(r=>r[0]===e.lineID),'must not add a chain for a bus-substituted stroke');
});
test('stale own source/route/node/window/raw and actual measured reference dependencies are rejected',()=>{
 for(const change of [p=>{p.lines[0].segments[10][0]+=0.1;},p=>{p.lines[0].serviceStatus='operating';},p=>{p.lines[0].stations[10][0]='changed';}]){
  const input=pkg();change(input);assert.throws(()=>repairPackage(input),/baseline/);
 }
 for(const[change,pattern]of [
  [x=>{x.sourceFiles[0].sha256='0'.repeat(64);},/source bytes/],
  [x=>{x.passengerRoutes[0].members[1].ref+=1;},/passenger/],
  [x=>{x.sourceWays[1].nodes[0]+=1;},/node/],
  [x=>{x.fragment.window.outerGuards.after.coordinate[0]+=0.00001;},/outside guards/],
  [x=>{x.fragment.window.startProjection.point[0]+=0.00001;},/projection/],
  [x=>{x.rawSourceFeature.geometry.coordinates[20][0]+=0.00001;},/raw N02/]
 ]){const changed=structuredClone(e);change(changed);assert.throws(()=>repairPackage(pkg(),changed),pattern);}
 const repaired=repairPackage(pkg());
 for(const[key,value]of [
  ['partsByRegion',[e.lineID,0,0,12,588,26944.3,null,null,[]]],
  ['byRegion',[e.lineID,0,0,100,0.5]],
  ['followsByRegion',['other',0,0,100,e.lineID,0,100,200]],
  ['familyWindowsByRegion',[e.lineID,0,0,100,0,'new']],
  ['loopsByRegion',{id:'new',lineIds:[e.lineID]}],
  ['reversedLoopParts',e.lineID+'#0'],
  ['strokeExcludedByRegion',[e.lineID,'operating']],
  ['chainBoundariesByRegion',[e.lineID,0,1,'new']],
  ['releasedIntervalsByRegion',[e.lineID,10]]
 ]){const changed=lanes();changed[key]??={};changed[key].jp??=[];changed[key].jp.push(value);assert.throws(()=>repairParts(repaired,changed),new RegExp(key));}
 const external={sharedCorridors:{corridors:[],displayLandlords:[]},releases:{releases:[]},junctions:{junctions:[]}};
 assert.doesNotThrow(()=>assertExternalReferences(external));
 for(const [owner,key,value]of [['sharedCorridors','corridors',{lineIds:[e.lineID]}],['sharedCorridors','displayLandlords',{tenantLineId:'other',landlordLineId:e.lineID}],['releases','releases',{lineId:e.lineID,interval:10}],['junctions','junctions',{lineIDs:[e.lineID]}]]){const changed=structuredClone(external);changed[owner][key].push(value);assert.throws(()=>assertExternalReferences(changed),/reference changed/);}
 const hub=lanes();hub.hubReportByRegion.jp.push({hubId:'new',members:[{lineId:e.lineID,partIndex:0,from:10,to:20}]});assert.throws(()=>repairParts(repaired,hub),/hub/);
});
