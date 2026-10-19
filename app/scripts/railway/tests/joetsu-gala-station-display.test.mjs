import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { candidateGeoJSON, repairPackage, repairParts }
  from '../repair-joetsu-gala-station-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const e = JSON.parse(fs.readFileSync(new URL('../joetsu-gala-station-display-evidence.json', import.meta.url)));

function referenceLine() {
  const source = e.source.referenceLine;
  const stations = Array.from({ length: source.stationIndex + 1 }, (_, index) =>
    index === source.stationIndex ? structuredClone(source.station) : [`ref-${index}`, `Ref ${index}`, 0, 0]);
  return { id: source.lineID, railwayIdentity: source.railwayIdentity, stations, segments: [] };
}

function fixture(line = e.baseline.line) {
  const lines = Array.from({ length: e.packageIndex + 1 }, (_, index) => ({ id: `before-${index}` }));
  lines[e.source.referenceLine.packageIndex] = referenceLine();
  lines[e.packageIndex - 1] = { id: 'same-station-unrelated', stations: [
    [e.stationID, '越後湯沢', ...e.baseline.oldDisplayAnchor, 'Echigo-Yuzawa', 1],
  ], segments: [] };
  lines[e.packageIndex] = structuredClone(line);
  lines.push({ id: 'unrelated-after', keep: true });
  return { lines, geometrySource: { manualOverrides: { concurrent: { keep: true } } } };
}

function lanes() {
  return {
    partsByRegion: { jp: [...structuredClone(e.baseline.nativeRows), ['unrelated', 0, 0, 0, 2, 1, null, null, []]] },
    byRegion: { jp: [...structuredClone(e.baseline.byRegion), ['unrelated', 0, 0, 1, 0]] },
    followsByRegion: { jp: [] }, familyWindowsByRegion: { jp: [] }, reversedLoopParts: { jp: [] },
    chainBoundariesByRegion: { jp: [] }, releasedIntervalsByRegion: { jp: [] },
  };
}

test('frozen Main/GSI evidence and registered Shinkansen anchor reject source drift', () => {
  for (const source of e.source.savedCartography) {
    const file = new URL(`../../../../${source.path}`, import.meta.url);
    const digest = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    assert.equal(digest, source.sha256);
  }
  assert.deepEqual(e.displayAnchor, e.source.referenceLine.station.slice(2, 4));
  const moved = fixture();
  moved.lines[e.source.referenceLine.packageIndex].stations[e.source.referenceLine.stationIndex][2] += .00001;
  assert.throws(() => repairPackage(moved, e), /Shinkansen station anchor/);
  const wrongIdentity = fixture();
  wrongIdentity.lines[e.source.referenceLine.packageIndex].railwayIdentity = 'wrong';
  assert.throws(() => repairPackage(wrongIdentity, e), /identity/);
  const wrongRawFeature = structuredClone(e);
  wrongRawFeature.source.rawStationFeatures[0].feature.properties.line_name = 'wrong';
  assert.throws(() => repairPackage(fixture(), wrongRawFeature), /N02 station feature/);
});

test('repair replaces only the Gala display endpoint and preserves every physical record', () => {
  const input = fixture(), beforeReference = structuredClone(input.lines[e.source.referenceLine.packageIndex]);
  const beforeSameStation = structuredClone(input.lines[e.packageIndex - 1]);
  const pkg = repairPackage(input, e), line = pkg.lines[e.packageIndex];
  assert.deepEqual(line.stations, e.baseline.line.stations);
  assert.deepEqual(line.segments, e.baseline.line.segments);
  assert.deepEqual(network.decodeIntervals(line), e.baseline.physicalInterval.length ? [e.baseline.physicalInterval] : []);
  assert.deepEqual(line.displayStationCoordinates, { [e.stationID]: e.displayAnchor });
  assert.deepEqual(line.displayIntervalCoordinates[0].slice(0, -1), e.baseline.physicalInterval.slice(0, -1));
  assert.deepEqual(line.displayIntervalCoordinates[0].at(-1), e.displayAnchor);
  assert.equal(line.displayIntervalCoordinates[0].length, 25);
  assert.deepEqual(pkg.lines[e.source.referenceLine.packageIndex], beforeReference);
  assert.deepEqual(pkg.lines[e.packageIndex - 1], beforeSameStation);
  assert.deepEqual(pkg.lines.at(-1), input.lines.at(-1));
  assert.deepEqual(pkg.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.equal(pkg.geometrySource.manualOverrides['joetsu-gala-station-display'].physicalTopologyChanged, false);
  assert.deepEqual(repairPackage(pkg, e), pkg);
});

test('native rows and base lane total replay without creating measured consumers', () => {
  const pkg = repairPackage(fixture(), e), before = lanes(), after = repairParts(pkg, before, e);
  const row = after.partsByRegion.jp.find(item => item[0] === e.lineID);
  const base = after.byRegion.jp.find(item => item[0] === e.lineID);
  assert.deepEqual(row.slice(0, 5), [e.lineID, 0, 0, 0, 25]);
  assert.equal(row[7], null, 'complete source interval remains referenced without a cached coordinate copy');
  assert(row[5] < e.baseline.nativeRows[0][5] && e.baseline.nativeRows[0][5] - row[5] < 15,
    'only the reviewed terminal chord length may change');
  assert.deepEqual(base, [e.lineID, 0, 0, row[5], e.baseline.byRegion[0][4]]);
  for (const key of ['followsByRegion', 'familyWindowsByRegion', 'reversedLoopParts',
    'chainBoundariesByRegion', 'releasedIntervalsByRegion']) assert.deepEqual(after[key], before[key]);
  assert.deepEqual(after.partsByRegion.jp.at(-1), before.partsByRegion.jp.at(-1));
  assert.deepEqual(repairParts(pkg, after, e), after);
});

test('candidate is one complete interval feature with explicit reference identity', () => {
  const pkg = repairPackage(fixture(), e), geojson = candidateGeoJSON(pkg, e);
  assert.equal(geojson.features.length, 1);
  const feature = geojson.features[0];
  assert.equal(feature.properties.lineID, e.lineID);
  assert.equal(feature.properties.referenceLineID, e.lineID);
  assert.equal(feature.properties.anchorReferenceLineID, e.source.referenceLine.lineID);
  assert.equal(feature.properties.intervalIndex, 0);
  assert.deepEqual(feature.geometry.coordinates, pkg.lines[e.packageIndex].displayIntervalCoordinates[0]);
});

test('runtime compact model keeps the accepted endpoint as a station anchor', () => {
  const pkg = repairPackage(fixture(), e), repairedLanes = repairParts(pkg, lanes(), e);
  const built = network.buildNetworkFromCompactPackage({ format: 'compact-v1', country: 'jp',
    lines: [pkg.lines[e.packageIndex]] }, null, repairedLanes);
  const part = built.strokeModel.lines.find(row => row.lineId === e.lineID).parts[0];
  assert.deepEqual(part.coordinates.slice(0, -1), e.baseline.physicalInterval.slice(0, -1));
  assert.deepEqual(part.coordinates.at(-1), e.displayAnchor);
  assert(part.anchors.includes(part.coordinates.length - 1));
});

test('physical drift and new measured references require explicit review', () => {
  const changed = fixture();
  changed.lines[e.packageIndex].segments[0][2][23][0] += .00001;
  assert.throws(() => repairPackage(changed, e), /dependency|physical interval/);
  const pkg = repairPackage(fixture(), e), input = lanes();
  input.familyWindowsByRegion.jp.push([e.lineID, 0, 0, 1]);
  assert.throws(() => repairParts(pkg, input, e), /measured reference/);
});
