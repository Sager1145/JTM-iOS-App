#!/usr/bin/env node
// Final outer display stage for the two reviewed JR East Shinagawa forks.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const EVIDENCE = 'scripts/railway/shinagawa-apple-forks-display-evidence.json';
const PACKAGE = 'public/rail/jp-2025.json';
const LANES = 'public/rail/display-lanes.json';
const STAGE = 'shinagawa-apple-forks-display';
export const YAMANOTE = 'jp-東日本旅客鉄道-山手線';
export const TOKAIDO = 'jp-東日本旅客鉄道-東海道線';
const TARGETS = [YAMANOTE, TOKAIDO];
const TARGET_SET = new Set(TARGETS);
const CANDIDATE_HASHES = {
  [YAMANOTE]: '41d9eebcd0bec1260c170fb5d44d4bfb3bc321f0066ca8a0632a8f91cd633a82',
  [TOKAIDO]: '75ac31b4b78c9347e512b3627899d7088b19dddb8f67f8e4995d91c3bb394ffb',
};
const BASELINE_LINE_HASHES = {
  [YAMANOTE]: '553eb391f628177cb3855a326787bfa9a12a5d9834c8691aec88e06e3858c52b',
  [TOKAIDO]: 'b9fed471656cc2e1e8824f9b1ac69aa0583bfc4f84fba8e87626926ea669a263',
};
const STEM_HASH = 'affa844775a2844ae51b4cad9f390c9b72a38e835b078253e7bf3bccd672642d';
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const jsonHash = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const fileHash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
const round1 = value => +value.toFixed(1);
const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
  (b[1] - a[1]) * 111320);
const cumulative = points => points.reduce((result, point, index) => {
  if (index) result.push(result.at(-1) + distance(points[index - 1], point));
  return result;
}, [0]);

function displayedLine(line) {
  return { ...line,
    stations: line.stations.map(row => [...row.slice(0, 2),
      ...(line.displayStationCoordinates?.[row[0]] || row.slice(2, 4)), ...row.slice(4)]),
    segments: line.segments.map((row, index) => line.displayIntervalCoordinates?.[index]
      ? [row[0], 0, line.displayIntervalCoordinates[index]] : row) };
}

function repairedLine(e, id) {
  const line = structuredClone(e.baseline.lines[id]), candidate = e.candidates[id];
  line.displayIntervalCoordinates = { ...(line.displayIntervalCoordinates || {}),
    [candidate.intervalIndex]: structuredClone(candidate.coordinates) };
  if (id === YAMANOTE) line.displayStationCoordinates = { ...(line.displayStationCoordinates || {}),
    [e.transverseStationFix.stationCode]: structuredClone(e.transverseStationFix.after) };
  return line;
}

function previousAcceptedYamanoteLine(e) {
  const line = structuredClone(e.baseline.lines[YAMANOTE]);
  line.displayIntervalCoordinates = { ...(line.displayIntervalCoordinates || {}),
    0: structuredClone(e.transverseStationFix.previousAcceptedCoordinates) };
  return line;
}

function stageRecord(e) {
  return { reviewedAt: e.reviewedAt, status: e.status,
    script: 'app/scripts/railway/repair-shinagawa-apple-forks-display.mjs',
    evidence: `app/${EVIDENCE}`, source: e.source.candidatePath,
    sourceSHA256: e.source.candidateSha256,
    nativeViews: e.transverseStationFix.nativeViews?.length || 0,
    historicalNativeViews: e.source.nativeViews.length,
    intervals: e.policy.acceptedIntervalIDs,
    pointCounts: Object.fromEntries(TARGETS.map(id => [id, e.candidates[id].pointCount])),
    physicalTopologyChanged: false,
    transverseStationFix: { stationCode: e.transverseStationFix.stationCode,
      before: e.transverseStationFix.before, after: e.transverseStationFix.after,
      sameChainage: true, wholePlatformCentre: e.transverseStationFix.wholePlatformCentre,
      status: e.transverseStationFix.status, currentPlatformIdentity: e.transverseStationFix.currentPlatformIdentity,
      limits: e.transverseStationFix.limits },
    previousAcceptedStage: e.transverseStationFix.previousStageRecord };
}

export function validateEvidence(e) {
  assert.equal(e.format, 'jtm-shinagawa-apple-forks-display-v1');
  assert(['candidate-transverse-station-fix', 'accepted-display-cartography'].includes(e.status));
  const fix = e.transverseStationFix;
  assert.equal(fix.lineID, YAMANOTE);
  assert.equal(fix.stationCode, '004095');
  assert.deepEqual(fix.before, [139.738535, 35.628135]);
  assert.deepEqual(fix.after, [139.73845609051148, 35.628135]);
  assert.equal(fix.sameChainage, true);
  assert.equal(fix.wholePlatformCentre, 'unresolved');
  assert.equal(fix.status, e.status === 'accepted-display-cartography'
    ? 'accepted-display-cartography' : 'candidate-only-needs-native-review');
  assert.equal(jsonHash(fix.previousAcceptedCoordinates),
    '70034a46ac8e455787d9c1b94b44e98bb92ebd3bc0bc2a635b9c359290de2a00');
  assert.deepEqual(fix.previousAcceptedCoordinates[0], fix.before);
  assert.deepEqual(e.candidates[YAMANOTE].coordinates.slice(1), fix.previousAcceptedCoordinates.slice(1));
  assert.equal(fix.previousStageRecord.status, 'accepted-display-cartography');
  assert.equal(fix.previousStageRecord.reviewedAt, '2026-10-12');
  assert.equal(e.crs, 'WGS84 longitude latitude');
  assert.deepEqual(e.policy.acceptedIntervalIDs, [`${YAMANOTE}#0`, `${TOKAIDO}#6`]);
  assert.equal(e.policy.maximumSourceDisplacementMetres, 80);
  assert.equal(e.policy.maximumMeasuredReferenceDisplacementMetres, 80);
  assert.equal(e.policy.physicalChangesAllowed, false);
  assert.equal(jsonHash(e.policy.exactOsakiStem), STEM_HASH, 'Reviewed Osaki stem changed');
  assert.deepEqual(e.policy.exactOsakiStem.slice(-3),
    [[139.7295, 35.6183], [139.72888, 35.61912], [139.728245, 35.619945]]);
  assert.equal(fileHash(path.join(REPO, e.source.candidatePath)), e.source.candidateSha256,
    'Shinagawa candidate source changed');
  const original = JSON.parse(fs.readFileSync(path.join(REPO, e.source.candidatePath)))
    .candidates.find(row => row.lineId === YAMANOTE);
  assert.deepEqual(original.fullCandidatePoints, fix.previousAcceptedCoordinates);
  assert.deepEqual(original.stationEndWindow.identifiedPairCentre, fix.after);
  assert.equal(e.source.nativeViews.length, 15);
  assert.equal(new Set(e.source.nativeViews.map(row => `${row.scope}/${row.view}`)).size, 15);
  for (const record of e.source.nativeViews) {
    assert.equal(record.review, 'accepted-display-cartography');
    const expectedID = record.scope === e.candidates[YAMANOTE].sourceViewSet ? YAMANOTE
      : record.scope === e.candidates[TOKAIDO].sourceViewSet ? TOKAIDO : null;
    assert(expectedID, `Unknown native source scope ${record.scope}`);
    for (const name of ['basemap.png', 'reference.png', 'view.json']) {
      const source = record[name], file = path.join(REPO, source.path);
      assert.equal(fileHash(file), source.sha256, `Accepted native source changed: ${source.path}`);
    }
    const view = JSON.parse(fs.readFileSync(path.join(REPO, record['view.json'].path)));
    assert.deepEqual([view.format, view.lineID, view.intervalIndex, view.itemID, view.pointOrdinal],
      ['jtm-rail-view-v1', expectedID, e.candidates[expectedID].intervalIndex,
        `${expectedID}#${e.candidates[expectedID].intervalIndex}`, Number(record.view)]);
  }
  assert.equal(e.source.nativeViews.filter(row => row.scope === e.candidates[YAMANOTE].sourceViewSet).length, 7);
  assert.equal(e.source.nativeViews.filter(row => row.scope === e.candidates[TOKAIDO].sourceViewSet).length, 8);
  for (const id of TARGETS) {
    const line = e.baseline.lines[id], candidate = e.candidates[id], interval = candidate.intervalIndex;
    assert.equal(e.baseline.packageIndices[id], id === YAMANOTE ? 354 : 372);
    assert.equal(jsonHash(line), BASELINE_LINE_HASHES[id], `${id} frozen baseline changed`);
    assert.equal(candidate.pointCount, id === YAMANOTE ? 177 : 54);
    assert.equal(candidate.coordinates.length, candidate.pointCount);
    assert.equal(jsonHash(candidate.coordinates), CANDIDATE_HASHES[id], `${id} accepted coordinates changed`);
    const displayStart = id === YAMANOTE ? fix.after : line.stations[interval].slice(2, 4);
    assert.deepEqual(candidate.coordinates[0], displayStart);
    assert.deepEqual(candidate.coordinates.at(-1), line.stations[interval + 1].slice(2, 4));
    const source = network.decodeIntervals(line)[interval];
    assert(distance(source[0], id === YAMANOTE ? fix.before : candidate.coordinates[0]) < 1e-6 &&
      distance(source.at(-1), candidate.coordinates.at(-1)) < 1e-6);
    const maximumDisplacement = Math.max(...candidate.coordinates.map(point => {
      let best = Infinity;
      for (let index = 1; index < source.length; index += 1)
        best = Math.min(best, project(point, source[index - 1], source[index]).displacementMetres);
      return best;
    }));
    assert(maximumDisplacement <= e.policy.maximumSourceDisplacementMetres,
      `${id} accepted coordinates exceed source bound`);
  }
  const yamanote = e.candidates[YAMANOTE].coordinates;
  const stemAt = yamanote.findIndex(point => same(point, e.policy.exactOsakiStem[0]));
  assert(stemAt >= 0);
  assert.deepEqual(yamanote.slice(stemAt), e.policy.exactOsakiStem);
  assert.equal(e.immutable.physicalStationsSegmentsKilometresIDsDirections, true);
  assert.equal(e.immutable.osakiStationTwoSouthArmsOneMergedOneNorth, true);
  assert.equal(e.immutable.sobu13To15DisplayUnchanged, true);
  return e;
}

export function repairPackage(input, e = read(EVIDENCE)) {
  validateEvidence(e);
  const pkg = structuredClone(input);
  for (const id of TARGETS) {
    const index = e.baseline.packageIndices[id], current = pkg.lines[index], repaired = repairedLine(e, id);
    assert.equal(current?.id, id, `${id} package index changed`);
    assert(equal(current, e.baseline.lines[id]) || equal(current, repaired) ||
      (id === YAMANOTE && equal(current, previousAcceptedYamanoteLine(e))), `${id} dependency changed`);
    assert.deepEqual(repaired.stations, e.baseline.lines[id].stations);
    assert.deepEqual(repaired.segments, e.baseline.lines[id].segments);
    pkg.lines[index] = repaired;
  }
  pkg.geometrySource ||= {}; pkg.geometrySource.manualOverrides ||= {};
  const record = stageRecord(e), currentStage = pkg.geometrySource.manualOverrides[STAGE];
  assert(!currentStage || equal(currentStage, record) || equal(currentStage, e.transverseStationFix.previousStageRecord),
    'Shinagawa Apple fork provenance changed');
  pkg.geometrySource.manualOverrides[STAGE] = record;
  return pkg;
}

function pointAt(points, measures, target) {
  if (target <= 0) return points[0];
  if (target >= measures.at(-1)) return points.at(-1);
  let index = 1;
  while (measures[index] < target) index += 1;
  const fraction = (target - measures[index - 1]) / (measures[index] - measures[index - 1]);
  return points[index - 1].map((value, axis) => value + fraction * (points[index][axis] - value));
}

function project(point, a, b) {
  const latitude = (a[1] + b[1] + point[1]) / 3 * Math.PI / 180;
  const sx = 111320 * Math.cos(latitude), sy = 111320;
  const vx = (b[0] - a[0]) * sx, vy = (b[1] - a[1]) * sy;
  const px = (point[0] - a[0]) * sx, py = (point[1] - a[1]) * sy;
  const fraction = Math.max(0, Math.min(1, (px * vx + py * vy) / (vx * vx + vy * vy || 1)));
  const coordinate = [a[0] + fraction * (b[0] - a[0]), a[1] + fraction * (b[1] - a[1])];
  return { fraction, coordinate, displacementMetres: distance(point, coordinate) };
}

function measureMapper(beforeLine, afterLine, beforeRow, afterRow, e) {
  const pointsForRow = (line, row) => row[7] || network.displayPartsForLine(line)[row[1]];
  const oldPoints = pointsForRow(beforeLine, beforeRow), newPoints = pointsForRow(afterLine, afterRow);
  const oldMeasures = cumulative(oldPoints), newMeasures = cumulative(newPoints);
  const stationCoordinate = (line, station) => line.displayStationCoordinates?.[station[0]] || station.slice(2, 4);
  const locate = (points, coordinate) => points.findIndex(point => same(point, coordinate));
  const oldStations = beforeLine.stations.map(station => locate(oldPoints, stationCoordinate(beforeLine, station)));
  const newStations = afterLine.stations.map(station => locate(newPoints, stationCoordinate(afterLine, station)));
  assert(oldStations.every(index => index >= 0) && newStations.every(index => index >= 0),
    `${beforeLine.id} station seam missing from native part`);
  const stationMeasures = oldStations.map(index => oldMeasures[index]);
  return measure => {
    assert(measure >= -1e-6 && measure <= oldMeasures.at(-1) + .2, `${beforeLine.id} measure outside part`);
    const bounded = Math.max(0, Math.min(oldMeasures.at(-1), measure));
    const stationIndex = stationMeasures.findIndex(value => Math.abs(value - bounded) < 1e-6);
    if (stationIndex >= 0) {
      const displacementMetres = distance(oldPoints[oldStations[stationIndex]], newPoints[newStations[stationIndex]]);
      assert(displacementMetres <= e.policy.maximumMeasuredReferenceDisplacementMetres,
        `${beforeLine.id} station reference exceeds bound`);
      return { measure: newMeasures[newStations[stationIndex]], displacementMetres,
        interval: Math.min(stationIndex, stationMeasures.length - 2) };
    }
    let interval = stationMeasures.length - 2;
    for (let index = 0; index < stationMeasures.length - 1; index += 1) {
      if (bounded <= stationMeasures[index + 1] + 1e-6) { interval = index; break; }
    }
    const source = pointAt(oldPoints, oldMeasures, bounded);
    for (let index = newStations[interval]; index <= newStations[interval + 1]; index += 1) {
      if (same(newPoints[index], source)) return { measure: newMeasures[index], displacementMetres: 0, interval };
    }
    let best = null;
    for (let index = newStations[interval]; index < newStations[interval + 1]; index += 1) {
      const candidate = project(source, newPoints[index], newPoints[index + 1]);
      if (!best || candidate.displacementMetres < best.displacementMetres)
        best = { ...candidate, measure: newMeasures[index] + candidate.fraction *
          (newMeasures[index + 1] - newMeasures[index]), interval };
    }
    assert(best && best.displacementMetres <= e.policy.maximumMeasuredReferenceDisplacementMetres,
      `${beforeLine.id} measured reference exceeds bound`);
    return best;
  };
}

const rowReferences = (lanes, key) => {
  const rows = lanes[key]?.jp || [];
  if (key === 'followsByRegion') return rows.filter(row => TARGET_SET.has(row[0]) || TARGET_SET.has(row[4]));
  return rows.filter(row => TARGET_SET.has(row[0]));
};
const hubReferences = lanes => (lanes.hubReportByRegion?.jp || []).flatMap(hub =>
  (hub.members || []).filter(member => TARGET_SET.has(member.lineId)).map(member => [hub.hubId, member]));
function replaceRows(rows, predicate, replacements) {
  let index = 0;
  const result = rows.map(row => predicate(row) ? structuredClone(replacements[index++]) : row);
  assert.equal(index, replacements.length, 'Shinagawa measured replacement count changed');
  return result;
}

function expectedLanes(pkg, e, targets = TARGETS) {
  const result = structuredClone(e.baseline.lanes), maps = new Map(), targetSet = new Set(targets);
  for (const id of targets) {
    const line = pkg.lines[e.baseline.packageIndices[id]], shown = displayedLine(line);
    const parts = network.displayPartsForLine(line);
    assert.equal(parts.length, 1, `${id} part topology changed`);
    const rows = partRowsForLine(line, parts,
      { stations: shown.stations, intervals: network.decodeIntervals(shown) }, null);
    assert.equal(rows.length, 1);
    const beforeRow = e.baseline.lanes.partsByRegion.jp.find(row => row[0] === id);
    assert(beforeRow && beforeRow[1] === 0);
    maps.set(id, measureMapper(e.baseline.lines[id], line, beforeRow, rows[0], e));
    result.partsByRegion.jp = result.partsByRegion.jp.map(row => row[0] === id ? rows[0] : row);
  }
  result.byRegion.jp = result.byRegion.jp.map(row => targetSet.has(row[0])
    ? [row[0], row[1], round1(maps.get(row[0])(row[2]).measure), round1(maps.get(row[0])(row[3]).measure), row[4]] : row);
  result.followsByRegion.jp = result.followsByRegion.jp.map(row => {
    const mapped = row.slice();
    if (targetSet.has(row[0])) {
      mapped[2] = maps.get(row[0])(row[2]).measure; mapped[3] = maps.get(row[0])(row[3]).measure;
    }
    if (targetSet.has(row[4])) {
      mapped[6] = maps.get(row[4])(row[6]).measure; mapped[7] = maps.get(row[4])(row[7]).measure;
    }
    return mapped;
  });
  result.familyWindowsByRegion.jp = result.familyWindowsByRegion.jp.map(row => targetSet.has(row[0])
    ? [...row.slice(0, 2), maps.get(row[0])(row[2]).measure, maps.get(row[0])(row[3]).measure, ...row.slice(4)] : row);
  for (const hub of result.hubReportByRegion?.jp || []) for (const member of hub.members || []) {
    if (!targetSet.has(member.lineId)) continue;
    assert.equal(member.partIndex, 0);
    for (const key of ['from', 'to', 'alongsideFrom', 'alongsideTo']) if (Number.isFinite(member[key]))
      member[key] = round1(maps.get(member.lineId)(member[key]).measure);
  }
  return result;
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  validateEvidence(e);
  for (const id of TARGETS)
    assert.deepEqual(pkg.lines[e.baseline.packageIndices[id]], repairedLine(e, id), `${id} package repair missing`);
  for (const key of ['reversedLoopParts', 'chainBoundariesByRegion'])
    assert(!(input[key]?.jp || []).some(row => TARGETS.some(id => JSON.stringify(row).includes(id))),
      `unknown measured reference in ${key}`);
  // Recover the accepted 2026-10-12 ruler, then rebase only Yamanote's
  // transverse endpoint. Tokaido keeps its exact accepted geometry and ruler.
  const previousPackage = structuredClone(pkg);
  previousPackage.lines[e.baseline.packageIndices[YAMANOTE]] = previousAcceptedYamanoteLine(e);
  const previous = expectedLanes(previousPackage, e);
  const previousEvidence = { ...e, baseline: { ...e.baseline,
    lines: { ...e.baseline.lines, [YAMANOTE]: previousPackage.lines[e.baseline.packageIndices[YAMANOTE]],
      [TOKAIDO]: previousPackage.lines[e.baseline.packageIndices[TOKAIDO]] }, lanes: previous } };
  const expected = expectedLanes(pkg, previousEvidence, [YAMANOTE]), result = structuredClone(input);
  for (const key of ['partsByRegion', 'byRegion', 'followsByRegion', 'familyWindowsByRegion']) {
    const current = rowReferences(input, key), before = rowReferences(e.baseline.lanes, key), after = rowReferences(expected, key);
    const accepted = rowReferences(previous, key);
    assert(equal(accepted, e.transverseStationFix.previousAcceptedRows[key]), `${key} historical accepted reference changed`);
    assert(equal(current, before) || equal(current, accepted) || equal(current, after), `${key} reference changed`);
    const predicate = key === 'followsByRegion'
      ? row => TARGET_SET.has(row[0]) || TARGET_SET.has(row[4]) : row => TARGET_SET.has(row[0]);
    result[key].jp = replaceRows(result[key].jp, predicate, after);
  }
  const currentHubs = hubReferences(input), beforeHubs = hubReferences(e.baseline.lanes), afterHubs = hubReferences(expected);
  const acceptedHubs = hubReferences(previous);
  assert(equal(acceptedHubs, e.transverseStationFix.previousAcceptedHubs), 'historical accepted hub references changed');
  assert(equal(currentHubs, beforeHubs) || equal(currentHubs, acceptedHubs) || equal(currentHubs, afterHubs),
    'hubReportByRegion reference changed');
  let hubIndex = 0;
  for (const hub of result.hubReportByRegion?.jp || []) hub.members = (hub.members || []).map(member =>
    TARGET_SET.has(member.lineId) ? structuredClone(afterHubs[hubIndex++][1]) : member);
  assert.equal(hubIndex, afterHubs.length);
  return result;
}

function prepare(args) {
  const candidateAt = args.indexOf('--candidate-root');
  const candidate = candidateAt >= 0 && args.length === 2 && candidateAt === 0;
  const apply = equal(args, ['--apply']);
  assert(candidate || apply, 'Usage: node repair-shinagawa-apple-forks-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  const paths = { package: PACKAGE, lanes: LANES, evidence: EVIDENCE, ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  if (apply) assert.equal(e.transverseStationFix.status, 'accepted-display-cartography',
    'Transverse endpoint remains a candidate pending native review');
  const sourcePaths = [e.source.candidatePath, ...e.source.nativeViews.flatMap(record =>
    ['basemap.png', 'reference.png', 'view.json'].map(key => record[key].path))];
  const sources = sourcePaths.map(relative => {
    const file = path.join(REPO, relative); return { path: file, before: fs.readFileSync(file) };
  });
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  return { candidate: candidate ? path.resolve(args[1]) : null, apply, snapshots, sources, pkg, lanes, dependencies };
}

function main(args = process.argv.slice(2)) {
  const prepared = prepare(args);
  const outputs = { package: JSON.stringify(prepared.pkg), lanes: JSON.stringify(prepared.lanes) + '\n',
    ...Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, JSON.stringify(prepared.dependencies[key], null, 2) + '\n'])) };
  if (prepared.candidate) {
    assert(prepared.candidate.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
    fs.mkdirSync(prepared.candidate, { recursive: true });
    for (const [key, contents] of Object.entries(outputs))
      fs.writeFileSync(path.join(prepared.candidate, path.basename(prepared.snapshots[key].path)), contents);
  } else {
    const writes = Object.entries(outputs).filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path, before: prepared.snapshots[key].before,
        after: contents, temporary: `${prepared.snapshots[key].path}.shinagawa-forks-${process.pid}.tmp` }));
    try {
      for (const write of writes) fs.writeFileSync(write.temporary, write.after);
      for (const snapshot of Object.values(prepared.snapshots))
        assert.equal(fs.readFileSync(snapshot.path, 'utf8'), snapshot.before, 'Concurrent input changed before Shinagawa apply');
      for (const source of prepared.sources)
        assert(fs.readFileSync(source.path).equals(source.before), 'Concurrent source changed before Shinagawa apply');
      for (const write of writes) fs.renameSync(write.temporary, write.path);
    } finally {
      for (const write of writes) if (fs.existsSync(write.temporary)) fs.unlinkSync(write.temporary);
    }
  }
  console.log(JSON.stringify({ mode: prepared.apply ? 'applied' : 'candidate', intervals: TARGETS.map(id => {
    const line = prepared.pkg.lines.find(row => row.id === id), intervalIndex = evidenceInterval(prepared.pkg, id);
    return { lineID: id, intervalIndex, pointCount: line.displayIntervalCoordinates[intervalIndex].length };
  }) }));
}

function evidenceInterval(pkg, id) {
  const line = pkg.lines.find(row => row.id === id);
  if (id === YAMANOTE && line.displayIntervalCoordinates?.[0]) return 0;
  if (id === TOKAIDO && line.displayIntervalCoordinates?.[6]) return 6;
  throw new Error(`Missing repaired interval for ${id}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
