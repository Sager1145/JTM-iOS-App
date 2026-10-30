import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {sha} from '../lib/display-candidate-repair.mjs';
import {SPEC, AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview} from '../repair-nishitetsu-amagi-r13a-display.mjs';
const authority = JSON.parse(fs.readFileSync(AUTHORITY_PATH));
const LINE = SPEC.lineID;
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const lanesOf = (native, lane) => ({partsByRegion: {jp: [['other', 'x'], ...structuredClone(native)]}, byRegion: {jp: [['other', 0, 0, 1, 0.5], ...structuredClone(lane)]}});
const own = pkg => pkg.lines.find(l => l.id === LINE);
test('repairPackage turns the baseline into the candidate and is idempotent', () => {
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), SPEC.candidateSha);
  assert.equal(sha(authority.baselineLine), SPEC.baselineSha);
  assert.equal(out.geometrySource.manualOverrides[SPEC.key].MainCertified, false);
  assert.deepEqual(repairPackage(out), out);
});
test('rejects tampered authority, scope and stale baseline', () => {
  const bad = structuredClone(authority); bad.candidateLine.displayStationCoordinates[SPEC.stationIDs[0]][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const scope = structuredClone(authority); scope.intervalIndices = scope.intervalIndices.slice(1);
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
  const stale = structuredClone(authority.baselineLine); stale.stations[0][2] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(stale)), /stale|physical/);
});
test('repairParts writes the candidate native rows and carried lane rows only', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows, authority.baselineLaneRows));
  assert.deepEqual(out.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r[4]), authority.candidatePartLengths);
  assert.deepEqual(out.byRegion.jp.filter(r => r[0] === LINE), authority.candidateLaneRows);
  assert.deepEqual(out.byRegion.jp[0], ['other', 0, 0, 1, 0.5]);
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows); stale[0][4] -= 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale, authority.baselineLaneRows)), /stale/);
});
test('candidate review receipt must match scope and sha', () => {
  const receipt = {format: SPEC.receiptFormat, status: 'bounded-candidate-reviewed', lineID: LINE, stationIDs: SPEC.stationIDs,
    intervalIndices: SPEC.intervalIndices, reviewedOwnLineSha256: SPEC.candidateSha, MainCertified: false, wholeLineAccepted: false};
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: SPEC.baselineSha}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(null, authority.candidateLine));
});
