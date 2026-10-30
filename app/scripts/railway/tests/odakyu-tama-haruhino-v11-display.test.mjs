import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {
  repairPackage,
  repairParts,
  validateCandidateReview,
  AUTHORITY_PATH,
} from '../repair-odakyu-tama-haruhino-v11-display.mjs';

const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = path => JSON.parse(fs.readFileSync(path));
const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const authority = read(AUTHORITY_PATH);
const LINE = authority.lineID;
const KEY = 'odakyu-tama-haruhino-v11-display';
const BASE = '12ad9402b0becadcf802a3fccdbb886918bdc828a68a2b58a9df8eb9410c9ec0';
const CAND = '0167fe5b9374abac21e7cbc16e35c997aa4b23392c8f349779aea1293b62f15b';
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const lanesOf = (rows, lanes = authority.baselineLaneRows) => ({
  partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]},
  byRegion: {jp: [['other', 0, 0, 1, 0], ...structuredClone(lanes)]},
});
const own = pkg => pkg.lines.find(line => line.id === LINE);

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

test('repairPackage turns the 155-point baseline into the 184-point scoped v11 candidate and is idempotent', () => {
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), CAND);
  assert.equal(sha(authority.baselineLine), BASE);
  assert.equal(out.geometrySource.manualOverrides[KEY].MainCertified, false);
  assert.deepEqual(repairPackage(out), out);
});

test('rejects tampered authority, wrong scope and stale foreign baseline', () => {
  const bad = structuredClone(authority);
  bad.candidateLine.displayIntervalCoordinates['3'][1][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const foreign = structuredClone(authority.baselineLine);
  foreign.stations[0][2] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(foreign)), /stale/);
  const scope = structuredClone(authority);
  scope.intervalIndices = [];
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
});

test('repairParts yields one 184-point row and accepts the baseline native row', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows));
  const rows = out.partsByRegion.jp.filter(row => row[0] === LINE);
  assert.equal(rows.length, 1);
  assert.equal(rows[0][4], 184);
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows);
  stale[0][4] -= 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale)), /stale/);
});

test('candidate review receipt must match v11 scope and sha', () => {
  const receipt = {
    format: 'jtm-odakyu-tama-haruhino-v11-candidate-review-v1',
    status: 'bounded-candidate-reviewed',
    lineID: LINE,
    stationIDs: ['004090', '004141', '004168'],
    intervalIndices: [2, 3],
    reviewedOwnLineSha256: CAND,
    MainCertified: false,
    wholeLineAccepted: false,
  };
  const line = own(repairPackage(pkgOf(authority.baselineLine)));
  validateCandidateReview(receipt, line);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: BASE}, line));
  assert.throws(() => validateCandidateReview({...receipt, intervalIndices: [2]}, line));
});

test('visible witnesses remain within 0.5 m and Haruhino uses the ruled display alias', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  for (const support of authority.supports)
    assert(distance(support.longitudeLatitude, parts) <= 0.5, support.id);
  assert.deepEqual(authority.candidateLine.displayStationCoordinates['004141'], [139.46508887811257, 35.61843825585889]);
  assert.deepEqual(net.decodeIntervals(authority.candidateLine), net.decodeIntervals(authority.baselineLine));
});
