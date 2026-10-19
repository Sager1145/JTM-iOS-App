import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { repairPackage, repairParts } from '../repair-hakone-gora-terminal-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const stroke = require('../../../public/rail-stroke.js');
const e = JSON.parse(fs.readFileSync(new URL('../hakone-gora-terminal-display-evidence.json', import.meta.url)));
const fixture = () => ({ lines: [structuredClone(e.baselineLine), { id: 'unrelated', keep: true }],
  geometrySource: { manualOverrides: { concurrent: { keep: true } } } });
const lanes = () => Object.fromEntries([['partsByRegion', { jp: structuredClone(e.baselineNativeRows) }],
  ...Object.entries(e.baselineMeasuredReferences).map(([key, rows]) => [key, { jp: structuredClone(rows) }])]);
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);

test('reviewed native station frame reproduces the approved MapKit coordinate and rejects tampering', () => {
  const world = 2 ** 28, [longitude, latitude] = e.displayAnchor;
  const x = (longitude + 180) / 360 * world;
  const radians = latitude * Math.PI / 180;
  const y = (1 - Math.log(Math.tan(radians) + 1 / Math.cos(radians)) / Math.PI) / 2 * world;
  const analysis = JSON.parse(fs.readFileSync(e.source.analysisPath));
  const pixel = [(x - analysis.mapRect.x) / (analysis.mapRect.width / analysis.width),
    (y - analysis.mapRect.y) / (analysis.mapRect.height / analysis.height)];
  assert.ok(Math.abs(pixel[0] - e.stationFrame.centrePixel[0]) < 1e-6);
  assert.ok(Math.abs(pixel[1] - e.stationFrame.centrePixel[1]) < 1e-6);
  assert.equal(e.stationFrame.centrePixelY, (e.stationFrame.northPixelY + e.stationFrame.southPixelY) / 2);
  for (const index of [e.stationFrame.railSamplePair, e.stationFrame.railSamplePair + 1])
    assert.equal(analysis.samples[index].supported, true);
  for (const mutate of [v => v.displayAnchor[0] += .00001, v => v.stationFrame.centrePixelY += 1,
    v => v.stationFrame.railSamplePair = 0, v => v.window.guardIndex--]) {
    const changed = structuredClone(e); mutate(changed);
    assert.throws(() => repairPackage(fixture(), changed));
  }
});

test('Gora terminal display clips only the reviewed tail and preserves physical Hakone identity', () => {
  const before = fixture(), pkg = repairPackage(before, e), line = pkg.lines[0];
  const interval = line.displayIntervalCoordinates[e.interval];
  assert.deepEqual(line.displayStationCoordinates[e.stationID], e.displayAnchor);
  assert.deepEqual(interval.at(-1), e.displayAnchor);
  assert.deepEqual(interval.slice(0, e.window.guardIndex + 1),
    e.baselineLine.displayIntervalCoordinates[e.interval].slice(0, e.window.guardIndex + 1));
  assert.equal(interval.length, e.window.guardIndex + 2);
  assert.equal(line.stationLaneByCode[e.stationID], 0);
  assert.deepEqual(line.stations, e.baselineLine.stations);
  assert.deepEqual(line.segments, e.baselineLine.segments);
  for (let i = 0; i < e.interval; i++)
    assert.deepEqual(line.displayIntervalCoordinates[i], e.baselineLine.displayIntervalCoordinates[i]);
  assert.deepEqual(line.displayReversalBranches, e.baselineLine.displayReversalBranches);
  assert.deepEqual(line.reversalTails, e.baselineLine.reversalTails);
  const parts = network.displayPartsForLine(line);
  assert.equal(parts.length, 7);
  assert.deepEqual(parts[e.nativePart].at(-1), e.displayAnchor);
  assert.deepEqual(pkg.lines[1], before.lines[1]);
  assert.deepEqual(pkg.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.deepEqual(repairPackage(pkg, e), pkg);
});

test('native terminal part and its ruler alone change, with a zero-lane final 300 metres', () => {
  const pkg = repairPackage(fixture(), e), before = lanes();
  before.partsByRegion.jp.push(['unrelated', 0, 9, 9]);
  before.byRegion.jp.push(['unrelated', 0, 0, 123, 1]);
  const result = repairParts(pkg, before, e);
  const ours = result.partsByRegion.jp.filter(row => row[0] === e.lineID);
  assert.equal(ours.length, 7);
  for (let i = 0; i < e.nativePart; i++) assert.deepEqual(ours[i], e.baselineNativeRows[i]);
  assert.notDeepEqual(ours[e.nativePart], e.baselineNativeRows[e.nativePart]);
  assert.deepEqual(ours[e.nativePart][7].at(-1), e.displayAnchor);
  const ruler = result.byRegion.jp.filter(row => row[0] === e.lineID && row[1] === e.nativePart);
  const total = ours[e.nativePart][5];
  assert.deepEqual(ruler, [[e.lineID, e.nativePart, 0, total - 300, .5],
    [e.lineID, e.nativePart, total - 300, total, 0]]);
  for (const key of ['followsByRegion', 'familyWindowsByRegion', 'chainBoundariesByRegion', 'reversedLoopParts'])
    assert.deepEqual(result[key].jp, before[key].jp);
  assert.deepEqual(result.partsByRegion.jp.at(-1), before.partsByRegion.jp.at(-1));
  assert.deepEqual(result.byRegion.jp.find(row => row[0] === 'unrelated'), ['unrelated', 0, 0, 123, 1]);
  assert.deepEqual(repairParts(pkg, result, e), result);
});

test('production stroke ends at the reviewed Gora centre at z16, z18 and z19', () => {
  const pkg = repairPackage(fixture(), e), repairedLanes = repairParts(pkg, lanes(), e);
  const built = network.buildNetworkFromCompactPackage({ format: 'compact-v1', country: 'jp',
    lines: [pkg.lines[0]] }, null, repairedLanes);
  const part = built.strokeModel.lines.find(row => row.lineId === e.lineID).parts[e.nativePart];
  assert.deepEqual(part.coordinates.at(-1), e.displayAnchor);
  for (const zoom of [16, 18, 19]) {
    const rendered = stroke.buildStroke(part.coordinates.map(point => stroke.project(point, zoom)), {
      measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
      laneGapPx: 2.7, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: 3,
      anchors: part.anchors, enforceMinimumCornerRadius: true, follows: [],
    });
    const expected = stroke.project(e.displayAnchor, zoom);
    assert.ok(Math.hypot(rendered.points.at(-1)[0] - expected[0], rendered.points.at(-1)[1] - expected[1]) < 1e-9,
      `z${zoom}: terminal stroke endpoint moved off reviewed centre`);
  }
});

test('unknown measured references are rejected', () => {
  const pkg = repairPackage(fixture(), e), input = lanes();
  input.followsByRegion.jp.push([e.lineID, e.nativePart, 0, 1, 'unknown', 0, 0, 1]);
  assert.throws(() => repairParts(pkg, input, e), /measured references/);
});
