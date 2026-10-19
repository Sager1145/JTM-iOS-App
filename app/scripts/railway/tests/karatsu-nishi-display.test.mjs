import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { assertApplyAccepted, candidateGeoJSON, loadReviewedCandidate, repairPackage,
  repairParts, repairedNativeRow } from '../repair-karatsu-nishi-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const e = JSON.parse(fs.readFileSync(new URL('../karatsu-nishi-display-evidence.json', import.meta.url)));
const livePackage = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const liveLanes = JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json', import.meta.url)));
const hash = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');

function packageFixture() {
  const lines = Array.from({ length: e.packageIndex + 2 }, (_, index) => ({ id: `unrelated-${index}` }));
  lines[e.packageIndex] = structuredClone(livePackage.lines[e.packageIndex]);
  lines[e.packageIndex + 1] = { id: 'unrelated-after', keep: true };
  return { format: 'compact-v1', country: 'jp', lines,
    geometrySource: { manualOverrides: { concurrent: { keep: true } } } };
}

function laneFixture() {
  const row = liveLanes.partsByRegion.jp.find(item => item[0] === e.lineID);
  return { partsByRegion: { jp: [structuredClone(row), ['unrelated', 0, 1]] },
    byRegion: { jp: [...structuredClone(e.baseline.measuredReferences.byRegion),
      ['unrelated', 0, 0, 1, 0.5]] },
    followsByRegion: { jp: [['unrelated', 0, 0, 1, 'other', 0, 0, 1]] },
    familyWindowsByRegion: { jp: [] } };
}

test('frozen candidate binds eight baseline/raw/reprojection frames and the literal guard suffix', () => {
  const candidate = loadReviewedCandidate(e), guard = e.candidate.guard;
  assert.deepEqual([candidate.sourceCoordinates.length, candidate.coordinates.length], [28, 208]);
  assert.deepEqual(candidate.coordinates[guard.candidateIndex], guard.coordinate);
  assert.deepEqual(candidate.coordinates.slice(guard.candidateIndex),
    candidate.sourceCoordinates.slice(guard.sourceIndex));
  assert.deepEqual(candidate.coordinates[0], e.candidate.stationAliases['009270']);
  assert.deepEqual(candidate.coordinates.at(-1), e.candidate.stationAliases['009278']);
  const manifest = JSON.parse(fs.readFileSync(new URL(`../../../../${e.candidate.manifest}`,
    import.meta.url)));
  assert.deepEqual([manifest.baselineFrameCount, manifest.rawFrameCount,
    manifest.finalReprojectionFrameCount], [8, 8, 8]);
});

test('repair owns only interval 0 and its two aliases while physical IDs, mileage, and other intervals stay exact', () => {
  const before = packageFixture(), original = structuredClone(before.lines[e.packageIndex]);
  const physical = network.decodeIntervals(original), after = repairPackage(before, e);
  const line = after.lines[e.packageIndex], candidate = loadReviewedCandidate(e);
  assert.deepEqual(Object.keys(line.displayIntervalCoordinates), ['0']);
  assert.deepEqual(line.displayIntervalCoordinates[0], candidate.coordinates);
  assert.deepEqual(line.displayStationCoordinates, e.candidate.stationAliases);
  assert.deepEqual(line.displayStationCoordinates['009278'],
    original.stations.find(station => station[0] === '009278').slice(2, 4));
  assert.deepEqual(network.decodeIntervals(line), physical);
  assert.deepEqual(line.stations, original.stations);
  assert.deepEqual(line.segments, original.segments);
  assert.deepEqual(physical.slice(1), network.decodeIntervals(line).slice(1));
  assert.deepEqual(after.lines.at(-1), before.lines.at(-1));
  assert.deepEqual(after.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.equal(after.geometrySource.manualOverrides['karatsu-nishi-display'].physicalTopologyChanged, false);
  assert.deepEqual(repairPackage(after, e), after);
});

test('owning helper rebuilds one native row, preserves its remote suffix, and updates only the existing length row', () => {
  const pkg = repairPackage(packageFixture(), e), before = laneFixture();
  const oldRow = before.partsByRegion.jp.find(row => row[0] === e.lineID);
  const after = repairParts(pkg, before, e), row = after.partsByRegion.jp.find(item => item[0] === e.lineID);
  assert.deepEqual(row, repairedNativeRow(pkg, e));
  assert.equal(hash(row), e.nativeReplay.candidateRowSha256);
  assert.deepEqual({ partCount: 1, pointCount: row[4], metres: row[5], classification: row[6] },
    e.nativeReplay.candidateSummary);
  assert.deepEqual(row[7].slice(-e.nativeReplay.commonSuffixPoints),
    oldRow[7].slice(-e.nativeReplay.commonSuffixPoints));
  assert.deepEqual(after.byRegion.jp.filter(item => item[0] === e.lineID),
    e.nativeReplay.candidateMeasuredReferences.byRegion);
  assert.deepEqual(after.followsByRegion, before.followsByRegion);
  assert.deepEqual(after.familyWindowsByRegion, before.familyWindowsByRegion);
  assert.deepEqual(after.partsByRegion.jp.at(-1), before.partsByRegion.jp.at(-1));
  assert.deepEqual(repairParts(pkg, after, e), after);
});

test('candidate is one complete feature and stale physical, display, native, or measured inputs fail closed', () => {
  const pkg = repairPackage(packageFixture(), e), feature = candidateGeoJSON(pkg, e);
  assert.deepEqual([feature.properties.referenceLineID, feature.properties.referenceIntervalIndex],
    [e.lineID, 0]);
  assert.deepEqual(feature.geometry.coordinates, loadReviewedCandidate(e).coordinates);
  const physical = packageFixture(); physical.lines[e.packageIndex].segments[0][0] += .001;
  assert.throws(() => repairPackage(physical, e), /physical dependency/);
  const display = packageFixture(); display.lines[e.packageIndex].displayIntervalCoordinates =
    { 0: [[0, 0], [1, 1]] };
  assert.throws(() => repairPackage(display, e), /display dependency/);
  const native = laneFixture(); native.partsByRegion.jp[0][5] += 1;
  assert.throws(() => repairParts(pkg, native, e), /native dependency/);
  const measured = laneFixture(); measured.followsByRegion.jp.push([e.lineID, 0, 0, 1, 'other', 0, 0, 1]);
  assert.throws(() => repairParts(pkg, measured, e), /measured reference/);
});

test('apply stays blocked until actual native and Main review changes the evidence status', () => {
  const pending = structuredClone(e); pending.status = 'candidate-only';
  assert.throws(() => assertApplyAccepted(pending), /accepted native and Main/);
  const accepted = structuredClone(e); accepted.status = accepted.policy.acceptanceGate;
  assert.doesNotThrow(() => assertApplyAccepted(accepted));
});
