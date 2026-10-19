#!/usr/bin/env node
// Display-only correction for the complete Keikyu Airport Line. Physical railway data stays fixed.
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
const EVIDENCE = 'scripts/railway/keikyu-airport-terminal-display-evidence.json';
const OVERRIDE = 'keikyu-airport-complete-display';
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
  assert.equal(sha256(fs.readFileSync(file)), expected, `Frozen Keikyu airport artifact changed: ${relative}`);
  return file;
}

export function loadReviewedCandidate(e = read(EVIDENCE)) {
  assert.equal(e.format, 'jtm-keikyu-airport-complete-display-v1');
  assert(['candidate-only', e.policy.acceptanceGate].includes(e.status), 'Unknown Keikyu airport review status');
  assert.deepEqual([e.lineID, e.packageIndex, e.intervalIndexes],
    ['jp-京浜急行電鉄-空港線', 86, [0, 1, 2, 3, 4, 5]]);
  const manifestFile = artifact(e.candidate.manifest, e.candidate.manifestSha256);
  const manifest = JSON.parse(fs.readFileSync(manifestFile));
  assert.deepEqual([manifest.format, manifest.rawFrameCount,
    manifest.finalReprojectionFrameCount],
  ['jtm-keikyu-airport-complete-display-candidate-manifest-v5', 27, 27]);
  for (const item of manifest.files) {
    const file = path.join(path.dirname(manifestFile), item.path);
    assert.equal(sha256(fs.readFileSync(file)), item.sha256,
      `Frozen Keikyu airport artifact changed: ${item.path}`);
  }
  const candidate = JSON.parse(fs.readFileSync(artifact(e.candidate.candidateFile,
    e.candidate.candidateSha256)));
  assert.deepEqual([candidate.format, candidate.status, candidate.lineID],
    ['jtm-keikyu-airport-complete-display-candidate-v5',
      'candidate-only-ready-for-root-native-main-review', e.lineID]);
  assert.deepEqual(candidate.sourceIntervals.map(item => item.length), e.candidate.sourcePointCounts);
  assert.deepEqual(candidate.coordinates.map(item => item.length), e.candidate.candidatePointCounts);
  assert.deepEqual(candidate.displayStationCoordinates, e.candidate.stationAliases);
  assert.deepEqual(candidate.manualFramePixels, e.candidate.manualFramePixels);
  assert.match(candidate.rejectedCompetitor, /Tokyo Monorail/);
  assert.match(candidate.fitEvidence.interval1Gap, /building\/frame-edge hump/);
  assert.match(candidate.fitEvidence.interval5, /single labelled Keikyu/);
  for (const intervalIndex of e.intervalIndexes) {
    const interval = JSON.parse(fs.readFileSync(artifact(e.candidate.intervalFiles[intervalIndex],
      e.candidate.intervalSha256[intervalIndex])));
    assert.deepEqual(interval.geometry.coordinates, candidate.coordinates[intervalIndex]);
    const next = candidate.coordinates[intervalIndex + 1];
    if (next) assert.deepEqual(candidate.coordinates[intervalIndex].at(-1), next[0]);
    for (let index = 1; index < candidate.coordinates[intervalIndex].length; index += 1)
      assert(distance(candidate.coordinates[intervalIndex][index - 1],
        candidate.coordinates[intervalIndex][index]) >= e.candidate.minimumEdgeMetres,
      `Degenerate Keikyu airport candidate edge: ${intervalIndex}/${index}`);
  }
  for (const [stationID, intervalIndex] of Object.entries(e.candidate.stationEndIntervals))
    assert.deepEqual(candidate.coordinates[intervalIndex].at(-1),
      candidate.displayStationCoordinates[stationID]);
  assert.deepEqual(candidate.coordinates[0][0], candidate.sourceIntervals[0][0]);
  return candidate;
}

function baseLine(current, e) {
  const base = structuredClone(current);
  delete base.displayIntervalCoordinates;
  delete base.displayStationCoordinates;
  assert.equal(jsonSha256(base), e.baseline.lineSha256,
    'Unreviewed Keikyu airport physical dependency changed');
  return base;
}

function repairedLine(current, candidate, e) {
  const base = baseLine(current, e), physical = network.decodeIntervals(base);
  assert.deepEqual(physical, candidate.sourceIntervals, 'Keikyu airport source intervals changed');
  base.displayIntervalCoordinates = Object.fromEntries(e.intervalIndexes.map(index =>
    [index, structuredClone(candidate.coordinates[index])]));
  base.displayStationCoordinates = Object.fromEntries(Object.entries(
    candidate.displayStationCoordinates).filter(([stationID]) => stationID !== '004331'));
  return base;
}

function metadata(e) {
  return { reviewedAt: e.reviewedAt, status: e.status, lineID: e.lineID,
    intervalIndexes: e.intervalIndexes, stationIDs: e.stationIDs,
    candidate: e.candidate, nativeReplay: e.nativeReplay,
    policy: e.policy, physicalTopologyChanged: false,
    script: 'app/scripts/railway/repair-keikyu-airport-terminal-display.mjs',
    evidence: 'app/scripts/railway/keikyu-airport-terminal-display-evidence.json' };
}

export function repairPackage(input, e = read(EVIDENCE)) {
  const candidate = loadReviewedCandidate(e), current = input.lines[e.packageIndex];
  assert.equal(current?.id, e.lineID, 'Keikyu airport package index changed');
  const repaired = repairedLine(current, candidate, e);
  const owned = { displayIntervalCoordinates: current.displayIntervalCoordinates,
    displayStationCoordinates: current.displayStationCoordinates };
  assert((owned.displayIntervalCoordinates == null && owned.displayStationCoordinates == null) ||
    (equal(owned.displayIntervalCoordinates, repaired.displayIntervalCoordinates) &&
      equal(owned.displayStationCoordinates, repaired.displayStationCoordinates)),
  'Unreviewed Keikyu airport display dependency changed');
  assert.deepEqual(repaired.stations, baseLine(current, e).stations);
  assert.deepEqual(repaired.segments, baseLine(current, e).segments);
  assert.deepEqual(network.decodeIntervals(repaired), network.decodeIntervals(baseLine(current, e)));
  const result = structuredClone(input), override = metadata(e);
  result.lines[e.packageIndex] = repaired;
  result.geometrySource ||= {}; result.geometrySource.manualOverrides ||= {};
  if (equal(current, repaired) && result.geometrySource.manualOverrides[OVERRIDE])
    assert.deepEqual(result.geometrySource.manualOverrides[OVERRIDE], override,
      'Accepted Keikyu airport metadata changed');
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
  assert(first >= 0, `Missing Keikyu airport row: ${lineID}`);
  const result = rows.filter(row => row[0] !== lineID);
  result.splice(first, 0, ...replacement);
  return result;
}

export function repairedNativeRow(pkg, e = read(EVIDENCE)) {
  const line = pkg.lines[e.packageIndex], candidate = loadReviewedCandidate(e);
  assert(line && equal(line, repairedLine(line, candidate, e)), 'Keikyu airport package repair missing');
  const rows = partRowsForLine(line, network.displayPartsForLine(line), displayInputs(line), null);
  assert.equal(rows.length, 1, 'Keikyu airport native part count changed');
  const row = rows[0], summary = e.nativeReplay.candidateSummary;
  assert.equal(jsonSha256(row), e.nativeReplay.candidateRowSha256,
    'Keikyu airport native owning replay changed');
  assert.deepEqual({ partCount: rows.length, pointCount: row[4], metres: row[5],
    classification: row[6] }, summary);
  return row;
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  const row = repairedNativeRow(pkg, e), current = input.partsByRegion.jp.filter(item => item[0] === e.lineID);
  assert.equal(current.length, 1, 'Keikyu airport native part count changed');
  assert([e.baseline.nativeRowSha256, e.nativeReplay.candidateRowSha256]
    .includes(jsonSha256(current[0])), 'Unreviewed Keikyu airport native dependency changed');
  assert.deepEqual(measuredReferences(input, e.lineID), e.baseline.measuredReferences,
    'Unreviewed Keikyu airport measured reference');
  const result = structuredClone(input);
  result.partsByRegion.jp = replaceRows(result.partsByRegion.jp, e.lineID, [row]);
  assert.deepEqual(measuredReferences(result, e.lineID), e.nativeReplay.candidateMeasuredReferences);
  return result;
}

export function candidateGeoJSON(pkg, e = read(EVIDENCE)) {
  return { type: 'FeatureCollection', features: e.intervalIndexes.map(intervalIndex => ({
    type: 'Feature', properties: { lineID: e.lineID, referenceLineID: e.lineID,
      intervalIndex, referenceIntervalIndex: intervalIndex, status: e.status,
      representation: e.policy.representation }, geometry: { type: 'LineString',
      coordinates: pkg.lines[e.packageIndex].displayIntervalCoordinates[intervalIndex] } })) };
}

export function assertApplyAccepted(e) {
  assert.equal(e.status, e.policy.acceptanceGate,
    'Keikyu airport candidate requires accepted native and Main comparison before apply');
}

function prepare(args) {
  const candidate = args[0] === '--candidate-root' && args.length === 2, apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-keikyu-airport-terminal-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
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
    for (const feature of candidateGeoJSON(prepared.pkg, prepared.e).features)
      fs.writeFileSync(path.join(prepared.candidate,
        `keikyu-airport-interval-${feature.properties.intervalIndex}.geojson`),
      JSON.stringify(feature, null, 2) + '\n');
  } else {
    const writes = Object.entries(outputs).filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path,
        before: prepared.snapshots[key].before, after: contents,
        temporary: `${prepared.snapshots[key].path}.keikyu-airport-${process.pid}.tmp` }));
    applyPreparedWrites(writes, [...Object.values(prepared.snapshots), ...prepared.sources]);
  }
  const line = prepared.pkg.lines[prepared.e.packageIndex];
  const row = prepared.lanes.partsByRegion.jp.find(item => item[0] === prepared.e.lineID);
  console.log(JSON.stringify({ mode: prepared.apply ? 'applied' : 'candidate', status: prepared.e.status,
    lineID: prepared.e.lineID, intervalIndexes: prepared.e.intervalIndexes,
    displayPointCounts: prepared.e.intervalIndexes.map(index => line.displayIntervalCoordinates[index].length),
    nativePointCount: row[4], nativeMetres: row[5], physicalTopologyChanged: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
