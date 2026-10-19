import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import test from 'node:test';
import { repairPackage, repairParts, LINE } from '../repair-nihongi-switchback.mjs';
import { partRowsForLine } from '../build-display-lanes.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const packageInput = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const nativeInput = JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json', import.meta.url)));
const evidence = JSON.parse(fs.readFileSync(new URL('../nihongi-switchback-evidence.json', import.meta.url)));
const baseline = structuredClone(packageInput);
delete baseline.lines.find(line => line.id === LINE).reversalTails;
delete baseline.geometrySource.manualOverrides?.['nihongi-switchback-display'];
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const nativeBaseline = structuredClone(nativeInput);
const oldParts = network.displayPartsForLine(baseline.lines.find(line => line.id === LINE));
const oldRows = partRowsForLine(baseline.lines.find(line => line.id === LINE), oldParts, null, null);
nativeBaseline.partsByRegion.jp = nativeBaseline.partsByRegion.jp.map(row => row[0] === LINE ? oldRows[row[1]] : row);
nativeBaseline.byRegion.jp = nativeBaseline.byRegion.jp.filter(row => row[0] !== LINE);
nativeBaseline.byRegion.jp.push([LINE, 1, 22100, 22695.4, -0.5]);
nativeBaseline.followsByRegion.jp = nativeBaseline.followsByRegion.jp.filter(row => row[0] !== LINE && row[4] !== LINE);
nativeBaseline.followsByRegion.jp.push([LINE, 0, 13950, 14002.021865360595, LINE, 1, 25, 0]);

function distance(a, b) {
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
    (b[1] - a[1]) * 111320);
}

function pointAt(points, target) {
  for (let i = 1, measure = 0; i < points.length; i++) {
    const length = distance(points[i - 1], points[i]);
    if (measure + length >= target) {
      const t = (target - measure) / length;
      return points[i - 1].map((value, k) => value + (points[i][k] - value) * t);
    }
    measure += length;
  }
  return points.at(-1);
}

test('Nihongi draws the physical south spur once and keeps the through main continuous', () => {
  const beforeLine = baseline.lines.find(line => line.id === LINE);
  const before = network.displayPartsForLine(beforeLine);
  assert.equal(before.length, 2);
  assert.deepEqual(before[1].slice(0, 2), [evidence.station, evidence.oldDiagonalEnd]);
  const afterPackage = repairPackage(baseline, evidence);
  const afterLine = afterPackage.lines.find(line => line.id === LINE);
  const after = network.displayPartsForLine(afterLine);
  assert.deepEqual(after.map(points => points.length), [7, 472]);
  assert.deepEqual(after[0], evidence.incomingTail);
  assert.deepEqual(after[0][0], evidence.protectedExtent);
  assert.deepEqual(after[0].at(-1), evidence.station);
  const junction = after[1].findIndex(point => same(point, evidence.protectedExtent));
  assert.equal(junction, 211);
  assert.deepEqual(after[1].slice(0, junction + 1), before[0].slice(0, junction + 1));
  assert.deepEqual(after[1].slice(junction + 6), before[1].slice(1));
  assert(!after[1].some(point => same(point, evidence.station)), 'the off-main station belongs to its spur');
  assert.deepEqual(afterLine.stations, beforeLine.stations);
  assert.deepEqual(afterLine.segments, beforeLine.segments);
  assert.deepEqual(baseline.lines.filter(line => line.id !== LINE), afterPackage.lines.filter(line => line.id !== LINE));
  assert.deepEqual(repairPackage(afterPackage, evidence), afterPackage);
});

test('native replay remaps the terminal lane and removes the obsolete duplicate self-follow', () => {
  const repaired = repairPackage(baseline, evidence);
  const result = repairParts(repaired, nativeBaseline, evidence);
  const rows = result.partsByRegion.jp.filter(row => row[0] === LINE);
  assert.deepEqual(rows.map(row => row[4]), [7, 472]);
  assert.deepEqual(rows.map(row => row.slice(2, 4)), [[-1, -1], [-1, -1]]);
  assert.deepEqual(rows[0][7], evidence.incomingTail);
  const main = rows[1][7];
  const lane = result.byRegion.jp.find(row => row[0] === LINE);
  assert.deepEqual(lane, [LINE, 1, 35929.1, 36524.5, -0.5]);
  assert.equal(lane[3], rows[1][5]);
  assert(distance(pointAt(oldParts[1], 22100), pointAt(main, lane[2])) < 0.06);
  assert(!result.followsByRegion.jp.some(row => row[0] === LINE || row[4] === LINE));
  for (const key of ['partsByRegion', 'byRegion', 'followsByRegion']) {
    const unrelated = row => row[0] !== LINE && (key !== 'followsByRegion' || row[4] !== LINE);
    assert.deepEqual(result[key].jp.filter(unrelated), nativeBaseline[key].jp.filter(unrelated));
  }
  assert.deepEqual(result.familyWindowsByRegion, nativeBaseline.familyWindowsByRegion);
  assert.deepEqual(repairParts(repaired, result, evidence), result);
});

test('accepts the previous protected two-leg cache without moving its terminal physical span', () => {
  const line = baseline.lines.find(row => row.id === LINE);
  const intervals = network.decodeIntervals(line);
  const previousParts = [intervals[0].concat(intervals[1].slice(1)),
    intervals.slice(2).flatMap((points, i) => i ? points.slice(1) : points)];
  const previousRows = partRowsForLine(line, previousParts, null, null);
  const previous = structuredClone(nativeBaseline);
  previous.partsByRegion.jp = previous.partsByRegion.jp.map(row => row[0] === LINE ? previousRows[row[1]] : row);
  previous.byRegion.jp = previous.byRegion.jp.map(row => row[0] === LINE ? [LINE, 1, 22505.6, 23101, -0.5] : row);
  previous.followsByRegion.jp = previous.followsByRegion.jp.map(row => row[0] === LINE
    ? [LINE, 0, 13950, 14002.021865360595, LINE, 1, 52.02186536059526, 0] : row);
  const result = repairParts(repairPackage(baseline, evidence), previous, evidence);
  const main = result.partsByRegion.jp.find(row => row[0] === LINE && row[1] === 1)[7];
  assert(distance(pointAt(previousParts[1], 22505.6), pointAt(main, 35929.1)) < 0.06);
  assert.deepEqual(result, repairParts(repairPackage(baseline, evidence), nativeBaseline, evidence));
});

test('changed source or unreviewed affected measures stop the scoped replay', () => {
  const changed = structuredClone(baseline);
  changed.lines.find(line => line.id === LINE).segments[2][2][5][0] += 0.00001;
  assert.throws(() => repairPackage(changed, evidence), /source changed/);
  const repaired = repairPackage(baseline, evidence);
  for (const [key, row] of [
    ['byRegion', [LINE, 1, 100, 200, 0.5]],
    ['byRegion', [LINE, 0, 100, 200, 0.5]],
    ['familyWindowsByRegion', [LINE, 1, 100, 200, 1, 'unexpected']],
    ['familyWindowsByRegion', [LINE, 0, 100, 200, 1, 'unexpected']],
    ['followsByRegion', [LINE, 1, 100, 200, 'another-line', 0, 0, 100]],
    ['followsByRegion', ['another-line', 0, 100, 200, LINE, 1, 0, 100]],
  ]) {
    const input = structuredClone(nativeBaseline);
    (input[key].jp ||= []).push(row);
    assert.throws(() => repairParts(repaired, input, evidence), /measure/);
  }
});
