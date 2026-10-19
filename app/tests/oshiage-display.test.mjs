import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { repairPackage, repairLanes, MAIN, BRANCH, METRO, OSHIAGE } from '../scripts/railway/repair-oshiage-display.mjs';
import { partRowsForLine } from '../scripts/railway/build-display-lanes.mjs';

const require = createRequire(import.meta.url);
const RailNetwork = require('../public/rail-network.js');
const RailStroke = require('../public/rail-stroke.js');
const full = JSON.parse(fs.readFileSync(new URL('../public/rail/jp-2025.json', import.meta.url)));
const lanes = JSON.parse(fs.readFileSync(new URL('../public/rail/display-lanes.json', import.meta.url)));
const pkg = { ...full, lines: full.lines.filter(line => [MAIN, BRANCH, METRO].includes(line.id)) };
const network = RailNetwork.buildNetworkFromCompactPackage(pkg, null, lanes);

test('Asakusa passenger display follows exposed cross-river black rail instead of the southeast chord', () => {
  const id = 'jp-東京都-1号線浅草線';
  const b1 = RailNetwork.buildNetworkFromCompactPackage({ ...full,
    lines: full.lines.filter(line => [id, 'jp-京成電鉄-押上線'].includes(line.id)) }, null, lanes);
  const part = b1.strokeModel.lines.find(line => line.lineId === id).parts.at(-1);
  const zoom = 19;
  const { points } = RailStroke.buildStroke(part.coordinates.map(point => RailStroke.project(point, zoom)), {
    measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
    laneGapPx: 4, cornerRadiusPx: 6, minRampPx: 2, anchors: part.anchors, follows: part.follows,
  });
  // Actual production stroke must retain the visible entry bend as well as
  // the labelled cross-river rail; a straight replacement through one point
  // cannot satisfy all these independent native image supports.
  for (const rail of [[139.8099876,35.7089145], [139.8101967,35.7090052], [139.810870,35.709468]]) {
    const projected = RailStroke.project(rail, zoom);
    const scale = 156543.03392804097 * Math.cos(rail[1] * Math.PI / 180) / 2 ** zoom;
    let distance = Infinity;
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1].map((v, j) => (v - projected[j]) * scale);
      const b = points[i].map((v, j) => (v - projected[j]) * scale);
      const d = b.map((v, j) => v - a[j]);
      const t = Math.max(0, Math.min(1, -(a[0] * d[0] + a[1] * d[1]) / (d[0] ** 2 + d[1] ** 2)));
      distance = Math.min(distance, Math.hypot(a[0] + d[0] * t, a[1] + d[1] * t));
    }
    assert.ok(distance < 4, `passenger stroke is ${distance} m from visible black rail at ${rail}`);
  }
});

test('Keisei and Asakusa shared display point is inside their independent B1 platform body', () => {
  const ids = ['jp-京成電鉄-押上線', 'jp-東京都-1号線浅草線'];
  const points = ids.map(id => {
    const line = full.lines.find(line => line.id === id);
    return line.displayStationCoordinates?.['003526'] || line.stations.at(-1).slice(2, 4);
  });
  assert.deepEqual(points[0], points[1]);
  const [lon, lat] = points[0];
  assert.ok(lon > 139.8123 && lon < 139.81255 && lat > 35.71030 && lat < 35.71046,
    `B1 point remains outside the reviewed central platform-body window: ${points[0]}`);
  assert.notDeepEqual(points[0], OSHIAGE); // B3 is a separate platform family
});

test('reviewed north Oshiage arc has no isolated hard turn at high zoom', () => {
  const part = network.strokeModel.lines.find(line => line.lineId === BRANCH).parts[0];
  const zoom = 19;
  const stroke = RailStroke.buildStroke(part.coordinates.map(point => RailStroke.project(point, zoom)), {
    measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
    laneGapPx: 4, cornerRadiusPx: 6, minRampPx: 2,
    anchors: part.anchors, follows: part.follows,
  });
  const apex = RailStroke.project([139.81336, 35.71012], zoom);
  const metresPerPixel = 156543.03392804097 * Math.cos(OSHIAGE[1] * Math.PI / 180) / 2 ** zoom;
  const turns = [];
  for (let i = 1; i + 1 < stroke.points.length; i++) {
    const [a, b, c] = stroke.points.slice(i - 1, i + 2);
    if (Math.hypot(b[0] - apex[0], b[1] - apex[1]) * metresPerPixel > 30) continue;
    const u = b.map((x, j) => x - a[j]), v = c.map((x, j) => x - b[j]);
    const size = Math.hypot(...u) * Math.hypot(...v);
    if (size > 1e-12) turns.push(Math.acos(Math.max(-1, Math.min(1,
      (u[0] * v[0] + u[1] * v[1]) / size))) * 180 / Math.PI);
  }
  assert.ok(turns.length > 0);
  assert.ok(Math.max(...turns) < 8, `reviewed circular arc contains a hard turn: ${Math.max(...turns)} degrees`);
});

test('Oshiage repair preserves physical intervals and is replayable', () => {
  const copy = structuredClone(pkg);
  const physical = copy.lines.map(({ id, stations, segments, structure }) => ({ id, stations, segments, structure }));
  repairPackage(copy);
  assert.deepEqual(copy.lines.map(({ id, stations, segments, structure }) => ({ id, stations, segments, structure })), physical);
  assert.deepEqual(repairPackage(structuredClone(copy)), copy);
  assert.deepEqual(repairLanes(copy, structuredClone(lanes)), lanes);
});

test('Hikifune display removes only original N02 control C and refreshes the explicit native part', () => {
  const copy = structuredClone(pkg);
  const original = copy.lines.find(line => line.id === BRANCH);
  const physical = structuredClone(original.segments);
  const stations = structuredClone(original.stations);
  const main = structuredClone(copy.lines.find(line => line.id === MAIN));
  const metro = structuredClone(copy.lines.find(line => line.id === METRO));
  const before = structuredClone(original.displayIntervalCoordinates[0]);
  const source = RailNetwork.decodeIntervals(original)[0];
  const A = [139.816637, 35.718314], B = [139.81658, 35.71726];
  const C = [139.81651, 35.71726], D = [139.81643, 35.71575];
  assert.deepEqual(source.slice(0, 4), [A, B, C, D]);
  repairPackage(copy);
  const branch = copy.lines.find(line => line.id === BRANCH);
  const display = branch.displayIntervalCoordinates[0];
  assert.deepEqual(branch.segments, physical);
  assert.deepEqual(branch.stations, stations);
  assert.equal(branch.segments[0][0], 1.184);
  assert.deepEqual(display.slice(0, 3), [A, B, D]);
  assert.deepEqual(display, before.filter(point => point[0] !== C[0] || point[1] !== C[1]));
  assert.deepEqual(display.at(-1), OSHIAGE);
  assert.deepEqual(copy.lines.find(line => line.id === MAIN), main);
  assert.deepEqual(copy.lines.find(line => line.id === METRO), metro);
  const turn = (a, b, c) => {
    const sx = 111320 * Math.cos(B[1] * Math.PI / 180);
    const u = [(b[0] - a[0]) * sx, (b[1] - a[1]) * 111320];
    const v = [(c[0] - b[0]) * sx, (c[1] - b[1]) * 111320];
    return Math.acos(Math.max(-1, Math.min(1,
      (u[0] * v[0] + u[1] * v[1]) / (Math.hypot(...u) * Math.hypot(...v))))) * 180 / Math.PI;
  };
  assert.ok(turn(A, B, C) > 87 && turn(B, C, D) > 87);
  assert.ok(turn(...display.slice(0, 3)) < 2.1);
  const parts = RailNetwork.displayPartsForLine(branch);
  const [row] = partRowsForLine(branch, parts, null, null);
  assert.deepEqual(row.slice(0, 7), [BRANCH, 0, -1, -1, 35, 1038.4, 'complex']);
  assert.deepEqual(row[7], display);
  assert.deepEqual(row[8], []);
  assert.deepEqual(parts[0], display);
  assert.deepEqual(repairPackage(structuredClone(copy)), copy);
});

test('Hikifune deletion refuses changed physical A/B/C/D source controls', () => {
  const copy = structuredClone(pkg);
  copy.lines.find(line => line.id === BRANCH).segments[0][2][2][0] += 0.000001;
  assert.throws(() => repairPackage(copy), /Hikifune own-branch source controls changed/);
});

test('shared Tobu/Metro point retains both company marks and display approaches', () => {
  const circles = network.stations.features.filter(feature => feature.properties.stationGroupId === '003526');
  assert.equal(circles.length, 2);
  assert.deepEqual(new Set(circles.map(circle => circle.properties.lineId)), new Set([BRANCH, METRO]));
  for (const circle of circles) assert.deepEqual(circle.geometry.coordinates, OSHIAGE);
  for (const id of [BRANCH, METRO]) assert.ok(network.stationById.has(`${id}:003526`));
  // Engineering figures 4/103/104 place the platform centre at the river
  // crossing, not at the northern end of the N02 station fragment.
  assert.ok(OSHIAGE[1] > 35.70965 && OSHIAGE[1] < 35.70977);
  for (const id of [BRANCH, METRO]) {
    const part = network.strokeModel.lines.find(line => line.lineId === id).parts.at(-1);
    assert.deepEqual(part.coordinates.at(-1), OSHIAGE);
  }
});

test('Oshiage central cut preserves surveyed supports without a northward Tobu reversal', () => {
  const branch = RailNetwork.decodeIntervals(pkg.lines.find(line => line.id === BRANCH))[0];
  const repaired = structuredClone(pkg);
  repairPackage(repaired);
  const north = repaired.lines.find(line => line.id === BRANCH).displayIntervalCoordinates[0];
  const southLine = repaired.lines.find(line => line.id === METRO);
  const south = southLine.displayIntervalCoordinates[southLine.segments.length - 1];
  const boundary = branch.findIndex(point => point[0] === 139.81336 && point[1] === 35.71012);
  // The reviewed southern elbow and single Hikifune source notch are the
  // only exceptions; all other earlier controls remain exact.
  assert.deepEqual(north.slice(0, boundary - 1), branch.slice(0, boundary).filter((_, index) => index !== 2));
  assert.ok(!north.some(point => point[0] === branch[boundary][0] && point[1] === branch[boundary][1]));
  const apex = branch[boundary];
  const scale = 111320 * Math.cos(apex[1] * Math.PI / 180);
  assert.ok(Math.min(...north.map(point => Math.hypot((point[0] - apex[0]) * scale,
    (point[1] - apex[1]) * 111320))) <= 3.01);
  assert.ok(north.slice(-3).every((point, i, points) => i === 0 || point[1] < points[i - 1][1]));
  assert.ok(south.some(point => point[0] === 139.81359 && point[1] === 35.70908));
  assert.ok(south.slice(-3).every((point, i, points) => i === 0 || point[1] > points[i - 1][1]));
  assert.deepEqual(north.at(-1), south.at(-1));
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
