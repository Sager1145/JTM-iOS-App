import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import {
  familyFollowCoverage, deriveFamilyWindows, snapSharedFollowEndpoints,
} from '../scripts/railway/build-display-lanes.mjs';

const require = createRequire(import.meta.url);
const Network = require('../public/rail-network.js');
const Stroke = require('../public/rail-stroke.js');
const pkg = JSON.parse(fs.readFileSync(new URL('../public/rail/jp-2025.json', import.meta.url)));
const lanes = JSON.parse(fs.readFileSync(new URL('../public/rail/display-lanes.json', import.meta.url)));
const network = Network.buildNetworkFromCompactPackage(pkg, null, lanes);
const lines = new Map(network.strokeModel.lines.map(line => [line.lineId, line]));
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const unit = (a, b) => {
  const length = distance(a, b);
  return length ? [(b[0] - a[0]) / length, (b[1] - a[1]) / length] : null;
};

function strokesAt(zoom) {
  const cache = new Map();
  const project = part => part.coordinates.map(point => Stroke.project(point, zoom));
  const joint = (line, index) => {
    const before = line.parts[index - 1], after = line.parts[index];
    if (!before || !after || after.joinPrevious === false ||
        distance(before.coordinates.at(-1), after.coordinates[0])) return null;
    const a = project(before), b = project(after);
    return {
      incoming: unit(a.at(-2), a.at(-1)), outgoing: unit(b[0], b[1]),
      beforeLane: Stroke.terminalLanes(before.rows, before.totalMetres).end,
      afterLane: Stroke.terminalLanes(after.rows, after.totalMetres).start,
    };
  };
  return (lineId, partIndex) => {
    const key = `${lineId}#${partIndex}`;
    if (cache.has(key)) return cache.get(key);
    const line = lines.get(lineId), part = line.parts[partIndex];
    const start = joint(line, partIndex), end = joint(line, partIndex + 1);
    const result = Stroke.buildStroke(project(part), {
      measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
      laneGapPx: 2.7, minRampPx: 24, cornerRadiusPx: 3.6,
      minCornerRadiusPx: 3, enforceMinimumCornerRadius: true, anchors: part.anchors,
      follows: part.follows.map(follow => {
        const canon = lines.get(follow.canonLineId).parts[follow.canonPartIndex];
        return { ...follow, points: project(canon), measures: canon.measures };
      }),
      joinStart: start ? { ...start, lane: start.beforeLane } : null,
      joinEnd: end ? { ...end, lane: end.afterLane } : null,
    });
    cache.set(key, result);
    return result;
  };
}

function at(stroke, measure) {
  const piece = Stroke.sliceStroke(stroke.points, stroke.measures, measure, measure + 0.001);
  return piece[0] || stroke.points.at(-1);
}

function nearest(point, polyline) {
  let best = Infinity;
  for (let i = 1; i < polyline.length; i++) {
    const a = polyline[i - 1], b = polyline[i];
    const dx = b[0] - a[0], dy = b[1] - a[1], squared = dx * dx + dy * dy;
    const t = squared ? Math.max(0, Math.min(1,
      ((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / squared)) : 0;
    best = Math.min(best, distance(point, [a[0] + t * dx, a[1] + t * dy]));
  }
  return best;
}

test('short follows and guarded joints retain their own approaches', () => {
  const row = ['jp-branch', 0, 200, 700, 'jp-main', 0, 400, 900];
  assert.equal(familyFollowCoverage(row, 1000), null);
  assert.deepEqual(familyFollowCoverage(['jp-branch', 0, 0, 2000, 'jp-main', 0, 0, 2000], 2000, true, true), [600, 1400]);
});

test('reverse lane signs must agree before a branch can be suppressed', () => {
  const parts = ['jp-branch', 'jp-main'].map(lineId => ({
    lineId, partIndex: 0, coordinates: [[139, 35], [139.02, 35]], stationPoints: [],
  }));
  const metrics = new Map(parts.map(part => [part.lineId + '#0', { cumulative: [0, 2000], total: 2000 }]));
  const groups = { byLineId: { 'jp-branch': 'family', 'jp-main': 'family' }, families: { family: { color: '#123456' } } };
  const follows = [['jp-branch', 0, 0, 2000, 'jp-main', 0, 2000, 0]];
  const wrong = [['jp-branch', 0, 0, 2000, 0.5], ['jp-main', 0, 0, 2000, 0.5]];
  assert.deepEqual(deriveFamilyWindows(parts, follows, groups, metrics, wrong), []);
  const right = structuredClone(wrong); right[0][4] = -0.5;
  assert.equal(deriveFamilyWindows(parts, follows, groups, metrics, right).length, 2);
});

test('nearby separate platforms never become a shared follow endpoint', () => {
  const parts = [
    { lineId: 'jp-branch', partIndex: 0, coordinates: [[139, 35], [139.01, 35]] },
    { lineId: 'jp-main', partIndex: 0, coordinates: [[139.0001, 35], [139.0101, 35]] },
  ];
  const metrics = new Map(parts.map(part => [part.lineId + '#0', { cumulative: [0, 1000], total: 1000 }]));
  const follows = [['jp-branch', 0, 0, 1000, 'jp-main', 0, 10, 990]];
  assert.deepEqual(snapSharedFollowEndpoints(parts, structuredClone(follows), metrics), follows);
});

for (const zoom of [12, 16, 19]) {
  test(`every shipped Japan family handoff reaches drawn leader ink at zoom ${zoom}`, () => {
    const build = strokesAt(zoom);
    let checked = 0;
    for (const line of lines.values()) for (const [partIndex, part] of line.parts.entries()) {
      for (const window of part.tenantWindows) {
        const follow = part.follows.find(row => row.from <= window.from + 0.1 && row.to >= window.to - 0.1);
        assert.ok(follow, `${line.lineId}: family window has no follow`);
        const leader = build(follow.canonLineId, follow.canonPartIndex);
        const own = build(line.lineId, partIndex);
        for (const edge of [window.from, window.to]) {
          assert.ok(nearest(at(own, edge), leader.points) <= Stroke.STROKE_SIMPLIFY_TOLERANCE_PX,
            `${line.lineId}: broken family handoff at ${edge}m`);
          checked++;
        }
      }
    }
    assert.ok(checked > 0, 'must exercise real family handoffs');
  });
  test(`Sobu Ochanomizu branch reaches the exact Kinshicho anchor at zoom ${zoom}`, () => {
    const id = 'jp-東日本旅客鉄道-総武線-2';
    const endpoint = pkg.lines.find(line => line.id === id).stations.at(-1).slice(2, 4);
    assert.ok(distance(strokesAt(zoom)(id, 0).points.at(-1), Stroke.project(endpoint, zoom)) < 1e-7);
    assert.equal(lines.get(id).parts[0].tenantWindows.length, 0,
      'surface/tunnel blend is continuously drawn because the trunk has a changing lane profile');
  });
}
