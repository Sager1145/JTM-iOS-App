import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {repairPackage,repairParts,validateExternalReferences} from '../repair-kyudai-kurume-display.mjs';
const network=createRequire(import.meta.url)('../../../public/rail-network.js');
const e=JSON.parse(fs.readFileSync(new URL('../kyudai-kurume-display-evidence.json',import.meta.url)));
const pkg={lines:[e.baselineLine,{id:'unrelated',stations:[],segments:[]}],geometrySource:{manualOverrides:{unrelated:{preserved:true}}}};
const lanes=()=>Object.fromEntries(Object.entries(e.baselineRows).filter(([k])=>k!=='hubMembers').map(([k,v])=>[k,{jp:structuredClone(v)}]));
test('Kyudai new station repartitions both display intervals forward and preserves physical graph and outer guards',()=>{
 const result=repairPackage(pkg,e),line=result.lines[0],alias=e.stationTrackRepair.coordinate;
 assert.deepEqual(line.displayStationCoordinates?.['009398'],alias,'old station remains west of own frame');
 assert.deepEqual(line.displayIntervalCoordinates[32].at(-1),alias);assert.deepEqual(line.displayIntervalCoordinates[33][0],alias);
 const chain=[...line.displayIntervalCoordinates[32],...line.displayIntervalCoordinates[33].slice(1)];
 assert(network.displayPartsForLine(line).flat().some(p=>p[0]===alias[0]&&p[1]===alias[1]),'production grooming dropped station alias');
 assert(!chain.some(p=>p[0]===130.54763),'removed preexisting short control was restored');
 assert(chain.every((p,i)=>i===0||chain[i-1][0]>p[0]),'alias replacement caused backward overlap');
 const oldWestLongitude=130.54802;
 assert(line.displayIntervalCoordinates[33].some(p=>Math.abs(p[0]-oldWestLongitude)<1e-10),'former #32 western supports not transferred to #33');
 assert.deepEqual(line.stations,e.baselineLine.stations);assert.deepEqual(line.segments,e.baselineLine.segments);
 assert.deepEqual(network.decodeIntervals(line),network.decodeIntervals(e.baselineLine));
 assert.deepEqual(line.displayIntervalCoordinates[32][0],e.baselineLine.stations[32].slice(2,4));assert.deepEqual(line.displayIntervalCoordinates[33].at(-1),e.baselineLine.stations[34].slice(2,4));
 assert.deepEqual(Object.keys(line.displayIntervalCoordinates),['32','33']);assert.deepEqual(result.lines[1],pkg.lines[1]);assert.deepEqual(result.geometrySource.manualOverrides.unrelated,{preserved:true});assert.deepEqual(repairPackage(result,e),result);
});
test('Kyudai refuses changed station projection, source evidence and baseline rather than adopting stale coordinates',()=>{
 for(const mutate of [x=>x.stationTrackRepair.coordinate[1]+=.00002,x=>x.appleSources[0].sha256='wrong',x=>x.n02Source.records[0].feature.properties.N02_003='other',x=>x.osmSource.elements[0].tags.operator='other']){
  const bad=structuredClone(e);mutate(bad);assert.throws(()=>repairPackage(pkg,bad),/projection|source|identity/);
 }
 const bad=structuredClone(pkg);bad.lines[0].segments[32][0]+=1;assert.throws(()=>repairPackage(bad,e),/baseline/);
 const badRefs=structuredClone(e.baselineExternalDisplayReferences);badRefs.releases.push({changed:true});assert.throws(()=>validateExternalReferences(badRefs,e),/external reference/);
});
test('Kyudai native rows rebuild from real display helpers and preserve all unrelated metadata',()=>{
 const repaired=repairPackage(pkg,e),input=lanes(),other=['unrelated',0,0,0,2,100,null,null,[]];input.partsByRegion.jp.push(other);
 const output=repairParts(repaired,input,e);assert.deepEqual(output.partsByRegion.jp.at(-1),other);assert.notDeepEqual(output.partsByRegion.jp[0],e.baselineRows.partsByRegion[0]);
 for(const key of Object.keys(e.baselineRows).filter(k=>k!=='partsByRegion'&&k!=='byRegion'&&k!=='hubMembers'))assert.deepEqual(output[key],input[key]);
 assert.deepEqual(repairParts(repaired,output,e),output);
 const changed=lanes();changed.followsByRegion.jp.push(['other',0,0,10,e.lineID,0,0,10]);assert.throws(()=>repairParts(repaired,changed,e),/reference/);
});

test('Kyudai whole-part lane covers the rebuilt endpoint and preserves lane minus one and unrelated rows',()=>{
 const repaired=repairPackage(pkg,e),input=lanes(),other=['unrelated',0,0,456,-2];input.byRegion.jp.push(other);
 const result=repairParts(repaired,input,e),part=result.partsByRegion.jp.find(r=>r[0]===e.lineID),lane=result.byRegion.jp.find(r=>r[0]===e.lineID);
 assert.equal(lane[3],part[5],'final rebuilt metres fall outside lane minus one coverage');
 assert.deepEqual([lane[0],lane[1],lane[2],lane[4]],[e.lineID,0,0,-1]);assert.deepEqual(result.byRegion.jp.at(-1),other);
 assert.deepEqual(repairParts(repaired,result,e),result);
 const changed=lanes();changed.byRegion.jp[0][4]=0;assert.throws(()=>repairParts(repaired,changed,e),/reference/);
});

test('Kyudai refuses altered or missing reviewed native replay evidence',()=>{
 for(const missing of [false,true]){
  const bad=structuredClone(e),source=bad.nativeCandidateReview.candidatePairs[0].sources[0];
  if(missing)source.path='/private/tmp/jtm-kyudai-missing-native-replay-view.json';else source.sha256='wrong';
  assert.throws(()=>repairPackage(pkg,bad),missing?/ENOENT/:/source bytes changed/);
 }
 const bad=structuredClone(e);bad.nativeCandidateReview.stationZ20Sources[1].sha256='wrong';assert.throws(()=>repairPackage(pkg,bad),/source bytes changed/);
});
