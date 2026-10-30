import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {repairPackage, repairParts, validateCandidateReview, AUTHORITY_PATH} from '../repair-fukubu-whole-line-wl4-display.mjs';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const sha = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
const authority = read(AUTHORITY_PATH);
const LINE = authority.lineID;
const CAND = "f5948b97cc844b00d42226c1ef2c263d434dc41b9d29c4b4c5d6acdbca53e104";
const BASE = "54aabc725cc2b1b47e7d3b37bd0bdc604f7017d14b646ff59b3feeb4d0b45866";
// Self-contained inputs built from the authority, independent of production state.
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const lanesOf = rows => ({partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]}});
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
test('repairPackage turns the baseline into the candidate and is idempotent', () => {
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), CAND);
  assert.equal(sha(authority.baselineLine), BASE);
  assert.equal(out.geometrySource.manualOverrides["fukubu-whole-line-wl4-display"].MainCertified, false);
  const again = repairPackage(out);
  assert.equal(sha(own(again)), CAND);
  assert.deepEqual(again, out);
});
test('rejects tampered authority, stale foreign baseline and changed scope', () => {
  const bad = structuredClone(authority);
  const k = 0;
  if (k !== null) bad.candidateLine.displayIntervalCoordinates[k][1][0] += 1e-6;
  else bad.candidateLine.displayStationCoordinates["002669"][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const foreign = structuredClone(authority.baselineLine); foreign.stations[0][2] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(foreign)), /stale|Physical|changed/);
  const scope = structuredClone(authority); scope.intervalIndices = scope.intervalIndices.slice(1);
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
});
test('repairParts yields the guarded part rows and accepts the baseline native rows', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows));
  const rows = out.partsByRegion.jp.filter(r => r[0] === LINE);
  assert.equal(rows.length, authority.partGuards.length);
  rows.forEach((r, k) => assert.equal(r[4], authority.partGuards[k].vertices));
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows); stale[0][4] -= 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale)), /stale/);
});
test('candidate review receipt must match scope and sha', () => {
  const receipt = {format: "jtm-fukubu-whole-line-wl4-candidate-review-v1", status: 'bounded-candidate-reviewed',
    lineID: LINE, stationIDs: ["002669","002680","002686","002695","002698","002703","002712","002718","002725","002730","002740","002748","002757","002773","002780","002797","002816","002828","002840","002853","002873","002883","002901","002911"], intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22],
    reviewedOwnLineSha256: CAND, MainCertified: false, wholeLineAccepted: false};
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: BASE}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(undefined, authority.candidateLine));
});
test('every reviewed support (10086) lies within 0.6 m of the candidate public line', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  assert.equal(authority.supportCoordinates.length, 10086);
  for (const s of authority.supportCoordinates) assert(distance(s.longitudeLatitude, parts) <= 0.6, s.id + ' within 0.6m');
  for (const p of authority.sourceReviews) assert(fs.existsSync(new URL('../../../../' + p, import.meta.url)), p);
});
test('physical source, other intervals and other aliases are unchanged', () => {
  const b = authority.baselineLine, c = authority.candidateLine;
  assert.deepEqual(net.decodeIntervals(c), net.decodeIntervals(b));
  for (let i = 0; i < b.segments.length; i++) if (!authority.displayIntervals.includes(i))
    assert.deepEqual(c.displayIntervalCoordinates?.[i], b.displayIntervalCoordinates?.[i]);
  for (const [id, v] of Object.entries(b.displayStationCoordinates || {}))
    if (!authority.stationIDs.includes(id)) assert.deepEqual(c.displayStationCoordinates[id], v, id);
});
