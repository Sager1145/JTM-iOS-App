import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {repairPackage, repairParts, validateCandidateReview, AUTHORITY_PATH} from '../repair-geibi-kotachi-kamikawatachi-display.mjs';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const sha = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
const authority = read(AUTHORITY_PATH);
const LINE = authority.lineID, KEY = 'geibi-kotachi-kamikawatachi-display';
const CAND = '6e4349d707afab72dbe62309f7842243096be4a28bbdb9eda712f1f7e70efb67', BASE = '8dbae924d62be175e108cf0aeba65d9f8c85544adb3a23c63cea15af879d4bf8';
// Self-contained inputs built from the authority, independent of production state.
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const lanesOf = (rows, lanes = authority.baselineLaneRows) => ({partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]}, byRegion: {jp: [['other', 0, 0, 1, 0], ...structuredClone(lanes)]}});
const own = pkg => pkg.lines.find(l => l.id === LINE);
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
test('repairPackage turns the 3020 baseline into the 3141 candidate and is idempotent', () => {
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), CAND);
  assert.equal(sha(authority.baselineLine), BASE);
  assert.equal(out.geometrySource.manualOverrides[KEY].MainCertified, false);
  const again = repairPackage(out);
  assert.equal(sha(own(again)), CAND);
  assert.deepEqual(again, out);
});
test('rejects tampered authority, wrong scope and stale foreign baseline', () => {
  const bad = structuredClone(authority);
  bad.candidateLine.displayIntervalCoordinates['16'][1][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const foreign = structuredClone(authority.baselineLine);
  foreign.stations[0][2] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(foreign)), /stale/);
  const scope = structuredClone(authority); scope.intervalIndices = [];
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
});
test('repairParts yields one 3141-point row and accepts the baseline native row', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows));
  const rows = out.partsByRegion.jp.filter(r => r[0] === LINE);
  assert.equal(rows.length, 1); assert.equal(rows[0][4], 3141);
  const lanes = out.byRegion.jp.filter(r => r[0] === LINE);
  assert.deepEqual(lanes, authority.baselineLaneRows.map(r => [r[0], 0, 0, rows[0][5], r[4]]));
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows); stale[0][4] = 3020 - 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale)), /stale/);
});
test('candidate review receipt must match scope and sha', () => {
  const receipt = {format: 'jtm-geibi-kotachi-kamikawatachi-candidate-review-v1', status: 'bounded-candidate-reviewed',
    lineID: LINE, stationIDs: ["007130", "006949"], intervalIndices: [16],
    reviewedOwnLineSha256: CAND, MainCertified: false, wholeLineAccepted: false};
  const line = own(repairPackage(pkgOf(authority.baselineLine)));
  validateCandidateReview(receipt, line);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: BASE}, line));
  assert.throws(() => validateCandidateReview({...receipt, intervalIndices: []}, line));
});
test('every own-glyph support is within 0.5 m of the public candidate line', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  for (const s of authority.supports) assert(distance(s.longitudeLatitude, parts) <= 0.5, s.id);
  assert.deepEqual(net.decodeIntervals(authority.candidateLine), net.decodeIntervals(authority.baselineLine));
});
