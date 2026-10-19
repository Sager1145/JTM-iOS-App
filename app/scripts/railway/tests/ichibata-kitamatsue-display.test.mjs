import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {repairPackage,repairParts} from '../repair-ichibata-kitamatsue-display.mjs';
const network=createRequire(import.meta.url)('../../../public/rail-network.js');
const e=JSON.parse(fs.readFileSync(new URL('../ichibata-kitamatsue-display-evidence.json',import.meta.url)));
const pkg={lines:[e.baselineLine,{id:'unrelated',stations:[],segments:[]}],geometrySource:{license:'OpenStreetMap ODbL',manualOverrides:{unrelated:{preserved:true}}}};
const lanes=()=>Object.fromEntries(Object.entries(e.baselineRows).filter(([k])=>k!=='hubMembers').map(([k,v])=>[k,{jp:structuredClone(v)}]));
test('Kitamatsue removes only three raw display stair lows, preserves real curve and rebases the self-follow suffix',()=>{
 const result=repairPackage(pkg,e),line=result.lines[0],expected=e.oldDecodedInterval.filter((_,i)=>![15,17,19].includes(i));
 assert.deepEqual(line.displayIntervalCoordinates?.[6],expected,'three isolated red stair lows remain');
 assert.deepEqual(line.displayIntervalCoordinates[6].slice(0,15),e.oldDecodedInterval.slice(0,15));
 assert.deepEqual(line.displayIntervalCoordinates[6].slice(17),e.oldDecodedInterval.slice(20),'retained southwest curve changed');
 assert.deepEqual(line.segments,e.baselineLine.segments);assert.deepEqual(line.stations,e.baselineLine.stations);assert.deepEqual(network.decodeIntervals(line),network.decodeIntervals(e.baselineLine));
 const unchanged=structuredClone(line);delete unchanged.displayIntervalCoordinates;assert.deepEqual(unchanged,e.baselineLine);
 assert.deepEqual(result.lines[1],pkg.lines[1]);assert.deepEqual(result.geometrySource.manualOverrides.unrelated,{preserved:true});assert.deepEqual(repairPackage(result,e),result);
 const input=lanes();input.partsByRegion.jp.push(['unrelated',0,0,0,0,0]);input.byRegion.jp.push(['unrelated',0,0,123,0]);
 const native=repairParts(result,input,e);assert.deepEqual(native.partsByRegion.jp,[...e.candidateNativeRows,input.partsByRegion.jp[2]]);assert.deepEqual(native.byRegion,input.byRegion);
 const old=e.baselineRows.partsByRegion[0][7],actual=native.partsByRegion.jp[0][7];assert.deepEqual(actual,old.filter(c=>![[132.92675,35.47012],[132.92665,35.47007],[132.92657,35.47004]].some(p=>p[0]===c[0]&&p[1]===c[1])));
 assert.deepEqual(native.partsByRegion.jp[1],e.baselineRows.partsByRegion[1]);
 assert.deepEqual(native.followsByRegion.jp,e.candidateFollowRows);assert(Math.abs(native.followsByRegion.jp[0][2]-16146.9)<0.1);assert.deepEqual(native.followsByRegion.jp[0].slice(4),e.baselineRows.followsByRegion[0].slice(4),'target part1 ruler changed');assert.deepEqual(repairParts(result,native,e),native);
 for(const [key,row]of[['followsByRegion',['other',0,1,2,e.lineID,0,1,2]],['followsByRegion',[e.lineID,0,1,2,'other',0,1,2]],['loopsByRegion',{lineIds:[e.lineID]}],['reversedLoopParts',e.lineID+'#0']]){const bad=lanes();bad[key].jp.push(row);assert.throws(()=>repairParts(result,bad,e),/reference changed/);}
 const changed=structuredClone(pkg);changed.lines[0].segments[6][0]+=1;assert.throws(()=>repairPackage(changed,e),/baseline changed/);
 const bad=structuredClone(e);bad.appleSources[0].sha256='changed';assert.throws(()=>repairPackage(pkg,bad),/Apple source bytes changed/);
});
