import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { assertApplyAccepted, candidateGeoJSON, loadReviewedCandidate, repairPackage,
  repairParts, repairedNativeRows } from '../repair-manyo-east-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const e = JSON.parse(fs.readFileSync(new URL('../manyo-east-display-evidence.json', import.meta.url)));
const livePackage = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const liveLanes = JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json', import.meta.url)));
const hash = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');

function packageFixture() {
  const max = Math.max(...Object.values(e.baseline.packageIndices));
  const lines = Array.from({ length: max + 2 }, (_, index) => ({ id: `unrelated-${index}` }));
  for (const lineID of e.lineIDs) {
    const index = e.baseline.packageIndices[lineID];
    lines[index] = structuredClone(livePackage.lines[index]);
  }
  lines[max + 1] = { id: 'unrelated-after', keep: true };
  return { format: 'compact-v1', country: 'jp', lines,
    geometrySource: { manualOverrides: { concurrent: { keep: true } } } };
}

function laneFixture() {
  const rows = e.lineIDs.map(lineID => structuredClone(liveLanes.partsByRegion.jp.find(row =>
    row[0] === lineID)));
  assert(rows.every(Boolean));
  return { partsByRegion: { jp: [...rows, ['unrelated', 0, 1]] },
    followsByRegion: { jp: [['unrelated', 0, 0, 1, 'other', 0, 0, 1]] },
    crossingsByRegion: { jp: [['unrelated', 1, 2]] } };
}

test('V5 freezes 24 continuous intervals and replaces all five rejected V4 gap aliases', () => {
  const { manifest, records } = loadReviewedCandidate(e);
  assert.equal(manifest.rawFrameCount, 76);
  assert.equal(manifest.finalReprojectionFrameCount, 76);
  assert.equal(manifest.files.filter(item => item.path.startsWith('raw/')).length, 76);
  assert.equal(manifest.files.filter(item => item.path.startsWith('reprojection/')).length, 76);
  assert.deepEqual([manifest.reusedV4ReprojectionFrameCount, manifest.newV5ReprojectionFrameCount],
    [52, 24]);
  assert.deepEqual(e.lineIDs.map(lineID => records[lineID].candidateIntervals.length), [7, 17]);
  for (const lineID of e.lineIDs) {
    const record = records[lineID];
    for (let index = 1; index < record.candidateIntervals.length; index += 1)
      assert.deepEqual(record.candidateIntervals[index - 1].coordinates.at(-1),
        record.candidateIntervals[index].coordinates[0]);
    assert.deepEqual(record.candidateIntervals[0].coordinates[0], e.candidate.sharedCoordinate);
  }
  const high = records[e.lineIDs[1]];
  assert.deepEqual(high.displayStationCoordinates['001870'], e.candidate.retainedTerminalCoordinate);
  assert.match(high.retainedTerminalWarning, /RETAINED original exact tuple/);
  for (const pick of e.candidate.manualPicks) {
    assert.deepEqual(high.displayStationCoordinates[pick.stationID], pick.coordinate);
    assert.notDeepEqual(pick.coordinate, pick.oldCoordinate, `Rejected V4 gap alias returned: ${pick.stationID}`);
    const xs = pick.visibleLongitudinalEndsApproxPixels.map(point => point[0]);
    const ys = pick.visibleLongitudinalEndsApproxPixels.map(point => point[1]);
    assert(pick.pixel[0] >= Math.min(...xs) && pick.pixel[0] <= Math.max(...xs));
    assert(pick.pixel[1] >= Math.min(...ys) && pick.pixel[1] <= Math.max(...ys));
  }
});

test('unified owner changes only display geometry on the two complete Manyo lines', () => {
  const before = packageFixture();
  const originals = Object.fromEntries(e.lineIDs.map(lineID => {
    const line = before.lines[e.baseline.packageIndices[lineID]];
    return [lineID, { line: structuredClone(line), intervals: network.decodeIntervals(line) }];
  }));
  const after = repairPackage(before, e);
  for (const lineID of e.lineIDs) {
    const line = after.lines[e.baseline.packageIndices[lineID]], original = originals[lineID];
    assert.deepEqual(network.decodeIntervals(line), original.intervals);
    assert.deepEqual(line.stations, original.line.stations);
    assert.deepEqual(line.segments, original.line.segments);
    assert.equal(Object.keys(line.displayIntervalCoordinates).length, e.candidate.intervalCounts[lineID]);
    for (let index = 0; index < line.stations.length; index += 1) {
      const stationID = line.stations[index][0], alias = line.displayStationCoordinates[stationID];
      if (index > 0) assert.deepEqual(line.displayIntervalCoordinates[index - 1].at(-1), alias);
      if (index < line.stations.length - 1) assert.deepEqual(line.displayIntervalCoordinates[index][0], alias);
    }
  }
  assert.deepEqual(after.lines.at(-1), before.lines.at(-1));
  assert.deepEqual(after.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.equal(after.geometrySource.manualOverrides['manyo-complete-display'].physicalTopologyChanged, false);
  assert.deepEqual(repairPackage(after, e), after);
  const liveAfter = repairPackage(livePackage, e);
  const westIndex = livePackage.lines.findIndex(line => line.id === 'jp-九州旅客鉄道-唐津線');
  assert.deepEqual(liveAfter.lines[westIndex], livePackage.lines[westIndex]);
  assert.deepEqual(liveAfter.geometrySource.manualOverrides['karatsu-nishi-display'],
    livePackage.geometrySource.manualOverrides['karatsu-nishi-display']);
});

test('owning helper rebuilds exactly two native parts without creating measured references', () => {
  const pkg = repairPackage(packageFixture(), e), before = laneFixture();
  const after = repairParts(pkg, before, e), rebuilt = repairedNativeRows(pkg, e);
  for (const lineID of e.lineIDs) {
    const row = after.partsByRegion.jp.find(item => item[0] === lineID);
    assert.deepEqual(row, rebuilt[lineID]);
    assert.equal(hash(row), e.nativeReplay.candidateRowSha256[lineID]);
    assert.deepEqual({ partCount: 1, pointCount: row[4], metres: row[5], classification: row[6] },
      e.nativeReplay.candidateSummary[lineID]);
  }
  assert.deepEqual(after.followsByRegion, before.followsByRegion);
  assert.deepEqual(after.crossingsByRegion, before.crossingsByRegion);
  assert.deepEqual(after.partsByRegion.jp.at(-1), before.partsByRegion.jp.at(-1));
  assert.deepEqual(repairParts(pkg, after, e), after);
  const livePkg = repairPackage(livePackage, e), liveAfter = repairParts(livePkg, liveLanes, e);
  const westRow = rows => rows.partsByRegion.jp.find(row => row[0] === 'jp-九州旅客鉄道-唐津線');
  assert.deepEqual(westRow(liveAfter), westRow(liveLanes));
});

test('24-feature candidate is complete and stale physical, display, native, or reference inputs fail closed', () => {
  const pkg = repairPackage(packageFixture(), e), geo = candidateGeoJSON(pkg, e);
  assert.equal(geo.features.length, 24);
  assert.deepEqual(geo.features.map(feature =>
    `${feature.properties.referenceLineID}#${feature.properties.referenceIntervalIndex}`),
  e.lineIDs.flatMap(lineID => Array.from({ length: e.candidate.intervalCounts[lineID] },
    (_, index) => `${lineID}#${index}`)));
  const changedPhysical = packageFixture();
  changedPhysical.lines[e.baseline.packageIndices[e.lineIDs[0]]].segments[0][0] += .001;
  assert.throws(() => repairPackage(changedPhysical, e), /physical dependency/);
  const conflictingDisplay = packageFixture();
  conflictingDisplay.lines[e.baseline.packageIndices[e.lineIDs[1]]].displayIntervalCoordinates = { 0: [[0, 0], [1, 1]] };
  assert.throws(() => repairPackage(conflictingDisplay, e), /display dependency/);
  const changedNative = laneFixture();
  changedNative.partsByRegion.jp.find(row => row[0] === e.lineIDs[1])[5] += 1;
  assert.throws(() => repairParts(pkg, changedNative, e), /native dependency/);
  const newReference = laneFixture();
  newReference.followsByRegion.jp.push([e.lineIDs[0], 0, 0, 1, 'unknown', 0, 0, 1]);
  assert.throws(() => repairParts(pkg, newReference, e), /measured reference/);
});

test('apply remains blocked until native and Main acceptance is explicit', () => {
  const pending = structuredClone(e);
  pending.status = 'candidate-only';
  assert.throws(() => assertApplyAccepted(pending), /accepted native and Main/);
  const reviewed = structuredClone(e);
  reviewed.status = reviewed.policy.acceptanceGate;
  assert.doesNotThrow(() => assertApplyAccepted(reviewed));
});
