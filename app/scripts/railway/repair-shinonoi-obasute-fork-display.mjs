#!/usr/bin/env node
// Display-only Obasute fork alignment. The registered station seam and physical switchback stay unchanged.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS }
  from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const EVIDENCE = 'scripts/railway/shinonoi-obasute-fork-display-evidence.json';
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

function coordinateForPixel(source, pixel) {
  const world = 268435456;
  const x = source.mapRect.x + pixel[0] / source.width * source.mapRect.width;
  const y = source.mapRect.y + pixel[1] / source.height * source.mapRect.height;
  return [x / world * 360 - 180,
    Math.atan(Math.sinh(Math.PI * (1 - 2 * y / world))) * 180 / Math.PI];
}

function sourceFiles(candidate) {
  const files = [];
  for (const source of Object.values(candidate.sources)) {
    for (const [key, relative] of Object.entries(source)) {
      if (!key.endsWith('Path')) continue;
      const digestKey = `${key.slice(0, -4)}Sha256`;
      assert.equal(typeof source[digestKey], 'string', `Missing digest for ${relative}`);
      files.push({ path: path.join(REPO, relative), relative, sha256: source[digestKey] });
    }
  }
  return files;
}

function loadReviewedCandidate(e) {
  assert.equal(e.format, 'jtm-shinonoi-obasute-fork-display-v1');
  assert(['candidate-only', 'accepted-display-cartography'].includes(e.status),
    'Unknown Obasute review status');
  assert.deepEqual([e.lineID, e.stationID, e.stationIndex, e.intervals, e.nativeParts],
    ['jp-東日本旅客鉄道-篠ノ井線', '002178', 12, [11, 12], [0, 1]]);
  const sourcePath = key => path.join(REPO, e.source[key]);
  for (const [pathKey, digestKey] of [['candidatePath', 'candidateSha256'],
    ['intervalsPath', 'intervalsSha256'], ['interval11Path', 'interval11Sha256'],
    ['interval12Path', 'interval12Sha256']])
    assert.equal(sha256(sourcePath(pathKey)), e.source[digestKey], `Frozen Obasute ${pathKey} changed`);
  const candidate = JSON.parse(fs.readFileSync(sourcePath('candidatePath')));
  assert.deepEqual([candidate.format, candidate.status, candidate.lineID, candidate.packageIndex,
    candidate.station.id, candidate.station.preserved, candidate.intervals],
  ['jtm-shinonoi-obasute-display-candidate-v1',
    'candidate-only; requires native full interval 11/12 comparison; not production truth',
    e.lineID, e.baseline.packageIndex, e.stationID, true, e.intervals]);
  assert.deepEqual(candidate.station.registeredCoordinate, e.stationCoordinate);
  assert.deepEqual(candidate.junction.candidate, e.junction.displayFork);
  assert.deepEqual(candidate.guard.coordinate, e.guard.coordinate);
  assert.equal(candidate.guard.suffixPreservedFromIndex, e.guard.suffixPreservedFromIndex);
  for (const source of sourceFiles(candidate))
    assert.equal(sha256(source.path), source.sha256, `Reviewed Obasute source changed: ${source.relative}`);
  const interval11 = JSON.parse(fs.readFileSync(sourcePath('interval11Path')));
  const interval12 = JSON.parse(fs.readFileSync(sourcePath('interval12Path')));
  const intervals = JSON.parse(fs.readFileSync(sourcePath('intervalsPath')));
  assert.deepEqual(interval11.geometry.coordinates, candidate.candidate.interval11);
  assert.deepEqual(interval12.geometry.coordinates, candidate.candidate.interval12);
  assert.deepEqual(intervals.features.map(feature => feature.geometry.coordinates),
    [candidate.candidate.interval11, candidate.candidate.interval12]);
  const physical = network.decodeIntervals(e.baseline.line);
  assert.equal(physical[11].length, 100); assert.equal(physical[12].length, 155);
  assert.equal(candidate.candidate.interval11.length, 100);
  assert.equal(candidate.candidate.interval12.length, 184);
  assert.deepEqual(candidate.candidate.interval11.slice(0, 94), physical[11].slice(0, 94));
  assert.deepEqual(candidate.candidate.interval11.slice(95), physical[11].slice(95));
  assert.deepEqual(candidate.candidate.interval12.slice(0, 5), physical[12].slice(0, 5));
  assert.deepEqual(candidate.candidate.interval12.slice(e.guard.candidateIndex),
    physical[12].slice(e.guard.suffixPreservedFromIndex));
  assert.deepEqual(candidate.candidate.interval11[94], e.junction.displayFork);
  assert.deepEqual(candidate.candidate.interval12[5], e.junction.displayFork);
  assert.deepEqual(candidate.candidate.interval11.at(-1), e.stationCoordinate);
  assert.deepEqual(candidate.candidate.interval12[0], e.stationCoordinate);
  assert.deepEqual(physical[12][e.guard.oldIndex], e.guard.coordinate);
  assert.deepEqual(candidate.candidate.interval12[e.guard.candidateIndex], e.guard.coordinate);
  const projectedCoordinate = coordinateForPixel(candidate.sources.fold, candidate.junction.projectedPixel);
  assert(distance(projectedCoordinate, e.junction.displayFork) < 1e-6,
    'Reviewed projected fork pixel changed');
  const appleCoordinate = coordinateForPixel(candidate.sources.fold, candidate.junction.sourcePixelApprox);
  const edge = physical[12].slice(4, 6), projection = projectPointOntoPolyline(appleCoordinate, edge);
  assert.equal(projection.insertIndex, 0);
  assert(distance(projection.point, e.junction.displayFork) < .05,
    'Reviewed representative fork projection changed');
  assert(Math.abs(projection.distanceM - e.junction.projectionResidualMetres) < .05);
  assert(projection.distanceM < e.junction.maximumProjectionResidualMetres);
  return candidate;
}

function repairedLine(e) {
  const candidate = loadReviewedCandidate(e), line = structuredClone(e.baseline.line);
  assert(!line.displayStationCoordinates, 'Unreviewed Shinonoi station alias already exists');
  assert(!line.displayIntervalCoordinates, 'Unreviewed Shinonoi interval alias already exists');
  line.displayIntervalCoordinates = {
    11: structuredClone(candidate.candidate.interval11),
    12: structuredClone(candidate.candidate.interval12),
  };
  return line;
}

function overrideMetadata(e) {
  return {
    reviewedAt: e.reviewedAt, status: e.status, lineID: e.lineID, stationID: e.stationID,
    intervals: e.intervals, nativeParts: e.nativeParts, stationCoordinate: e.stationCoordinate,
    junction: e.junction, guard: e.guard, source: e.source, policy: e.policy,
    script: 'app/scripts/railway/repair-shinonoi-obasute-fork-display.mjs',
    evidence: 'app/scripts/railway/shinonoi-obasute-fork-display-evidence.json',
    physicalTopologyChanged: false,
  };
}

export function repairPackage(input, e = read(EVIDENCE)) {
  const current = input.lines[e.baseline.packageIndex], repaired = repairedLine(e);
  assert(current?.id === e.lineID && (equal(current, e.baseline.line) || equal(current, repaired)),
    'Unreviewed Shinonoi dependency changed');
  assert.deepEqual(repaired.stations, e.baseline.line.stations);
  assert.deepEqual(repaired.segments, e.baseline.line.segments);
  assert.deepEqual(network.decodeIntervals(repaired), network.decodeIntervals(e.baseline.line));
  assert.equal(repaired.displayStationCoordinates, undefined);
  const beforeParts = network.displayPartsForLine(e.baseline.line);
  const afterParts = network.displayPartsForLine(repaired);
  assert.equal(beforeParts.length, 2); assert.equal(afterParts.length, 2);
  assert(afterParts.every((part, index) => !equal(part, beforeParts[index])),
    'Both Obasute native parts must be recomputed');
  const metadata = overrideMetadata(e);
  if (equal(current, repaired) && input.geometrySource?.manualOverrides?.['shinonoi-obasute-fork-display'])
    assert.deepEqual(input.geometrySource.manualOverrides['shinonoi-obasute-fork-display'], metadata,
      'Accepted Obasute dependency metadata changed');
  const pkg = structuredClone(input);
  pkg.lines[e.baseline.packageIndex] = repaired;
  pkg.geometrySource ||= {}; pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['shinonoi-obasute-fork-display'] = metadata;
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
  return Object.fromEntries(Object.keys(e.baseline.measuredReferences).map(key => {
    const region = input[key]?.jp;
    const rows = Array.isArray(region)
      ? region.filter(row => JSON.stringify(row).includes(e.lineID))
      : Object.entries(region || {}).filter(([name, value]) =>
        name.includes(e.lineID) || JSON.stringify(value).includes(e.lineID));
    return [key, rows];
  }));
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  const line = pkg.lines[e.baseline.packageIndex];
  assert(line && equal(line, repairedLine(e)), 'Obasute package repair missing');
  assert.deepEqual(references(input, e), e.baseline.measuredReferences,
    'Unreviewed Shinonoi measured reference');
  const rows = partRowsForLine(line, network.displayPartsForLine(line), displayInputs(line), null);
  assert.equal(rows.length, 2);
  for (const [index, row] of rows.entries()) {
    const baseline = e.baseline.nativeRows[index];
    assert.deepEqual(row.slice(0, 4), baseline.slice(0, 4), 'Obasute native part identity changed');
    assert.equal(row[4], row[7].length, 'Obasute native point count does not describe its coordinates');
    assert.equal(row[6], baseline[6], 'Obasute native part classification changed');
    assert.deepEqual(row[8], baseline[8], 'Obasute native anchors changed');
  }
  assert(rows.every((row, index) => !equal(row, e.baseline.nativeRows[index])),
    'Both Obasute native rows must change');
  const current = input.partsByRegion.jp.filter(row => row[0] === e.lineID);
  assert(equal(current, e.baseline.nativeRows) || equal(current, rows), 'Shinonoi native rows changed');
  const first = input.partsByRegion.jp.findIndex(row => row[0] === e.lineID);
  assert(first >= 0);
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.filter(row => row[0] !== e.lineID);
  result.partsByRegion.jp.splice(first, 0, ...rows);
  assert.deepEqual(references(result, e), e.baseline.measuredReferences,
    'Obasute repair changed a measured consumer');
  return result;
}

export function candidateGeoJSON(pkg, e) {
  const line = pkg.lines[e.baseline.packageIndex], first = line.displayIntervalCoordinates[11];
  const second = line.displayIntervalCoordinates[12];
  return { type: 'FeatureCollection', features: [{ type: 'Feature', properties: {
    lineID: e.lineID, referenceLineID: e.lineID, stationID: e.stationID,
    intervalIndices: e.intervals, displayFork: e.junction.displayFork,
    representation: 'accepted Apple cartographic display; not surveyed rail truth', status: e.status,
  }, geometry: { type: 'LineString', coordinates: [...first, ...second.slice(1)] } }] };
}

function prepare(args) {
  const candidate = args[0] === '--candidate-root' && args.length === 2, apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-shinonoi-obasute-fork-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  const paths = { package: PACKAGE, lanes: LANES, evidence: EVIDENCE, ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  if (apply) assert.equal(e.status, 'accepted-display-cartography',
    'Obasute candidate requires accepted native comparison before apply');
  const reviewedCandidate = loadReviewedCandidate(e);
  const reviewedPaths = [e.source.candidatePath, e.source.intervalsPath,
    e.source.interval11Path, e.source.interval12Path,
    ...sourceFiles(reviewedCandidate).map(source => source.relative)];
  const sources = reviewedPaths.map(relative => {
    const file = path.join(REPO, relative); return { path: file, before: fs.readFileSync(file) };
  });
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  return { candidate: candidate ? path.resolve(args[1]) : null, apply, snapshots, sources, e, pkg, lanes, dependencies };
}

function main(args = process.argv.slice(2)) {
  const prepared = prepare(args);
  for (const source of prepared.sources)
    assert(fs.readFileSync(source.path).equals(source.before), 'Reviewed Obasute source changed during preparation');
  const outputs = { package: JSON.stringify(prepared.pkg), lanes: JSON.stringify(prepared.lanes) + '\n',
    ...Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key =>
      [key, JSON.stringify(prepared.dependencies[key], null, 2) + '\n'])) };
  if (prepared.candidate) {
    assert(prepared.candidate.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
    fs.mkdirSync(prepared.candidate, { recursive: true });
    for (const [key, contents] of Object.entries(outputs))
      fs.writeFileSync(path.join(prepared.candidate, path.basename(prepared.snapshots[key].path)), contents);
    fs.writeFileSync(path.join(prepared.candidate, 'shinonoi-obasute-intervals-11-12.geojson'),
      JSON.stringify(candidateGeoJSON(prepared.pkg, prepared.e), null, 2) + '\n');
  } else {
    const writes = Object.entries(outputs).filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path, before: prepared.snapshots[key].before,
        after: contents, temporary: `${prepared.snapshots[key].path}.obasute-${process.pid}.tmp` }));
    applyPreparedWrites(writes, Object.values(prepared.snapshots));
  }
  const line = prepared.pkg.lines[prepared.e.baseline.packageIndex];
  const parts = prepared.lanes.partsByRegion.jp.filter(row => row[0] === prepared.e.lineID);
  console.log(JSON.stringify({ mode: prepared.apply ? 'applied' : 'candidate', lineID: prepared.e.lineID,
    stationID: prepared.e.stationID, displayFork: prepared.e.junction.displayFork,
    intervals: prepared.e.intervals.map(index => ({ index, pointCount: line.displayIntervalCoordinates[index].length })),
    nativeParts: parts.map(row => ({ partIndex: row[1], pointCount: row[4], metres: row[5] })),
    physicalTopologyChanged: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
