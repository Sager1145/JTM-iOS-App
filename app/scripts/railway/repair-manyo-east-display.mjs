#!/usr/bin/env node
// Unified display-only correction for both Manyo lines.
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
const EVIDENCE = 'scripts/railway/manyo-east-display-evidence.json';
const OVERRIDE = 'manyo-complete-display';
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
  assert.equal(sha256(fs.readFileSync(file)), expected, `Frozen Manyo artifact changed: ${relative}`);
  return file;
}

function candidateRecords(candidate) {
  return Object.fromEntries(candidate.lines.map(record => [record.lineID, record]));
}

export function loadReviewedCandidate(e = read(EVIDENCE)) {
  assert.equal(e.format, 'jtm-manyo-complete-display-v5');
  assert(['candidate-only', e.policy.acceptanceGate].includes(e.status), 'Unknown Manyo review status');
  assert.deepEqual(e.lineIDs, ['jp-万葉線-新湊港線', 'jp-万葉線-高岡軌道線']);
  const manifestFile = artifact(e.candidate.manifest, e.candidate.manifestSha256);
  const manifest = JSON.parse(fs.readFileSync(manifestFile));
  assert.deepEqual([manifest.format, manifest.rawFrameCount, manifest.finalReprojectionFrameCount,
    manifest.reusedV4ReprojectionFrameCount, manifest.newV5ReprojectionFrameCount],
  ['jtm-manyo-complete-display-candidate-v5-manifest', e.candidate.rawFrameCount,
    e.candidate.finalReprojectionFrameCount, e.candidate.reusedV4ReprojectionFrameCount,
    e.candidate.newV5ReprojectionFrameCount]);
  for (const item of manifest.files) {
    const file = path.join(path.dirname(manifestFile), item.path);
    assert.equal(sha256(fs.readFileSync(file)), item.sha256,
      `Frozen Manyo artifact changed: ${item.path}`);
  }
  assert.equal(manifest.files.filter(item => item.path.startsWith('raw/')).length,
    e.candidate.rawFrameCount, 'Incomplete frozen Manyo raw evidence');
  assert.equal(manifest.files.filter(item => item.path.startsWith('reprojection/')).length,
    e.candidate.finalReprojectionFrameCount, 'Incomplete frozen Manyo reprojection evidence');
  const candidateFile = artifact(e.candidate.candidateFile, e.candidate.candidateSha256);
  const candidate = JSON.parse(fs.readFileSync(candidateFile));
  const v4 = JSON.parse(fs.readFileSync(artifact(e.candidate.v4RejectedFile,
    e.candidate.v4RejectedSha256)));
  const picks = JSON.parse(fs.readFileSync(artifact(e.candidate.picksFile, e.candidate.picksSha256)));
  const frameMap = JSON.parse(fs.readFileSync(artifact(e.candidate.frameMapFile,
    e.candidate.frameMapSha256)));
  assert.deepEqual([candidate.format, candidate.status, candidate.rawFrameCount,
    candidate.finalReprojectionFrameCount],
  ['jtm-manyo-complete-display-candidate-v5',
    'candidate-only-ready-for-root-native-main-review',
    e.candidate.rawFrameCount, e.candidate.finalReprojectionFrameCount]);
  const records = candidateRecords(candidate);
  assert.deepEqual(Object.keys(records), e.lineIDs);
  let intervalTotal = 0;
  for (const lineID of e.lineIDs) {
    const record = records[lineID], expected = e.candidate.intervalCounts[lineID];
    assert.deepEqual(record.candidateIntervals.map(item => item.intervalIndex),
      Array.from({ length: expected }, (_, index) => index), `Incomplete Manyo intervals: ${lineID}`);
    assert.equal(record.candidateIntervals.length, expected);
    intervalTotal += expected;
    for (const item of record.candidateIntervals) {
      assert(item.coordinates.length >= 2, `Empty Manyo interval: ${lineID}#${item.intervalIndex}`);
      for (const point of item.coordinates) assert(point.every(Number.isFinite), 'Non-finite Manyo point');
      for (let index = 1; index < item.coordinates.length; index += 1)
        assert(distance(item.coordinates[index - 1], item.coordinates[index]) >=
          e.candidate.minimumEdgeMetres, `Degenerate Manyo edge: ${lineID}#${item.intervalIndex}`);
    }
    for (let index = 1; index < record.candidateIntervals.length; index += 1)
      assert.deepEqual(record.candidateIntervals[index - 1].coordinates.at(-1),
        record.candidateIntervals[index].coordinates[0], `Manyo seam changed: ${lineID}#${index}`);
  }
  assert.equal(intervalTotal, 24);
  for (const lineID of e.lineIDs) {
    const record = records[lineID];
    assert.deepEqual(record.displayStationCoordinates[e.candidate.sharedStationID],
      e.candidate.sharedCoordinate, 'Manyo shared 001802 tuple changed');
    assert.deepEqual(record.candidateIntervals[0].coordinates[0],
      e.candidate.sharedCoordinate, 'Manyo shared 001802 interval endpoint changed');
  }
  const high = records[e.lineIDs[1]];
  assert.deepEqual(high.displayStationCoordinates[e.candidate.retainedTerminalStationID],
    e.candidate.retainedTerminalCoordinate, 'Takaoka 001870 retained tuple changed');
  assert.deepEqual(high.candidateIntervals.at(-1).coordinates.at(-1),
    e.candidate.retainedTerminalCoordinate, 'Takaoka 001870 terminal endpoint changed');
  const v4Records = candidateRecords(v4), changed = new Set(e.candidate.changedHighIntervals);
  assert.deepEqual(records[e.lineIDs[0]], v4Records[e.lineIDs[0]], 'V5 changed the accepted Shin line');
  for (const item of high.candidateIntervals) {
    if (!changed.has(item.intervalIndex)) assert.deepEqual(item,
      v4Records[e.lineIDs[1]].candidateIntervals[item.intervalIndex],
    `V5 changed an unaffected High interval: ${item.intervalIndex}`);
  }
  const pickProjection = item => ({ stationID: item.stationID, fromRawInterval: item.fromRawInterval,
    viewIndex: item.viewIndex, pixel: item.pixel, coordinate: item.coordinate,
    oldCoordinate: item.oldCoordinate, visibleLongitudinalEndsApproxPixels:
    item.visibleLongitudinalEndsApproxPixels, localRampSupportMetres: item.localRampSupportMetres });
  assert.deepEqual(candidate.revisionV5.changedStationIDs, e.candidate.changedStationIDs);
  assert.deepEqual(candidate.revisionV5.changedIntervalIndices, e.candidate.changedHighIntervals);
  assert.deepEqual(candidate.revisionV5.manualPicks.map(pickProjection), e.candidate.manualPicks);
  assert.deepEqual([frameMap.format, frameMap.changedFrameCount, frameMap.frames.length],
    ['jtm-manyo-v5-changed-frame-map', e.candidate.newV5ReprojectionFrameCount,
      e.candidate.newV5ReprojectionFrameCount]);
  assert.deepEqual(picks.map(item => ({ stationID: item.stationID, fromRawInterval: item.fromRawInterval,
    viewIndex: item.viewIndex, pixel: item.pixel, coordinate: item.coordinate,
    oldCoordinate: item.oldCoordinate, localRampSupportMetres: item.localRampSupportMetres })),
  e.candidate.manualPicks.map(({ visibleLongitudinalEndsApproxPixels, ...item }) => item));
  for (const intervalIndex of e.candidate.changedHighIntervals) {
    const intervalFile = path.join(path.dirname(manifestFile), 'intervals',
      `interval-${intervalIndex}.geojson`);
    const interval = JSON.parse(fs.readFileSync(intervalFile));
    assert.deepEqual(interval.geometry.coordinates, high.candidateIntervals[intervalIndex].coordinates,
      `V5 changed frozen interval ${intervalIndex}`);
  }
  const changedStations = new Set(e.candidate.changedStationIDs);
  for (const [stationID, coordinate] of Object.entries(high.displayStationCoordinates))
    if (!changedStations.has(stationID)) assert.deepEqual(coordinate,
      v4Records[e.lineIDs[1]].displayStationCoordinates[stationID],
    `V5 changed unaffected High alias: ${stationID}`);
  for (const pick of e.candidate.manualPicks) {
    assert.deepEqual(v4Records[e.lineIDs[1]].displayStationCoordinates[pick.stationID],
      pick.oldCoordinate, `Frozen V4 gap alias changed: ${pick.stationID}`);
    assert.deepEqual(high.displayStationCoordinates[pick.stationID], pick.coordinate,
      `V5 own-frame alias changed: ${pick.stationID}`);
    assert(!equal(pick.coordinate, pick.oldCoordinate), `V5 restored rejected gap alias: ${pick.stationID}`);
    const frame = frameMap.frames.find(item => item.intervalIndex === pick.fromRawInterval &&
      item.viewIndex === pick.viewIndex);
    assert.deepEqual(frame?.manualPick, { stationID: pick.stationID, pixel: pick.pixel,
      visibleLongitudinalEndsApproxPixels: pick.visibleLongitudinalEndsApproxPixels,
      coordinate: pick.coordinate, oldCoordinate: pick.oldCoordinate },
    `V5 manual-pick frame mapping changed: ${pick.stationID}`);
  }
  return { candidate, manifest, records };
}

function baseLine(current, e, lineID) {
  const base = structuredClone(current);
  delete base.displayIntervalCoordinates;
  delete base.displayStationCoordinates;
  assert.equal(jsonSha256(base), e.baseline.lineSha256[lineID],
    `Unreviewed Manyo physical dependency changed: ${lineID}`);
  return base;
}

function repairedLine(current, record, e) {
  const lineID = current.id, base = baseLine(current, e, lineID);
  const intervals = Object.fromEntries(record.candidateIntervals.map(item =>
    [item.intervalIndex, structuredClone(item.coordinates)]));
  assert.equal(Object.keys(intervals).length, network.decodeIntervals(base).length,
    `Manyo interval ownership incomplete: ${lineID}`);
  for (let index = 0; index < base.stations.length; index += 1) {
    const stationID = base.stations[index][0], alias = record.displayStationCoordinates[stationID];
    assert(alias, `Missing Manyo station alias: ${lineID}:${stationID}`);
    if (index < base.stations.length - 1) assert.deepEqual(intervals[index][0], alias);
    if (index > 0) assert.deepEqual(intervals[index - 1].at(-1), alias);
  }
  base.displayStationCoordinates = structuredClone(record.displayStationCoordinates);
  base.displayIntervalCoordinates = intervals;
  return base;
}

function metadata(e) {
  return { reviewedAt: e.reviewedAt, status: e.status, lineIDs: e.lineIDs,
    candidate: e.candidate, nativeReplay: e.nativeReplay, policy: e.policy,
    script: 'app/scripts/railway/repair-manyo-east-display.mjs',
    evidence: 'app/scripts/railway/manyo-east-display-evidence.json',
    physicalTopologyChanged: false };
}

export function repairPackage(input, e = read(EVIDENCE)) {
  const { records } = loadReviewedCandidate(e), result = structuredClone(input);
  for (const lineID of e.lineIDs) {
    const index = e.baseline.packageIndices[lineID], current = input.lines[index];
    assert.equal(current?.id, lineID, `Manyo package index changed: ${lineID}`);
    const repaired = repairedLine(current, records[lineID], e);
    const owned = { displayStationCoordinates: current.displayStationCoordinates,
      displayIntervalCoordinates: current.displayIntervalCoordinates };
    assert((owned.displayStationCoordinates == null && owned.displayIntervalCoordinates == null) ||
      (equal(owned.displayStationCoordinates, repaired.displayStationCoordinates) &&
        equal(owned.displayIntervalCoordinates, repaired.displayIntervalCoordinates)),
    `Unreviewed Manyo display dependency changed: ${lineID}`);
    assert.deepEqual(repaired.stations, baseLine(current, e, lineID).stations);
    assert.deepEqual(repaired.segments, baseLine(current, e, lineID).segments);
    assert.deepEqual(network.decodeIntervals(repaired), network.decodeIntervals(baseLine(current, e, lineID)));
    result.lines[index] = repaired;
  }
  result.geometrySource ||= {}; result.geometrySource.manualOverrides ||= {};
  if (e.lineIDs.every(lineID => equal(input.lines[e.baseline.packageIndices[lineID]],
    result.lines[e.baseline.packageIndices[lineID]])) && input.geometrySource?.manualOverrides?.[OVERRIDE])
    assert.deepEqual(input.geometrySource.manualOverrides[OVERRIDE], metadata(e),
      'Accepted Manyo metadata changed');
  result.geometrySource.manualOverrides[OVERRIDE] = metadata(e);
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

function measuredReferences(input, e) {
  const includesID = value => e.lineIDs.some(id => JSON.stringify(value).includes(id));
  const found = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === 'partsByRegion') continue;
    const region = value?.jp;
    if (Array.isArray(region)) {
      const rows = region.filter(includesID); if (rows.length) found[key] = rows;
    } else if (region && typeof region === 'object') {
      const rows = Object.entries(region).filter(([name, row]) => e.lineIDs.includes(name) || includesID(row));
      if (rows.length) found[key] = rows;
    }
  }
  return found;
}

export function repairedNativeRows(pkg, e = read(EVIDENCE)) {
  const result = {};
  for (const lineID of e.lineIDs) {
    const line = pkg.lines[e.baseline.packageIndices[lineID]];
    assert(line && equal(line, repairedLine(line, loadReviewedCandidate(e).records[lineID], e)),
      `Manyo package repair missing: ${lineID}`);
    const rows = partRowsForLine(line, network.displayPartsForLine(line), displayInputs(line), null);
    assert.equal(rows.length, 1, `Manyo native part count changed: ${lineID}`);
    assert.equal(jsonSha256(rows[0]), e.nativeReplay.candidateRowSha256[lineID],
      `Manyo native owning replay changed: ${lineID}`);
    const expected = e.nativeReplay.candidateSummary[lineID];
    assert.deepEqual({ partCount: rows.length, pointCount: rows[0][4], metres: rows[0][5],
      classification: rows[0][6] }, expected);
    result[lineID] = rows[0];
  }
  return result;
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  assert.deepEqual(measuredReferences(input, e), e.baseline.measuredReferences,
    'Unreviewed Manyo measured reference');
  const rows = repairedNativeRows(pkg, e), result = structuredClone(input);
  for (const lineID of e.lineIDs) {
    const current = input.partsByRegion.jp.filter(row => row[0] === lineID);
    assert.equal(current.length, 1, `Manyo native part count changed: ${lineID}`);
    assert([e.baseline.nativeRowSha256[lineID], e.nativeReplay.candidateRowSha256[lineID]]
      .includes(jsonSha256(current[0])), `Manyo native dependency changed: ${lineID}`);
    const index = result.partsByRegion.jp.findIndex(row => row[0] === lineID);
    result.partsByRegion.jp.splice(index, 1, rows[lineID]);
  }
  assert.deepEqual(measuredReferences(result, e), e.baseline.measuredReferences);
  return result;
}

export function candidateGeoJSON(pkg, e = read(EVIDENCE)) {
  const features = [];
  for (const lineID of e.lineIDs) {
    const line = pkg.lines[e.baseline.packageIndices[lineID]];
    for (const [key, coordinates] of Object.entries(line.displayIntervalCoordinates)) {
      const index = Number(key);
      features.push({ type: 'Feature', properties: { lineID, referenceLineID: lineID,
        intervalIndex: index, referenceIntervalIndex: index, status: e.status,
        representation: e.policy.representation },
      geometry: { type: 'LineString', coordinates } });
    }
  }
  return { type: 'FeatureCollection', features };
}

export function assertApplyAccepted(e) {
  assert.equal(e.status, e.policy.acceptanceGate,
    'Manyo candidate requires accepted native and Main comparison before apply');
}

function prepare(args) {
  const candidate = args[0] === '--candidate-root' && args.length === 2, apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-manyo-east-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  const paths = { package: PACKAGE, lanes: LANES, evidence: EVIDENCE, ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  if (apply) assertApplyAccepted(e);
  const reviewed = loadReviewedCandidate(e);
  const manifestDirectory = path.dirname(path.join(REPO, e.candidate.manifest));
  const sources = [{ path: path.join(REPO, e.candidate.manifest),
    before: fs.readFileSync(path.join(REPO, e.candidate.manifest)) }, ...reviewed.manifest.files.map(item => {
    const file = path.join(manifestDirectory, item.path); return { path: file, before: fs.readFileSync(file) };
  })];
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
    const geo = candidateGeoJSON(prepared.pkg, prepared.e);
    fs.writeFileSync(path.join(prepared.candidate, 'manyo-complete-display.geojson'),
      JSON.stringify(geo, null, 2) + '\n');
    const compact = { format: 'jtm-manyo-complete-display-compact-v5', status: prepared.e.status,
      lines: prepared.e.lineIDs.map(lineID => {
        const line = prepared.pkg.lines[prepared.e.baseline.packageIndices[lineID]];
        return { lineID, displayStationCoordinates: line.displayStationCoordinates,
          displayIntervalCoordinates: line.displayIntervalCoordinates };
      }) };
    fs.writeFileSync(path.join(prepared.candidate, 'manyo-complete-display.json'),
      JSON.stringify(compact, null, 2) + '\n');
    for (const feature of geo.features) fs.writeFileSync(path.join(prepared.candidate,
      `${feature.properties.lineID === prepared.e.lineIDs[0] ? 'shin' : 'taka'}-interval-${feature.properties.intervalIndex}.geojson`),
    JSON.stringify(feature, null, 2) + '\n');
  } else {
    const writes = Object.entries(outputs).filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path, before: prepared.snapshots[key].before,
        after: contents, temporary: `${prepared.snapshots[key].path}.manyo-complete-${process.pid}.tmp` }));
    applyPreparedWrites(writes, [...Object.values(prepared.snapshots), ...prepared.sources]);
  }
  const summaries = Object.fromEntries(prepared.e.lineIDs.map(lineID => {
    const row = prepared.lanes.partsByRegion.jp.find(item => item[0] === lineID);
    return [lineID, { intervals: Object.keys(prepared.pkg.lines[prepared.e.baseline.packageIndices[lineID]]
      .displayIntervalCoordinates).length, nativePointCount: row[4], nativeMetres: row[5] }];
  }));
  console.log(JSON.stringify({ mode: prepared.apply ? 'applied' : 'candidate',
    status: prepared.e.status, summaries,
    refreshedDependencyPaths: Object.values(DEPENDENCY_PATHS), physicalTopologyChanged: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
