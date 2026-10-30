import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {partRowsForLine} from '../build-display-lanes.mjs';
const net=createRequire(import.meta.url)('../../../public/rail-network.js');
const authority=JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/proposals/daishi-eastern-stations-20261020/bounded-visible-track-candidate.json',import.meta.url)));
const target=new URL('../repair-daishi-eastern-stations-display.mjs',import.meta.url);
const impl=await import(target);
const input=()=>({lines:[structuredClone(authority.baselineLine),{id:'unrelated',keep:['existing']}],geometrySource:{manualOverrides:{unrelated:{keep:true}}}});

test('three eastern station dots move onto selected visible north strokes with exact protected western prefix and Kojima tail',()=>{
 const before=input(),result=impl.repairPackage(before,authority),line=result.lines[0];
 assert.deepEqual(line.displayStationCoordinates['004413'],[139.72596817790986,35.535786369912024]);
 assert.deepEqual(line.displayStationCoordinates['004408'],[139.7343786441803,35.53660527842849]);
 assert.deepEqual(line.displayStationCoordinates['004407'],[139.74057911045077,35.536629008953284]);
 assert.deepEqual(line,authority.candidateLine);
 assert.deepEqual(net.displayPartsForLine(line)[0].slice(0,55),net.displayPartsForLine(before.lines[0])[0].slice(0,55));
 for(const i of [0,1])assert.deepEqual(line.displayIntervalCoordinates[i],before.lines[0].displayIntervalCoordinates[i]);
 assert.deepEqual(line.displayIntervalCoordinates[2].slice(0,6),before.lines[0].displayIntervalCoordinates[2].slice(0,6));
 assert.deepEqual(line.displayIntervalCoordinates[5].slice(-9),before.lines[0].displayIntervalCoordinates[5].slice(-9));
 for(const id of ['004417','004415','004418'])assert.deepEqual(line.displayStationCoordinates[id],before.lines[0].displayStationCoordinates[id]);
 assert.deepEqual(line.stations,before.lines[0].stations);assert.deepEqual(line.segments,before.lines[0].segments);assert.deepEqual(net.decodeIntervals(line),net.decodeIntervals(before.lines[0]));
 assert.deepEqual(result.lines[1],before.lines[1]);assert.deepEqual(result.geometrySource.manualOverrides.unrelated,{keep:true});assert.deepEqual(impl.repairPackage(result,authority),result);
});

test('actual JS native fallback preserves every unrelated lane field and the previously applied Kojima tail', () => {
  const pkg=impl.repairPackage(input(),authority), oldRows=partRowsForLine(authority.baselineLine,net.displayPartsForLine(authority.baselineLine),null,null);
  const other=['unrelated',0,0,0,2,20,null,null,[]];
  const lanes={partsByRegion:{jp:[...oldRows,other],tw:[other]},byRegion:{jp:[['unrelated',0,0,10,0.5]]},followsByRegion:{jp:[]},colorByRegion:{jp:{unrelated:'blue'}},keep:{value:42}};
  const before=structuredClone(lanes),result=impl.repairParts(pkg,lanes,authority),row=result.partsByRegion.jp[0];
  assert.deepEqual(row.slice(1,7),[0,-1,-1,89,4335.3,'complex']);
  assert.deepEqual(row[7],net.displayPartsForLine(pkg.lines[0])[0]);
  assert.deepEqual(row[7].at(-1),authority.baselineLine.displayStationCoordinates['004418']);
  assert.deepEqual(result.partsByRegion.jp[1],other);
  for(const k of Object.keys(lanes).filter(k=>k!=='partsByRegion'))assert.deepEqual(result[k],lanes[k]);
  assert.deepEqual(result.partsByRegion.tw,lanes.partsByRegion.tw);
  assert.deepEqual(impl.repairParts(pkg,result,authority),result);
  assert.deepEqual(lanes,before);
  const bad=structuredClone(lanes);bad.partsByRegion.jp[0][4]++;
  assert.throws(()=>impl.repairParts(pkg,bad,authority),/stale\/foreign own native row/);
  const foreign=structuredClone(lanes);foreign.followsByRegion.jp.push(['unrelated',0,0,1,authority.lineID,0,0,1]);
  assert.throws(()=>impl.repairParts(pkg,foreign,authority),/own native reference requires review/);
});

test('stale own line and withdrawn lower/label control are rejected instead of applying to changed input', () => {
  const stale=input();stale.lines[0].segments[0][0]+=.001;
  assert.throws(()=>impl.repairPackage(stale,authority),/current own source changed/);
  const wrong=input();wrong.lines[0].displayIntervalCoordinates[5][8][1]+=.0001;
  assert.throws(()=>impl.repairPackage(wrong,authority),/current own source changed/);
  const rejected=structuredClone(authority);rejected.supportAuthority[0].supports[6].pixel=[1190,980];
  assert.throws(()=>impl.repairPackage(input(),rejected),/own-track pixel authority changed/);
  const badProjection=structuredClone(authority);badProjection.supportAuthority[1].supports[3].coordinate[1]+=.00001;
  assert.throws(()=>impl.repairPackage(input(),badProjection),/support projection changed/);
});

test('production apply review requires exact candidate hash and scoped interval/station proof', () => {
  const line=impl.repairPackage(input(),authority).lines[0];
  assert.throws(()=>impl.validateCandidateReview(null,line),/receipt required/);
  const receipt={format:'jtm-daishi-eastern-stations-candidate-review-v1',status:'bounded-candidate-reviewed',lineID:authority.lineID,stationIDs:['004413','004408','004407'],intervalIndices:[2,3,4,5],wholeLineAccepted:false,MainCertified:false,reviewedOwnLineSha256:createHash('sha256').update(JSON.stringify(line)).digest('hex'),captures:[]};
  assert.throws(()=>impl.validateCandidateReview(receipt,line),/scoped reviewed captures required/);
  assert.throws(()=>impl.validateCandidateReview({...receipt,reviewedOwnLineSha256:'stale'},line),/reviewed own line changed/);
  assert.throws(()=>impl.validateCandidateReview({...receipt,intervalIndices:[1]},line),/review scope changed/);
});
