import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {repairPackage,repairParts,validateExternalReferences} from '../repair-joshin-own-display.mjs';
const network=createRequire(import.meta.url)('../../../public/rail-network.js');
const fullEvidence=JSON.parse(fs.readFileSync(new URL('../joshin-own-display-evidence.json',import.meta.url)));
const e=structuredClone(fullEvidence);delete e.stationTrackRepair;
const pkg={lines:[e.baselineLine,{id:'unrelated',stations:[],segments:[]}],geometrySource:{license:'OpenStreetMap ODbL',manualOverrides:{unrelated:{preserved:true}}}};
const lanes=()=>Object.fromEntries(Object.entries(e.baselineRows).filter(([k])=>k!=='hubMembers').map(([k,v])=>[k,{jp:structuredClone(v)}]));

test('Joshin removes only displayed interval4 middle sag, retaining both neighboring supports and physical inputs',()=>{
  const result=repairPackage(pkg,e),line=result.lines[0];
  assert.deepEqual(line.displayIntervalCoordinates?.[4],e.oldDecodedInterval.filter((_,i)=>i!==3),'isolated red middle sag remains');
  assert.deepEqual(line.displayIntervalCoordinates[4].slice(0,3),e.oldDecodedInterval.slice(0,3));
  assert.deepEqual(line.displayIntervalCoordinates[4][2],[139.02989,36.28422]);
  assert.deepEqual(line.displayIntervalCoordinates[4][3],[139.02995,36.28419]);
  assert.deepEqual(line.displayIntervalCoordinates[4].slice(3),e.oldDecodedInterval.slice(4));
  assert.deepEqual(network.decodeIntervals(line),network.decodeIntervals(e.baselineLine));
  const unchanged=structuredClone(line);delete unchanged.displayIntervalCoordinates;assert.deepEqual(unchanged,e.baselineLine);
  assert.deepEqual(result.lines[1],pkg.lines[1]);assert.deepEqual(result.geometrySource.manualOverrides.unrelated,{preserved:true});
  assert.deepEqual(repairPackage(result,e),result);
});

test('Joshin native ruler loses one display vertex and preserves absent lane plus unrelated rows',()=>{
  const result=repairPackage(pkg,e),input=lanes();
  const other=['unrelated',0,0,0,2,100,null,null,[]];input.partsByRegion.jp.push(other);input.byRegion.jp.push(['unrelated',0,0,100,0]);
  const native=repairParts(result,input,e);
  assert.deepEqual(native.partsByRegion.jp,[[e.lineID,0,0,19,736,33597.3,null,null,[]],other]);
  assert.deepEqual(native.byRegion,input.byRegion,'no lane row should be invented');
  assert.deepEqual(repairParts(result,native,e),native);
  for(const [key,row] of [['followsByRegion',[e.lineID,0,1,2,'other',0,1,2]],['followsByRegion',['other',0,1,2,e.lineID,0,1,2]],['byRegion',[e.lineID,0,0,12,0]],['loopsByRegion',{lineIds:[e.lineID]}],['reversedLoopParts',e.lineID+'#0']]){
    const bad=lanes();bad[key].jp.push(row);assert.throws(()=>repairParts(result,bad,e),/reference changed/);
  }
});

test('Joshin refuses changed source bytes, physical baseline, and own external references',()=>{
  const changed=structuredClone(pkg);changed.lines[0].segments[4][0]+=1;assert.throws(()=>repairPackage(changed,e),/baseline changed/);
  for(const source of ['appleSources','osmSource','rawFeature']){
    const bad=structuredClone(e);if(source==='appleSources')bad.appleSources[0].sha256='wrong';else bad[source].sha256='wrong';
    assert.throws(()=>repairPackage(pkg,bad),/source.*changed/);
  }
  const missing=structuredClone(e);missing.rawFeature.path='/private/tmp/jtm-joshin-source-does-not-exist.json';
  assert.throws(()=>repairPackage(pkg,missing),/ENOENT/,'missing raw evidence must not be replayed from the frozen line');
  const refs=structuredClone(e.baselineExternalDisplayReferences);validateExternalReferences(refs,e);
  for(const key of ['corridors','displayLandlords','excludedLineIds','releases','junctions']){
    const changed=structuredClone(refs);changed[key].push({unexpected:true});assert.throws(()=>validateExternalReferences(changed,e),/external reference changed/);
  }
});

// Actual station-frame/own-rail measurement; the legacy middle-only contract
// previously left this dot off the rail even while it was inside the frame.
function stationEvidence(){
  return structuredClone(fullEvidence);
}

test('Joshin station dot and both adjacent interval endpoints use the measured own rail while physical graph stays intact',()=>{
  const next=stationEvidence(),result=repairPackage(pkg,next),line=result.lines[0];
  assert.deepEqual(line.displayStationCoordinates?.['002445'],[139.02946008708466,36.28445546894988],'frame-inside station remains off the own rail');
  assert.deepEqual(line.displayIntervalCoordinates[3].at(-1),line.displayStationCoordinates['002445']);
  assert.deepEqual(line.displayIntervalCoordinates[4][0],line.displayStationCoordinates['002445']);
  assert.deepEqual(line.stations,e.baselineLine.stations);assert.deepEqual(line.segments,e.baselineLine.segments);
  assert.deepEqual(line.displayIntervalCoordinates[3][0],network.decodeIntervals(e.baselineLine)[3][0]);
  assert.deepEqual(line.displayIntervalCoordinates[4].at(-1),e.oldDecodedInterval.at(-1));
  assert.deepEqual(repairPackage(result,next),result);
});

test('Joshin station correction refuses altered or missing new native image evidence',()=>{
  for(const missing of [false,true]){
    const next=stationEvidence();if(missing)next.stationTrackRepair.sources[0].path='/private/tmp/jtm-joshin-missing-station-image';else next.stationTrackRepair.sources[0].sha256='wrong';
    assert.throws(()=>repairPackage(pkg,next),missing?/ENOENT/:/source.*changed/);
  }
  const offRail=stationEvidence();offRail.stationTrackRepair.coordinate[1]-=.00002;
  assert.throws(()=>repairPackage(pkg,offRail),/own-rail projection changed/);
});

test('Joshin native station slot follows the display anchor and preserves unresolved outer throats',()=>{
  const next=stationEvidence(),result=repairPackage(pkg,next),line=result.lines[0],native=repairParts(result,lanes(),next);
  assert.deepEqual(native.partsByRegion.jp,[[e.lineID,0,0,19,736,33594.5,null,null,[]]]);
  assert(network.displayPartsForLine(line).flat().some(p=>p[0]===139.02946008708466&&p[1]===36.28445546894988),'native chain dropped the moved station slot');
  assert.deepEqual(line.displayIntervalCoordinates[4].slice(-2),e.oldDecodedInterval.slice(-2));
  const bad=stationEvidence();bad.stationTrackRepair.intervals[4].at(-2)[0]+=.00001;
  assert.throws(()=>repairPackage(pkg,bad),/Yamana throat guards changed/);
});
