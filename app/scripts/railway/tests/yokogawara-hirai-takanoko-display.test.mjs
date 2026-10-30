import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(new URL(p, import.meta.url)));
const reference = read('./fixtures/yokogawara-hirai-takanoko-display-reference.json');
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
// This short, manually established straight corridor runs westward. This is not
// a global longitude rule for other intervals or real curved/reversing railways.
function shortEastwardFold(paths) {
  return paths.some(p => p.some((v,i) => i && v[0]<132.82847 && v[0]>132.8145 &&
    p[i-1][0]<132.82847 && p[i-1][0]>132.8145 && v[0]-p[i-1][0]>1e-10));
}
test('Hirai west display follows four independently read q2 thin-running-glyph witnesses', () => {
  for (const witness of reference.manualWitnesses)
    assert(distance(witness.longitudeLatitude, parts)<=reference.thresholdMetres,
      `q2 control ${witness.controlIndex} remains within 0.5m of selected own running glyph`);
});
test('Takanoko dot uses the reference-assisted same-track locus, with full caps still unknown', () => {
  assert.equal(reference.capsCertified,false);
  assert.deepEqual(line.displayStationCoordinates?.[reference.stationID],reference.displayStationCoordinate);
  assert(distance(reference.displayStationCoordinate,parts)<1e-6,'dot is on public display path');
});
test('Hirai–Takanoko and its short outgoing collar contain no spurious endpoint reversal', () => {
  assert(shortEastwardFold([reference.rejected169Line.displayIntervalCoordinates[7],
    reference.rejected169Line.displayIntervalCoordinates[8]]),
    'the actual rejected169 candidate exposes the short endpoint fold');
  assert(!shortEastwardFold([line.displayIntervalCoordinates?.[7] || [],
    line.displayIntervalCoordinates?.[8] || net.decodeIntervals(line)[8]]),
    'private display station collar must not double back eastward');
  assert(!shortEastwardFold(parts),'public display station collar must not double back eastward');
});
