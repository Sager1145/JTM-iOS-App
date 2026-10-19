import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { repairPackage, repairParts } from '../repair-hakone-yamasaki-display.mjs';
const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const stroke = require('../../../public/rail-stroke.js');
const e = JSON.parse(fs.readFileSync(new URL('../hakone-yamasaki-display-evidence.json', import.meta.url)));
const fixture = () => ({ lines: [structuredClone(e.baselineLine), { id: 'unrelated', keep: true }], geometrySource: {} });
const lanes = () => Object.fromEntries([['partsByRegion', { jp: structuredClone(e.baselineNativeRows) }],
  ...Object.entries(e.baselineMeasuredReferences).map(([k, rows]) => [k, { jp: structuredClone(rows) }])]);
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos(a[1] * Math.PI / 180), (b[1] - a[1]) * 111320);
const cross = (a, b, c) => (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);

test('Yamasaki display follows identified aerial-corroborated supports without changing physical or other intervals', () => {
  const before = fixture(), result = repairPackage(before, e), line = result.lines[0];
  const physical = network.decodeIntervals(e.baselineLine)[3], displayed = line.displayIntervalCoordinates?.[3];
  assert(displayed, 'Yamasaki display correction absent');
  for (const p of e.ways[1].coordinates.slice(17, 25)) assert(displayed.some(q => equal(p, q)), 'Identified curve support lost');
  assert.deepEqual(displayed.slice(0, 14), physical.slice(0, 14));
  assert.deepEqual(displayed.slice(-physical.slice(35).length), physical.slice(35));
  assert.deepEqual(line.stations, e.baselineLine.stations);
  assert.deepEqual(line.segments, e.baselineLine.segments);
  assert.deepEqual(line.displayStationCoordinates, e.baselineLine.displayStationCoordinates);
  for (let i = 4; i <= 9; i++) assert.deepEqual(line.displayIntervalCoordinates[i], e.baselineLine.displayIntervalCoordinates[i]);
  assert.deepEqual(line.displayReversalBranches, e.baselineLine.displayReversalBranches);
  assert.deepEqual(result.lines[1], before.lines[1]);
  assert.deepEqual(repairPackage(result, e), result);
});

test('tapered transition preserves source guard tangents and production stroke keeps the repaired curve', () => {
  const line = repairPackage(fixture(), e).lines[0], displayed = line.displayIntervalCoordinates?.[3];
  assert(displayed, 'Yamasaki display correction absent');
  const physical = network.decodeIntervals(e.baselineLine)[3], begin = 13;
  const end = displayed.findIndex(p => equal(p, physical[35]));
  assert(Math.abs(cross(physical[13], physical[14], displayed[begin + 1])) < 1e-14, 'Initial perpendicular connector');
  assert(Math.abs(cross(physical[34], physical[35], displayed[end - 1])) < 1e-14, 'Final perpendicular connector');
  const origin = displayed[0], projected = displayed.map(p => [(p[0] - origin[0]) * 111320 * .817, -(p[1] - origin[1]) * 111320]);
  const measures = [0]; for (let i = 1; i < displayed.length; i++) measures.push(measures.at(-1) + distance(displayed[i - 1], displayed[i]));
  const ink = stroke.buildStroke(projected, { measures, totalMetres: measures.at(-1), rows: [{ from: 0, to: measures.at(-1), lane: 0 }],
    laneGapPx: 2.7, cornerRadiusPx: 0, minCornerRadiusPx: 3, anchors: [0, displayed.length - 1], enforceMinimumCornerRadius: true });
  for (const p of e.ways[1].coordinates.slice(17, 25)) {
    const q = [(p[0] - origin[0]) * 111320 * .817, -(p[1] - origin[1]) * 111320];
    const residuals = ink.points.slice(1).map((b, i) => {
      const a = ink.points[i], dx = b[0] - a[0], dy = b[1] - a[1];
      const t = Math.max(0, Math.min(1, ((q[0] - a[0]) * dx + (q[1] - a[1]) * dy) / (dx * dx + dy * dy || 1)));
      return Math.hypot(q[0] - a[0] - t * dx, q[1] - a[1] - t * dy);
    });
    assert(Math.min(...residuals) < 1, 'Production stroke bypassed curve');
  }
});

test('outer stage rejects disconnected primary support, source guards and unknown measured references', () => {
  for (const mutate of [v => v.ways[1].nodes[0]++, v => v.ways[1].tags.service = 'siding',
    v => v.window.physicalGuards[0][1] += .0001]) {
    const changed = structuredClone(e); mutate(changed);
    assert.throws(() => repairPackage(fixture(), changed));
  }
  const pkg = repairPackage(fixture(), e), input = lanes();
  input.followsByRegion.jp.push([e.lineID, 1, 'unreviewed']);
  assert.throws(() => repairParts(pkg, input, e), /measured references/);
});

test('unrelated line and native metadata survive current-package outer-stage replay', () => {
  const before = fixture(); before.lines[1].displayIntervalCoordinates = { 2: [[1, 2], [3, 4]] };
  before.geometrySource.manualOverrides = { concurrentKisuki: { preserve: true } };
  const pkg = repairPackage(before, e), input = lanes();
  input.partsByRegion.jp.push(['unrelated', 0, 9, 9]);
  input.byRegion.jp.push(['unrelated', 0, 0, 123, .5]);
  const result = repairParts(pkg, input, e);
  assert.deepEqual(pkg.lines[1], before.lines[1]);
  assert.deepEqual(pkg.geometrySource.manualOverrides.concurrentKisuki, { preserve: true });
  assert.deepEqual(result.partsByRegion.jp.at(-1), input.partsByRegion.jp.at(-1));
  assert.deepEqual(result.byRegion.jp.at(-1), input.byRegion.jp.at(-1));
});

test('native repair updates only changed main-part geometry and its measured extent', () => {
  const pkg = repairPackage(fixture(), e), before = lanes(), result = repairParts(pkg, before, e);
  assert.notDeepEqual(result.partsByRegion.jp[1], before.partsByRegion.jp[1], 'Native part still stale');
  for (const i of [0, 2, 3, 4, 5, 6]) assert.deepEqual(result.partsByRegion.jp[i], before.partsByRegion.jp[i]);
  assert.deepEqual(result.partsByRegion.jp.map(r => r[7]), network.displayPartsForLine(pkg.lines[0]));
  assert.notEqual(result.byRegion.jp[1][3], before.byRegion.jp[1][3]);
  for (const [k, rows] of Object.entries(e.baselineMeasuredReferences)) if (k !== 'byRegion') assert.deepEqual(result[k].jp, rows);
  assert.deepEqual(result.byRegion.jp.filter(r => r[1] !== 1), before.byRegion.jp.filter(r => r[1] !== 1));
  assert.deepEqual(repairParts(pkg, result, e), result);
});
