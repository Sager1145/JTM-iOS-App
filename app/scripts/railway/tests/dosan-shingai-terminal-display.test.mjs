import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { candidateGeoJSON, repairPackage, repairParts } from '../repair-dosan-shingai-terminal-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const stroke = require('../../../public/rail-stroke.js');
const e = JSON.parse(fs.readFileSync(new URL('../dosan-shingai-terminal-display-evidence.json', import.meta.url)));
const candidate = JSON.parse(fs.readFileSync(new URL(`../../../../${e.source.candidatePath}`, import.meta.url)));
const fixture = () => ({ lines: Array.from({ length: e.baseline.packageIndex }, (_, index) => ({ id: `before-${index}` }))
  .concat([structuredClone(e.baseline.line), { id: 'unrelated', keep: true }]),
geometrySource: { manualOverrides: { concurrent: { keep: true } } } });
const lanes = () => ({ partsByRegion: { jp: [...structuredClone(e.baseline.nativeRows), ['unrelated', 0, 1]] },
  ...Object.fromEntries(Object.entries(e.baseline.measuredReferences).map(([key, rows]) =>
    [key, { jp: [...structuredClone(rows), ...(key === 'byRegion' ? [['unrelated', 0, 0, 1, 0]] : [])] }])) });

test('frozen Main georeference reproduces the bounded Shingai rail projection and rejects tampering', () => {
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(new URL(`../../../../${e.source.candidatePath}`, import.meta.url)))
    .digest('hex'), e.source.candidateSha256);
  assert.deepEqual(candidate.displayAnchor, e.displayAnchor);
  assert.equal(candidate.projectionTransverseMetres, e.projection.transverseResidualMetres);
  assert.equal(candidate.status, 'candidate pending full native comparison, not production acceptance');
  for (const mutate of [v => v.displayAnchor[0] += .00001, v => v.projection.sourceSpur[1][0] += .00001,
    v => v.projection.maximumTransverseMetres = 2, v => v.projection.maximumTrimMetres = 39]) {
    const changed = structuredClone(e); mutate(changed);
    assert.throws(() => repairPackage(fixture(), changed));
  }
});

test('Shingai repair trims only the doubled display tail and preserves the physical Dosan line', () => {
  const input = fixture(), pkg = repairPackage(input, e), line = pkg.lines[e.baseline.packageIndex];
  assert.deepEqual(line.stations, e.baseline.line.stations);
  assert.deepEqual(line.segments, e.baseline.line.segments);
  assert.deepEqual(network.decodeIntervals(line), network.decodeIntervals(e.baseline.line));
  assert.deepEqual(Object.keys(line.displayIntervalCoordinates).map(Number).sort((a, b) => a - b), e.intervals);
  assert.deepEqual(line.displayStationCoordinates, { [e.stationID]: e.displayAnchor });
  const physical = network.decodeIntervals(e.baseline.line);
  assert.deepEqual(line.displayIntervalCoordinates[23], [...physical[23].slice(0, -2), e.displayAnchor]);
  assert.deepEqual(line.displayIntervalCoordinates[24], [e.displayAnchor, ...physical[24].slice(2)]);
  assert(!line.displayIntervalCoordinates[23].some(point => point[0] === 133.69566 && point[1] === 33.64934));
  assert(!line.displayIntervalCoordinates[24].some(point => point[0] === 133.69566 && point[1] === 33.64934));
  const beforeParts = network.displayPartsForLine(e.baseline.line), afterParts = network.displayPartsForLine(line);
  assert.deepEqual(afterParts[0], [...e.projection.sourceSpur.slice(0, 2), e.displayAnchor]);
  assert.deepEqual(afterParts[1], beforeParts[1]);
  assert.equal(afterParts[1].length, 3176);
  assert.deepEqual(pkg.lines.at(-1), input.lines.at(-1));
  assert.deepEqual(pkg.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.deepEqual(repairPackage(pkg, e), pkg);
});

test('only the Shingai native spur changes; independent candidate covers complete intervals 23 and 24', () => {
  const pkg = repairPackage(fixture(), e), before = lanes(), after = repairParts(pkg, before, e);
  const ours = after.partsByRegion.jp.filter(row => row[0] === e.lineID);
  assert.equal(ours.length, 2);
  assert.notDeepEqual(ours[0], e.baseline.nativeRows[0]);
  assert.deepEqual(ours[0][7], [...e.projection.sourceSpur.slice(0, 2), e.displayAnchor]);
  assert.deepEqual(ours[1], e.baseline.nativeRows[1]);
  for (const key of Object.keys(e.baseline.measuredReferences))
    assert.deepEqual(after[key], before[key], `unexpected ${key} change`);
  assert.deepEqual(after.partsByRegion.jp.at(-1), before.partsByRegion.jp.at(-1));
  assert.deepEqual(repairParts(pkg, after, e), after);
  const geojson = candidateGeoJSON(pkg, e);
  assert.deepEqual(geojson.features.filter(feature => feature.properties.intervalIndex != null)
    .map(feature => feature.properties.intervalIndex), [23, 24]);
  assert.deepEqual(geojson.features[0].geometry.coordinates, pkg.lines[e.baseline.packageIndex].displayIntervalCoordinates[23]);
  assert.deepEqual(geojson.features[1].geometry.coordinates, pkg.lines[e.baseline.packageIndex].displayIntervalCoordinates[24]);
  assert.deepEqual(geojson.features[2].geometry.coordinates, ours[0][7]);
});

test('production stroke keeps the true reversal cusp and ends at the candidate centre at z16, z18 and z19', () => {
  const pkg = repairPackage(fixture(), e), repairedLanes = repairParts(pkg, lanes(), e);
  const built = network.buildNetworkFromCompactPackage({ format: 'compact-v1', country: 'jp',
    lines: [pkg.lines[e.baseline.packageIndex]] }, null, repairedLanes);
  const part = built.strokeModel.lines.find(row => row.lineId === e.lineID).parts[e.nativePart];
  assert.deepEqual(part.coordinates, [...e.projection.sourceSpur.slice(0, 2), e.displayAnchor]);
  for (const zoom of [16, 18, 19]) {
    const rendered = stroke.buildStroke(part.coordinates.map(point => stroke.project(point, zoom)), {
      measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
      laneGapPx: 2.7, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: 3,
      anchors: part.anchors, enforceMinimumCornerRadius: true, follows: [],
    });
    const cusp = stroke.project(e.projection.sourceSpur[0], zoom), anchor = stroke.project(e.displayAnchor, zoom);
    assert.ok(Math.hypot(rendered.points[0][0] - cusp[0], rendered.points[0][1] - cusp[1]) < 1e-9);
    assert.ok(Math.hypot(rendered.points.at(-1)[0] - anchor[0], rendered.points.at(-1)[1] - anchor[1]) < 1e-9);
  }
});

test('changed physical baselines and unknown measured references require review', () => {
  const altered = fixture(); altered.lines[e.baseline.packageIndex].segments[23][0] += 1;
  assert.throws(() => repairPackage(altered, e), /Unreviewed Dosan dependency/);
  const pkg = repairPackage(fixture(), e), input = lanes();
  input.followsByRegion.jp.push([e.lineID, 0, 0, 1, 'unknown', 0, 0, 1]);
  assert.throws(() => repairParts(pkg, input, e), /measured reference/);
});
