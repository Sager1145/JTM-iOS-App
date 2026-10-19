#!/usr/bin/env node
// Display-only correction for the west approach to Suzumeda. Physical and branch geometry stay fixed.
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
const EVIDENCE = 'scripts/railway/onoda-suzumeda-west-curve-display-evidence.json';
const FOLLOW_EVIDENCE = 'scripts/railway/onoda-suzumeda-follow-evidence.json';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function artifactPath(e, name) {
  const item = e.candidate.artifacts.find(row => path.basename(row.path) === name);
  assert(item, `Missing frozen Onoda artifact: ${name}`);
  const file = path.join(REPO, item.path);
  assert.equal(sha256(file), item.sha256, `Frozen Onoda artifact changed: ${item.path}`);
  return file;
}
const artifact = (e, name) => JSON.parse(fs.readFileSync(artifactPath(e, name)));

function baselineLine(e, id) {
  return e.baseline.followEvidence.packageLines.find(item => item.line.id === id);
}

export function loadReviewedCandidate(e = read(EVIDENCE)) {
  assert.equal(e.format, 'jtm-onoda-suzumeda-west-curve-display-v1');
  assert(['candidate-only', e.policy.acceptanceGate].includes(e.status), 'Unknown Onoda curve review status');
  assert.deepEqual([e.lineID, e.branchLineID, e.intervalIndex],
    ['jp-西日本旅客鉄道-小野田線', 'jp-西日本旅客鉄道-小野田線-2', 4]);
  assert.equal(crypto.createHash('sha256').update(`${JSON.stringify(e.baseline.followEvidence, null, 2)}\n`).digest('hex'),
    e.baseline.followEvidenceSha256, 'Frozen pre-curve Onoda follow evidence changed');
  const candidate = artifact(e, 'candidate.json');
  const collection = artifact(e, 'candidate.geojson');
  const interval = artifact(e, 'interval-4.geojson');
  // The reviewed images are immutable evidence even though they are not parsed.
  for (const name of ['frame-1-reprojection.png', 'frame-2-reprojection.png']) artifactPath(e, name);
  assert.deepEqual([candidate.format, candidate.status, candidate.lineID, candidate.intervalIndex],
    ['jtm-onoda-suzumeda-west-curve-candidate-v1', 'candidate-only', e.lineID, e.intervalIndex]);
  for (const source of candidate.sources)
    assert.equal(sha256(path.join(REPO, source.path)), source.sha256,
      `Reviewed Onoda extraction changed: ${source.path}`);
  const source = collection.features.find(feature => feature.properties.role === 'source').geometry.coordinates;
  const reviewed = collection.features.find(feature => feature.properties.role === 'candidate').geometry.coordinates;
  assert.deepEqual(reviewed, candidate.candidateIntervalCoordinates);
  assert.deepEqual(interval.geometry.coordinates, reviewed);
  assert.deepEqual([source.length, reviewed.length],
    [e.candidate.sourcePointCount, e.candidate.candidatePointCount]);
  const base = baselineLine(e, e.lineID).line;
  const physical = network.decodeIntervals(base)[e.intervalIndex];
  assert.deepEqual(source, physical);
  const guardIndex = e.candidate.guard.sourceIndex;
  assert.deepEqual(reviewed.slice(0, guardIndex + 1), physical.slice(0, guardIndex + 1));
  assert.deepEqual(reviewed[guardIndex], e.candidate.guard.coordinate);
  assert.deepEqual(reviewed.at(-1), e.candidate.stationS.coordinate);
  assert.deepEqual(physical.at(-1), e.candidate.stationS.coordinate);
  assert.equal(e.candidate.stationS.preserved, true);
  assert.equal(reviewed.length - physical.length, 44);
  return reviewed;
}

function overrideMetadata(e) {
  return { reviewedAt: e.reviewedAt, status: e.status, lineID: e.lineID,
    branchLineID: e.branchLineID, intervalIndex: e.intervalIndex, candidate: e.candidate,
    nativeReplay: e.nativeReplay, producer: e.producer, policy: e.policy, physicalTopologyChanged: false,
    script: 'app/scripts/railway/repair-onoda-suzumeda-west-curve-display.mjs',
    evidence: 'app/scripts/railway/onoda-suzumeda-west-curve-display-evidence.json' };
}

function repairedBaseLine(e) {
  const line = structuredClone(baselineLine(e, e.lineID).line);
  assert(!line.displayIntervalCoordinates, 'Unreviewed Onoda display interval already exists');
  line.displayIntervalCoordinates = { 4: structuredClone(loadReviewedCandidate(e)) };
  return line;
}

export function repairPackage(input, e = read(EVIDENCE)) {
  const base = baselineLine(e, e.lineID), branch = baselineLine(e, e.branchLineID);
  const repaired = repairedBaseLine(e), current = input.lines[base.index];
  assert(current?.id === e.lineID && (equal(current, base.line) || equal(current, repaired)),
    'Unreviewed Onoda base package dependency changed');
  assert.deepEqual(input.lines[branch.index], branch.line, 'Onoda branch package dependency changed');
  assert.deepEqual(repaired.stations, base.line.stations);
  assert.deepEqual(repaired.segments, base.line.segments);
  assert.deepEqual(network.decodeIntervals(repaired), network.decodeIntervals(base.line));
  const metadata = overrideMetadata(e);
  if (equal(current, repaired) && input.geometrySource?.manualOverrides?.['onoda-suzumeda-west-curve-display'])
    assert.deepEqual(input.geometrySource.manualOverrides['onoda-suzumeda-west-curve-display'], metadata,
      'Accepted Onoda curve metadata changed');
  const result = structuredClone(input);
  result.lines[base.index] = repaired;
  result.geometrySource ||= {}; result.geometrySource.manualOverrides ||= {};
  result.geometrySource.manualOverrides['onoda-suzumeda-west-curve-display'] = metadata;
  return result;
}

function displayInputs(line) {
  const displayed = { ...line, segments: line.segments.map((segment, index) =>
    line.displayIntervalCoordinates?.[index] ? [segment[0], 0, line.displayIntervalCoordinates[index]] : segment) };
  return { stations: displayed.stations, intervals: network.decodeIntervals(displayed) };
}

function references(lanes, e) {
  const ids = [e.lineID, e.branchLineID], contains = value => ids.some(id => JSON.stringify(value).includes(id));
  const result = {};
  for (const [key, value] of Object.entries(lanes)) {
    if (key === 'partsByRegion' || key === 'followsByRegion') continue;
    const region = value?.jp;
    if (Array.isArray(region)) {
      const rows = region.filter(contains); if (rows.length) result[key] = rows;
    } else if (region && typeof region === 'object') {
      const rows = Object.fromEntries(Object.entries(region).filter(([name, row]) => ids.includes(name) || contains(row)));
      if (Object.keys(rows).length) result[key] = rows;
    }
  }
  return result;
}

export function repairedNativeRows(pkg, e = read(EVIDENCE)) {
  const line = pkg.lines[baselineLine(e, e.lineID).index];
  assert(line && equal(line, repairedBaseLine(e)), 'Onoda curve package repair missing');
  return partRowsForLine(line, network.displayPartsForLine(line), displayInputs(line), null);
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  const baseline = e.baseline.followEvidence, rows = repairedNativeRows(pkg, e);
  assert.equal(rows.length, 1);
  const oldBase = baseline.nativeParts.find(row => row[0] === e.lineID);
  const oldBranch = baseline.nativeParts.find(row => row[0] === e.branchLineID);
  const row = rows[0];
  assert.deepEqual(row.slice(0, 4), oldBase.slice(0, 4));
  assert.equal(row[4], row[7].length);
  assert.equal(row[6], oldBase[6]);
  assert.deepEqual(row[8], oldBase[8]);
  assert.equal(row[4], e.nativeReplay.candidatePointCount);
  assert.deepEqual(references(input, e), baseline.otherReferences, 'Onoda measured reference changed');
  assert.deepEqual(input.followsByRegion.jp.filter(item =>
    [item[0], item[4]].some(id => id === e.lineID || id === e.branchLineID)), [],
  'Accepted obsolete Onoda follow returned');
  const currentBase = input.partsByRegion.jp.find(item => item[0] === e.lineID);
  const currentBranch = input.partsByRegion.jp.find(item => item[0] === e.branchLineID);
  assert(equal(currentBase, oldBase) || equal(currentBase, row), 'Onoda base native part changed');
  assert.deepEqual(currentBranch, oldBranch, 'Onoda branch native part changed');
  const result = structuredClone(input), index = result.partsByRegion.jp.findIndex(item => item[0] === e.lineID);
  result.partsByRegion.jp[index] = row;
  assert.deepEqual(references(result, e), baseline.otherReferences);
  return result;
}

export function repairFollowEvidence(pkg, lanes, current, e = read(EVIDENCE)) {
  const baseline = e.baseline.followEvidence, expected = structuredClone(baseline);
  const baseLine = pkg.lines[baselineLine(e, e.lineID).index];
  const baseRow = lanes.partsByRegion.jp.find(row => row[0] === e.lineID);
  expected.packageLines.find(item => item.line.id === e.lineID).line = structuredClone(baseLine);
  expected.nativeParts[expected.nativeParts.findIndex(row => row[0] === e.lineID)] = structuredClone(baseRow);
  assert(equal(current, baseline) || equal(current, expected), 'Onoda follow evidence changed outside coordinated slots');
  // All fields except the two documented base slots remain frozen by construction.
  const stripped = value => { const copy = structuredClone(value);
    copy.packageLines.find(item => item.line.id === e.lineID).line = null;
    copy.nativeParts[copy.nativeParts.findIndex(row => row[0] === e.lineID)] = null; return copy; };
  assert.deepEqual(stripped(expected), stripped(baseline));
  return expected;
}

export function candidateGeoJSON(pkg, e = read(EVIDENCE)) {
  return { type: 'FeatureCollection', features: [{ type: 'Feature', properties: {
    lineID: e.lineID, referenceLineID: e.lineID, intervalIndex: e.intervalIndex,
    status: e.status, representation: e.policy.representation,
  }, geometry: { type: 'LineString', coordinates:
    pkg.lines[baselineLine(e, e.lineID).index].displayIntervalCoordinates[e.intervalIndex] } }] };
}

function prepare(args) {
  const candidate = args[0] === '--candidate-root' && args.length === 2, apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-onoda-suzumeda-west-curve-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  const paths = { package: PACKAGE, lanes: LANES, evidence: EVIDENCE, followEvidence: FOLLOW_EVIDENCE,
    ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  if (apply) assert.equal(e.status, e.policy.acceptanceGate,
    'Onoda curve candidate requires accepted native comparison before apply');
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const followEvidence = repairFollowEvidence(pkg, lanes, load('followEvidence'), e);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  return { candidate: candidate ? path.resolve(args[1]) : null, apply, snapshots, e, pkg, lanes,
    followEvidence, dependencies };
}

function main(args = process.argv.slice(2)) {
  const prepared = prepare(args);
  const outputs = { package: JSON.stringify(prepared.pkg), lanes: JSON.stringify(prepared.lanes) + '\n',
    followEvidence: JSON.stringify(prepared.followEvidence, null, 2) + '\n',
    ...Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key =>
      [key, JSON.stringify(prepared.dependencies[key], null, 2) + '\n'])) };
  if (prepared.candidate) {
    assert(prepared.candidate.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
    fs.mkdirSync(prepared.candidate, { recursive: true });
    for (const [key, contents] of Object.entries(outputs))
      fs.writeFileSync(path.join(prepared.candidate, path.basename(prepared.snapshots[key].path)), contents);
    fs.writeFileSync(path.join(prepared.candidate, 'onoda-suzumeda-west-curve-interval-4.geojson'),
      JSON.stringify(candidateGeoJSON(prepared.pkg, prepared.e), null, 2) + '\n');
  } else {
    const writes = Object.entries(outputs).filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path, before: prepared.snapshots[key].before,
        after: contents, temporary: `${prepared.snapshots[key].path}.onoda-west-curve-${process.pid}.tmp` }));
    applyPreparedWrites(writes, Object.values(prepared.snapshots));
  }
  const line = prepared.pkg.lines[baselineLine(prepared.e, prepared.e.lineID).index];
  const row = prepared.lanes.partsByRegion.jp.find(item => item[0] === prepared.e.lineID);
  console.log(JSON.stringify({ mode: prepared.apply ? 'applied' : 'candidate', status: prepared.e.status,
    lineID: prepared.e.lineID, intervalIndex: prepared.e.intervalIndex,
    displayPointCount: line.displayIntervalCoordinates[prepared.e.intervalIndex].length,
    nativePointCount: row[4], nativeMetres: row[5], physicalTopologyChanged: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
