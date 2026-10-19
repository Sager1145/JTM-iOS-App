import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { assertApplyAccepted, candidateGeoJSON, loadReviewedCandidate, repairPackage,
  repairParts, repairedNativeRow } from '../repair-keikyu-airport-terminal-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const e = JSON.parse(fs.readFileSync(new URL('../keikyu-airport-terminal-display-evidence.json',
  import.meta.url)));
const livePackage = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json',
  import.meta.url)));
const liveLanes = JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json',
  import.meta.url)));
const hash = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');

function packageFixture() {
  const lines = Array.from({ length: e.packageIndex + 2 }, (_, index) => ({ id: `unrelated-${index}` }));
  const line = structuredClone(livePackage.lines[e.packageIndex]);
  delete line.displayIntervalCoordinates;
  delete line.displayStationCoordinates;
  lines[e.packageIndex] = line;
  lines[e.packageIndex + 1] = { id: 'unrelated-after', keep: true };
  return { format: 'compact-v1', country: 'jp', lines,
    geometrySource: { manualOverrides: { concurrent: { keep: true } } } };
}

function laneFixture() {
  const live = liveLanes.partsByRegion.jp.find(item => item[0] === e.lineID);
  const row = hash(live) === e.nativeReplay.candidateRowSha256
    ? structuredClone(e.baseline.nativeRow) : structuredClone(live);
  return { partsByRegion: { jp: [row, ['unrelated', 0, 1]] },
    byRegion: { jp: [['unrelated', 0, 0, 1, 0.5]] },
    followsByRegion: { jp: [['unrelated', 0, 0, 1, 'other', 0, 0, 1]] },
    familyWindowsByRegion: { jp: [] }, groupWindowsByRegion: { jp: {} } };
}

test('frozen V5 follows own Keikyu glyphs and literal station-frame seams', () => {
  const candidate = loadReviewedCandidate(e);
  assert.deepEqual(candidate.coordinates.map(item => item.length), [53, 53, 33, 40, 62, 94]);
  assert.deepEqual(candidate.coordinates[0][0], candidate.sourceIntervals[0][0]);
  for (const [stationID, intervalIndex] of Object.entries(e.candidate.stationEndIntervals)) {
    assert.deepEqual(candidate.coordinates[intervalIndex].at(-1), e.candidate.stationAliases[stationID]);
    if (intervalIndex < 5)
      assert.deepEqual(candidate.coordinates[intervalIndex + 1][0], e.candidate.stationAliases[stationID]);
  }
  assert.match(candidate.fitEvidence.interval1Gap, /rejected upper building\/frame-edge hump/);
  assert.match(candidate.fitEvidence.interval5, /normal cross-section trace/);
  assert(candidate.fitEvidence.interval5Trace.signedNormalOffsetsMetres.includes(26));
  assert(candidate.fitEvidence.interval5Trace.signedNormalOffsetsMetres.includes(-3));
  for (const [revision, sha256] of Object.entries(e.candidate.rejectedEarlierCandidates))
    if (revision !== 'reason') assert.notEqual(e.candidate.candidateSha256, sha256);
});

test('repair changes only complete display geometry and six aliases while physical identity and mileage stay exact', () => {
  const before = packageFixture();
  const original = structuredClone(before.lines[e.packageIndex]);
  const physical = network.decodeIntervals(original);
  const after = repairPackage(before, e);
  const line = after.lines[e.packageIndex];
  const candidate = loadReviewedCandidate(e);
  assert.deepEqual(Object.keys(line.displayIntervalCoordinates), ['0', '1', '2', '3', '4', '5']);
  assert.deepEqual(Object.values(line.displayIntervalCoordinates), candidate.coordinates);
  assert.deepEqual(line.displayStationCoordinates,
    Object.fromEntries(Object.entries(candidate.displayStationCoordinates)
      .filter(([stationID]) => stationID !== '004331')));
  assert.equal(line.displayStationCoordinates['004331'], undefined);
  assert.deepEqual(network.decodeIntervals(line), physical);
  assert.deepEqual(line.stations, original.stations);
  assert.deepEqual(line.segments, original.segments);
  assert.deepEqual(after.lines.at(-1), before.lines.at(-1));
  assert.deepEqual(after.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.equal(after.geometrySource.manualOverrides['keikyu-airport-complete-display']
    .physicalTopologyChanged, false);
  assert.deepEqual(repairPackage(after, e), after);
});

test('owning helper rebuilds only one Keikyu native row and introduces no measured reference', () => {
  const pkg = repairPackage(packageFixture(), e);
  const before = laneFixture();
  const after = repairParts(pkg, before, e);
  const row = after.partsByRegion.jp.find(item => item[0] === e.lineID);
  assert.deepEqual(row, repairedNativeRow(pkg, e));
  assert.equal(hash(row), e.nativeReplay.candidateRowSha256);
  assert.deepEqual({ partCount: 1, pointCount: row[4], metres: row[5], classification: row[6] },
    e.nativeReplay.candidateSummary);
  assert.deepEqual(after.byRegion, before.byRegion);
  assert.deepEqual(after.followsByRegion, before.followsByRegion);
  assert.deepEqual(after.familyWindowsByRegion, before.familyWindowsByRegion);
  assert.deepEqual(after.groupWindowsByRegion, before.groupWindowsByRegion);
  assert.deepEqual(after.partsByRegion.jp.at(-1), before.partsByRegion.jp.at(-1));
  assert.deepEqual(repairParts(pkg, after, e), after);
});

test('candidate exports all six intervals and stale physical, display, native, or measured inputs fail closed', () => {
  const pkg = repairPackage(packageFixture(), e);
  const collection = candidateGeoJSON(pkg, e);
  assert.equal(collection.type, 'FeatureCollection');
  assert.deepEqual(collection.features.map(item => item.properties.referenceIntervalIndex),
    e.intervalIndexes);
  const physical = packageFixture();
  physical.lines[e.packageIndex].segments[5][0] += .001;
  assert.throws(() => repairPackage(physical, e), /physical dependency/);
  const display = packageFixture();
  display.lines[e.packageIndex].displayIntervalCoordinates = { 5: [[0, 0], [1, 1]] };
  assert.throws(() => repairPackage(display, e), /display dependency/);
  const native = laneFixture();
  native.partsByRegion.jp[0][5] += 1;
  assert.throws(() => repairParts(pkg, native, e), /native dependency/);
  const measured = laneFixture();
  measured.followsByRegion.jp.push([e.lineID, 0, 0, 1, 'other', 0, 0, 1]);
  assert.throws(() => repairParts(pkg, measured, e), /measured reference/);
});

test('apply stays blocked until actual native and Main review changes evidence status', () => {
  const pending = structuredClone(e);
  pending.status = 'candidate-only';
  assert.throws(() => assertApplyAccepted(pending), /accepted native and Main/);
  const accepted = structuredClone(e);
  accepted.status = accepted.policy.acceptanceGate;
  assert.doesNotThrow(() => assertApplyAccepted(accepted));
});
