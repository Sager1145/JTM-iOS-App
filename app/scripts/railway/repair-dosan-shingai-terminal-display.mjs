#!/usr/bin/env node
// Final Shingai display stage. The N02 physical reversal and route stay unchanged.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const EVIDENCE = 'scripts/railway/dosan-shingai-terminal-display-evidence.json';
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

function inverseMercator(frame, pixel) {
  const longitude = frame.west + pixel[0] / frame.viewportWidth * (frame.east - frame.west);
  const mercator = latitude => Math.log(Math.tan(Math.PI / 4 + latitude * Math.PI / 360));
  const north = mercator(frame.north), south = mercator(frame.south);
  const value = north + pixel[1] / frame.viewportHeight * (south - north);
  return [longitude, (2 * Math.atan(Math.exp(value)) - Math.PI / 2) * 180 / Math.PI];
}

function validateEvidence(e) {
  assert.equal(e.format, 'jtm-dosan-shingai-terminal-display-v1');
  assert.deepEqual([e.lineID, e.stationID, e.stationIndex, e.intervals, e.nativePart, e.mainPart],
    ['jp-四国旅客鉄道-土讃線', '008946', 24, [23, 24], 0, 1]);
  const candidatePath = path.join(REPO, e.source.candidatePath);
  assert.equal(sha256(candidatePath), e.source.candidateSha256, 'Frozen Shingai candidate changed');
  const candidate = JSON.parse(fs.readFileSync(candidatePath));
  assert.deepEqual([candidate.format, candidate.lineID, candidate.stationID, candidate.status],
    ['jtm-shingai-main-georeference-v1', e.lineID, e.stationID,
      'candidate pending full native comparison, not production acceptance']);
  for (const source of candidate.sources) {
    const file = path.join(REPO, source.path);
    assert.equal(sha256(file), source.sha256, `Reviewed Shingai source changed: ${source.path}`);
  }
  const frame = { ...candidate.mapRegion, viewportWidth: candidate.viewport[0], viewportHeight: candidate.viewport[1] };
  const coordinate = inverseMercator(frame, candidate.stationFrame.centreRailPixel);
  assert(distance(coordinate, candidate.inverseMercatorCoordinate) < 1e-7,
    'Reviewed Main map coordinate is no longer reproducible');
  const projection = projectPointOntoPolyline(coordinate, e.projection.sourceSpur);
  assert.equal(projection.insertIndex, e.projection.segmentIndex);
  assert(distance(projection.point, e.displayAnchor) < 1e-7, 'Reviewed rail projection changed');
  assert(Math.abs(projection.distanceM - e.projection.transverseResidualMetres) < 1e-9);
  assert(projection.distanceM < e.projection.maximumTransverseMetres);
  assert.deepEqual(candidate.displayAnchor, e.displayAnchor);
  assert.equal(candidate.projectionTransverseMetres, e.projection.transverseResidualMetres);
  const sourceTail = e.projection.sourceSpur.slice(e.projection.segmentIndex + 1);
  const trim = distance(e.displayAnchor, sourceTail[0]) + sourceTail.slice(1)
    .reduce((total, point, index) => total + distance(sourceTail[index], point), 0);
  assert(Math.abs(trim - e.projection.trimMetres) < 1e-9);
  assert(trim < e.projection.maximumTrimMetres);
}

function repairedLine(e) {
  validateEvidence(e);
  const line = structuredClone(e.baseline.line);
  const physical = network.decodeIntervals(line), incoming = physical[e.intervals[0]], outgoing = physical[e.intervals[1]];
  assert.deepEqual(incoming.slice(-e.projection.sourceSpur.length), e.projection.sourceSpur,
    'Shingai incoming physical reversal changed');
  assert.deepEqual(outgoing.slice(0, e.projection.sourceSpur.length), e.projection.sourceSpur.toReversed(),
    'Shingai outgoing physical reversal changed');
  const retainedIncoming = incoming.slice(0, -2);
  const retainedOutgoing = outgoing.slice(2);
  assert.deepEqual(retainedIncoming.at(-1), e.projection.sourceSpur[1]);
  assert.deepEqual(retainedOutgoing[0], e.projection.sourceSpur[1]);
  line.displayStationCoordinates = { [e.stationID]: structuredClone(e.displayAnchor) };
  line.displayIntervalCoordinates = {
    [e.intervals[0]]: [...retainedIncoming, structuredClone(e.displayAnchor)],
    [e.intervals[1]]: [structuredClone(e.displayAnchor), ...retainedOutgoing],
  };
  return line;
}

export function repairPackage(input, e = read(EVIDENCE)) {
  const current = input.lines[e.baseline.packageIndex], repaired = repairedLine(e);
  assert(current && current.id === e.lineID && (equal(current, e.baseline.line) || equal(current, repaired)),
    'Unreviewed Dosan dependency changed');
  assert.deepEqual(repaired.stations, e.baseline.line.stations);
  assert.deepEqual(repaired.segments, e.baseline.line.segments);
  const beforeParts = network.displayPartsForLine(e.baseline.line), afterParts = network.displayPartsForLine(repaired);
  assert.equal(beforeParts.length, 2); assert.equal(afterParts.length, 2);
  assert.deepEqual(afterParts[e.nativePart], [...e.projection.sourceSpur.slice(0, 2), e.displayAnchor]);
  assert.deepEqual(afterParts[e.mainPart], beforeParts[e.mainPart], 'Dosan through main changed');
  const pkg = structuredClone(input);
  pkg.lines[e.baseline.packageIndex] = repaired;
  pkg.geometrySource ||= {}; pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['dosan-shingai-terminal-display'] = {
    reviewedAt: e.reviewedAt, status: e.status, lineID: e.lineID, stationID: e.stationID,
    intervals: e.intervals, nativePart: e.nativePart, displayAnchor: e.displayAnchor,
    source: e.source, projection: e.projection, policy: e.policy,
    script: 'app/scripts/railway/repair-dosan-shingai-terminal-display.mjs',
    evidence: 'app/scripts/railway/dosan-shingai-terminal-display-evidence.json',
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

function references(input, e) {
  return Object.fromEntries(Object.keys(e.baseline.measuredReferences).map(key => [key,
    key === 'reversedLoopParts'
      ? (input[key]?.jp || []).filter(row => String(row).includes(e.lineID))
      : (input[key]?.jp || []).filter(row => JSON.stringify(row).includes(e.lineID))]));
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  const line = pkg.lines[e.baseline.packageIndex];
  assert(line && equal(line, repairedLine(e)), 'Shingai package repair missing');
  assert.deepEqual(references(input, e), e.baseline.measuredReferences,
    'Unreviewed Dosan measured reference');
  const parts = network.displayPartsForLine(line);
  const rows = partRowsForLine(line, parts, displayInputs(line), null);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[e.mainPart], e.baseline.nativeRows[e.mainPart], 'Dosan through native part changed');
  const current = input.partsByRegion.jp.filter(row => row[0] === e.lineID);
  assert(equal(current, e.baseline.nativeRows) || equal(current, rows), 'Dosan native rows changed');
  const first = input.partsByRegion.jp.findIndex(row => row[0] === e.lineID);
  assert(first >= 0);
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.filter(row => row[0] !== e.lineID);
  result.partsByRegion.jp.splice(first, 0, ...rows);
  return result;
}

export function candidateGeoJSON(pkg, e) {
  const line = pkg.lines[e.baseline.packageIndex];
  return { type: 'FeatureCollection', features: [
    ...e.intervals.map(index => ({ type: 'Feature', properties: { lineID: e.lineID, intervalIndex: index },
      geometry: { type: 'LineString', coordinates: line.displayIntervalCoordinates[index] } })),
    { type: 'Feature', properties: { lineID: e.lineID, nativePart: e.nativePart, role: 'display-reversal-spur' },
      geometry: { type: 'LineString', coordinates: network.displayPartsForLine(line)[e.nativePart] } },
    { type: 'Feature', properties: { stationID: e.stationID, role: 'display-station-anchor' },
      geometry: { type: 'Point', coordinates: e.displayAnchor } },
  ] };
}

function prepare(args) {
  const candidateAt = args.indexOf('--candidate-root');
  const candidate = candidateAt === 0 && args.length === 2;
  const apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-dosan-shingai-terminal-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  const paths = { package: PACKAGE, lanes: LANES, evidence: EVIDENCE, ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  if (apply) assert.equal(e.status, 'accepted-display-cartography',
    'Shingai candidate requires accepted native comparison before apply');
  const candidateFile = path.join(REPO, e.source.candidatePath);
  const reviewedCandidate = JSON.parse(fs.readFileSync(candidateFile));
  const sources = [{ path: candidateFile, before: fs.readFileSync(candidateFile) }, ...reviewedCandidate.sources.map(source => {
    const file = path.join(REPO, source.path); return { path: file, before: fs.readFileSync(file) };
  })];
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  return { candidate: candidate ? path.resolve(args[1]) : null, apply, snapshots, sources, e, pkg, lanes, dependencies };
}

function main(args = process.argv.slice(2)) {
  const prepared = prepare(args);
  for (const source of prepared.sources)
    assert(fs.readFileSync(source.path).equals(source.before), 'Reviewed Shingai source changed during preparation');
  const outputs = { package: JSON.stringify(prepared.pkg), lanes: JSON.stringify(prepared.lanes) + '\n',
    ...Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key =>
      [key, JSON.stringify(prepared.dependencies[key], null, 2) + '\n'])) };
  if (prepared.candidate) {
    assert(prepared.candidate.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
    fs.mkdirSync(prepared.candidate, { recursive: true });
    for (const [key, contents] of Object.entries(outputs))
      fs.writeFileSync(path.join(prepared.candidate, path.basename(prepared.snapshots[key].path)), contents);
    fs.writeFileSync(path.join(prepared.candidate, 'shingai-display-candidate.geojson'),
      JSON.stringify(candidateGeoJSON(prepared.pkg, prepared.e), null, 2) + '\n');
  } else {
    const writes = Object.entries(outputs).filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path, before: prepared.snapshots[key].before,
        after: contents, temporary: `${prepared.snapshots[key].path}.shingai-${process.pid}.tmp` }));
    applyPreparedWrites(writes, Object.values(prepared.snapshots));
  }
  const line = prepared.pkg.lines[prepared.e.baseline.packageIndex];
  const part = prepared.lanes.partsByRegion.jp.find(row => row[0] === prepared.e.lineID && row[1] === prepared.e.nativePart);
  console.log(JSON.stringify({ mode: prepared.apply ? 'applied' : 'candidate', lineID: prepared.e.lineID,
    stationID: prepared.e.stationID, displayAnchor: line.displayStationCoordinates[prepared.e.stationID],
    intervals: prepared.e.intervals.map(index => ({ index, pointCount: line.displayIntervalCoordinates[index].length })),
    nativePartPointCount: part[4], nativePartMetres: part[5], physicalTopologyChanged: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
