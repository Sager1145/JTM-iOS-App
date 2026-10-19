import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { repairPackage, repairParts } from '../repair-denentoshi-shimmachi-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const e = JSON.parse(fs.readFileSync(new URL('../denentoshi-shimmachi-display-evidence.json', import.meta.url)));
const id = e.lineID;
const fixture = () => ({ format: 'compact-v1', country: 'jp', lines: [structuredClone(e.baselineLine), { id: 'unrelated', keep: true }],
  geometrySource: { license: '国土数値情報 CC BY 4.0; OpenStreetMap ODbL 1.0', manualOverrides: { concurrent: { keep: true } } } });
const lanes = () => ({ format: 'jtm-display-lanes-v1', ...Object.fromEntries(Object.entries(e.baselineRows).map(([key, rows]) =>
  [key, { jp: [['unrelated', 0, 0, 1, 0], ...structuredClone(rows)], tw: [['other-region']] }])),
  hubReportByRegion: { jp: e.baselineHubMembers.map(({ hubID, member }) => ({ hubId: hubID,
    members: [{ lineId: 'unrelated', keep: true }, structuredClone(member)], classes: [{ keep: true }] })) }, other: { keep: true } });
const interval = line => network.decodeIntervals(line)[3];
const expectedInterval = () => [...interval(e.baselineLine).slice(0, 8), ...structuredClone(e.reference.coordinates.slice(1, -1)),
  ...interval(e.baselineLine).slice(13)];
const partRow = value => value.partsByRegion.jp.find(row => row[0] === id);
function turn(a, b, c) {
  const cosine = Math.cos(b[1] * Math.PI / 180);
  const ab = [(b[0] - a[0]) * cosine, b[1] - a[1]], bc = [(c[0] - b[0]) * cosine, c[1] - b[1]];
  return Math.acos(Math.max(-1, Math.min(1, (ab[0] * bc[0] + ab[1] * bc[1]) / (Math.hypot(...ab) * Math.hypot(...bc))))) * 180 / Math.PI;
}

test('the reference copies only the identified westbound own way and preserves source files and inputs', () => {
  const sourceURL = new URL('../../../../' + e.referencePath, import.meta.url), before = fs.readFileSync(sourceURL, 'utf8');
  const source = JSON.parse(before), input = fixture(), original = structuredClone(input), evidence = structuredClone(e);
  assert.deepEqual(e.reference, source.fragments.find(row => row.wayID === '169057662'));
  assert.deepEqual(e.reference.directionRelationIDs, ['9341815']);
  assert.equal(e.reference.tags.source, 'KSJ2');
  assert.equal(e.reference.coordinates.slice(1, -1).length, 8);
  const result = repairPackage(input, e);
  assert.deepEqual(result.lines[0].displayIntervalCoordinates[3].slice(8, 16), e.reference.coordinates.slice(1, -1));
  assert.deepEqual(input, original);
  assert.deepEqual(e, evidence);
  assert.equal(fs.readFileSync(sourceURL, 'utf8'), before);
});

test('the rounded own curve retains both guards and the compound bend while preserving physical geometry and outside controls', () => {
  const input = fixture(), result = repairPackage(input, e), line = result.lines[0], original = interval(input.lines[0]);
  assert.deepEqual([original[7], original[13]], [[139.65614, 35.63095], [139.65139, 35.63089]]);
  assert(turn(...original.slice(8, 11)) > 29);
  const display = line.displayIntervalCoordinates[3];
  assert.deepEqual(display, expectedInterval());
  // Include the unchanged point before/after each guard, so a bad splice tangent fails.
  const bounded = display.slice(6, 18);
  for (let i = 1; i < bounded.length - 1; i++) assert(turn(bounded[i - 1], bounded[i], bounded[i + 1]) < 15);
  assert(turn(bounded[0], bounded[1], bounded.at(-1)) > 10, 'the genuine compound heading change must remain');
  assert.deepEqual(line.stations, input.lines[0].stations);
  assert.deepEqual(line.segments, input.lines[0].segments);
  assert.deepEqual(network.decodeIntervals(line), network.decodeIntervals(input.lines[0]));
  assert.deepEqual(line.displayIntervalCoordinates[0], input.lines[0].displayIntervalCoordinates[0]);
  assert.deepEqual(line.stationLaneByCode, input.lines[0].stationLaneByCode);
  assert.deepEqual(line.stationCircleOwnerByCode, input.lines[0].stationCircleOwnerByCode);
  assert.deepEqual(result.lines[1], input.lines[1]);
  assert.deepEqual(result.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.deepEqual(repairPackage(result, e), result);
});

test('the native embedded chain preserves station approaches and agrees with current Web geometry and endpoints', () => {
  const pkg = repairPackage(fixture(), e), input = lanes(), before = structuredClone(input), result = repairParts(pkg, input, e);
  const old = partRow(input), row = partRow(result), physical = interval(e.baselineLine);
  const start = old[7].findIndex(point => JSON.stringify(point) === JSON.stringify(physical[7]));
  assert.equal(start, 80);
  assert.deepEqual(old[7].slice(start, start + 7), physical.slice(7, 14));
  assert.deepEqual(row[7], [...old[7].slice(0, start + 1), ...e.reference.coordinates.slice(1, -1), ...old[7].slice(start + 6)]);
  assert.deepEqual(row.slice(0, 4), old.slice(0, 4));
  assert.equal(row[6], 'station-approach/groomed');
  assert.deepEqual(row.slice(8), old.slice(8));
  assert.equal(row[4], old[4] + 3);
  assert.equal(row[4], row[7].length);
  assert.notEqual(row[5], old[5]);
  const parts = network.displayPartsForLine(pkg.lines[0]);
  assert.equal(parts.length, 1);
  assert.deepEqual(parts[0].map(point => [...point]), row[7]);
  const oldParts = network.displayPartsForLine(e.baselineLine);
  assert.deepEqual([parts[0][0], parts[0].at(-1)], [oldParts[0][0], oldParts[0].at(-1)]);
  const owner = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url))).lines
    .find(line => line.id === 'jp-東京地下鉄-11号線半蔵門線');
  const built = network.buildNetworkFromCompactPackage({ ...pkg, lines: [pkg.lines[0], owner] }, null, result);
  const strokeParts = built.strokeModel.lines.find(line => line.lineId === id).parts;
  assert.equal(strokeParts.length, 1);
  assert.deepEqual(strokeParts[0].coordinates.map(point => [...point]), row[7]);
  assert.deepEqual([strokeParts[0].coordinates[0], strokeParts[0].coordinates.at(-1)], [oldParts[0][0], oldParts[0].at(-1)]);
  for (const key of Object.keys(e.baselineRows)) {
    if (key !== 'partsByRegion') assert.deepEqual(result[key], input[key]);
    assert.deepEqual(result[key].tw, input[key].tw);
    assert.deepEqual(result[key].jp.filter(row => row[0] !== id), input[key].jp.filter(row => row[0] !== id));
  }
  assert.deepEqual(result.hubReportByRegion, input.hubReportByRegion);
  assert.deepEqual(result.byRegion.jp.filter(row => row[0] === id), [[id, 0, 0, 300, 0]]);
  assert.deepEqual(input, before);
  assert.deepEqual(repairParts(pkg, result, e), result);
});

test('unreviewed package identity, geometry, source and dependent metadata reject', () => {
  for (const mutate of [pkg => pkg.lines[0].segments[3][0] += 1,
    pkg => pkg.lines[0].displayIntervalCoordinates[0][0][0] += .001,
    pkg => pkg.lines.push(structuredClone(pkg.lines[0])),
    pkg => pkg.geometrySource.license = 'unknown']) {
    const input = fixture(); mutate(input); assert.throws(() => repairPackage(input, e));
  }
  const bad = structuredClone(e); bad.reference.wayID = '671715587';
  assert.throws(() => repairPackage(fixture(), bad), /Unreviewed/);
  const pkg = repairPackage(fixture(), e);
  for (const mutate of [input => partRow(input)[7][0][0] += .001,
    input => partRow(input)[5] += 1,
    input => input.byRegion.jp.find(row => row[0] === id)[3] = 400,
    input => input.followsByRegion.jp.push(['other', 0, 0, 10, id, 0, 0, 10]),
    input => input.familyWindowsByRegion.jp.push([id, 0, 0, 10]),
    input => input.hubReportByRegion.jp[0].members[1].from = 0,
    input => input.unknownMetadata = { jp: [[id, 0, 0, 10]] }]) {
    const input = lanes(); mutate(input); assert.throws(() => repairParts(pkg, input, e), /Unreviewed/);
  }
});
