import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { LINE, repairPackage, repairParts, reviewSummary } from '../repair-keishin-display-curve.mjs';
import { refreshDependencyReferences, DEPENDENCY_PATHS } from '../repair-three-reversal-extents.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const evidence = JSON.parse(fs.readFileSync(new URL('../keishin-display-curve-evidence.json', import.meta.url)));
const input = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const cache = JSON.parse(fs.readFileSync(evidence.source.cacheAbsolutePath));
const raw = JSON.parse(fs.readFileSync(new URL('../../../data/rail-sections.json', import.meta.url)));
const find = pkg => pkg.lines.find(line => line.id === LINE);
// Replay the actual old display state even after later package integration.
delete find(input).displayIntervalCoordinates?.['4'];
delete input.geometrySource.manualOverrides['keishin-display-curve'];
const repaired = () => repairPackage(input, evidence, cache, raw);

test('Keishin display replaces the off-track kink with the exact ordered passenger curve', () => {
  const pkg = repaired(), line = find(pkg), original = network.decodeIntervals(find(input))[4];
  const display = line.displayIntervalCoordinates?.['4'];
  assert(display, 'reviewed curve must be represented in display coordinates');
  const start = original.findIndex(point => JSON.stringify(point) === JSON.stringify(evidence.start));
  const end = original.findIndex(point => JSON.stringify(point) === JSON.stringify(evidence.end));
  assert.deepEqual(display, [...original.slice(0, start + 1),
    ...evidence.way.coordinates.slice(38, 51), ...original.slice(end)]);
  assert(!display.some(point => JSON.stringify(point) === JSON.stringify([135.85919, 35.00058])));
  assert.deepEqual(display[0], line.stations[4].slice(2, 4));
  assert.deepEqual(display.at(-1), line.stations[5].slice(2, 4));
  assert(network.displayPartsForLine(line).flat().some(point => JSON.stringify(point) === JSON.stringify([135.8589637, 35.0006217])),
    'the surveyed rounded apex survives production display grooming');
});

test('display correction preserves physical geometry, mileage, identities and unrelated records', () => {
  const before = structuredClone(input), pkg = repaired(), line = find(pkg);
  assert.deepEqual(input, before);
  assert.deepEqual(line.segments, find(input).segments);
  assert.deepEqual(line.stations, find(input).stations);
  for (const key of Object.keys(find(input)).filter(key => key !== 'displayIntervalCoordinates'))
    assert.deepEqual(line[key], find(input)[key]);
  assert.deepEqual(pkg.lines.filter(row => row.id !== LINE), input.lines.filter(row => row.id !== LINE));
  assert.deepEqual(pkg.stats, input.stats);
  assert.deepEqual(repairPackage(pkg, evidence, cache, raw), pkg);
});

test('replay refuses changed physical seams, secondary source or an existing competing display override', () => {
  const changed = structuredClone(input);
  find(changed).segments[4][2][17][0] += 0.00001;
  assert.throws(() => repairPackage(changed, evidence, cache, raw), /source changed/);
  const source = structuredClone(cache);
  source.elements.find(way => way.id === 30662150).geometry[42].lon += 0.00001;
  assert.throws(() => repairPackage(input, evidence, source, raw), /source changed/);
  const competing = structuredClone(input);
  find(competing).displayIntervalCoordinates = { 4: [[0, 0], [1, 1]] };
  assert.throws(() => repairPackage(competing, evidence, cache, raw), /override changed/);
});

test('native part candidate carries the complete corrected curve and leaves unrelated cache references intact', () => {
  const inputLanes = JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json', import.meta.url)));
  const candidate = repaired(), lanes = repairParts(candidate, inputLanes, evidence);
  const rows = lanes.partsByRegion.jp.filter(row => row[0] === LINE);
  assert.equal(rows.length, 1);
  const row = rows[0];
  assert.deepEqual(row.slice(1, 5), [0, -1, -1, 124]);
  assert.equal(row[6], 'station-approach/groomed');
  assert(!row[7].some(point => JSON.stringify(point) === JSON.stringify([135.85919, 35.00058])));
  assert.deepEqual(row[7], network.displayPartsForLine(find(candidate))[0]);
  assert.deepEqual(lanes.partsByRegion.jp.filter(row => row[0] !== LINE), inputLanes.partsByRegion.jp.filter(row => row[0] !== LINE));
  assert.deepEqual(repairParts(candidate, lanes, evidence), lanes);
  const summary = reviewSummary(input, candidate, evidence);
  assert.deepEqual(summary.partVertexIndices, { oldStart: 84, oldEnd: 86, newStart: 84, newEnd: 98 });
  assert(summary.seamAliases.start.metres < 1 && summary.seamAliases.end.metres < 6);
  assert.equal(summary.partMeasuresMetres.oldStart, summary.partMeasuresMetres.newStart);
  const stale = structuredClone(inputLanes);
  stale.followsByRegion.jp.push([LINE, 0, 6100, 6200, 'other', 0, 0, 100]);
  assert.throws(() => repairParts(candidate, stale, evidence), /measured reference/);
});

test('dependency refresh updates package references while preserving all station and identity evidence', () => {
  const deps = Object.fromEntries(Object.entries(DEPENDENCY_PATHS).map(([key, relative]) =>
    [key, JSON.parse(fs.readFileSync(new URL('../../../' + relative, import.meta.url)))]));
  const before = structuredClone(deps), candidate = repaired();
  const result = refreshDependencyReferences(candidate, deps);
  assert.deepEqual(deps, before);
  const expectedHash = createHash('sha256').update(JSON.stringify(candidate)).digest('hex');
  for (const key of Object.keys(deps)) {
    const { inputSha256: oldReferences, ...oldContent } = deps[key];
    const { inputSha256: newReferences, ...newContent } = result[key];
    assert.deepEqual(newContent, oldContent, 'station identities, memberships, names and evidence remain unchanged');
    assert.deepEqual(Object.keys(newReferences), Object.keys(oldReferences));
    if (Object.hasOwn(oldReferences, 'public/rail/jp-2025.json'))
      assert.equal(newReferences['public/rail/jp-2025.json'], expectedHash);
  }
  assert.deepEqual(refreshDependencyReferences(candidate, result), result);
});
