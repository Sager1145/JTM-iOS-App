import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {repairPackage, repairParts, validateCandidateReview, AUTHORITY_PATH} from '../repair-nagaden-yudanaka-kirihara-display.mjs';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const sha = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
const authority = read(AUTHORITY_PATH);
const LINE = authority.lineID;
const CAND = '7f168b074ea21ec2f10cddd05961af6c1632b28741e7169253da600fbed3be8b';
const BASE = 'b147c8b9458c2c5496603bb810036f5c5e512882b4fb2ca61395222b1da675e2';
// Self-contained inputs built from the authority, independent of production state.
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const lanesOf = (rows, follows = authority.baselineFollowRows) => ({partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]},
  followsByRegion: {jp: [['other', 0, 0, 1, 'other2', 0, 0, 1], ...structuredClone(follows)]},
  ...Object.fromEntries(Object.entries(authority.baselineOtherLaneReferences).map(([k, v]) => [k, {jp: Array.isArray(v) && Array.isArray(v[0]) && typeof v[0][0] === 'string' && v[0].length === 2 && typeof v[0][1] === 'object' ? Object.fromEntries(v) : structuredClone(v)}]))});
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
  assert.equal(out.geometrySource.manualOverrides['nagaden-yudanaka-kirihara-display'].MainCertified, false);
  const again = repairPackage(out);
  assert.equal(sha(own(again)), CAND);
  assert.deepEqual(again, out);
});
test('rejects tampered authority, stale foreign baseline and changed scope', () => {
  const bad = structuredClone(authority);
  const k = String(authority.displayOverrideIntervals[0]);
  bad.candidateLine.displayIntervalCoordinates[k][1][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const foreign = structuredClone(authority.baselineLine);
  foreign.stations[0][4] = foreign.stations[0][4] + ' ';
  assert.throws(() => repairPackage(pkgOf(foreign)), /stale/);
  const scope = structuredClone(authority); scope.intervalIndices = scope.intervalIndices.slice(1);
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
});
test('repairParts yields the candidate rows and accepts the baseline native rows', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows));
  const rows = out.partsByRegion.jp.filter(r => r[0] === LINE);
  assert.deepEqual(rows.map(r => r[4]), authority.candidatePartCounts);
  assert.deepEqual(repairParts(pkg, out), out);
  assert.deepEqual(out.followsByRegion.jp.filter(r => r[0] === LINE || r[4] === LINE), authority.candidateFollowRows);
  const stale = structuredClone(authority.baselineNativeRows); stale[0][4] -= 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale)), /stale/);
  if (authority.baselineFollowRows.length) {
    const f = structuredClone(authority.baselineFollowRows); f[0][2] += 0.5;
    assert.throws(() => repairParts(pkg, lanesOf(authority.baselineNativeRows, f)), /stale/);
  }
});
test('candidate review receipt must match scope and sha', () => {
  const receipt = {format: 'jtm-r12b-nagaden-yudanaka-kirihara-display-candidate-review-v1', status: 'bounded-candidate-reviewed',
    lineID: LINE, stationIDs: authority.stationIDs, intervalIndices: authority.intervalIndices,
    reviewedOwnLineSha256: CAND, MainCertified: false, wholeLineAccepted: false};
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: BASE}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(undefined, authority.candidateLine));
});
test('all 4246 glyph supports lie within 0.5 m of the candidate public line', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  assert.deepEqual(parts.map(p => p.length), authority.candidatePartCounts);
  assert.equal(authority.supportCoordinates.length, 4246);
  for (const s of authority.supportCoordinates)
    assert(distance(s.longitudeLatitude, parts) <= 0.5, `${s.id} within 0.5m`);
  for (const p of authority.sourceReviews) assert(fs.existsSync(new URL('../../../../' + p, import.meta.url)), p);
});
test('other aliases, intervals and physical source are unchanged from baseline', () => {
  const b = authority.baselineLine, c = authority.candidateLine;
  for (const [id, v] of Object.entries(b.displayStationCoordinates || {}))
    if (!authority.stationIDs.includes(id)) assert.deepEqual(c.displayStationCoordinates[id], v, id);
  for (const [i, v] of Object.entries(b.displayIntervalCoordinates || {}))
    if (!authority.displayOverrideIntervals.includes(+i)) assert.deepEqual(c.displayIntervalCoordinates[i], v);
  assert.deepEqual(net.decodeIntervals(c), net.decodeIntervals(b));
});
