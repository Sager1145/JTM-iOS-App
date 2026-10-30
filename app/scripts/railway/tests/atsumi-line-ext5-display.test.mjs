import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {sha} from '../lib/display-candidate-repair.mjs';

const repair = await import('../repair-atsumi-line-ext5-display.mjs');
const {SPEC, AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview} = repair;
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const authority = JSON.parse(fs.readFileSync(AUTHORITY_PATH));
const LINE = SPEC.lineID;
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, structuredClone(line)], geometrySource: {}});
const lanesOf = (native, lane = authority.baselineLaneRows) => ({
  partsByRegion: {jp: [['other', 'x'], ...structuredClone(native)]},
  byRegion: {jp: [['other', 0, 0, 1, 0.5], ...structuredClone(lane)]},
});
const own = pkg => pkg.lines.find(line => line.id === LINE);

function distance(point, paths) {
  const xy = p => [(p[0] - point[0]) * 111320 * Math.cos(point[1] * Math.PI / 180), (p[1] - point[1]) * 111320];
  let best = Infinity;
  for (const path of paths) for (let i = 1; i < path.length; i += 1) {
    const a = xy(path[i - 1]);
    const b = xy(path[i]);
    const v = b.map((x, k) => x - a[k]);
    const t = Math.max(0, Math.min(1, -(a[0] * v[0] + a[1] * v[1]) / (v[0] ** 2 + v[1] ** 2 || 1)));
    best = Math.min(best, Math.hypot(a[0] + t * v[0], a[1] + t * v[1]));
  }
  return best;
}

test('repairPackage turns the frozen baseline into reviewed v13 and is idempotent', () => {
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), SPEC.candidateSha);
  assert.equal(sha(authority.baselineLine), SPEC.baselineSha);
  assert.equal(out.geometrySource.manualOverrides[SPEC.key].physicalTopologyChanged, false);
  assert.equal(out.geometrySource.manualOverrides[SPEC.key].MainCertified, false);
  assert.deepEqual(repairPackage(out), out);
});

test('repairPackage rejects tampered authority, changed scope and stale baseline', () => {
  const bad = structuredClone(authority);
  bad.candidateLine.displayStationCoordinates[SPEC.stationIDs[0]][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const scope = structuredClone(authority);
  scope.intervalIndices = scope.intervalIndices.slice(1);
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
  const stale = structuredClone(authority.baselineLine);
  stale.stations[0][2] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(stale)), /stale|physical/);
});

test('repairParts writes only the v13 native row and accepts idempotent lane state', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows));
  assert.deepEqual(out.partsByRegion.jp.filter(row => row[0] === LINE).map(row => row[4]), authority.candidatePartLengths);
  assert.deepEqual(out.byRegion.jp.filter(row => row[0] === LINE), authority.candidateLaneRows);
  assert.deepEqual(out.byRegion.jp[0], ['other', 0, 0, 1, 0.5]);
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows);
  stale[0][4] -= 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale)), /stale/);
});

test('candidate-review receipt is pinned to the reviewed sha and whole-line scope', () => {
  const receipt = {
    format: SPEC.receiptFormat,
    status: 'bounded-candidate-reviewed',
    lineID: LINE,
    stationIDs: SPEC.stationIDs,
    intervalIndices: SPEC.intervalIndices,
    reviewedOwnLineSha256: SPEC.candidateSha,
    MainCertified: false,
    wholeLineAccepted: false,
  };
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: SPEC.baselineSha}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(null, authority.candidateLine));
});

test('all 3765 supports remain within 0.5 m and cited review evidence exists', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  assert.deepEqual(parts.map(part => part.length), authority.candidatePartLengths);
  assert.equal(authority.supportCoordinates.length, 3765);
  for (const support of authority.supportCoordinates)
    assert(distance(support.longitudeLatitude, parts) <= 0.5, `${support.id} within 0.5 m`);
  for (const evidence of authority.sourceReviews)
    assert(fs.existsSync(new URL('../../../../' + evidence, import.meta.url)), evidence);
});

test('v13 changes only scoped display data and keeps a continuous physical line', () => {
  const before = authority.baselineLine;
  const after = authority.candidateLine;
  assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before));
  assert.equal(net.displayPartsForLine(after).length, 1);
  for (let i = 0; i < SPEC.intervalIndices.length; i += 1) {
    const coordinates = after.displayIntervalCoordinates[i];
    const start = after.displayStationCoordinates[after.stations[i][0]];
    const end = after.displayStationCoordinates[after.stations[i + 1][0]];
    assert.deepEqual(coordinates[0], start, `interval ${i} start`);
    assert.deepEqual(coordinates.at(-1), end, `interval ${i} end`);
  }
});
