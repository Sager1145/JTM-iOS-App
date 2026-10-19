#!/usr/bin/env node
// Display-only correction for Nishi-Karatsu to Karatsu. Physical railway data stays fixed.
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
const PACKAGE = 'public/rail/jp-2025.json';
const LANES = 'public/rail/display-lanes.json';
const EVIDENCE = 'scripts/railway/karatsu-nishi-display-evidence.json';
const OVERRIDE = 'karatsu-nishi-display';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const jsonSha256 = value => sha256(JSON.stringify(value));

function distance(a, b) {
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
    (b[1] - a[1]) * 111320);
}

function artifact(relative, expected) {
  const file = path.join(REPO, relative);
  assert.equal(sha256(fs.readFileSync(file)), expected, `Frozen Karatsu artifact changed: ${relative}`);
  return file;
}

export function loadReviewedCandidate(e = read(EVIDENCE)) {
  assert.equal(e.format, 'jtm-karatsu-nishi-display-v1');
  assert(['candidate-only', e.policy.acceptanceGate].includes(e.status), 'Unknown Karatsu review status');
  assert.deepEqual([e.lineID, e.packageIndex, e.intervalIndex],
    ['jp-九州旅客鉄道-唐津線', 50, 0]);
  const manifestFile = artifact(e.candidate.manifest, e.candidate.manifestSha256);
  const manifest = JSON.parse(fs.readFileSync(manifestFile));
  assert.deepEqual([manifest.format, manifest.baselineFrameCount, manifest.rawFrameCount,
    manifest.finalReprojectionFrameCount],
  ['jtm-karatsu-nishi-display-candidate-manifest-v1', e.candidate.baselineFrameCount,
    e.candidate.rawFrameCount, e.candidate.finalReprojectionFrameCount]);
  for (const item of manifest.files) {
    const file = path.join(path.dirname(manifestFile), item.path);
    assert.equal(sha256(fs.readFileSync(file)), item.sha256,
      `Frozen Karatsu artifact changed: ${item.path}`);
  }
  const candidate = JSON.parse(fs.readFileSync(artifact(e.candidate.candidateFile,
    e.candidate.candidateSha256)));
  const interval = JSON.parse(fs.readFileSync(artifact(e.candidate.intervalFile,
    e.candidate.intervalSha256)));
  assert.deepEqual([candidate.format, candidate.status, candidate.lineID, candidate.intervalIndex],
    ['jtm-karatsu-nishi-display-candidate-v1',
      'candidate-only-ready-for-root-native-main-review', e.lineID, e.intervalIndex]);
  assert.deepEqual(interval.geometry.coordinates, candidate.coordinates);
  assert.deepEqual(candidate.displayStationCoordinates, e.candidate.stationAliases);
  assert.deepEqual([candidate.sourceCoordinates.length, candidate.coordinates.length],
    [e.candidate.sourcePointCount, e.candidate.candidatePointCount]);
  for (let index = 1; index < candidate.coordinates.length; index += 1)
    assert(distance(candidate.coordinates[index - 1], candidate.coordinates[index]) >=
      e.candidate.minimumEdgeMetres, `Degenerate Karatsu candidate edge: ${index}`);
  const guard = e.candidate.guard;
  assert.deepEqual(candidate.sourceCoordinates[guard.sourceIndex], guard.coordinate);
  assert.deepEqual(candidate.coordinates[guard.candidateIndex], guard.coordinate);
  assert.deepEqual(candidate.coordinates.slice(guard.candidateIndex),
    candidate.sourceCoordinates.slice(guard.sourceIndex), 'Karatsu guard/suffix changed');
  assert.deepEqual(candidate.coordinates[0], e.candidate.stationAliases['009270']);
  assert.deepEqual(candidate.coordinates.at(-1), e.candidate.stationAliases['009278']);
  return candidate;
}

function baseLine(current, e) {
  const base = structuredClone(current);
  delete base.displayIntervalCoordinates;
  delete base.displayStationCoordinates;
  assert.equal(jsonSha256(base), e.baseline.lineSha256,
    'Unreviewed Karatsu physical dependency changed');
  return base;
}

function repairedLine(current, candidate, e) {
  const base = baseLine(current, e), physical = network.decodeIntervals(base);
  assert.deepEqual(physical[e.intervalIndex], candidate.sourceCoordinates,
    'Karatsu interval 0 source changed');
  base.displayIntervalCoordinates = { [e.intervalIndex]: structuredClone(candidate.coordinates) };
  base.displayStationCoordinates = structuredClone(candidate.displayStationCoordinates);
  return base;
}

function metadata(e) {
  return { reviewedAt: e.reviewedAt, status: e.status, lineID: e.lineID,
    intervalIndex: e.intervalIndex, candidate: e.candidate, nativeReplay: e.nativeReplay,
    policy: e.policy, physicalTopologyChanged: false,
    script: 'app/scripts/railway/repair-karatsu-nishi-display.mjs',
    evidence: 'app/scripts/railway/karatsu-nishi-display-evidence.json' };
}

export function repairPackage(input, e = read(EVIDENCE)) {
  const candidate = loadReviewedCandidate(e), current = input.lines[e.packageIndex];
  assert.equal(current?.id, e.lineID, 'Karatsu package index changed');
  const repaired = repairedLine(current, candidate, e);
  const owned = { displayIntervalCoordinates: current.displayIntervalCoordinates,
    displayStationCoordinates: current.displayStationCoordinates };
  assert((owned.displayIntervalCoordinates == null && owned.displayStationCoordinates == null) ||
    (equal(owned.displayIntervalCoordinates, repaired.displayIntervalCoordinates) &&
      equal(owned.displayStationCoordinates, repaired.displayStationCoordinates)),
  'Unreviewed Karatsu display dependency changed');
  assert.deepEqual(repaired.stations, baseLine(current, e).stations);
  assert.deepEqual(repaired.segments, baseLine(current, e).segments);
  assert.deepEqual(network.decodeIntervals(repaired), network.decodeIntervals(baseLine(current, e)));
  const result = structuredClone(input), override = metadata(e);
  result.lines[e.packageIndex] = repaired;
  result.geometrySource ||= {}; result.geometrySource.manualOverrides ||= {};
  if (equal(current, repaired) && result.geometrySource.manualOverrides[OVERRIDE])
    assert.deepEqual(result.geometrySource.manualOverrides[OVERRIDE], override,
      'Accepted Karatsu metadata changed');
  result.geometrySource.manualOverrides[OVERRIDE] = override;
  return result;
}

function displayInputs(line) {
  const displayed = { ...line,
    stations: line.stations.map(station => line.displayStationCoordinates?.[station[0]]
      ? [...station.slice(0, 2), ...line.displayStationCoordinates[station[0]], ...station.slice(4)] : station),
    segments: line.segments.map((segment, index) => line.displayIntervalCoordinates?.[index]
      ? [segment[0], 0, line.displayIntervalCoordinates[index]] : segment) };
  return { stations: displayed.stations, intervals: network.decodeIntervals(displayed) };
}

function measuredReferences(input, lineID) {
  const result = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === 'partsByRegion') continue;
    const region = value?.jp;
    if (Array.isArray(region)) {
      const rows = region.filter(row => JSON.stringify(row).includes(lineID));
      if (rows.length) result[key] = rows;
    } else if (region && typeof region === 'object') {
      const rows = Object.fromEntries(Object.entries(region).filter(([name, row]) =>
        name === lineID || JSON.stringify(row).includes(lineID)));
      if (Object.keys(rows).length) result[key] = rows;
    }
  }
  return result;
}

function replaceRows(rows, lineID, replacement) {
  const first = rows.findIndex(row => row[0] === lineID);
  assert(first >= 0, `Missing Karatsu row: ${lineID}`);
  const result = rows.filter(row => row[0] !== lineID);
  result.splice(first, 0, ...replacement);
  return result;
}

export function repairedNativeRow(pkg, e = read(EVIDENCE)) {
  const line = pkg.lines[e.packageIndex], candidate = loadReviewedCandidate(e);
  assert(line && equal(line, repairedLine(line, candidate, e)), 'Karatsu package repair missing');
  const rows = partRowsForLine(line, network.displayPartsForLine(line), displayInputs(line), null);
  assert.equal(rows.length, 1, 'Karatsu native part count changed');
  const row = rows[0], summary = e.nativeReplay.candidateSummary;
  assert.equal(jsonSha256(row), e.nativeReplay.candidateRowSha256,
    'Karatsu native owning replay changed');
  assert.deepEqual({ partCount: rows.length, pointCount: row[4], metres: row[5],
    classification: row[6] }, summary);
  return row;
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  const row = repairedNativeRow(pkg, e), current = input.partsByRegion.jp.filter(item => item[0] === e.lineID);
  assert.equal(current.length, 1, 'Karatsu native part count changed');
  assert([e.baseline.nativeRowSha256, e.nativeReplay.candidateRowSha256]
    .includes(jsonSha256(current[0])), 'Unreviewed Karatsu native dependency changed');
  const references = measuredReferences(input, e.lineID);
  assert(equal(references, e.baseline.measuredReferences) ||
    equal(references, e.nativeReplay.candidateMeasuredReferences),
  'Unreviewed Karatsu measured reference');
  const result = structuredClone(input);
  result.partsByRegion.jp = replaceRows(result.partsByRegion.jp, e.lineID, [row]);
  result.byRegion.jp = replaceRows(result.byRegion.jp, e.lineID,
    e.nativeReplay.candidateMeasuredReferences.byRegion);
  assert.deepEqual(measuredReferences(result, e.lineID), e.nativeReplay.candidateMeasuredReferences);
  return result;
}

export function candidateGeoJSON(pkg, e = read(EVIDENCE)) {
  return { type: 'Feature', properties: { lineID: e.lineID, referenceLineID: e.lineID,
    intervalIndex: e.intervalIndex, referenceIntervalIndex: e.intervalIndex, status: e.status,
    representation: e.policy.representation }, geometry: { type: 'LineString',
    coordinates: pkg.lines[e.packageIndex].displayIntervalCoordinates[e.intervalIndex] } };
}

export function assertApplyAccepted(e) {
  assert.equal(e.status, e.policy.acceptanceGate,
    'Karatsu candidate requires accepted native and Main comparison before apply');
}

function prepare(args) {
  const candidate = args[0] === '--candidate-root' && args.length === 2, apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-karatsu-nishi-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  const paths = { package: PACKAGE, lanes: LANES, evidence: EVIDENCE, ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  if (apply) assertApplyAccepted(e);
  const reviewed = loadReviewedCandidate(e), manifestPath = path.join(REPO, e.candidate.manifest);
  const sourceDirectory = path.dirname(manifestPath);
  const sources = [{ path: manifestPath, before: fs.readFileSync(manifestPath) },
    ...JSON.parse(fs.readFileSync(manifestPath)).files.map(item => {
      const file = path.join(sourceDirectory, item.path); return { path: file, before: fs.readFileSync(file) };
    })];
  assert(reviewed);
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  return { candidate: candidate ? path.resolve(args[1]) : null, apply, snapshots, sources,
    e, pkg, lanes, dependencies };
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
    fs.writeFileSync(path.join(prepared.candidate, 'karatsu-nishi-interval-0.geojson'),
      JSON.stringify(candidateGeoJSON(prepared.pkg, prepared.e), null, 2) + '\n');
  } else {
    const writes = Object.entries(outputs).filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path,
        before: prepared.snapshots[key].before, after: contents,
        temporary: `${prepared.snapshots[key].path}.karatsu-nishi-${process.pid}.tmp` }));
    applyPreparedWrites(writes, [...Object.values(prepared.snapshots), ...prepared.sources]);
  }
  const line = prepared.pkg.lines[prepared.e.packageIndex];
  const row = prepared.lanes.partsByRegion.jp.find(item => item[0] === prepared.e.lineID);
  console.log(JSON.stringify({ mode: prepared.apply ? 'applied' : 'candidate', status: prepared.e.status,
    lineID: prepared.e.lineID, intervalIndex: prepared.e.intervalIndex,
    displayPointCount: line.displayIntervalCoordinates[prepared.e.intervalIndex].length,
    nativePointCount: row[4], nativeMetres: row[5], physicalTopologyChanged: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
