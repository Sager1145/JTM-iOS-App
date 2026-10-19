import assert from 'node:assert/strict';
import fs from 'node:fs';
import { test } from 'node:test';
import { createRequire } from 'node:module';
import { buildCandidate, repairPackage, repairLanes, repairDirectionSource, measure, LINE_ID, DIRECTION_SOURCE } from '../repair-hokuriku-p1-loop-display.mjs';

const root = new URL('../../../', import.meta.url);
const pkg = JSON.parse(fs.readFileSync(new URL('public/rail/jp-2025.json', root)));
const sections = JSON.parse(fs.readFileSync(new URL('data/rail-sections.json', root)));
const production = pkg.lines.find(row => row.id === LINE_ID);
const line = structuredClone(production);
delete line.displayIntervalCoordinates;
line.alignmentDirection = 'down';
line.alignmentSource = 'https://ja.wikipedia.org/wiki/北陸本線';
const turn = (a, b, c) => {
  const scale = Math.cos(b[1] * Math.PI / 180);
  const u = [(b[0] - a[0]) * scale, b[1] - a[1]];
  const v = [(c[0] - b[0]) * scale, c[1] - b[1]];
  return Math.acos(Math.max(-1, Math.min(1,
    (u[0] * v[0] + u[1] * v[1]) / Math.hypot(...u) / Math.hypot(...v)))) * 180 / Math.PI;
};

test('uses the eastern directional arc instead of turning at its crossing with the straight railway', () => {
  const baseline = line.segments[0][2];
  assert(turn(...baseline.slice(40, 43)) > 59, 'frozen failure is still represented');
  const candidate = buildCandidate(line, sections).line.displayIntervalCoordinates[0];
  assert(candidate.some(([x, y]) => x === 136.08323 && y === 35.61903), 'retains eastern arc witness');
  const junction = candidate.findIndex(([x, y]) => x === 136.08196 && y === 35.61644);
  assert(turn(...candidate.slice(junction - 1, junction + 2)) < 15);
  assert(Math.max(...candidate.slice(1, -1).map((_, i) => turn(...candidate.slice(i, i + 3)))) < 25);
});

test('retains physical topology, station anchors and the complete loop after the crossing', () => {
  const result = buildCandidate(line, sections).line;
  assert.deepEqual(result.segments, line.segments);
  assert.deepEqual(result.stations, line.stations);
  const candidate = result.displayIntervalCoordinates[0];
  assert.deepEqual(candidate[0], line.segments[0][2][0]);
  assert.deepEqual(candidate.slice(48), line.segments[0][2].slice(42));
  assert.deepEqual(candidate.at(-1), line.segments[0][2].at(-1));
  assert.equal(line.displayIntervalCoordinates, undefined, 'input is not mutated');
});

test('rejects a competing railway source and an unreviewed display override', () => {
  const wrong = structuredClone(sections);
  wrong.features[9616].properties.N02_004 = 'other';
  assert.throws(() => buildCandidate(line, wrong));
  assert.throws(() => buildCandidate({ ...line, displayIntervalCoordinates: { 0: [] } }, sections));
});

test('existing production override is absent or exactly the reviewed candidate; replay is idempotent', () => {
  const result = buildCandidate(line, sections);
  if (production.displayIntervalCoordinates)
    assert.deepEqual(production.displayIntervalCoordinates, result.line.displayIntervalCoordinates);
  assert.deepEqual(buildCandidate(result.line, sections), result);
  const repaired = repairPackage(pkg, sections).pkg;
  assert.deepEqual(repairPackage(repaired, sections).pkg, repaired);
});

test('operator-backed loop up and straight down metadata preserve stored up order and physical data', () => {
  const repaired = repairPackage(pkg, sections).pkg;
  const loop = repaired.lines.find(row => row.id === LINE_ID);
  const baseID = 'jp-西日本旅客鉄道-北陸線';
  const base = repaired.lines.find(row => row.id === baseID);
  const beforeBase = pkg.lines.find(row => row.id === baseID);
  assert.equal(loop.alignmentDirection, 'up');
  assert.equal(loop.stationOrderDirection, 'up');
  assert.equal(loop.alignmentSource, DIRECTION_SOURCE);
  assert.equal(base.alignmentPairs.find(pair => pair.with === LINE_ID).direction, 'down');
  assert.deepEqual(base.segments, beforeBase.segments);
  assert.deepEqual(base.stations, beforeBase.stations);
  assert.deepEqual(repaired.lines.filter(row => ![LINE_ID, baseID].includes(row.id)),
    pkg.lines.filter(row => ![LINE_ID, baseID].includes(row.id)));
  const network = createRequire(import.meta.url)('../../../public/rail-network.js');
  const lineById = new Map([loop, base].map(row => [row.id, {
    ...row, lineId: row.id, stationNames: row.stations.map(station => station[1]),
  }]));
  assert.deepEqual(network.intervalDirections({ lineById }, { lineId: LINE_ID, intervalIndex: 0 }),
    { forward: true, reverse: false });
  assert.deepEqual(network.intervalDirections({ lineById }, { lineId: baseID, intervalIndex: 0 }),
    { forward: false, reverse: true });
  const master = JSON.parse(fs.readFileSync(new URL('scripts/railway/jp-directional-alignment-overrides.json', root)));
  const updated = repairDirectionSource(master);
  const family = updated.families.find(row => row.baseLineID === baseID);
  assert.deepEqual([family.pairs[0].alignmentDirection, family.pairs[0].mainAlignmentDirection, family.pairs[0].alignmentSource],
    ['up', 'down', DIRECTION_SOURCE]);
  assert.deepEqual(repairDirectionSource(updated), updated);
  assert.deepEqual(updated.families.filter(row => row.baseLineID !== baseID),
    master.families.filter(row => row.baseLineID !== baseID));
});

test('retires unproven prefix substitution and rebases only unchanged suffix owners', () => {
  const lanes = JSON.parse(fs.readFileSync(new URL('public/rail/display-lanes.json', root)));
  const candidate = buildCandidate(line, sections).line;
  const { lanes: result, metadata } = repairLanes(lanes, candidate);
  const follows = result.followsByRegion.jp.filter(row => row[0] === LINE_ID);
  assert.equal(follows.length, 1);
  assert.equal(follows[0][2], 8350 + metadata.displayDeltaMetres);
  assert.equal(follows[0][3], measure(candidate.displayIntervalCoordinates[0]));
  assert.deepEqual(follows[0].slice(4), ['jp-西日本旅客鉄道-北陸線', 0, 5250, 6629.699966332292]);
  const pointAt = (points, metres) => {
    for (let i = 1; i < points.length; i++) {
      const length = measure(points.slice(i - 1, i + 1));
      if (metres <= length) return points[i - 1].map((value, axis) =>
        value + (points[i][axis] - value) * metres / length);
      metres -= length;
    }
    return points.at(-1);
  };
  const family = result.familyWindowsByRegion.jp.find(row => row[0] === LINE_ID);
  for (const [oldMetres, newMetres] of [[8350, follows[0][2]], [9726.821586632404, follows[0][3]],
    [8650, family[2]], [9726.8, family[3]]]) {
    const before = pointAt(line.segments[0][2], oldMetres);
    const after = pointAt(candidate.displayIntervalCoordinates[0], newMetres);
    assert(before.every((value, axis) => Math.abs(value - after[axis]) < 1e-10), 'suffix geographic boundary moved');
  }
  assert.deepEqual(repairLanes(result, candidate).lanes, result);
  for (const key of ['byRegion', 'followsByRegion', 'familyWindowsByRegion', 'partsByRegion'])
    assert.deepEqual(result[key].jp.filter(row => row[0] !== LINE_ID), lanes[key].jp.filter(row => row[0] !== LINE_ID));
  const unknown = structuredClone(lanes);
  unknown.followsByRegion.jp.find(row => row[0] === LINE_ID)[2] += 1;
  assert.throws(() => repairLanes(unknown, candidate));
});
