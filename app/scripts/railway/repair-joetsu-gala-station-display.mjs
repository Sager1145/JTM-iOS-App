#!/usr/bin/env node
// Display-only Gala-Yuzawa branch approach at Echigo-Yuzawa.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS }
  from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const EVIDENCE = 'scripts/railway/joetsu-gala-station-display-evidence.json';
const PACKAGE = 'public/rail/jp-2025.json';
const LANES = 'public/rail/display-lanes.json';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function distance(a, b) {
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
    (b[1] - a[1]) * 111320);
}

function validateEvidence(e, input) {
  assert.equal(e.format, 'jtm-joetsu-gala-station-display-v1');
  assert.deepEqual([e.lineID, e.packageIndex, e.stationID, e.stationIndex, e.intervalIndex, e.nativePart],
    ['jp-東日本旅客鉄道-上越線-2', 319, '001717', 1, 0, 0]);
  assert.deepEqual(e.displayAnchor, [138.809496, 36.935445]);
  for (const source of e.source.savedCartography) {
    const file = path.join(REPO, source.path);
    assert.equal(sha256(file), source.sha256, `Reviewed Gala source changed: ${source.path}`);
  }
  const rawStations = read('data/stations.json').features;
  for (const source of e.source.rawStationFeatures)
    assert.deepEqual(rawStations[source.featureIndex], source.feature,
      `Relevant N02 station feature changed: ${source.featureIndex}`);
  const reference = input.lines[e.source.referenceLine.packageIndex];
  assert.equal(reference?.id, e.source.referenceLine.lineID, 'Registered Shinkansen line index changed');
  assert.deepEqual(reference.stations[e.source.referenceLine.stationIndex], e.source.referenceLine.station,
    'Registered Shinkansen station anchor changed');
  assert.equal(reference.railwayIdentity, e.source.referenceLine.railwayIdentity,
    'Registered Shinkansen identity changed');
  const registered = reference.displayStationCoordinates?.[e.stationID] ||
    reference.stations[e.source.referenceLine.stationIndex].slice(2, 4);
  assert.deepEqual(registered, e.displayAnchor, 'Candidate no longer uses the registered Shinkansen anchor');
}

function repairedLine(e, input) {
  validateEvidence(e, input);
  const line = structuredClone(e.baseline.line);
  assert.deepEqual(line.stations[e.stationIndex].slice(0, 4),
    [e.stationID, '越後湯沢', ...e.baseline.oldDisplayAnchor]);
  assert(!line.displayStationCoordinates?.[e.stationID], 'Unreviewed Gala station alias already exists');
  assert(!line.displayIntervalCoordinates?.[e.intervalIndex], 'Unreviewed Gala interval alias already exists');
  const physical = network.decodeIntervals(line)[e.intervalIndex];
  assert.deepEqual(physical, e.baseline.physicalInterval, 'Gala physical interval changed');
  assert.deepEqual(physical.slice(-5), e.baseline.lastFivePoints, 'Gala terminal approach changed');
  assert.equal(physical.length, 25);
  const display = [...physical.slice(0, -1), structuredClone(e.displayAnchor)];
  assert.deepEqual(display.slice(0, -1), physical.slice(0, -1), 'Gala first 24 display points changed');
  assert(distance(display.at(-2), display.at(-1)) < e.guard.maximumFinalSegmentMetres);
  assert(Math.abs(distance(display.at(-2), display.at(-1)) - e.guard.finalSegmentMetres) < 1e-6);
  line.displayStationCoordinates = { ...line.displayStationCoordinates,
    [e.stationID]: structuredClone(e.displayAnchor) };
  line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates,
    [e.intervalIndex]: display };
  return line;
}

export function repairPackage(input, e = read(EVIDENCE)) {
  const current = input.lines[e.packageIndex], repaired = repairedLine(e, input);
  assert(current?.id === e.lineID && (equal(current, e.baseline.line) || equal(current, repaired)),
    'Unreviewed Gala package dependency changed');
  assert.deepEqual(repaired.stations, e.baseline.line.stations);
  assert.deepEqual(repaired.segments, e.baseline.line.segments);
  const pkg = structuredClone(input);
  pkg.lines[e.packageIndex] = repaired;
  pkg.geometrySource ||= {}; pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['joetsu-gala-station-display'] = {
    reviewedAt: e.reviewedAt, status: e.status, lineID: e.lineID, stationID: e.stationID,
    intervalIndex: e.intervalIndex, nativePart: e.nativePart, displayAnchor: e.displayAnchor,
    referenceLineID: e.source.referenceLine.lineID, source: e.source.savedCartography,
    policy: e.policy,
    script: 'app/scripts/railway/repair-joetsu-gala-station-display.mjs',
    evidence: 'app/scripts/railway/joetsu-gala-station-display-evidence.json',
    physicalTopologyChanged: false,
  };
  return pkg;
}

function displayInputs(line) {
  const displayLine = { ...line,
    stations: line.stations.map(station => line.displayStationCoordinates?.[station[0]]
      ? [...station.slice(0, 2), ...line.displayStationCoordinates[station[0]], ...station.slice(4)] : station),
    segments: line.segments.map((segment, index) => line.displayIntervalCoordinates?.[index]
      ? [segment[0], 0, line.displayIntervalCoordinates[index]] : segment) };
  return { stations: displayLine.stations, intervals: network.decodeIntervals(displayLine) };
}

function measuredReferences(input, lineID) {
  const result = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === 'partsByRegion' || !Array.isArray(value?.jp)) continue;
    const rows = value.jp.filter(row => JSON.stringify(row).includes(lineID));
    if (rows.length) result[key] = rows;
  }
  return result;
}

function replaceRows(rows, lineID, replacement) {
  const first = rows.findIndex(row => row[0] === lineID);
  assert(first >= 0, `Missing measured row for ${lineID}`);
  const result = rows.filter(row => row[0] !== lineID);
  result.splice(first, 0, ...replacement);
  return result;
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  const line = pkg.lines[e.packageIndex], expected = repairedLine(e, pkg);
  assert(line && equal(line, expected), 'Gala package repair missing');
  const rows = partRowsForLine(line, network.displayPartsForLine(line), displayInputs(line), null);
  assert.equal(rows.length, 1);
  assert.deepEqual(rows[0].slice(0, 4), [e.lineID, e.nativePart, 0, 0]);
  assert.equal(rows[0][4], 25);
  const current = input.partsByRegion.jp.filter(row => row[0] === e.lineID);
  assert(equal(current, e.baseline.nativeRows) || equal(current, rows), 'Gala native row changed');
  const byRegion = [[e.lineID, e.nativePart, 0, rows[0][5], e.baseline.byRegion[0][4]]];
  const expectedReferences = { ...e.baseline.measuredReferences, byRegion };
  const references = measuredReferences(input, e.lineID);
  assert(equal(references, e.baseline.measuredReferences) || equal(references, expectedReferences),
    'Unreviewed Gala measured reference');
  const result = structuredClone(input);
  result.partsByRegion.jp = replaceRows(result.partsByRegion.jp, e.lineID, rows);
  result.byRegion.jp = replaceRows(result.byRegion.jp, e.lineID, byRegion);
  return result;
}

export function candidateGeoJSON(pkg, e) {
  const line = pkg.lines[e.packageIndex];
  return { type: 'FeatureCollection', features: [{ type: 'Feature', properties: {
    lineID: e.lineID, referenceLineID: e.lineID,
    anchorReferenceLineID: e.source.referenceLine.lineID, intervalIndex: e.intervalIndex,
    stationID: e.stationID, displayAnchor: e.displayAnchor, status: e.status,
  }, geometry: { type: 'LineString', coordinates: line.displayIntervalCoordinates[e.intervalIndex] } }] };
}

function prepare(args) {
  const candidate = args[0] === '--candidate-root' && args.length === 2, apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-joetsu-gala-station-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  const paths = { package: PACKAGE, lanes: LANES, evidence: EVIDENCE, ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  if (apply) assert.equal(e.status, 'accepted-display-cartography',
    'Gala candidate requires accepted native comparison before apply');
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  return { candidate: candidate ? path.resolve(args[1]) : null, apply, snapshots, e, pkg, lanes, dependencies };
}

function main(args = process.argv.slice(2)) {
  const prepared = prepare(args);
  const outputs = { package: JSON.stringify(prepared.pkg), lanes: JSON.stringify(prepared.lanes) + '\n',
    ...Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key =>
      [key, JSON.stringify(prepared.dependencies[key], null, 2) + '\n'])) };
  if (prepared.candidate) {
    assert(prepared.candidate.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
    fs.mkdirSync(prepared.candidate, { recursive: true });
    for (const [key, contents] of Object.entries(outputs))
      fs.writeFileSync(path.join(prepared.candidate, path.basename(prepared.snapshots[key].path)), contents);
    fs.writeFileSync(path.join(prepared.candidate, 'joetsu-gala-interval-0.geojson'),
      JSON.stringify(candidateGeoJSON(prepared.pkg, prepared.e), null, 2) + '\n');
  } else {
    const writes = Object.entries(outputs).filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path, before: prepared.snapshots[key].before,
        after: contents, temporary: `${prepared.snapshots[key].path}.gala-${process.pid}.tmp` }));
    applyPreparedWrites(writes, Object.values(prepared.snapshots));
  }
  const line = prepared.pkg.lines[prepared.e.packageIndex];
  const part = prepared.lanes.partsByRegion.jp.find(row => row[0] === prepared.e.lineID);
  console.log(JSON.stringify({ mode: prepared.apply ? 'applied' : 'candidate', lineID: prepared.e.lineID,
    stationID: prepared.e.stationID, displayAnchor: line.displayStationCoordinates[prepared.e.stationID],
    intervalPointCount: line.displayIntervalCoordinates[prepared.e.intervalIndex].length,
    nativePartPointCount: part[4], nativePartMetres: part[5], physicalTopologyChanged: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
