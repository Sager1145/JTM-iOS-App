import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {partRowsForLine} from '../build-display-lanes.mjs';

const net=createRequire(import.meta.url)('../../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(new URL(p,import.meta.url)));
const authority=read('./fixtures/yokogawara-middle-display-reference.json');
const line=read('../../../public/rail/jp-2025.json').lines.find(l=>l.id===authority.lineID);

function distanceMetres(point,parts){
 const scale=111320,cos=Math.cos(point[1]*Math.PI/180);
 const xy=p=>[(p[0]-point[0])*scale*cos,(p[1]-point[1])*scale];
 let best=Infinity;
 for(const part of parts)for(let i=1;i<part.length;i++){
  const a=xy(part[i-1]),b=xy(part[i]),dx=b[0]-a[0],dy=b[1]-a[1];
  const t=Math.max(0,Math.min(1,-(a[0]*dx+a[1]*dy)/(dx*dx+dy*dy||1)));
  best=Math.min(best,Math.hypot(a[0]+t*dx,a[1]+t*dy));
 }
 return best;
}

test('four dots use the selected running tracks while physical routing stays exact',()=>{
 for(const id of authority.stationIDs)
  assert.deepEqual(line.displayStationCoordinates?.[id],authority.displayStationCoordinates[id],id+' own-track display anchor');
 assert.deepEqual(line.stations,authority.baselineLine.stations);
 assert.deepEqual(line.segments,authority.baselineLine.segments);
 assert.deepEqual(net.decodeIntervals(line),net.decodeIntervals(authority.baselineLine));
 const parts=net.displayPartsForLine(line);
 for(const id of authority.stationIDs)assert(distanceMetres(line.displayStationCoordinates[id],parts)<1e-6);
});

test('Minara west curve follows the mapped arc instead of cutting across the southern fields',()=>{
 const current=net.displayPartsForLine(line),old=net.displayPartsForLine(authority.baselineLine);
 for(const id of ['minara-tanokubo-arc-4','minara-tanokubo-arc-7','minara-tanokubo-arc-10']){
  const s=authority.supportAuthority.find(s=>s.id===id);
  assert(distanceMetres(s.coordinate,old)>8,id+' exposes the original departure');
  assert(distanceMetres(s.coordinate,current)<1,id+' reaches its own visible-track witness');
 }
});

test('Minara northeast branch follows its curve instead of the rejected sparse chord',()=>{
 for(const id of ['minara-ne-middle-1','minara-ne-middle-2','minara-ne-middle-3']){
  const s=authority.supportAuthority.find(s=>s.id===id);
  assert(distanceMetres(s.coordinate,[authority.rejectedNortheastPath])>1,id+' exposes the observed sparse chord');
  assert(distanceMetres(s.coordinate,net.displayPartsForLine(line))<0.15,id+' remains on the selected branch');
 }
});

test('native fallback and ruler use the same final JS geometry with zero lane offset',()=>{
 const native=read('../../../public/rail/display-lanes.json');
 const rows=native.partsByRegion.jp.filter(r=>r[0]===authority.lineID),parts=net.displayPartsForLine(line);
 assert.equal(rows.length,1);assert.equal(parts.length,1);
 assert.equal(rows[0][4],parts[0].length);assert.deepEqual(rows[0][7],parts[0]);
 assert.equal(rows[0][5],partRowsForLine(line,parts,null,null)[0][5]);
 assert(!(native.byRegion?.jp||[]).some(r=>r[0]===authority.lineID));
 assert(!(native.followsByRegion?.jp||[]).some(r=>r.includes(authority.lineID)));
});
