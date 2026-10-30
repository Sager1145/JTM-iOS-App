import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {repairPackage, repairParts, validateCandidateReview, laneReferenceAfter, AUTHORITY_PATH, C} from '../repair-rinkai-shinonome-shinkiba-display.mjs';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const sha = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
const authority = read(AUTHORITY_PATH), LINE = authority.lineID;
// Self-contained inputs built from the authority, independent of production state.
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const R = authority.baselineLaneReferences;
const lanesOf = rows => structuredClone({partsByRegion: {jp: [['other', 'x'], ...rows]}, byRegion: {jp: [['other', 0, 0, 1, 0], ...R.byRegion]},
  followsByRegion: {jp: R.follows}, familyWindowsByRegion: {jp: R.familyWindows},
  hubReportByRegion: {jp: [...new Set(R.hubMembers.map(h => h.hubId))].map(hubId => ({hubId, members: R.hubMembers.filter(h => h.hubId === hubId).map(h => h.member)}))}});
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
const receipt = {format: C.RECEIPT_FORMAT, status: 'bounded-candidate-reviewed', lineID: LINE, stationIDs: C.STATIONS,
  intervalIndices: C.INTERVALS, reviewedOwnLineSha256: C.CANDIDATE_SHA, MainCertified: false, wholeLineAccepted: false,
  continuityCheck: {ok: true}};
test('repairPackage turns the baseline into the candidate and is idempotent', () => {
  assert.equal(sha(authority.baselineLine), C.BASELINE_SHA);
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), C.CANDIDATE_SHA);
  assert.equal(out.geometrySource.manualOverrides[C.KEY].MainCertified, false);
  assert.deepEqual(repairPackage(out), out);
});
test('rejects tampered authority, scope and stale foreign baseline', () => {
  const bad = structuredClone(authority), i = C.INTERVALS[0];
  bad.candidateLine.displayIntervalCoordinates[i][1][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const foreign = structuredClone(authority.baselineLine); foreign.stations[0][2] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(foreign)), /stale/);
  const scope = structuredClone(authority); scope.intervalIndices = C.INTERVALS.slice(1);
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
});
test('repairParts yields the candidate native rows and accepts the baseline rows', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows));
  assert.deepEqual(out.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r[4]), C.POINTS);
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows); stale[0][4] -= 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale)), /stale/);
});
test('measured lane references are remapped onto the candidate parts and idempotent', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine)), out = repairParts(pkg, lanesOf(authority.baselineNativeRows));
  const next = laneReferenceAfter(R, net.displayPartsForLine(authority.baselineLine), net.displayPartsForLine(authority.candidateLine));
  assert.deepEqual(out.byRegion.jp.slice(1), next.byRegion);
  assert.deepEqual(out.followsByRegion.jp, next.follows);
  assert.deepEqual(repairParts(pkg, out), out);
  for (const [b, a] of R.byRegion.map((b, k) => [b, next.byRegion[k]])) assert(a[2] <= a[3] && Math.abs((a[3] - a[2]) - (b[3] - b[2])) < 60, 'lane window ' + b);
  const extra = lanesOf(authority.baselineNativeRows); extra.byRegion.jp.push([LINE, 0, 1, 2, 0]);
  assert.throws(() => repairParts(pkg, extra), /unreviewed byRegion/);
  const foreign = lanesOf(authority.baselineNativeRows); foreign.reviewedSharedCorridors = [LINE];
  assert.throws(() => repairParts(pkg, foreign), /requires review/);
});
test('candidate review receipt must match scope, sha and continuity', () => {
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: C.BASELINE_SHA}, authority.candidateLine));
  assert.throws(() => validateCandidateReview({...receipt, continuityCheck: {ok: false}}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(undefined, authority.candidateLine));
});
test('Apple-glyph supports and aliases lie within 0.5 m of the candidate public line; physical unchanged', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  assert.deepEqual(parts.map(p => p.length), C.POINTS);
  for (const s of authority.supportCoordinates) assert(distance(s.longitudeLatitude, parts) <= 0.5, s.id + ' within 0.5 m');
  for (const id of C.STATIONS) assert(authority.supportCoordinates.some(s => s.id === 'alias:' + id));
  assert.deepEqual(net.decodeIntervals(authority.candidateLine), net.decodeIntervals(authority.baselineLine));
  for (const p of authority.sourceReviews) assert(fs.existsSync(new URL('../../../../' + p, import.meta.url)), p);
});
