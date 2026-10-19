import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { candidateGeoJSON, repairPackage, repairParts }
  from '../repair-shinonoi-obasute-fork-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const stroke = require('../../../public/rail-stroke.js');
const e = JSON.parse(fs.readFileSync(new URL('../shinonoi-obasute-fork-display-evidence.json', import.meta.url)));
const candidate = JSON.parse(fs.readFileSync(new URL(`../../../../${e.source.candidatePath}`, import.meta.url)));
const fixture = () => ({ lines: Array.from({ length: e.baseline.packageIndex }, (_, index) => ({ id: `before-${index}` }))
  .concat([structuredClone(e.baseline.line), { id: 'unrelated', keep: true }]),
geometrySource: { manualOverrides: { concurrent: { keep: true } } } });
const lanes = () => ({ partsByRegion: { jp: [...structuredClone(e.baseline.nativeRows), ['unrelated', 0, 1]] },
  ...Object.fromEntries(Object.entries(e.baseline.measuredReferences).map(([key, rows]) =>
    [key, { jp: [...structuredClone(rows), ...(key === 'byRegion' ? [['unrelated', 0, 0, 1, 0]] : [])] }])) });

test('frozen Obasute candidate and source cartography reject provenance drift', () => {
  for (const [key, digest] of [['candidatePath', 'candidateSha256'], ['intervalsPath', 'intervalsSha256'],
    ['interval11Path', 'interval11Sha256'], ['interval12Path', 'interval12Sha256']]) {
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(new URL(`../../../../${e.source[key]}`,
      import.meta.url))).digest('hex'), e.source[digest]);
  }
  assert.deepEqual(candidate.junction.candidate, e.junction.displayFork);
  assert.deepEqual(candidate.station.registeredCoordinate, e.stationCoordinate);
  for (const mutate of [value => value.junction.displayFork[0] += .00001,
    value => value.baseline.line.segments[11][0] += 1,
    value => value.source.candidateSha256 = 'wrong']) {
    const changed = structuredClone(e); mutate(changed);
    assert.throws(() => repairPackage(fixture(), changed));
  }
});

test('repair adds only the two reviewed display intervals and preserves physical ownership', () => {
  const input = fixture(), pkg = repairPackage(input, e), line = pkg.lines[e.baseline.packageIndex];
  const physical = network.decodeIntervals(e.baseline.line);
  assert.deepEqual(line.stations, e.baseline.line.stations);
  assert.deepEqual(line.segments, e.baseline.line.segments);
  assert.deepEqual(network.decodeIntervals(line), physical);
  assert.equal(line.displayStationCoordinates, undefined);
  assert.deepEqual(Object.keys(line.displayIntervalCoordinates).map(Number).sort((a, b) => a - b), [11, 12]);
  assert.deepEqual(line.displayIntervalCoordinates[11], candidate.candidate.interval11);
  assert.deepEqual(line.displayIntervalCoordinates[12], candidate.candidate.interval12);
  assert.deepEqual(line.displayIntervalCoordinates[11].slice(0, 94), physical[11].slice(0, 94));
  assert.deepEqual(line.displayIntervalCoordinates[11].slice(95), physical[11].slice(95));
  assert.deepEqual(line.displayIntervalCoordinates[12].slice(0, 5), physical[12].slice(0, 5));
  assert.deepEqual(line.displayIntervalCoordinates[12].slice(e.guard.candidateIndex),
    physical[12].slice(e.guard.suffixPreservedFromIndex));
  assert.deepEqual(line.displayIntervalCoordinates[11][94], e.junction.displayFork);
  assert.deepEqual(line.displayIntervalCoordinates[12][5], e.junction.displayFork);
  assert.deepEqual(line.displayIntervalCoordinates[11].at(-1), e.stationCoordinate);
  assert.deepEqual(line.displayIntervalCoordinates[12][0], e.stationCoordinate);
  assert.deepEqual(pkg.lines.at(-1), input.lines.at(-1));
  assert.deepEqual(pkg.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.equal(pkg.geometrySource.manualOverrides['shinonoi-obasute-fork-display'].physicalTopologyChanged, false);
  assert.deepEqual(repairPackage(pkg, e), pkg);
  const stale = structuredClone(pkg);
  stale.geometrySource.manualOverrides['shinonoi-obasute-fork-display'].status = 'wrong';
  assert.throws(() => repairPackage(stale, e), /dependency metadata/);
});

test('both native parts replay while the Matsumoto measure and all other consumers remain frozen', () => {
  const pkg = repairPackage(fixture(), e), before = lanes(), after = repairParts(pkg, before, e);
  const ours = after.partsByRegion.jp.filter(row => row[0] === e.lineID);
  assert.equal(ours.length, 2);
  assert.notDeepEqual(ours[0], e.baseline.nativeRows[0]);
  assert.notDeepEqual(ours[1], e.baseline.nativeRows[1]);
  assert.deepEqual(ours.map(row => row.slice(0, 4)), e.baseline.nativeRows.map(row => row.slice(0, 4)));
  assert.equal(ours[0][4], e.baseline.nativeRows[0][4]);
  assert.equal(ours[1][4], e.baseline.nativeRows[1][4] + 29);
  assert.deepEqual(ours.map(row => row[6]), e.baseline.nativeRows.map(row => row[6]));
  assert.deepEqual(ours.map(row => row[8]), e.baseline.nativeRows.map(row => row[8]));
  assert.deepEqual(ours[0][7][0], e.junction.displayFork);
  assert(ours[1][7].some(point => JSON.stringify(point) === JSON.stringify(e.junction.displayFork)));
  for (const key of Object.keys(e.baseline.measuredReferences)) assert.deepEqual(after[key], before[key]);
  assert.deepEqual(after.byRegion.jp.find(row => row[0] === e.lineID),
    [e.lineID, 1, 13257.1, 14975, -0.5]);
  assert.deepEqual(after.partsByRegion.jp.at(-1), before.partsByRegion.jp.at(-1));
  assert.deepEqual(repairParts(pkg, after, e), after);
});

test('candidate root geometry is one feature containing both complete reviewed intervals', () => {
  const pkg = repairPackage(fixture(), e), geojson = candidateGeoJSON(pkg, e);
  assert.equal(geojson.features.length, 1);
  assert.deepEqual(geojson.features[0].properties.intervalIndices, [11, 12]);
  assert.deepEqual(geojson.features[0].geometry.coordinates,
    [...candidate.candidate.interval11, ...candidate.candidate.interval12.slice(1)]);
});

test('runtime parts retain the station spur, representative fork, and source guard', () => {
  const pkg = repairPackage(fixture(), e), repairedLanes = repairParts(pkg, lanes(), e);
  const built = network.buildNetworkFromCompactPackage({ format: 'compact-v1', country: 'jp',
    lines: [pkg.lines[e.baseline.packageIndex]] }, null, repairedLanes);
  const parts = built.strokeModel.lines.find(row => row.lineId === e.lineID).parts;
  assert.equal(parts.length, 2);
  assert.deepEqual(parts[0].coordinates, candidate.candidate.interval11.slice(94));
  const forkIndex = parts[1].coordinates.findIndex(point => JSON.stringify(point) === JSON.stringify(e.junction.displayFork));
  const guardIndex = parts[1].coordinates.findIndex(point => JSON.stringify(point) === JSON.stringify(e.guard.coordinate));
  assert(forkIndex > 0 && guardIndex > forkIndex);
  assert.equal(parts[1].coordinates.length, e.baseline.nativeRows[1][4] + 29);
  assert(parts[0].anchors.includes(parts[0].coordinates.length - 1), 'Obasute station remains the spur anchor');
  for (const zoom of [17, 18]) {
    const rendered = stroke.buildStroke(parts[0].coordinates.map(point => stroke.project(point, zoom)), {
      measures: parts[0].measures, rows: parts[0].rows, totalMetres: parts[0].totalMetres,
      laneGapPx: 2.7, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: 3,
      anchors: parts[0].anchors, enforceMinimumCornerRadius: true, follows: [],
    });
    const station = stroke.project(e.stationCoordinate, zoom);
    assert(rendered.points.some(point => Math.hypot(point[0] - station[0], point[1] - station[1]) < 1e-9));
  }
});

test('changed physical baselines and new measured consumers require explicit review', () => {
  const altered = fixture(); altered.lines[e.baseline.packageIndex].segments[12][2][25][0] += .00001;
  assert.throws(() => repairPackage(altered, e), /dependency|baseline/);
  const pkg = repairPackage(fixture(), e), input = lanes();
  input.familyWindowsByRegion.jp.push([e.lineID, 1, 0, 1]);
  assert.throws(() => repairParts(pkg, input, e), /measured reference/);
});
