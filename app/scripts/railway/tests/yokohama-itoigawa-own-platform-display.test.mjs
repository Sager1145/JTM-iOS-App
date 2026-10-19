import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { repairPackage, repairParts } from '../repair-yokohama-itoigawa-own-platform-display.mjs';
const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const stroke = require('../../../public/rail-stroke.js');
const e = JSON.parse(fs.readFileSync(new URL('../yokohama-itoigawa-own-platform-display-evidence.json', import.meta.url)));
const ids = e.items.map(item => item.lineID);
// All owned inputs are frozen evidence, so these regressions survive production apply.
const fixture = () => ({ format: 'compact-v1', country: 'jp', lines: [...e.items.map(item => structuredClone(item.baselineLine)),
  { id: 'unrelated', retain: { stations: true } }], geometrySource: {
    license: '国土数値情報 CC BY 4.0; OpenStreetMap ODbL 1.0', manualOverrides: { concurrent: { keep: true } } } });
const lanes = () => ({ format: 'jtm-display-lanes-v1', ...Object.fromEntries(Object.entries(e.baselineRows).map(([key, value]) =>
  [key, { jp: [...structuredClone(value), ['unrelated', 0, 0, 1, 0]], tw: [['other-region']] }])),
  hubReportByRegion: { jp: e.baselineHubMembers.map(({ hubID, member }) => ({ hubId: hubID,
    members: [structuredClone(member), { lineId: 'unrelated', keep: true }], classes: [{ keep: true }] })) },
  followsElsewhere: { keep: true } });
function turn(a, b, c) {
  const latitude = b[1] * Math.PI / 180;
  const ab = [(b[0] - a[0]) * Math.cos(latitude), b[1] - a[1]];
  const bc = [(c[0] - b[0]) * Math.cos(latitude), c[1] - b[1]];
  return Math.acos(Math.max(-1, Math.min(1, (ab[0] * bc[0] + ab[1] * bc[1]) /
    (Math.hypot(...ab) * Math.hypot(...bc))))) * 180 / Math.PI;
}

test('Yokohama removes only the false 49.7 degree control and keeps the owner station and C support', () => {
  const input = fixture(), pkg = repairPackage(input, e), original = network.decodeIntervals(e.items[0].baselineLine)[0];
  const repaired = pkg.lines[0].displayIntervalCoordinates[0];
  assert(Math.abs(turn(...original.slice(0, 3)) - 49.7) < 1);
  assert(turn(...repaired.slice(0, 3)) < 15);
  assert.deepEqual(repaired, [original[0], ...original.slice(2)]);
  assert.deepEqual(repaired[0], e.items[0].baselineLine.stations[0].slice(2, 4));
  assert.deepEqual(repaired[1], original[2]);
  assert.equal(pkg.lines[0].stationLaneByCode['004633'], 0);
  assert.deepEqual(input, fixture(), 'repair mutated input');
});

test('Itoigawa ends on the own Oito bay platform; physical IDs, km and other intervals stay unchanged', () => {
  const input = fixture(), pkg = repairPackage(input, e);
  for (let i = 0; i < e.items.length; i++) {
    const item = e.items[i], line = pkg.lines[i], physical = network.decodeIntervals(item.baselineLine);
    assert.deepEqual(line.stations, item.baselineLine.stations);
    assert.deepEqual(line.segments, item.baselineLine.segments);
    assert.deepEqual(network.decodeIntervals(line), physical);
    assert.deepEqual(Object.keys(line.displayIntervalCoordinates), [String(item.intervalIndex)]);
    const displayLine = { ...line, segments: line.segments.map((row, index) => line.displayIntervalCoordinates[index]
      ? [row[0], 0, line.displayIntervalCoordinates[index]] : row) };
    const expanded = network.decodeIntervals(displayLine);
    physical.forEach((points, index) => { if (index !== item.intervalIndex) assert.deepEqual(expanded[index], points); });
  }
  const item = e.items[1], line = pkg.lines[1], physical = network.decodeIntervals(item.baselineLine)[7];
  assert.deepEqual(line.displayIntervalCoordinates[7], [...physical.slice(0, 33), ...item.ownDisplayTail.slice(1)]);
  assert.deepEqual(line.displayIntervalCoordinates[7].at(-1), item.displayAnchor);
  assert.deepEqual(line.displayStationCoordinates['001666'], item.displayAnchor);
  assert(!line.displayIntervalCoordinates[7].some(point => JSON.stringify(point) === JSON.stringify(physical.at(-1))));
  assert.equal(line.stationLaneByCode, undefined);
  assert.deepEqual(pkg.lines[2], input.lines[2]);
  assert.deepEqual(pkg.geometrySource.license, input.geometrySource.license);
  assert.deepEqual(pkg.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.deepEqual(repairPackage(pkg, e), pkg);
});

test('native parts and measured hub metadata change only for the reviewed owners and remain idempotent', () => {
  const pkg = repairPackage(fixture(), e), input = lanes(), before = structuredClone(input), result = repairParts(pkg, input, e);
  for (const key of Object.keys(e.baselineRows)) {
    assert.deepEqual(result[key].jp.filter(row => !ids.includes(row[0])), input[key].jp.filter(row => !ids.includes(row[0])));
    assert.deepEqual(result[key].tw, input[key].tw);
  }
  assert.equal(result.partsByRegion.jp.filter(row => ids.includes(row[0])).length, 2);
  assert.equal(result.byRegion.jp.filter(row => row[0] === ids[1]).length, 0);
  const rows = result.byRegion.jp.filter(row => row[0] === ids[0]);
  assert.deepEqual(rows[0], [ids[0], 0, 0, 300, 0]);
  const hub = result.hubReportByRegion.jp[0];
  assert.deepEqual(hub.members[1], input.hubReportByRegion.jp[0].members[1]);
  assert.deepEqual(hub.classes, input.hubReportByRegion.jp[0].classes);
  assert.equal(hub.members[0].from, 300);
  assert.equal(hub.members[0].to, rows[1][3]);
  assert.equal(hub.members[0].previousLane, 0);
  assert.equal(hub.members[0].slot, 1.5);
  assert(rows[1][3] < 1100);
  assert.equal(rows.at(-1)[3], result.partsByRegion.jp.find(row => row[0] === ids[0])[5]);
  assert.deepEqual(input, before);
  assert.deepEqual(result.followsElsewhere, input.followsElsewhere);
  assert.deepEqual(repairParts(pkg, result, e), result);
});

test('production Web stroke at zoom 19 reaches each reviewed owner platform', () => {
  const pkg = repairPackage(fixture(), e), repairedLanes = repairParts(pkg, lanes(), e);
  const built = network.buildNetworkFromCompactPackage({ ...pkg, lines: pkg.lines.slice(0, 2) }, null, repairedLanes);
  for (let index = 0; index < e.items.length; index++) {
    const item = e.items[index], line = pkg.lines[index];
    const parts = built.strokeModel.lines.find(row => row.lineId === item.lineID).parts;
    assert.equal(parts.length, 1);
    const part = parts[0], zoom = 19;
    const rendered = stroke.buildStroke(part.coordinates.map(point => stroke.project(point, zoom)), {
      measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
      laneGapPx: 2.7, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: 3,
      anchors: part.anchors, enforceMinimumCornerRadius: true, follows: [],
    });
    const first = line.displayStationCoordinates?.[line.stations[0][0]] || line.stations[0].slice(2, 4);
    const last = line.displayStationCoordinates?.[line.stations.at(-1)[0]] || line.stations.at(-1).slice(2, 4);
    const actual = index === 0 ? rendered.points[0] : rendered.points.at(-1);
    const coordinate = index === 0 ? first : last;
    {
      const expected = stroke.project(coordinate, zoom);
      assert(Math.hypot(actual[0] - expected[0], actual[1] - expected[1]) < 1e-8);
    }
    if (index === 0) assert.equal(part.rows[0].lane, 0, 'station pin must reach the final production stroke');
  }
});

test('unknown source geometry, ownership and measured metadata reject before repair', () => {
  for (const mutate of [pkg => pkg.lines[0].segments[0][0] += 1,
    pkg => pkg.lines[1].stations.at(-1)[2] += .001,
    pkg => pkg.lines[0].displayIntervalCoordinates = { 1: [[1, 2], [3, 4]] },
    pkg => pkg.geometrySource.license = 'unknown']) {
    const input = fixture(); mutate(input); assert.throws(() => repairPackage(input, e));
  }
  const badEvidence = structuredClone(e); badEvidence.sources.itoigawa[1] = 'https://example.com/unreviewed';
  assert.throws(() => repairPackage(fixture(), badEvidence), /Unreviewed source/);
  const pkg = repairPackage(fixture(), e);
  for (const mutate of [input => input.followsByRegion.jp.push([ids[0], 0, 0, 10, 'foreign', 0, 0, 10]),
    input => input.followsByRegion.jp.push(['foreign', 0, 0, 10, ids[1], 0, 0, 10]),
    input => input.familyWindowsByRegion.jp.push([ids[0], 0, 0, 10]),
    input => input.byRegion.jp[0][4] = 99,
    input => input.partsByRegion.jp[0][5] += 1,
    input => input.hubReportByRegion.jp[0].members[0].slot = 9,
    input => input.newMeasuredByRegion = { jp: [[ids[0], 0, 0, 10]] }]) {
    const input = lanes(); mutate(input); assert.throws(() => repairParts(pkg, input, e), /Unreviewed owner/);
  }
});
