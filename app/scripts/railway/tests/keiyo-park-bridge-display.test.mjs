import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { repairPackage, repairParts, corridor } from '../repair-keiyo-park-bridge-display.mjs';
const require=createRequire(import.meta.url), network=require('../../../public/rail-network.js'),stroke=require('../../../public/rail-stroke.js');
const e=JSON.parse(fs.readFileSync(new URL('../keiyo-park-bridge-display-evidence.json',import.meta.url)));
const fixture=()=>({lines:[...structuredClone(e.baselineLines),{id:'unrelated',keep:true}],geometrySource:{manualOverrides:structuredClone(e.baselineMarkers)}});
const lanes=()=>({partsByRegion:{jp:structuredClone(e.baselineNativeRows)},...Object.fromEntries(Object.entries(e.baselineMeasuredReferences).map(([k,v])=>[k,{jp:structuredClone(v)}]))});
const cross=(a,b,c)=>(b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]);
test('coupled display preserves physical railway, prior forks and independent rows',()=>{
 const b=fixture(),p=repairPackage(b,e),l=p.lines[0],old=e.baselineLines[0],iv=network.decodeIntervals(old);
 assert(l.displayIntervalCoordinates[11]);assert(l.displayIntervalCoordinates[12]);
 assert.deepEqual(l.segments,old.segments);assert.deepEqual(l.stations,old.stations);
 for(const i of [6,7,8,9])assert.deepEqual(l.displayIntervalCoordinates[i],old.displayIntervalCoordinates[i]);
 assert.deepEqual(p.lines.slice(1),b.lines.slice(1));
 assert.deepEqual(l.displayIntervalCoordinates[11].slice(0,4),iv[11].slice(0,4));
 assert.deepEqual(l.displayIntervalCoordinates[12].slice(-iv[12].slice(16).length),iv[12].slice(16));
 const point=l.displayStationCoordinates[e.stationID];assert.deepEqual(l.displayIntervalCoordinates[11].at(-1),point);assert.deepEqual(l.displayIntervalCoordinates[12][0],point);
 assert.deepEqual(repairPackage(p,e),p);
});
test('longitudinal projection and tangent transitions survive actual production stroke',()=>{
 const c=corridor(e),iv=network.decodeIntervals(e.baselineLines[0]);assert(c.station.distanceM>20&&c.station.distanceM<40);
 assert(Math.abs(cross(iv[11][3],iv[11][4],c.points[4]))<1e-14);
 const end=c.points.findIndex(p=>JSON.stringify(p)===JSON.stringify(e.window.westGuard));assert(Math.abs(cross(iv[12][15],iv[12][16],c.points[end-1]))<1e-14);
 const project=p=>[(p[0]-c.points[0][0])*111320*.812,-(p[1]-c.points[0][1])*111320], pts=c.points.map(project), m=[0];for(let i=1;i<pts.length;i++)m.push(m.at(-1)+Math.hypot(pts[i][0]-pts[i-1][0],pts[i][1]-pts[i-1][1]));
 const ink=stroke.buildStroke(pts,{measures:m,totalMetres:m.at(-1),rows:[{from:0,to:m.at(-1),lane:0}],laneGapPx:2.7,cornerRadiusPx:0,minCornerRadiusPx:3,anchors:[0,c.stationIndex,pts.length-1],enforceMinimumCornerRadius:true});
 for(const p of c.core){const q=project(p),d=ink.points.slice(1).map((b,i)=>{const a=ink.points[i],dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,((q[0]-a[0])*dx+(q[1]-a[1])*dy)/(dx*dx+dy*dy||1)));return Math.hypot(q[0]-a[0]-t*dx,q[1]-a[1]-t*dy);});assert(Math.min(...d)<1,'Production stroke bypassed identified mean');}
});
test('native part updates while shared measurements and unrelated metadata stay exact',()=>{
 const p=repairPackage(fixture(),e),a=lanes();a.partsByRegion.jp.push(['unrelated',0,9,9]);const r=repairParts(p,a,e);
 assert.notDeepEqual(r.partsByRegion.jp.find(x=>x[0]===e.lineID),a.partsByRegion.jp.find(x=>x[0]===e.lineID));
 for(const k of Object.keys(e.baselineMeasuredReferences))assert.deepEqual(r[k],a[k]);
 assert.deepEqual(r.partsByRegion.jp.filter(x=>x[0]!==e.lineID),a.partsByRegion.jp.filter(x=>x[0]!==e.lineID));
 assert.deepEqual(repairParts(p,r,e),r);
});
test('changed paired identities, physical source and unknown native rulers reject',()=>{
 const bad=structuredClone(e);bad.ways[0].nodes[0]++;assert.throws(()=>repairPackage(fixture(),bad));
 const p=fixture();p.lines[0].segments[11][0]++;assert.throws(()=>repairPackage(p,e));
 const a=lanes();a.followsByRegion.jp.push([e.lineID,0,999,1000,'unknown',0,1,2]);assert.throws(()=>repairParts(repairPackage(fixture(),e),a,e));
});
