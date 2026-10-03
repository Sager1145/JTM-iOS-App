import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { repairPackage, registry } from '../scripts/railway/repair-through-running-display.mjs';

const require = createRequire(import.meta.url);
const RailNetwork = require('../public/rail-network.js');
const RailStroke = require('../public/rail-stroke.js');
const full = JSON.parse(fs.readFileSync(new URL('../public/rail/jp-2025.json', import.meta.url)));
const lanes = JSON.parse(fs.readFileSync(new URL('../public/rail/display-lanes.json', import.meta.url)));
const ids = new Set([...registry.joins.flatMap(join => join.lineIds), 'jp-東武鉄道-伊勢崎線']);
const pkg = { ...full, lines: full.lines.filter(line => ids.has(line.id)) };
const network = RailNetwork.buildNetworkFromCompactPackage(pkg, null, lanes);

test('reviewed through joins preserve physical intervals and station identities on replay', () => {
  const copy = structuredClone(pkg);
  const source = copy.lines.map(({ id, railwayIdentity, stations, segments, structure }) => ({ id, railwayIdentity, stations, segments, structure }));
  repairPackage(copy);
  assert.deepEqual(copy.lines.map(({ id, railwayIdentity, stations, segments, structure }) => ({ id, railwayIdentity, stations, segments, structure })), source);
  assert.deepEqual(repairPackage(structuredClone(copy)), copy);
});

for (const join of registry.joins) {
  for (const zoom of [12, 16, 19]) {
    test(`${join.id}: emitted endpoints and directions align at zoom ${zoom}`, () => {
      const approaches = join.lineIds.map(id => {
        const line = pkg.lines.find(line => line.id === id);
        const index = line.stations.findIndex(station => station[0] === join.stationCode);
        const parts = network.strokeModel.lines.find(line => line.lineId === id).parts;
        const part = index === 0 ? parts[0] : parts.at(-1);
        const stroke = RailStroke.buildStroke(part.coordinates.map(point => RailStroke.project(point, zoom)), {
          measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
          laneGapPx: 4, cornerRadiusPx: 6, minRampPx: 2,
          anchors: part.anchors, follows: part.follows,
        });
        const source = part.coordinates.map(point => RailStroke.project(point, zoom));
        return { drawn: index === 0 ? stroke.points.slice(0, 2).reverse() : stroke.points.slice(-2),
          source: index === 0 ? source.slice(0, 2).reverse() : source.slice(-2) };
      });
      assert.deepEqual(approaches[0].drawn[1], approaches[1].drawn[1]);
      const vectors = approaches.map(({ source: [a, b] }) => b.map((x, i) => x - a[i]));
      const dot = vectors[0].reduce((sum, x, i) => sum + x * vectors[1][i], 0);
      const cosine = dot / (Math.hypot(...vectors[0]) * Math.hypot(...vectors[1]));
      // Opposing incoming headings form one continuing straight stroke.
      assert.ok(cosine < -0.99999, `through endpoint has an angle: cosine=${cosine}`);
      // At low zoom the 20 m platform ray is sub-pixel; the production
      // simplifier may absorb it within the shared Web/Swift pixel tolerance.
      for (const { drawn: [a, b], source: [before, anchor] } of approaches) {
        const direction = b.map((x, i) => x - a[i]);
        const length = Math.hypot(...direction);
        const ray = anchor.map((x, i) => x - before[i]);
        const error = Math.abs(direction[0] * ray[1] - direction[1] * ray[0]) / length;
        assert.ok(error <= RailStroke.STROKE_SIMPLIFY_TOLERANCE_PX + 1e-6,
          `rendered through tangent exceeds simplification tolerance: ${error} px`);
      }
      if (zoom >= 16) {
        const drawn = approaches.map(({ drawn: [a, b] }) => b.map((x, i) => x - a[i]));
        const dot = drawn[0].reduce((sum, x, i) => sum + x * drawn[1][i], 0);
        assert.ok(dot / (Math.hypot(...drawn[0]) * Math.hypot(...drawn[1])) < -0.99999);
      }
      const circles = network.stations.features.filter(feature =>
        join.lineIds.includes(feature.properties.lineId) && feature.properties.stationGroupId === join.stationCode);
      assert.deepEqual(circles.map(feature => feature.properties.lineId), [join.circleOwner]);
      for (const id of join.lineIds) assert.ok(network.stationById.has(`${id}:${join.stationCode}`));
    });
  }
}

test('terminal alignment rejects a through pair aimed at an interior station', () => {
  const copy = structuredClone(pkg), join = registry.joins.find(join => join.id === 'shibuya-denentoshi-hanzomon');
  const line = copy.lines.find(line => line.id === join.lineIds[0]);
  const station = line.stations.shift();
  line.stations.splice(2, 0, station);
  assert.throws(() => repairPackage(copy), /explicitly select a terminal/);
});
