import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(new URL(p, import.meta.url)));
const reference = read('./fixtures/yokogawara-kume-kitakume-display-reference.json');
const line = read('../../../public/rail/jp-2025.json').lines.find(l => l.id === reference.lineID);
const parts = net.displayPartsForLine(line);
function distance(point, paths) {
  const xy = p => [(p[0]-point[0])*111320*Math.cos(point[1]*Math.PI/180), (p[1]-point[1])*111320];
  let best = Infinity;
  for (const path of paths) for (let i=1; i<path.length; i++) {
    const a=xy(path[i-1]), b=xy(path[i]), v=b.map((x,k)=>x-a[k]);
    const t=Math.max(0,Math.min(1,-(a[0]*v[0]+a[1]*v[1])/(v[0]**2+v[1]**2||1)));
    best=Math.min(best,Math.hypot(a[0]+t*v[0],a[1]+t*v[1]));
  }
  return best;
}
test('Kume and Kitakume dots use the selected literal own running members', () => {
  assert.equal(reference.capsCertified, false);
  for (const [id, coordinate] of Object.entries(reference.stationAliases)) {
    assert.deepEqual(line.displayStationCoordinates?.[id], coordinate, `station ${id} selected member`);
    assert(distance(coordinate, parts)<1e-6, `station ${id} lies on public own path`);
  }
});
test('Kume southeast curve follows three fresh q2 running-stroke witnesses; rejected192 cuts the curve', () => {
  const witnesses=reference.manualWitnesses.filter(s=>s.id.includes('-SE-'));
  assert.equal(witnesses.length,3);
  const rejected=net.displayPartsForLine(reference.rejected192Line);
  assert(Math.max(...witnesses.map(s=>distance(s.longitudeLatitude,rejected)))>1,
    'actual rejected192 sparse candidate has a greater-than-one-metre chord departure');
  for (const s of witnesses) assert(distance(s.longitudeLatitude,parts)<=reference.thresholdMetres,
    `${s.id} remains within 0.5m of manually identified running stroke`);
});
test('Kume northwest curve follows three fresh q2 thin-core witnesses', () => {
  const witnesses=reference.manualWitnesses.filter(s=>s.id.includes('-NW-'));
  assert.equal(witnesses.length,3);
  for (const s of witnesses) assert(distance(s.longitudeLatitude,parts)<=reference.thresholdMetres,
    `${s.id} remains within 0.5m of manually identified thin core`);
});
