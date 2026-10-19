import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {repairPackage,repairParts} from '../repair-watarase-hanawa-step-display.mjs';
const network=createRequire(import.meta.url)('../../../public/rail-network.js');
const e=JSON.parse(fs.readFileSync(new URL('../watarase-hanawa-step-display-evidence.json',import.meta.url)));
const pkg={lines:[e.baselineLine,{id:'unrelated',stations:[],segments:[]}],geometrySource:{license:'OpenStreetMap ODbL',manualOverrides:{unrelated:{preserved:true}}}};
const lanes=()=>Object.fromEntries(Object.entries(e.baselineRows).filter(([k])=>k!=='hubMembers').map(([k,v])=>[k,{jp:structuredClone(v)}]));
test('Hanawa removes only B vertex5 while retaining A, station guards and native groomed dependencies',()=>{
  const result=repairPackage(pkg,e),line=result.lines[0],expected=e.oldDecodedInterval.filter((_,i)=>i!==5);
  assert.deepEqual(line.displayIntervalCoordinates?.[8],expected,'B east shoulder remains');
  assert.deepEqual(line.displayIntervalCoordinates[8].slice(0,5),e.oldDecodedInterval.slice(0,5),'A or nearer-source v4 was changed');
  assert.deepEqual(line.displayIntervalCoordinates[8].slice(5),e.oldDecodedInterval.slice(6));
  assert.deepEqual(line.segments,e.baselineLine.segments);assert.deepEqual(line.stations,e.baselineLine.stations);
  assert.deepEqual(network.decodeIntervals(line),network.decodeIntervals(e.baselineLine));
  const unchanged=structuredClone(line);delete unchanged.displayIntervalCoordinates;assert.deepEqual(unchanged,e.baselineLine);
  assert.deepEqual(result.lines[1],pkg.lines[1]);assert.deepEqual(result.geometrySource.manualOverrides.unrelated,{preserved:true});assert.deepEqual(repairPackage(result,e),result);
  const input=lanes(),other=['unrelated',0,0,123,0];input.byRegion.jp.push(other);input.partsByRegion.jp.push(['unrelated',0,0,0,0,0]);
  const native=repairParts(result,input,e);assert.deepEqual(native.partsByRegion.jp,[...e.candidateNativeRows,input.partsByRegion.jp[1]]);assert.deepEqual(native.byRegion.jp,[[e.lineID,0,0,44208.5,-0.5],other]);assert.deepEqual(repairParts(result,native,e),native);
  const oldCoords=e.baselineRows.partsByRegion[0][7],newCoords=native.partsByRegion.jp[0][7],removed=oldCoords.findIndex(c=>c[0]===139.30941&&c[1]===36.52174);
  assert(removed>=0);assert.deepEqual(newCoords,oldCoords.filter((_,i)=>i!==removed),'native grooming changed beyond the one display point');
  assert.equal(native.partsByRegion.jp[0][6],'station-approach/groomed');
  for(const [key,row] of [['followsByRegion',[e.lineID,0,1,2,'other',0,1,2]],['followsByRegion',['other',0,1,2,e.lineID,0,1,2]],['familyWindowsByRegion',[e.lineID,0,1,2,0,'family']],['loopsByRegion',{lineIds:[e.lineID]}],['reversedLoopParts',e.lineID+'#0']]){const bad=lanes();bad[key].jp.push(row);assert.throws(()=>repairParts(result,bad,e),/reference changed/);}
  const changed=structuredClone(pkg);changed.lines[0].segments[8][0]+=1;assert.throws(()=>repairPackage(changed,e),/baseline changed/);
  const badEvidence=structuredClone(e);badEvidence.appleSources[0].sha256='changed';assert.throws(()=>repairPackage(pkg,badEvidence),/Apple source bytes changed/);
});
