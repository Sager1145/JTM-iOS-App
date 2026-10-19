import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { candidateGeoJSON, repairPackage, repairParts }
  from '../repair-dosan-tsubojiri-station-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const stroke = require('../../../public/rail-stroke.js');
const e = JSON.parse(fs.readFileSync(new URL('../dosan-tsubojiri-station-display-evidence.json', import.meta.url)));
const shingai = JSON.parse(fs.readFileSync(new URL('../dosan-shingai-terminal-display-evidence.json', import.meta.url)));
const candidate = JSON.parse(fs.readFileSync(new URL(`../../../../${e.source.candidatePath}`, import.meta.url)));
const shingaiMetadata = {
  reviewedAt: shingai.reviewedAt, status: shingai.status, lineID: shingai.lineID, stationID: shingai.stationID,
  intervals: shingai.intervals, nativePart: shingai.nativePart, displayAnchor: shingai.displayAnchor,
  source: shingai.source, projection: shingai.projection, policy: shingai.policy,
  script: 'app/scripts/railway/repair-dosan-shingai-terminal-display.mjs',
  evidence: 'app/scripts/railway/dosan-shingai-terminal-display-evidence.json', physicalTopologyChanged: false,
};

function fixture(line = e.baseline.line, withShingaiMetadata = true) {
  return { lines: Array.from({ length: e.baseline.packageIndex }, (_, index) => ({ id: `before-${index}` }))
    .concat([structuredClone(line), { id: 'unrelated', keep: true }]),
  geometrySource: { manualOverrides: {
    concurrent: { keep: true }, ...(withShingaiMetadata ? { 'dosan-shingai-terminal-display': shingaiMetadata } : {}),
  } } };
}

function lanes(rows = e.baseline.nativeRows) {
  return { partsByRegion: { jp: [...structuredClone(rows), ['unrelated', 0, 1]] },
    ...Object.fromEntries(Object.entries(e.baseline.measuredReferences).map(([key, values]) =>
      [key, { jp: [...structuredClone(values), ...(key === 'byRegion' ? [['unrelated', 0, 0, 1, 0]] : [])] }])) };
}

test('frozen Main frame reproduces the bounded Tsubojiri projection and rejects tampering', () => {
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(new URL(`../../../../${e.source.candidatePath}`,
    import.meta.url))).digest('hex'), e.source.candidateSha256);
  assert.deepEqual(candidate.displayAnchor, e.displayAnchor);
  assert.equal(candidate.projectionTransverseMetres, e.projection.transverseResidualMetres);
  assert.equal(candidate.status, 'candidate pending full native comparison, not production acceptance');
  for (const mutate of [value => value.displayAnchor[0] += .00001,
    value => value.projection.sourceInterval[103][0] += .00001,
    value => value.projection.segmentIndex = 102,
    value => value.projection.maximumTransverseMetres = 2]) {
    const changed = structuredClone(e); mutate(changed);
    assert.throws(() => repairPackage(fixture(), changed));
  }
});

test('repair composes after accepted Shingai and changes only the Tsubojiri display seam', () => {
  const input = fixture(), pkg = repairPackage(input, e, shingai), line = pkg.lines[e.baseline.packageIndex];
  const physical = network.decodeIntervals(e.baseline.line);
  assert.deepEqual(line.stations, e.baseline.line.stations);
  assert.deepEqual(line.segments, e.baseline.line.segments);
  assert.deepEqual(network.decodeIntervals(line), physical);
  assert.deepEqual(Object.keys(line.displayIntervalCoordinates).map(Number).sort((a, b) => a - b), [6, 7, 23, 24]);
  assert.deepEqual(line.displayStationCoordinates, {
    [e.stationID]: e.displayAnchor,
    [shingai.stationID]: shingai.displayAnchor,
  });
  assert.deepEqual(line.displayIntervalCoordinates[6], [...physical[6].slice(0, 104), e.displayAnchor]);
  assert.deepEqual(line.displayIntervalCoordinates[7],
    [e.displayAnchor, ...physical[6].slice(104), ...physical[7].slice(1)]);
  assert(line.displayIntervalCoordinates[7].every((point, index, coordinates) =>
    index === 0 || JSON.stringify(point) !== JSON.stringify(coordinates[index - 1])));
  assert.deepEqual(line.displayIntervalCoordinates[23], e.baseline.line.displayIntervalCoordinates[23]);
  assert.deepEqual(line.displayIntervalCoordinates[24], e.baseline.line.displayIntervalCoordinates[24]);
  assert.deepEqual(line.displayIntervalCoordinates[7].slice(1, 3), e.projection.retainedSuffix);
  const beforeParts = network.displayPartsForLine(e.baseline.line), afterParts = network.displayPartsForLine(line);
  assert.deepEqual(afterParts[0], beforeParts[0]);
  const inserted = afterParts[1].findIndex(point => JSON.stringify(point) === JSON.stringify(e.displayAnchor));
  assert(inserted > 0);
  assert.deepEqual(afterParts[1].filter((_, index) => index !== inserted), beforeParts[1]);
  assert.deepEqual(pkg.lines.at(-1), input.lines.at(-1));
  assert.deepEqual(pkg.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.equal(pkg.geometrySource.manualOverrides['dosan-shingai-terminal-display'].status,
    'accepted-display-cartography');
  assert.deepEqual(repairPackage(pkg, e, shingai), pkg);
  const stale = structuredClone(pkg);
  stale.geometrySource.manualOverrides['dosan-shingai-terminal-display'].status = 'candidate-pending-native-comparison';
  assert.throws(() => repairPackage(stale, e, shingai), /Shingai dependency metadata/);
});

test('repair replays from the pre-Shingai frozen baseline without weakening either stage', () => {
  const input = fixture(shingai.baseline.line, false);
  const pkg = repairPackage(input, e, shingai);
  assert.deepEqual(pkg.lines[e.baseline.packageIndex], repairPackage(fixture(), e, shingai).lines[e.baseline.packageIndex]);
  assert.deepEqual(pkg.geometrySource.manualOverrides['dosan-shingai-terminal-display'], shingaiMetadata);
  assert.equal(pkg.geometrySource.manualOverrides['dosan-tsubojiri-station-display'].status,
    'candidate-pending-native-comparison');
  const result = repairParts(pkg, lanes(shingai.baseline.nativeRows), e, shingai);
  assert.deepEqual(result.partsByRegion.jp.filter(row => row[0] === e.lineID),
    repairParts(pkg, lanes(), e, shingai).partsByRegion.jp.filter(row => row[0] === e.lineID));
});

test('native part inserts one collinear support and the candidate GeoJSON is one complete interval 6/7 feature', () => {
  const pkg = repairPackage(fixture(), e, shingai), before = lanes();
  const after = repairParts(pkg, before, e, shingai), ours = after.partsByRegion.jp.filter(row => row[0] === e.lineID);
  assert.equal(ours.length, 2);
  assert.deepEqual(ours[0], e.baseline.nativeRows[0]);
  assert.equal(ours[1][4], e.baseline.nativeRows[1][4] + 1);
  const inserted = ours[1][7].findIndex(point => JSON.stringify(point) === JSON.stringify(e.displayAnchor));
  assert(inserted > 0);
  assert.deepEqual(ours[1][7].slice(inserted - 1, inserted + 4), [
    e.projection.sourceEdge[0], e.displayAnchor, ...e.projection.retainedSuffix,
    network.decodeIntervals(e.baseline.line)[7][1],
  ]);
  assert.deepEqual(ours[1][7].filter((_, index) => index !== inserted), e.baseline.nativeRows[1][7]);
  for (const key of Object.keys(e.baseline.measuredReferences)) assert.deepEqual(after[key], before[key]);
  assert.deepEqual(after.partsByRegion.jp.at(-1), before.partsByRegion.jp.at(-1));
  assert.deepEqual(repairParts(pkg, after, e, shingai), after);
  const geojson = candidateGeoJSON(pkg, e);
  assert.equal(geojson.features.length, 1);
  assert.deepEqual(geojson.features[0].properties.intervalIndices, [6, 7]);
  assert.deepEqual(geojson.features[0].geometry.coordinates,
    [...pkg.lines[e.baseline.packageIndex].displayIntervalCoordinates[6],
      ...pkg.lines[e.baseline.packageIndex].displayIntervalCoordinates[7].slice(1)]);
});

test('runtime source and production stroke keep the Tsubojiri station seam at the accepted candidate', () => {
  const pkg = repairPackage(fixture(), e, shingai), repairedLanes = repairParts(pkg, lanes(), e, shingai);
  const built = network.buildNetworkFromCompactPackage({ format: 'compact-v1', country: 'jp',
    lines: [pkg.lines[e.baseline.packageIndex]] }, null, repairedLanes);
  const part = built.strokeModel.lines.find(row => row.lineId === e.lineID).parts[e.nativePart];
  const index = part.coordinates.findIndex(point => JSON.stringify(point) === JSON.stringify(e.displayAnchor));
  assert(index > 0);
  assert(part.anchors.includes(index), 'Tsubojiri display seam must remain a runtime station anchor');
  assert.deepEqual(part.coordinates.slice(index - 1, index + 4), [
    e.projection.sourceEdge[0], e.displayAnchor, ...e.projection.retainedSuffix,
    network.decodeIntervals(e.baseline.line)[7][1],
  ]);
  for (const zoom of [16, 18, 19]) {
    const rendered = stroke.buildStroke(part.coordinates.map(point => stroke.project(point, zoom)), {
      measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
      laneGapPx: 2.7, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: 3,
      anchors: part.anchors, enforceMinimumCornerRadius: true, follows: [],
    });
    const anchor = stroke.project(e.displayAnchor, zoom);
    assert(rendered.points.some(point => Math.hypot(point[0] - anchor[0], point[1] - anchor[1]) < 1e-9));
  }
});

test('changed physical baselines and new measured consumers require explicit review', () => {
  const altered = fixture(); altered.lines[e.baseline.packageIndex].segments[6][0] += 1;
  assert.throws(() => repairPackage(altered, e, shingai), /dependency|baseline/);
  const pkg = repairPackage(fixture(), e, shingai), input = lanes();
  input.familyWindowsByRegion.jp.push([e.lineID, 1, 0, 1]);
  assert.throws(() => repairParts(pkg, input, e, shingai), /measured reference/);
});
