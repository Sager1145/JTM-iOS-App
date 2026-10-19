import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import test from 'node:test';
import { repairPackage, repairParts, surveyedPath, LINE } from '../repair-tabata-curve.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const stroke = require('../../../public/rail-stroke.js');
const pkg = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const lanes = JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json', import.meta.url)));
const evidence = JSON.parse(fs.readFileSync(new URL('../tabata-curve-overrides.json', import.meta.url)));

test('repair keeps routing inputs, other intervals and other lines intact', () => {
  const before = structuredClone(pkg);
  const after = repairPackage(pkg, evidence);
  assert.deepEqual(pkg, before);
  for (const line of before.lines) {
    const changed = after.lines.find(row => row.id === line.id);
    if (line.id !== LINE) assert.deepEqual(changed, line);
    else {
      assert.deepEqual(changed.stations, line.stations);
      assert.deepEqual(changed.segments, line.segments);
      assert.deepEqual(changed.displayIntervalCoordinates['1'], line.displayIntervalCoordinates['1']);
      const original = network.decodeIntervals(line)[15];
      const display = changed.displayIntervalCoordinates['15'];
      const a = original.findIndex(p => p.toString() === evidence.start.toString());
      const b = original.findIndex(p => p.toString() === evidence.end.toString());
      assert.deepEqual(display.slice(0, a + 1), original.slice(0, a + 1));
      assert.deepEqual(display.slice(-original.slice(b).length), original.slice(b));
      assert.deepEqual(display.slice(a + 1, -original.slice(b).length), surveyedPath(evidence).slice(10, -1));
    }
  }
  assert.deepEqual(repairPackage(after, evidence), after);
});

test('disconnected survey and changed source refuse a guessed repair', () => {
  const broken = structuredClone(evidence);
  broken.ways['183185952'].coordinates[0][0] += 0.00001;
  assert.throws(() => surveyedPath(broken), /Disconnected/);
  const changed = structuredClone(pkg);
  const line = changed.lines.find(row => row.id === LINE);
  line.segments[15][2].find(p => p[0] === 139.7585)[1] += 0.00001;
  assert.throws(() => repairPackage(changed, evidence), /source changed/);
});

test('detailed-zoom smoothed curve stays within 3.5 m of the selected running track', () => {
  const line = repairPackage(pkg, evidence).lines.find(row => row.id === LINE);
  const coordinates = network.displayPartsForLine(line)[0];
  const metric = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
    (b[1] - a[1]) * 111320);
  const measures = [0];
  coordinates.slice(1).forEach((p, i) => measures.push(measures.at(-1) + metric(coordinates[i], p)));
  const reference = surveyedPath(evidence).map(p => stroke.project(p, 17));
  const start = stroke.project(evidence.start, 17), end = stroke.project(evidence.end, 17);
  const mpp = metric(evidence.start, evidence.end) / Math.hypot(end[0] - start[0], end[1] - start[1]);
  const distance = (p, a, b) => {
    const dx = b[0] - a[0], dy = b[1] - a[1], length2 = dx * dx + dy * dy;
    const t = Math.max(0, Math.min(1, length2 ? ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length2 : 0));
    return Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy);
  };
  const smooth = stroke.smoothCentreline(coordinates.map(p => stroke.project(p, 17)), measures).points;
  let samples = 0;
  for (let i = 1; i < smooth.length; i++) {
    for (let j = 0; j <= 20; j++) {
      const p = smooth[i - 1].map((v, k) => v + (smooth[i][k] - v) * j / 20);
      const c = stroke.unproject(p, 17);
      if (c[0] < evidence.start[0] || c[0] > evidence.end[0] || c[1] <= 35.7388) continue;
      const residual = Math.min(...reference.slice(1).map((b, k) => distance(p, reference[k], b))) * mpp;
      assert(residual < 3.5, `Smoothed Tabata curve departs ${residual} m from the registered track`);
      samples++;
    }
  }
  assert(samples > 500);
});

test('refreshes only the native part row and refuses affected measured rows', () => {
  const result = repairParts(repairPackage(pkg, evidence), lanes);
  const unrelated = structuredClone(lanes);
  unrelated.partsByRegion.jp = unrelated.partsByRegion.jp.filter(row => row[0] !== LINE);
  const actual = structuredClone(result);
  actual.partsByRegion.jp = actual.partsByRegion.jp.filter(row => row[0] !== LINE);
  assert.deepEqual(actual, unrelated);
  const row = result.partsByRegion.jp.find(row => row[0] === LINE);
  assert.equal(row[4], row[7].length);
  assert(row[7].some(p => p.toString() === '139.7583849,35.7399908'));
  assert(!row[7].some(p => p.toString() === '139.7585,35.74006'));
  const measured = structuredClone(lanes);
  measured.byRegion.jp.push([LINE, 0, 20000, 20500, 0.5]);
  assert.throws(() => repairParts(repairPackage(pkg, evidence), measured), /measure/);
});
