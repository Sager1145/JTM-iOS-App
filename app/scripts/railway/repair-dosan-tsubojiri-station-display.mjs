#!/usr/bin/env node
// Display-only Tsubojiri station seam, composed after the Shingai display stage.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { repairPackage as repairShingaiPackage, repairParts as repairShingaiParts }
  from './repair-dosan-shingai-terminal-display.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS }
  from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const EVIDENCE = 'scripts/railway/dosan-tsubojiri-station-display-evidence.json';
const SHINGAI_EVIDENCE = 'scripts/railway/dosan-shingai-terminal-display-evidence.json';
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

function inverseMercator(candidate, pixel) {
  const [width, height] = candidate.viewport, region = candidate.mapRegion;
  const longitude = region.west + pixel[0] / width * (region.east - region.west);
  const mercator = latitude => Math.log(Math.tan(Math.PI / 4 + latitude * Math.PI / 360));
  const north = mercator(region.north), south = mercator(region.south);
  const value = north + pixel[1] / height * (south - north);
  return [longitude, (2 * Math.atan(Math.exp(value)) - Math.PI / 2) * 180 / Math.PI];
}

function validateEvidence(e) {
  assert.equal(e.format, 'jtm-dosan-tsubojiri-station-display-v1');
  assert.deepEqual([e.lineID, e.stationID, e.stationIndex, e.intervals, e.nativePart],
    ['jp-四国旅客鉄道-土讃線', '008522', 7, [6, 7], 1]);
  const candidatePath = path.join(REPO, e.source.candidatePath);
  assert.equal(sha256(candidatePath), e.source.candidateSha256, 'Frozen Tsubojiri candidate changed');
  const candidate = JSON.parse(fs.readFileSync(candidatePath));
  assert.deepEqual([candidate.format, candidate.lineID, candidate.stationID, candidate.status],
    ['jtm-tsubojiri-main-georeference-v1', e.lineID, e.stationID,
      'candidate pending full native comparison, not production acceptance']);
  for (const source of candidate.sources) {
    const file = path.join(REPO, source.path);
    assert.equal(sha256(file), source.sha256, `Reviewed Tsubojiri source changed: ${source.path}`);
  }
  const coordinate = inverseMercator(candidate, candidate.stationFrame.centreRailPixel);
  assert(distance(coordinate, candidate.inverseMercatorCoordinate) < 1e-7,
    'Reviewed Main map coordinate is no longer reproducible');
  const projection = projectPointOntoPolyline(coordinate, e.projection.sourceInterval);
  assert.equal(projection.insertIndex, e.projection.segmentIndex);
  assert(distance(projection.point, e.displayAnchor) < 1e-7, 'Reviewed rail projection changed');
  assert(Math.abs(projection.distanceM - e.projection.transverseResidualMetres) < 1e-9);
  assert(projection.distanceM < e.projection.maximumTransverseMetres);
  assert.deepEqual(candidate.displayAnchor, e.displayAnchor);
  assert.equal(candidate.projectionTransverseMetres, e.projection.transverseResidualMetres);
  assert.deepEqual(e.projection.sourceInterval.slice(e.projection.segmentIndex, e.projection.segmentIndex + 2),
    e.projection.sourceEdge);
}

function repairedLine(e) {
  validateEvidence(e);
  const line = structuredClone(e.baseline.line);
  const physical = network.decodeIntervals(line), incoming = physical[e.intervals[0]], outgoing = physical[e.intervals[1]];
  assert.deepEqual(incoming, e.projection.sourceInterval, 'Tsubojiri incoming physical interval changed');
  assert.deepEqual(incoming.at(-1), e.projection.oldPhysicalStation);
  assert.deepEqual(line.stations[e.stationIndex].slice(0, 4),
    [e.stationID, '坪尻', ...e.projection.oldPhysicalStation]);
  assert(!line.displayStationCoordinates?.[e.stationID], 'Unreviewed Tsubojiri station alias already exists');
  assert(!line.displayIntervalCoordinates?.[e.intervals[0]] && !line.displayIntervalCoordinates?.[e.intervals[1]],
    'Unreviewed Tsubojiri interval alias already exists');
  const split = e.projection.segmentIndex;
  assert.deepEqual(outgoing[0], e.projection.oldPhysicalStation,
    'Tsubojiri outgoing physical seam changed');
  const incomingDisplay = [...incoming.slice(0, split + 1), structuredClone(e.displayAnchor)];
  const outgoingDisplay = [structuredClone(e.displayAnchor), ...incoming.slice(split + 1), ...outgoing.slice(1)];
  assert(outgoingDisplay.every((point, index) => index === 0 || !equal(point, outgoingDisplay[index - 1])),
    'Tsubojiri display interval contains an adjacent zero-length edge');
  assert.deepEqual(outgoingDisplay.slice(1, 3), e.projection.retainedSuffix,
    'Tsubojiri original curve supports were not retained');
  line.displayStationCoordinates = { ...line.displayStationCoordinates,
    [e.stationID]: structuredClone(e.displayAnchor) };
  line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates,
    [e.intervals[0]]: incomingDisplay, [e.intervals[1]]: outgoingDisplay };
  return line;
}

function withBaselineLine(pkg, e) {
  const result = structuredClone(pkg);
  result.lines[e.baseline.packageIndex] = structuredClone(e.baseline.line);
  return result;
}

function shingaiMetadata(e) {
  return {
    reviewedAt: e.reviewedAt, status: e.status, lineID: e.lineID, stationID: e.stationID,
    intervals: e.intervals, nativePart: e.nativePart, displayAnchor: e.displayAnchor,
    source: e.source, projection: e.projection, policy: e.policy,
    script: 'app/scripts/railway/repair-dosan-shingai-terminal-display.mjs',
    evidence: 'app/scripts/railway/dosan-shingai-terminal-display-evidence.json',
    physicalTopologyChanged: false,
  };
}

export function repairPackage(input, e = read(EVIDENCE), shingai = read(SHINGAI_EVIDENCE)) {
  const expected = repairedLine(e), current = input.lines[e.baseline.packageIndex];
  assert(current?.id === e.lineID, 'Dosan line index changed');
  let base;
  if (equal(current, expected)) base = structuredClone(input);
  else {
    base = repairShingaiPackage(input, shingai);
    assert.deepEqual(base.lines[e.baseline.packageIndex], e.baseline.line,
      'Unreviewed post-Shingai Dosan dependency changed');
    base.lines[e.baseline.packageIndex] = expected;
  }
  assert.deepEqual(base.geometrySource?.manualOverrides?.['dosan-shingai-terminal-display'],
    shingaiMetadata(shingai), 'Accepted Shingai dependency metadata changed');
  assert.deepEqual(expected.stations, e.baseline.line.stations);
  assert.deepEqual(expected.segments, e.baseline.line.segments);
  const beforeParts = network.displayPartsForLine(e.baseline.line), afterParts = network.displayPartsForLine(expected);
  assert.equal(beforeParts.length, 2); assert.equal(afterParts.length, 2);
  assert.deepEqual(afterParts[0], beforeParts[0], 'Shingai reversal spur changed');
  const before = beforeParts[e.nativePart], after = afterParts[e.nativePart];
  const index = after.findIndex(point => equal(point, e.displayAnchor));
  assert(index > 0 && equal(after[index + 1], e.projection.retainedSuffix[0]));
  assert.deepEqual(after.filter((_, i) => i !== index), before,
    'Tsubojiri changed the original rail locus');
  base.geometrySource ||= {}; base.geometrySource.manualOverrides ||= {};
  base.geometrySource.manualOverrides['dosan-tsubojiri-station-display'] = {
    reviewedAt: e.reviewedAt, status: e.status, lineID: e.lineID, stationID: e.stationID,
    intervals: e.intervals, nativePart: e.nativePart, displayAnchor: e.displayAnchor,
    source: e.source, projection: { segmentIndex: e.projection.segmentIndex,
      transverseResidualMetres: e.projection.transverseResidualMetres,
      maximumTransverseMetres: e.projection.maximumTransverseMetres }, policy: e.policy,
    script: 'app/scripts/railway/repair-dosan-tsubojiri-station-display.mjs',
    evidence: 'app/scripts/railway/dosan-tsubojiri-station-display-evidence.json',
    physicalTopologyChanged: false,
  };
  return base;
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

export function repairParts(pkg, input, e = read(EVIDENCE), shingai = read(SHINGAI_EVIDENCE)) {
  const line = pkg.lines[e.baseline.packageIndex], expected = repairedLine(e);
  assert(line && equal(line, expected), 'Tsubojiri package repair missing');
  assert.deepEqual(references(input, e), e.baseline.measuredReferences,
    'Unreviewed Dosan measured reference');
  const parts = network.displayPartsForLine(line);
  const rows = partRowsForLine(line, parts, displayInputs(line), null);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], e.baseline.nativeRows[0], 'Shingai native reversal spur changed');
  const current = input.partsByRegion.jp.filter(row => row[0] === e.lineID);
  if (equal(current, rows)) return structuredClone(input);
  const upstream = repairShingaiParts(withBaselineLine(pkg, e), input, shingai);
  assert.deepEqual(upstream.partsByRegion.jp.filter(row => row[0] === e.lineID), e.baseline.nativeRows,
    'Unreviewed post-Shingai native dependency changed');
  const first = upstream.partsByRegion.jp.findIndex(row => row[0] === e.lineID);
  const result = structuredClone(upstream);
  result.partsByRegion.jp = result.partsByRegion.jp.filter(row => row[0] !== e.lineID);
  result.partsByRegion.jp.splice(first, 0, ...rows);
  return result;
}

export function candidateGeoJSON(pkg, e) {
  const line = pkg.lines[e.baseline.packageIndex], first = line.displayIntervalCoordinates[e.intervals[0]];
  const second = line.displayIntervalCoordinates[e.intervals[1]];
  return { type: 'FeatureCollection', features: [{ type: 'Feature', properties: {
    lineID: e.lineID, stationID: e.stationID, intervalIndices: e.intervals,
    displayAnchor: e.displayAnchor, status: e.status,
  }, geometry: { type: 'LineString', coordinates: [...first, ...second.slice(1)] } }] };
}

function prepare(args) {
  const candidateAt = args.indexOf('--candidate-root');
  const candidate = candidateAt === 0 && args.length === 2, apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-dosan-tsubojiri-station-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  const paths = { package: PACKAGE, lanes: LANES, evidence: EVIDENCE, shingai: SHINGAI_EVIDENCE,
    ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence'), shingai = load('shingai');
  if (apply) {
    assert.equal(shingai.status, 'accepted-display-cartography',
      'Shingai candidate requires accepted native comparison before composed apply');
    assert.equal(e.status, 'accepted-display-cartography',
      'Tsubojiri candidate requires accepted native comparison before apply');
  }
  const candidateFile = path.join(REPO, e.source.candidatePath);
  const reviewedCandidate = JSON.parse(fs.readFileSync(candidateFile));
  const sources = [{ path: candidateFile, before: fs.readFileSync(candidateFile) }, ...reviewedCandidate.sources.map(source => {
    const file = path.join(REPO, source.path); return { path: file, before: fs.readFileSync(file) };
  })];
  const pkg = repairPackage(load('package'), e, shingai), lanes = repairParts(pkg, load('lanes'), e, shingai);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  return { candidate: candidate ? path.resolve(args[1]) : null, apply, snapshots, sources, e, pkg, lanes, dependencies };
}

function main(args = process.argv.slice(2)) {
  const prepared = prepare(args);
  for (const source of prepared.sources)
    assert(fs.readFileSync(source.path).equals(source.before), 'Reviewed Tsubojiri source changed during preparation');
  const outputs = { package: JSON.stringify(prepared.pkg), lanes: JSON.stringify(prepared.lanes) + '\n',
    ...Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key =>
      [key, JSON.stringify(prepared.dependencies[key], null, 2) + '\n'])) };
  if (prepared.candidate) {
    assert(prepared.candidate.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
    fs.mkdirSync(prepared.candidate, { recursive: true });
    for (const [key, contents] of Object.entries(outputs))
      fs.writeFileSync(path.join(prepared.candidate, path.basename(prepared.snapshots[key].path)), contents);
    fs.writeFileSync(path.join(prepared.candidate, 'tsubojiri-intervals-6-7.geojson'),
      JSON.stringify(candidateGeoJSON(prepared.pkg, prepared.e), null, 2) + '\n');
  } else {
    const writes = Object.entries(outputs).filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path, before: prepared.snapshots[key].before,
        after: contents, temporary: `${prepared.snapshots[key].path}.tsubojiri-${process.pid}.tmp` }));
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
