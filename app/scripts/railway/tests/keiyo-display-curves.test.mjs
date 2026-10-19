import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { LINES, surveyedPath, repairPackage, repairParts, reviewSummary } from '../repair-keiyo-display-curves.mjs';
import { refreshDependencyReferences, DEPENDENCY_PATHS } from '../repair-three-reversal-extents.mjs';
import { retainedShioPackage, westernPassengerApproach } from '../repair-keiyo-shio-transverse-display.mjs';
import { retainedMinamiPackage } from '../repair-keiyo-minami-passenger-centre.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = relative => JSON.parse(fs.readFileSync(new URL(relative, import.meta.url)));
const evidence = read('../keiyo-display-curves-evidence.json');
const input = retainedMinamiPackage(retainedShioPackage(read('../../../public/rail/jp-2025.json')));
const cache = JSON.parse(fs.readFileSync(evidence.source.cacheAbsolutePath));
const raw = read('../../../data/rail-sections.json');
const find = (pkg, id) => pkg.lines.find(row => row.id === id);
// Reconstruct the actual original display state after later integration.
for (const id of LINES) delete find(input, id).displayIntervalCoordinates?.['0'];
delete input.geometrySource.manualOverrides['keiyo-display-curves'];
delete input.geometrySource.manualOverrides['keiyo-west-shared-corridor'];
delete find(input, 'jp-東日本旅客鉄道-京葉線').displayIntervalCoordinates?.[8];
const repaired = () => repairPackage(input, evidence, cache, raw);

test('both tail corrections retain N02 seams and exact consecutive passenger-track points', () => {
  const pkg = repaired();
  for (const [index, window] of evidence.windows.entries()) {
    const line = find(pkg, window.lineId), original = network.decodeIntervals(find(input, window.lineId))[0];
    const display = line.displayIntervalCoordinates?.['0'];
    assert(display, 'the reviewed curve requires display coordinates');
    const survey = surveyedPath(window, evidence, cache), [a, b] = window.indices;
    assert.equal(survey.points.length, [12, 10][index]);
    const tail = [...original.slice(0, a + 1), ...survey.points, ...original.slice(b)];
    assert.deepEqual(display, window.passengerApproach ? westernPassengerApproach(tail, window.passengerApproach, cache) : tail);
    assert.deepEqual(display[0], line.stations[0].slice(2, 4));
    assert.deepEqual(display.at(-1), line.stations[1].slice(2, 4));
    assert(survey.start.distanceM <= 15 && survey.end.distanceM <= 15);
    const removed = index === 0 ? [139.99249, 35.68318] : [139.93326, 35.67651];
    assert(original.some(point => JSON.stringify(point) === JSON.stringify(removed)));
    assert(!display.some(point => JSON.stringify(point) === JSON.stringify(removed)));
  }
});

test('physical N02 geometry, passenger bindings, mileage, dates and unrelated records are unchanged', () => {
  const baseline = structuredClone(input), pkg = repaired();
  assert.deepEqual(input, baseline);
  for (const id of LINES) {
    const { displayIntervalCoordinates, ...after } = find(pkg, id);
    const { displayIntervalCoordinates: ignored, ...before } = find(input, id);
    assert.deepEqual(after, before);
  }
  assert.deepEqual(pkg.lines.filter(row => !LINES.includes(row.id)), input.lines.filter(row => !LINES.includes(row.id)));
  for (const key of Object.keys(input).filter(key => !['lines', 'geometrySource'].includes(key))) assert.deepEqual(pkg[key], input[key]);
  const afterGeometry = structuredClone(pkg.geometrySource);
  delete afterGeometry.manualOverrides['keiyo-display-curves'];
  assert.deepEqual(afterGeometry, input.geometrySource);
  assert.deepEqual(repairPackage(pkg, evidence, cache, raw), pkg);
});

test('replay rejects changed source points, passenger identity, track seam, physical source and competing override', () => {
  const physical = structuredClone(input);
  find(physical, LINES[0]).segments[0][2][60][0] += 0.00001;
  assert.throws(() => repairPackage(physical, evidence, cache, raw), /source changed/);
  const source = structuredClone(cache);
  source.elements.find(row => row.id === 1436589310).geometry[3].lon += 0.00001;
  assert.throws(() => repairPackage(input, evidence, source, raw), /source changed/);
  const freight = structuredClone(evidence);
  freight.windows[0].ways[0].tags.service = 'siding';
  assert.throws(() => repairPackage(input, freight, null, raw), /passenger main-track/);
  const gap = structuredClone(evidence);
  gap.windows[0].ways[1].coordinates.at(-1)[0] += 0.00001;
  assert.throws(() => repairPackage(input, gap, null, raw), /track chain has a seam/);
  const changedRaw = structuredClone(raw);
  changedRaw.features[14150].geometry.coordinates[3][0] += 0.00001;
  assert.throws(() => repairPackage(input, evidence, cache, changedRaw), /original N02/);
  const competing = structuredClone(input);
  find(competing, LINES[1]).displayIntervalCoordinates = { 0: [[0, 0], [1, 1]] };
  assert.throws(() => repairPackage(competing, evidence, cache, raw), /override changed|outer guards changed/);
});

test('native part changes are confined to owned reviewed windows and leave all other measures/references intact', () => {
  const originalLanes = read('../../../public/rail/display-lanes.json');
  // This test exercises the historical tail-only stage. The shipped cache
  // also contains the later midcurve/shared-corridor stage; restore the
  // retained tail baseline locally instead of comparing different rulers.
  for (const window of evidence.windows)
    originalLanes.partsByRegion.jp = originalLanes.partsByRegion.jp.map(row =>
      row[0] === window.lineId ? window.nativePartBaseline[row[1]] : row);
  originalLanes.followsByRegion.jp = originalLanes.followsByRegion.jp.filter(row =>
    !LINES.includes(row[0]) && !LINES.includes(row[4]));
  originalLanes.familyWindowsByRegion.jp = originalLanes.familyWindowsByRegion.jp.filter(row =>
    !LINES.includes(row[0]) && row[0] !== 'jp-東日本旅客鉄道-京葉線');
  const candidate = repaired(), lanes = repairParts(candidate, originalLanes, evidence);
  const summary = reviewSummary(input, candidate, evidence);
  for (const row of summary) {
    const approachDelta = row.passengerApproach?.prefixMeasureDeltaMetres || 0;
    assert.equal(row.partMeasuresMetres.oldStart + approachDelta, row.partMeasuresMetres.newStart);
    assert(Math.abs((row.partMeasuresMetres.newTotal - row.partMeasuresMetres.oldTotal)
      - (row.partMeasuresMetres.newEnd - row.partMeasuresMetres.oldEnd)) < 1e-6,
    'native measure delta must come entirely from the bounded curve');
    const native = lanes.partsByRegion.jp.find(part => part[0] === row.lineID);
    assert.deepEqual(native[7], network.displayPartsForLine(find(candidate, row.lineID))[0]);
  }
  assert.deepEqual(lanes.partsByRegion.jp.filter(row => !LINES.includes(row[0])), originalLanes.partsByRegion.jp.filter(row => !LINES.includes(row[0])));
  assert.deepEqual(repairParts(candidate, lanes, evidence), lanes);
  const stale = structuredClone(originalLanes);
  stale.followsByRegion.jp.push([LINES[0], 0, 4700, 5000, 'other', 0, 0, 100]);
  assert.throws(() => repairParts(candidate, stale, evidence), /measured reference/);
});

test('dependency proposals preserve every station membership and source-evidence field', () => {
  const deps = Object.fromEntries(Object.entries(DEPENDENCY_PATHS).map(([key, relative]) => [key, read('../../../' + relative)]));
  const before = structuredClone(deps), candidate = repaired();
  const after = refreshDependencyReferences(candidate, deps);
  assert.deepEqual(deps, before);
  const expected = { 'public/rail/jp-2025.json': createHash('sha256').update(JSON.stringify(candidate)).digest('hex') };
  for (const [key, relative] of Object.entries(DEPENDENCY_PATHS))
    expected[relative] = createHash('sha256').update(JSON.stringify(after[key], null, 2) + '\n').digest('hex');
  for (const key of Object.keys(deps)) {
    const { inputSha256: oldRefs, ...oldEvidence } = deps[key];
    const { inputSha256: newRefs, ...newEvidence } = after[key];
    assert.deepEqual(newEvidence, oldEvidence);
    assert.deepEqual(Object.keys(newRefs), Object.keys(oldRefs));
    for (const ref of Object.keys(oldRefs)) assert.equal(newRefs[ref], expected[ref] || oldRefs[ref]);
  }
  assert.deepEqual(refreshDependencyReferences(candidate, after), after);
});

// 004531/000004 showed an eastward lean into the competing branch before
// returning west. Only explicit own Tokyo-route members may support this cut.
test('western passenger approach uses the explicit Tokyo route and strict unchanged outer guards', () => {
  const window = evidence.windows[1], approach = window.passengerApproach;
  const original = network.decodeIntervals(find(input, window.lineId))[0];
  const result = westernPassengerApproach(original, approach, cache);
  assert.deepEqual(approach.chain.map(row => row[0]), [229030139, 180845372, 180845377, 180845376]);
  assert.equal(approach.routeMembership.id, 14656632);
  assert.equal(approach.routeMembership.tags.to, '東京');
  assert.deepEqual(result.slice(0, 22), original.slice(0, 22));
  assert.deepEqual(result.slice(22, 44), approach.candidateWindow);
  assert.deepEqual(result.slice(44), original.slice(35));
  assert.deepEqual(result[48], original[39], 'the physical lower fork survives at its new display index');
  assert.deepEqual(westernPassengerApproach(result, approach, cache), result);
  const expected = repaired(), legacy = structuredClone(expected);
  const display = find(legacy, window.lineId).displayIntervalCoordinates[0];
  find(legacy, window.lineId).displayIntervalCoordinates[0] =
    [...display.slice(0, 22), ...approach.baselineWindow, ...display.slice(44)];
  assert.deepEqual(repairPackage(legacy, evidence, cache, raw), expected,
    'the earlier exact tail replay must adopt the owned window rather than restore its raw prefix');
  const wrongWindow = structuredClone(result);
  wrongWindow[29][0] += 0.00001;
  assert.throws(() => westernPassengerApproach(wrongWindow, approach, cache), /Unreviewed western approach/);
  const east = structuredClone(approach);
  east.chain[0][0] = 229030138;
  assert.throws(() => westernPassengerApproach(original, east), /route membership|eastern arm/);
  const wrongCache = structuredClone(cache);
  wrongCache.elements.find(row => row.id === 180845377).geometry[3].lon += 0.00001;
  assert.throws(() => westernPassengerApproach(original, approach, wrongCache), /passenger source changed/);
});
