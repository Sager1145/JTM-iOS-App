import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { deriveOwnPair, repairPackage, repairParts } from '../repair-johoku-nakaotai-display.mjs';
import { partRowsForLine } from '../build-display-lanes.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const e = JSON.parse(fs.readFileSync(new URL('../johoku-nakaotai-display-evidence.json', import.meta.url)));
const pkg = { lines: [e.baselineLine, {id:'unrelated',stations:[],segments:[]}], geometrySource: {license:'OpenStreetMap ODbL',manualOverrides:{retained:{value:1}}} };
const laneFixture = () => Object.fromEntries(Object.entries(e.baselineRows).map(([key,rows])=>[key,{jp:structuredClone(rows)}]));
const turn = (a,b,c) => {
  const scale=Math.cos(b[1]*Math.PI/180), u=[(b[0]-a[0])*scale,b[1]-a[1]], v=[(c[0]-b[0])*scale,c[1]-b[1]];
  return Math.atan2(Math.abs(u[0]*v[1]-u[1]*v[0]),u[0]*v[0]+u[1]*v[1])*180/Math.PI;
};
test('own passenger-pair curve replaces only the interior window with exact physical and boundary guards', () => {
  const after=repairPackage(pkg), line=after.lines[0], coords=line.displayIntervalCoordinates[1];
  assert.deepEqual(coords,e.fragment.candidateDecodedInterval);
  assert.deepEqual(coords.slice(0,27),e.fragment.oldDecodedInterval.slice(0,27));
  assert.deepEqual(coords.slice(-5),e.fragment.oldDecodedInterval.slice(-5));
  assert.deepEqual(line.segments,e.baselineLine.segments);
  assert.deepEqual(line.stations,e.baselineLine.stations);
  assert.equal(line.displayStationCoordinates,undefined);
  assert.deepEqual(network.decodeIntervals(line),network.decodeIntervals(e.baselineLine));
  assert.deepEqual(after.lines[1],pkg.lines[1]);
  assert.deepEqual(after.geometrySource.manualOverrides.retained,{value:1});
  assert.deepEqual(repairPackage(after),after);
  const section=[coords[25],...e.fragment.replacementCoordinates,coords.at(-4)];
  assert(Math.max(...section.slice(1,-1).map((p,i)=>turn(section[i],p,section[i+2])))<2.21);
  assert(!coords.some(p=>JSON.stringify(p)===JSON.stringify([136.87427,35.21849])),'old northward chord support retained');
});
test('reproducible paired supports require both explicit opposite passenger routes and frozen source bytes', () => {
  assert.deepEqual(deriveOwnPair(e).replacement,e.fragment.replacementCoordinates);
  const texts=structuredClone(e.sourceFiles);
  texts['way-58218285-full.json']+=' ';
  assert.throws(()=>deriveOwnPair(e,texts),/source bytes changed/);
  const changed=structuredClone(e), relations=JSON.parse(changed.sourceFiles['way-768955042-relations.json']);
  relations.elements.find(r=>r.id===11728762).tags.route='railway';
  changed.sourceFiles['way-768955042-relations.json']=JSON.stringify(relations);
  assert.throws(()=>deriveOwnPair(changed,changed.sourceFiles),/passenger route/);
});
test('the native part is regenerated through the existing owner without touching unrelated rows', () => {
  const afterPkg=repairPackage(pkg), lanes=laneFixture(), other=['unrelated',0,0,1,2,100,null,null,[]];
  lanes.partsByRegion.jp.push(other);
  const after=repairParts(afterPkg,lanes), expected=partRowsForLine(afterPkg.lines[0],network.displayPartsForLine(afterPkg.lines[0]));
  assert.deepEqual(after.partsByRegion.jp,[expected[0],other]);
  assert.deepEqual(expected[0].slice(4,6),[149,11267.7]);
  assert.deepEqual(expected[0][7],network.displayPartsForLine(afterPkg.lines[0])[0]);
  assert.deepEqual(expected[0][8],[]);
  const beforePoints=network.displayPartsForLine(e.baselineLine)[0], afterPoints=expected[0][7];
  const locate=(points,index)=>points.findIndex(p=>JSON.stringify(p)===JSON.stringify(e.baselineLine.stations[index].slice(2,4)));
  assert.deepEqual(afterPoints.slice(0,locate(afterPoints,1)+1),beforePoints.slice(0,locate(beforePoints,1)+1));
  assert.deepEqual(afterPoints.slice(locate(afterPoints,2)),beforePoints.slice(locate(beforePoints,2)));
  assert.deepEqual(repairParts(afterPkg,after),after);
  for(const key of Object.keys(e.baselineRows).filter(k=>k!=='partsByRegion'))assert.deepEqual(after[key],lanes[key]);
});
test('unreviewed source or station changes cannot silently expand this correction', () => {
  for(const mutate of [l=>l.segments[1][2][29][0]+=.00001,l=>l.stations[1][2]+=.00001,l=>l.segments[1][0]+=1]){
    const changed=structuredClone(pkg);mutate(changed.lines[0]);
    assert.throws(()=>repairPackage(changed),/baseline changed/);
  }
});
test('new measured dependencies require review, including object loops and string reversed parts', () => {
  for(const [key,row] of [
    ['byRegion',[e.lineID,0,0,11264.3,.5]],
    ['followsByRegion',['unrelated',0,0,100,e.lineID,0,0,100]],
    ['loopsByRegion',{id:'new',lineIds:[e.lineID]}],
    ['reversedLoopParts',e.lineID+'#0'],
    ['hubReportByRegion',{hubId:'new',members:[{lineId:e.lineID,from:10,to:20}]}],
  ]){
    const lanes=laneFixture();lanes[key].jp.push(row);
    assert.throws(()=>repairParts(repairPackage(pkg),lanes),/reference changed/,key);
  }
});
