import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { physicalForkBoundaries } from '../build-display-lanes.mjs';
import { repairPackage, repairParts } from '../repair-hakone-passenger-corridor.mjs';
const network=createRequire(import.meta.url)('../../../public/rail-network.js');
const evidence=JSON.parse(fs.readFileSync(new URL('../hakone-passenger-corridor-evidence.json',import.meta.url)));
const fixture=()=>({lines:[structuredClone(evidence.baselineLine),{id:'unrelated',segments:[]}],geometrySource:{}});
test('Tonosawa display dot shares both passenger interval endpoints on reviewed station rail',()=>{
  const before=fixture(), line=repairPackage(before,evidence).lines[0];
  const anchor=[139.09405786781113,35.234538053387034];
  assert.deepEqual(line.displayStationCoordinates['005269'],anchor);
  assert.deepEqual(line.displayIntervalCoordinates[4].at(-1),anchor);
  assert.deepEqual(line.displayIntervalCoordinates[5][0],anchor);
  assert.deepEqual(line.stations,before.lines[0].stations);
  assert.deepEqual(line.segments,before.lines[0].segments);
});
test('full passenger corridor restores both real reversal tips and preserves physical graph',()=>{
  const before=fixture(), repaired=repairPackage(before,evidence), line=repaired.lines[0];
  assert.deepEqual(line.segments,before.lines[0].segments);
  assert.deepEqual(line.stations,before.lines[0].stations);
  assert.deepEqual(repaired.lines[1],before.lines[1]);
  assert.deepEqual(Object.keys(line.displayIntervalCoordinates),['4','5','6','7','8','9']);
  for(const [incoming,outgoing] of [[4,5],[6,7],[7,8],[8,9]])
    assert.deepEqual(line.displayIntervalCoordinates[incoming].at(-2),line.displayIntervalCoordinates[outgoing][1]);
  for(const [i,tip] of [[5,evidence.actualReversalTips[0]],[6,evidence.actualReversalTips[1]]]) {
    const points=line.displayIntervalCoordinates[i], j=points.findIndex(p=>JSON.stringify(p)===JSON.stringify(tip));
    assert(j>0 && j<points.length-1);
    assert.deepEqual(points[j-1],points[j+1], 'Must reverse along the same actual terminal stem');
    assert(!before.lines[0].displayIntervalCoordinates[i].some(p=>JSON.stringify(p)===JSON.stringify(tip)));
  }
  const parts=network.displayPartsForLine(line);
  assert.deepEqual(parts[0][0],[139.074289,35.2385735]);
  assert.deepEqual(parts[3].at(-1),parts[0][0]); assert.deepEqual(parts[4][0],parts[0][0]);
  assert.deepEqual(repairPackage(repaired,evidence),repaired);
});
test('old fork measured follows are removed and new native parts carry reviewed continuous geometry',()=>{
  const lanes=Object.fromEntries(Object.entries(evidence.baselineNativeDependencies).map(([k,v])=>[k,{jp:structuredClone(v)}]));
  const pkg=repairPackage(fixture(),evidence), result=repairParts(pkg,lanes,evidence);
  assert.deepEqual(result.followsByRegion.jp,[]);
  assert.deepEqual(result.chainBoundariesByRegion.jp.map(r=>r.slice(1,3)),[[1,3],[3,4],[4,6]]);
  assert.deepEqual(result.partsByRegion.jp.map(r=>r[7]),network.displayPartsForLine(pkg.lines[0]));
  assert.deepEqual(repairParts(pkg,result,evidence),result);
  assert.deepEqual(physicalForkBoundaries(result.partsByRegion.jp),result.chainBoundariesByRegion.jp);
});
test('disconnected switch, freight/service track and backwards one-way are rejected',()=>{
  for(const change of [e=>e.ways.find(w=>w.id===866484938).nodes[0]++,e=>e.ways[0].tags.service='siding',e=>e.ways[0].tags.usage='freight',e=>e.ways.find(w=>w.id===24355362).tags.oneway='yes']) {
    const e=structuredClone(evidence);change(e);assert.throws(()=>repairPackage(fixture(),e));
  }
});
test('cached passenger route display uses restored reversals in both directions',()=>{
  const pkg=repairPackage(fixture(),evidence);
  const line=pkg.lines[0];
  const net=network.buildNetworkFromCompactPackage({...pkg,format:'compact-v1',country:'jp',lines:[line]});
  const intervals=network.decodeIntervals(line);
  for(let i=4;i<=9;i++)for(const reverse of [false,true]) {
    const a=line.stations[i],b=line.stations[i+1];
    const code=`${line.id}@${[a[0],b[0]].sort().join(':')}`;
    const source=reverse ? intervals[i].toReversed() : intervals[i];
    const raw={type:'Feature',geometry:{type:'LineString',coordinates:source},properties:{
      from_n02_station_code:reverse ? b[0]:a[0],to_n02_station_code:reverse ? a[0]:b[0],
      required_line_names:[line.name],required_operator_names:[line.operator],section_codes:[code]}};
    const mapped=network.canonicalizeRouteFeature(net,raw);
    assert(mapped,'Source ride did not map to repaired display');
    const parts=mapped.geometry.type==='LineString' ? [mapped.geometry.coordinates] : mapped.geometry.coordinates;
    const anchor=s=>line.displayStationCoordinates?.[s[0]]||s.slice(2,4);
    assert.deepEqual(parts[0][0],anchor(reverse ? b:a));
    assert.deepEqual(parts.at(-1).at(-1),anchor(reverse ? a:b));
    if(i===5||i===6)assert.equal(parts.flat().filter(p=>JSON.stringify(p)===JSON.stringify(evidence.actualReversalTips[i-5])).length,1);
    assert.deepEqual(raw.geometry.coordinates,source);
  }
});

test('reviewed switchbacks draw three fork legs and a terminal stem once',()=>{
  const line=repairPackage(fixture(),evidence).lines[0];
  const parts=network.displayPartsForLine(line);
  assert.equal(parts.length,7);
  for(const stem of evidence.displayReversalBranches) {
    const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
    assert.equal(parts.filter(p=>equal(p,stem)).length,1);
    assert.equal(parts.filter(p=>equal(p[0],stem[0])||equal(p.at(-1),stem[0])).length,3);
    assert.equal(parts.flat().filter(p=>equal(p,stem.at(-1))).length,1,'Terminal must not be an interior hairpin');
  }
});

test('nearby but nonmatching fork metadata does not create a junction',()=>{
  const line=repairPackage(fixture(),evidence).lines[0];
  const before=network.displayPartsForLine({...line,displayReversalBranches:[]});
  line.displayReversalBranches=line.displayReversalBranches.map(stem=>stem.map(p=>[p[0]+0.000001,p[1]]));
  assert.deepEqual(network.displayPartsForLine(line),before);
});
