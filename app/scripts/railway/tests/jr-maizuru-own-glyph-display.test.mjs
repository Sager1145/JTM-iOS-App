import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {repairPackage, repairParts, validateCandidateReview, AUTHORITY_PATH} from '../repair-jr-maizuru-own-glyph-display.mjs';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const sha = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
const authority = JSON.parse(fs.readFileSync(AUTHORITY_PATH));
const LINE = authority.lineID, KEY = "jr-maizuru-own-glyph-display";
const BASE = '52e690098f2d48c520286a884f0c0c574e6717e5e73944b57081863f2dadaa10', CAND = '4192a6f5c8972f2418b0f97c9f3aae947a2c2318da97f461002c568db2528915';
// Self-contained inputs built from the authority, independent of production state.
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const lanesOf = (rows, laneRows) => ({...structuredClone(authority.frozenLaneReferences),
  partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]}, byRegion: {jp: [['other', 0, 0, 1, 0], ...structuredClone(laneRows)]}});
const own = pkg => pkg.lines.find(l => l.id === LINE);
function distance(point, paths) {
  const xy = p => [(p[0] - point[0]) * 111320 * Math.cos(point[1] * Math.PI / 180), (p[1] - point[1]) * 111320];
  let best = Infinity;
  for (const path of paths) for (let i = 1; i < path.length; i++) {
    const a = xy(path[i - 1]), b = xy(path[i]), v = b.map((x, k) => x - a[k]);
    const t = Math.max(0, Math.min(1, -(a[0] * v[0] + a[1] * v[1]) / (v[0] ** 2 + v[1] ** 2 || 1)));
    best = Math.min(best, Math.hypot(a[0] + t * v[0], a[1] + t * v[1]));
  }
  return best;
}
test('repairPackage turns the baseline into the reviewed candidate and is idempotent', () => {
  assert.equal(sha(authority.baselineLine), BASE);
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), CAND);
  assert.equal(out.geometrySource.manualOverrides[KEY].MainCertified, false);
  assert.deepEqual(repairPackage(out), out);
});
test('rejects a tampered authority, a widened scope and a foreign baseline', () => {
  const bad = structuredClone(authority), k = String(authority.intervalIndices[0]);
  bad.candidateLine.displayIntervalCoordinates[k][1][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const scope = structuredClone(authority); scope.intervalIndices = scope.intervalIndices.slice(1);
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
  const foreign = structuredClone(authority.baselineLine); foreign.stations[0][2] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(foreign)));
});
test('repairParts writes the candidate native rows and carried lane rows, and accepts its own output', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows, authority.baselineLaneRows));
  assert.deepEqual(out.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r[4]), authority.candidatePartLengths);
  assert.deepEqual(out.byRegion.jp.filter(r => r[0] === LINE), authority.candidateLaneRows);
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows); stale[0][4] -= 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale, authority.baselineLaneRows)), /stale/);
});
test('candidate review receipt must match scope and sha', () => {
  const receipt = {format: 'jtm-jr-maizuru-own-glyph-display-candidate-review-v4', status: 'bounded-candidate-reviewed', lineID: LINE,
    stationIDs: authority.stationIDs, intervalIndices: authority.intervalIndices, reviewedOwnLineSha256: CAND, MainCertified: false, wholeLineAccepted: false};
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: BASE}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(undefined, authority.candidateLine));
});
test('every own-glyph support lies within 0.5 m of the candidate public line', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  assert.deepEqual(parts.map(p => p.length), authority.candidatePartLengths);
  assert(authority.supportCoordinates.length > 10);
  for (const s of authority.supportCoordinates) assert(distance(s.longitudeLatitude, parts) <= 0.5, `${s.id} within 0.5 m`);
});
test('physical source, untouched intervals and untouched aliases equal the baseline', () => {
  const b = authority.baselineLine, c = authority.candidateLine;
  assert.deepEqual(net.decodeIntervals(c), net.decodeIntervals(b));
  for (let i = 0; i < b.segments.length; i++) if (!authority.intervalIndices.includes(i))
    assert.deepEqual(c.displayIntervalCoordinates?.[i], b.displayIntervalCoordinates?.[i], 'interval ' + i);
  for (const [id, v] of Object.entries(b.displayStationCoordinates || {})) if (!authority.stationIDs.includes(id))
    assert.deepEqual(c.displayStationCoordinates[id], v, id);
});
