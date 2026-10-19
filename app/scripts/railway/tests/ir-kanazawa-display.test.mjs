import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { repairPackage, repairParts } from '../repair-ir-kanazawa-display.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const e = JSON.parse(fs.readFileSync(new URL('../ir-kanazawa-display-evidence.json', import.meta.url)));
const pkg = { lines: [e.baselineLine], geometrySource: { license: 'OpenStreetMap ODbL', manualOverrides: {} } };
test('Kanazawa false V follows its own conventional chain and retains station approach and physical data', () => {
  const after = repairPackage(pkg);
  assert.deepEqual(after.lines[0].displayIntervalCoordinates[3], e.fragment.candidateDecodedInterval);
  assert.deepEqual(after.lines[0].segments, e.baselineLine.segments);
  assert.deepEqual(after.lines[0].stations, e.baselineLine.stations);
  assert.deepEqual(after.lines[0].displayIntervalCoordinates[3].slice(-4), [[136.64981,36.58058],[136.64922,36.57998],[136.64858,36.57927],[136.647771,36.578297]]);
  assert.deepEqual(repairPackage(after), after);
});
test('northern sparse chord is replaced by own track while station and adjacent intervals stay exact', () => {
  const line = repairPackage(pkg).lines[0];
  const before = network.decodeIntervals(e.baselineLine);
  const display = before.map((points,index) => line.displayIntervalCoordinates?.[index] ?? points);
  assert.deepEqual(display[3][0], before[3][0]);
  assert.deepEqual(display[3][1], [136.66895093184243,36.59294842648297]);
  for (const raw of before[3].slice(1,5)) {
    assert(!display[3].some(point => JSON.stringify(point) === JSON.stringify(raw)), 'northern raw chord control retained');
  }
  assert(display[3].some(point => JSON.stringify(point) === JSON.stringify([136.6689044,36.592909])), 'identified own node3977860975 missing');
  assert.deepEqual(display[2], before[2]);
  assert.deepEqual(display[4], before[4]);
});
test('native derived part and lane end change together without altering unrelated owners', () => {
  const lanes = Object.fromEntries(Object.entries(e.baselineRows).filter(([k])=>['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion'].includes(k)).map(([k,v])=>[k,{jp:structuredClone(v)}]));
  const other=['unrelated',0,0,123,0]; lanes.byRegion.jp.push(other);
  const after=repairParts(repairPackage(pkg),lanes);
  assert.deepEqual(after.byRegion.jp,[[e.lineID,0,0,64396.1,0.5],other]);
  assert.deepEqual(after.partsByRegion.jp.map(r=>[r[4],r[5]]),[[646,64396.1]]);
  assert.deepEqual(after.partsByRegion.jp[0][7],network.displayPartsForLine(repairPackage(pkg).lines[0])[0]);
  assert.deepEqual(repairParts(repairPackage(pkg),after),after);
});
test('unreviewed own physical baseline refuses repair', () => {
  const changed=structuredClone(pkg);changed.lines[0].segments[3][0]=2.6;
  assert.throws(()=>repairPackage(changed),/baseline changed/);
});
test('new measured dependencies must be reviewed before changing the native ruler', () => {
  for (const [key,rows,reason] of [
    ['hubReportByRegion',[{hubId:'new-own-hub',members:[{lineId:e.lineID,startMetres:64000,endMetres:64389}]}],/hub reference changed/],
    ['loopsByRegion',[{id:'new-own-loop',lineIds:[e.lineID]}],/reference changed: loopsByRegion/],
    ['reversedLoopParts',[e.lineID+'#0'],/reference changed: reversedLoopParts/],
  ]) {
    const lanes=Object.fromEntries(Object.entries(e.baselineRows).map(([k,v])=>[k,{jp:structuredClone(v)}]));
    lanes[key].jp=rows;
    assert.throws(()=>repairParts(repairPackage(pkg),lanes),reason,key);
  }
});
