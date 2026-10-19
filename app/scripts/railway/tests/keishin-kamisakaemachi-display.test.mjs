import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const read = p => JSON.parse(fs.readFileSync(new URL(p, import.meta.url)));
const evidence = read('../keishin-kamisakaemachi-display-evidence.json');
test('shipped Kamisakaemachi display shares the identified paired-rail anchor across both approaches', () => {
  const line = read('../../../public/rail/jp-2025.json').lines.find(l => l.id === evidence.lineID);
  assert.deepEqual(line.displayStationCoordinates?.['005987'], evidence.displayAnchor);
  assert.deepEqual(line.displayIntervalCoordinates[4].at(-1), evidence.displayAnchor);
  assert.deepEqual(line.displayIntervalCoordinates[5][0], evidence.displayAnchor);
});
import { createRequire } from 'node:module';
import { repairPackage, repairParts } from '../repair-keishin-kamisakaemachi-display.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const stroke = createRequire(import.meta.url)('../../../public/rail-stroke.js');
const fixture = () => ({lines:[structuredClone(evidence.baselineLine),{id:'unrelated',sentinel:1}],geometrySource:{manualOverrides:{other:{sentinel:1}}}});
const nativeFixture = () => ({partsByRegion:{jp:[...structuredClone(evidence.baselineNativeRows),['unrelated',0,1]],other:[['other']]},
 ...Object.fromEntries(Object.entries(evidence.baselineMeasuredReferences).map(([k,v])=>[k,{jp:structuredClone(v)}]))});
test('bounded replay preserves physical topology, prior Otani curve and unrelated native/measured work',()=>{
 const original=fixture(),pkg=repairPackage(original,evidence),line=pkg.lines[0],base=original.lines[0];
 assert.deepEqual(line.stations,base.stations);assert.deepEqual(line.segments,base.segments);
 assert.deepEqual({...line,displayIntervalCoordinates:base.displayIntervalCoordinates,displayStationCoordinates:undefined},{...base,displayStationCoordinates:undefined});
 const incoming=base.displayIntervalCoordinates[4],seam=incoming.findIndex(p=>p[0]===135.86004&&p[1]===35.00486);
 assert.deepEqual(line.displayIntervalCoordinates[4].slice(0,seam+1),incoming.slice(0,seam+1));
 const physical=network.decodeIntervals(base);
 assert.deepEqual(line.displayIntervalCoordinates[5].slice(-physical[5].slice(2).length),physical[5].slice(2));
 assert.deepEqual(pkg.lines[1],original.lines[1]);assert.deepEqual(pkg.geometrySource.manualOverrides.other,original.geometrySource.manualOverrides.other);
 assert.deepEqual(repairPackage(pkg,evidence),pkg);
 const before=nativeFixture(),after=repairParts(pkg,before,evidence);
 assert.deepEqual(after.partsByRegion.jp.at(-1),before.partsByRegion.jp.at(-1));
 assert.deepEqual(after.partsByRegion.other,before.partsByRegion.other);
 for(const key of Object.keys(before).filter(k=>k!=='partsByRegion'))assert.deepEqual(after[key],before[key]);
 assert.deepEqual(repairParts(pkg,after,evidence),after);
});
test('changed source identity, physical baseline and measured corridor references require review',()=>{
 const altered=structuredClone(evidence);altered.ways[0].tags.service='siding';assert.throws(()=>repairPackage(fixture(),altered));
 const input=fixture();input.lines[0].segments[5][0]+=1;assert.throws(()=>repairPackage(input,evidence),/Unreviewed Keishin dependency/);
 const pkg=repairPackage(fixture(),evidence),lanes=nativeFixture();lanes.followsByRegion.jp.push([evidence.lineID,'new']);
 assert.throws(()=>repairParts(pkg,lanes,evidence),/measured references changed/);
});
test('same-rail taper eliminates artificial hard seam in production stroke at both reviewed boundaries',(t)=>{
 const line=repairPackage(fixture(),evidence).lines[0];
 for(const origin of [[135.86004,35.00486],[135.86048,35.00564]])for(const pixels of [1,4]) {
  const scale=111320*Math.cos(origin[1]*Math.PI/180),points=network.displayPartsForLine(line)[0].map(p=>[(p[0]-origin[0])*scale,(p[1]-origin[1])*111320]);
  const measures=[0];for(let i=1;i<points.length;i++)measures.push(measures.at(-1)+Math.hypot(points[i][0]-points[i-1][0],points[i][1]-points[i-1][1]));
  const rendered=stroke.buildStroke(points.map(p=>p.map(v=>v*pixels)),{measures,anchors:[0,points.length-1],rows:[],totalMetres:measures.at(-1),laneGapPx:0,cornerRadiusPx:3.6,minRampPx:24});
  let worst=0;for(let i=1;i<rendered.points.length-1;i++) {
   const p=rendered.points[i];if(Math.hypot(...p)>25*pixels)continue;
   const a=p.map((v,j)=>v-rendered.points[i-1][j]),b=p.map((v,j)=>rendered.points[i+1][j]-v);
   worst=Math.max(worst,Math.abs(Math.atan2(a[0]*b[1]-a[1]*b[0],a[0]*b[0]+a[1]*b[1]))*180/Math.PI);
  }
  t.diagnostic(`Boundary ${origin} ${pixels}px/m worst angle ${worst.toFixed(3)} degrees`);
  assert(worst<20,`Artificial boundary corner ${worst.toFixed(3)} degrees at ${origin} (${pixels}px/m)`);
 }
});

test('each retained seam is tangent to its unchanged outside support, not a perpendicular connector',()=>{
 const line=repairPackage(fixture(),evidence).lines[0];
 for(const [interval,origin] of [[4,[135.86004,35.00486]],[5,[135.86048,35.00564]]]) {
  const points=line.displayIntervalCoordinates[interval],i=points.findIndex(p=>p[0]===origin[0]&&p[1]===origin[1]);
  assert(i>0&&i<points.length-1);const sx=Math.cos(origin[1]*Math.PI/180);
  const a=[(origin[0]-points[i-1][0])*sx,origin[1]-points[i-1][1]],b=[(points[i+1][0]-origin[0])*sx,points[i+1][1]-origin[1]];
  const angle=Math.abs(Math.atan2(a[0]*b[1]-a[1]*b[0],a[0]*b[0]+a[1]*b[1]))*180/Math.PI;
  assert(angle<0.001,`Retained seam has ${angle} degree artificial connector`);
 }
});
