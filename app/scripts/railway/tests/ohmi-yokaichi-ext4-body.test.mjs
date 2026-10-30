import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {sha} from '../lib/display-candidate-repair.mjs';
import {SPEC, AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview} from '../repair-ohmi-yokaichi-ext4-body.mjs';
const authority = JSON.parse(fs.readFileSync(AUTHORITY_PATH));
const LINE = SPEC.lineID;
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const lanesOf = (native, lane) => ({partsByRegion: {jp: [['other', 'x'], ...structuredClone(native)]}, byRegion: {jp: [['other', 0, 0, 1, 0.5], ...structuredClone(lane)]}});
const own = pkg => pkg.lines.find(line => line.id === LINE);
test('repairs only the reviewed body and is idempotent', () => {
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), SPEC.candidateSha);
  assert.deepEqual(own(out).displayIntervalCoordinates[0], authority.baselineLine.displayIntervalCoordinates?.[0]);
  assert.deepEqual(own(out).displayStationCoordinates['005652'], authority.baselineLine.displayStationCoordinates?.['005652']);
  assert.deepEqual(repairPackage(out), out);
});
test('rejects tampered authority, scope and stale baseline', () => {
  const bad = structuredClone(authority); bad.candidateLine.displayStationCoordinates['005665'][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const scope = structuredClone(authority); scope.intervalIndices = scope.intervalIndices.slice(1);
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
  const stale = structuredClone(authority.baselineLine); stale.stations[0][2] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(stale)), /stale|physical/);
});
test('writes candidate native rows without foreign changes', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows, authority.baselineLaneRows));
  assert.deepEqual(out.partsByRegion.jp.filter(row => row[0] === LINE).map(row => row[4]), authority.candidatePartLengths);
  assert.deepEqual(out.byRegion.jp.filter(row => row[0] === LINE), authority.candidateLaneRows);
  assert.deepEqual(repairParts(pkg, out), out);
});
test('review receipt must match bounded scope and candidate sha', () => {
  const receipt = {format: SPEC.receiptFormat, status: 'bounded-candidate-reviewed', lineID: LINE,
    stationIDs: SPEC.stationIDs, intervalIndices: SPEC.intervalIndices, reviewedOwnLineSha256: SPEC.candidateSha,
    MainCertified: false, wholeLineAccepted: false};
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: SPEC.baselineSha}, authority.candidateLine));
});
