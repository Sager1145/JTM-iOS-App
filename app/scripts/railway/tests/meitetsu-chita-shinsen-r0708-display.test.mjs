import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {sha} from '../lib/display-candidate-repair.mjs';
import {SPEC, AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview} from '../repair-meitetsu-chita-shinsen-r0708-display.mjs';

const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const authority = JSON.parse(fs.readFileSync(AUTHORITY_PATH));
const LINE = SPEC.lineID;
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, structuredClone(line)], geometrySource: {}});
const lanesOf = (rows, laneRows) => ({...structuredClone(authority.frozenLaneReferences),
  partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]}, byRegion: {jp: [['other', 0, 0, 1, 0.5], ...structuredClone(laneRows)]}});
const own = pkg => pkg.lines.find(line => line.id === LINE);

function distance(point, paths) {
  const xy = p => [(p[0] - point[0]) * 111320 * Math.cos(point[1] * Math.PI / 180), (p[1] - point[1]) * 111320];
  let best = Infinity;
  for (const path of paths) for (let i = 1; i < path.length; i += 1) {
    const a = xy(path[i - 1]), b = xy(path[i]), v = b.map((x, k) => x - a[k]);
    const t = Math.max(0, Math.min(1, -(a[0] * v[0] + a[1] * v[1]) / (v[0] ** 2 + v[1] ** 2 || 1)));
    best = Math.min(best, Math.hypot(a[0] + t * v[0], a[1] + t * v[1]));
  }
  return best;
}

test('repairPackage turns the frozen baseline into the reviewed candidate and is idempotent', () => {
  assert.equal(sha(authority.baselineLine), SPEC.baselineSha);
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), SPEC.candidateSha);
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

test('repairParts writes the candidate native rows and carried lane rows, and accepts its own output', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows, authority.baselineLaneRows));
  assert.deepEqual(out.partsByRegion.jp.filter(row => row[0] === LINE).map(row => row[4]), authority.candidatePartLengths);
  assert.deepEqual(out.byRegion.jp.filter(row => row[0] === LINE), authority.candidateLaneRows);
  assert.deepEqual(out.byRegion.jp[0], ['other', 0, 0, 1, 0.5]);
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows);
  stale[0][4] -= 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale, authority.baselineLaneRows)), /stale/);
});

test('candidate-review receipt is pinned to the reviewed sha and scope', () => {
  const receipt = {format: SPEC.receiptFormat, status: 'bounded-candidate-reviewed', lineID: LINE,
    stationIDs: SPEC.stationIDs, intervalIndices: SPEC.intervalIndices, reviewedOwnLineSha256: SPEC.candidateSha,
    MainCertified: false, wholeLineAccepted: false};
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: SPEC.baselineSha}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(null, authority.candidateLine));
});

test('all 1263 Apple-trace supports remain within 0.5 m and cited reviews exist', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  assert.deepEqual(parts.map(part => part.length), authority.candidatePartLengths);
  assert.equal(authority.supportCoordinates.length, 1263);
  // Each support is measured against its own display interval (as the independent gate does), else the public parts.
  for (const support of authority.supportCoordinates) {
    const own = authority.candidateLine.displayIntervalCoordinates?.[support.interval];
    assert(distance(support.longitudeLatitude, own ? [own] : parts) <= 0.5, `${support.id} within 0.5 m`);
  }
  for (const evidence of authority.sourceReviews)
    assert(fs.existsSync(new URL('../../../../' + evidence, import.meta.url)), evidence);
});

test('only scoped display data changes and the physical line stays continuous', () => {
  const before = authority.baselineLine, after = authority.candidateLine;
  assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before));
  assert.equal(net.displayPartsForLine(after).length, net.displayPartsForLine(before).length);
  for (let i = 0; i < before.segments.length; i += 1) if (!SPEC.intervalIndices.includes(i))
    assert.deepEqual(after.displayIntervalCoordinates?.[i], before.displayIntervalCoordinates?.[i], `interval ${i}`);
  for (const [id, value] of Object.entries(before.displayStationCoordinates || {})) if (!SPEC.stationIDs.includes(id))
    assert.deepEqual(after.displayStationCoordinates[id], value, id);
  for (const i of SPEC.intervalIndices) {
    const coordinates = after.displayIntervalCoordinates[i];
    const end = row => after.displayStationCoordinates?.[row[0]] ?? row.slice(2, 4);
    assert.deepEqual(coordinates[0], end(after.stations[i]), `interval ${i} start`);
    assert.deepEqual(coordinates.at(-1), end(after.stations[(i + 1) % after.stations.length]), `interval ${i} end`);
  }
});
