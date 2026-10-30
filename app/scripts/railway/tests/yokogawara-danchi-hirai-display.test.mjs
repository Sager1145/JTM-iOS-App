import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';

const net=createRequire(import.meta.url)('../../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(new URL(p,import.meta.url)));
const reference=read('./fixtures/yokogawara-danchi-hirai-display-reference.json');
const line=read('../../../public/rail/jp-2025.json').lines.find(l=>l.id===reference.lineID);
const parts=net.displayPartsForLine(line);
function distance(point,parts){
 const xy=p=>[(p[0]-point[0])*111320*Math.cos(point[1]*Math.PI/180),(p[1]-point[1])*111320];
 let best=Infinity;
 for(const part of parts)for(let i=1;i<part.length;i++){
  const a=xy(part[i-1]),b=xy(part[i]),v=b.map((x,k)=>x-a[k]);
  const t=Math.max(0,Math.min(1,-(a[0]*v[0]+a[1]*v[1])/(v[0]**2+v[1]**2||1)));
  best=Math.min(best,Math.hypot(a[0]+t*v[0],a[1]+t*v[1]));
 }
 return best;
}

test('Danchi, Umemoto and Hirai dots lie on their selected display members',()=>{
 for(const id of reference.stationIDs){
  assert.deepEqual(line.displayStationCoordinates?.[id],reference.displayStationCoordinates[id],id);
  assert(distance(reference.displayStationCoordinates[id],parts)<1e-6,id+' remains on rendered geometry');
 }
});

test('Danchi western throat retains the north branch rather than the observed southern chord',()=>{
 const witnesses=reference.manualWitnesses.filter(w=>w.id.startsWith('danchi-west'));
 assert(distance(witnesses.find(w=>w.id==='danchi-west-refinement-2').coordinate,reference.rejectedSparseDanchiParts)>1.5);
 for(const w of witnesses){
  assert(distance(w.coordinate,reference.oldPublicParts)>2,w.id+' exposes the old departure');
  assert(distance(w.coordinate,parts)<0.5,w.id+' follows the reviewed running glyph');
 }
});

test('Onogawa display keeps the mapped river curve instead of cutting across the inside',()=>{
 for(const w of reference.manualWitnesses.filter(w=>w.id.startsWith('onogawa-own-arc'))){
  assert(distance(w.coordinate,reference.oldPublicParts)>5,w.id+' exposes the old chord');
  assert(distance(w.coordinate,parts)<0.5,w.id+' retains the mapped arc');
 }
});

test('Umemoto anchoring keeps the visible incoming track instead of shifting the approach north',()=>{
 const w=reference.manualWitnesses.find(w=>w.id==='ushibuchi-danchi-umemoto-body-8');
 assert(distance(w.coordinate,reference.rejectedSparseUmemotoParts)>1,'exposes the observed anchoring departure');
 assert(distance(w.coordinate,parts)<0.5,'same-member collars retain the original running-track witness');
});
