import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { repairPackage, repairLanes, MAIN, BRANCH, METRO, OSHIAGE } from '../scripts/railway/repair-oshiage-display.mjs';

const require = createRequire(import.meta.url);
const RailNetwork = require('../public/rail-network.js');
const RailStroke = require('../public/rail-stroke.js');
const full = JSON.parse(fs.readFileSync(new URL('../public/rail/jp-2025.json', import.meta.url)));
const lanes = JSON.parse(fs.readFileSync(new URL('../public/rail/display-lanes.json', import.meta.url)));
const pkg = { ...full, lines: full.lines.filter(line => [MAIN, BRANCH, METRO].includes(line.id)) };
const network = RailNetwork.buildNetworkFromCompactPackage(pkg, null, lanes);

test('Oshiage repair preserves physical intervals and is replayable', () => {
  const copy = structuredClone(pkg);
  const physical = copy.lines.map(({ id, stations, segments, structure }) => ({ id, stations, segments, structure }));
  repairPackage(copy);
  assert.deepEqual(copy.lines.map(({ id, stations, segments, structure }) => ({ id, stations, segments, structure })), physical);
  assert.deepEqual(repairPackage(structuredClone(copy)), copy);
  assert.deepEqual(repairLanes(copy, structuredClone(lanes)), lanes);
});

test('shared Tobu/Metro platform moves north and remains on both display approaches', () => {
  const circles = network.stations.features.filter(feature => feature.properties.stationGroupId === '003526');
  assert.equal(circles.length, 1);
  assert.deepEqual(circles[0].geometry.coordinates, OSHIAGE);
  assert.ok(circles[0].properties.lineId === METRO);
  assert.ok(OSHIAGE[1] - pkg.lines.find(line => line.id === METRO).stations.at(-1)[3] > 0.0017);
  for (const id of [BRANCH, METRO]) {
    const part = network.strokeModel.lines.find(line => line.lineId === id).parts.at(-1);
    assert.deepEqual(part.coordinates.at(-1), OSHIAGE);
  }
});

for (const zoom of [12, 16, 19]) {
  test(`drawn Tobu branch meets main at Hikifune at zoom ${zoom}`, () => {
    const stroke = id => {
      const part = network.strokeModel.lines.find(line => line.lineId === id).parts[0];
      return RailStroke.buildStroke(part.coordinates.map(point => RailStroke.project(point, zoom)), {
        measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
        laneGapPx: 4, cornerRadiusPx: 6, minRampPx: 2,
        anchors: part.anchors, follows: part.follows,
      });
    };
    const main = stroke(MAIN);
    const branch = stroke(BRANCH);
    assert.ok(main.points.some(point => Math.hypot(point[0] - branch.points[0][0], point[1] - branch.points[0][1]) < 1e-8));
    const branchPart = network.strokeModel.lines.find(line => line.lineId === BRANCH).parts[0];
    assert.deepEqual(branchPart.rows, []);
    assert.deepEqual(branchPart.follows, []);
    assert.deepEqual(branchPart.tenantWindows, []);
    assert.deepEqual(branch.points.at(-1), RailStroke.project(OSHIAGE, zoom));
  });
}
