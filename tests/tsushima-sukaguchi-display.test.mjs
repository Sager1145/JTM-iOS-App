import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { LINE_IDS, INTERVAL_INDEXES, INTERVAL_IDS, physicalLine, jsonSha256,
  loadReviewedCandidate, repairPackage, deriveNativeRows, repairParts,
  measuredReferences, deriveCandidateMeasuredReferences, assertApplyAccepted, prepare }
  from '../app/scripts/railway/repair-tsushima-sukaguchi-display.mjs';
const network = createRequire(import.meta.url)('../app/public/rail-network.js');
const sha = value => crypto.createHash('sha256').update(value).digest('hex');

// Canonical fixture, not evidence of the unfrozen real Tsushima candidate.
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tsushima-display-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const station = (prefix, i, coordinate) => [`${prefix}${i}`, `${prefix} ${i}`, ...coordinate, i];
  const line = (id, prefix, coordinates) => ({ id, name: prefix, km: coordinates.length - 1,
    stations: coordinates.map((p, i) => station(prefix, i, p)),
    segments: coordinates.slice(1).map((p, i) => [1, 0, [coordinates[i], p]]) });
  const tsushima = line(LINE_IDS[0], 't', Array.from({ length: 8 }, (_, i) => [139 + i * 0.002, 35]));
  const mainPoints = Array.from({ length: 26 }, (_, i) => [139 + (18 - i) * 0.001, 35]);
  const main = line(LINE_IDS[1], 'm', mainPoints);
  // As in the real underground tail, unchanged interior supports isolate the
  // last owned interval's grooming context from the unowned suffix.
  main.segments[23][2] = [mainPoints[23],
    [mainPoints[23][0] - 0.0004, 35], [mainPoints[23][0] - 0.0007, 35], mainPoints[24]];
  // Existing Main display outside 16–20 must survive package and native replay.
  const previousAlias = [mainPoints[2][0], mainPoints[2][1] + 0.0001];
  main.displayStationCoordinates = { m2: previousAlias };
  main.displayIntervalCoordinates = { 1: [mainPoints[1], previousAlias], 2: [previousAlias, mainPoints[3]] };
  const pkg = { lines: [tsushima, main, { id: 'unrelated', keep: 'untouched' }],
    geometrySource: { manualOverrides: { existing: { keep: true } } } };
  const e = { format: 'jtm-tsushima-sukaguchi-display-v1', status: 'candidate-only',
    owners: { [LINE_IDS[0]]: { intervalIndexes: [...INTERVAL_INDEXES[LINE_IDS[0]]], stationIDs: ['t3'] },
      [LINE_IDS[1]]: { intervalIndexes: [...INTERVAL_INDEXES[LINE_IDS[1]]], stationIDs: ['m19'] } },
    baseline: { packageIndices: { [LINE_IDS[0]]: 0, [LINE_IDS[1]]: 1 },
      lineSha256: Object.fromEntries(pkg.lines.slice(0, 2).map(l => [l.id, jsonSha256(physicalLine(l))])),
      displayIntervals: Object.fromEntries(pkg.lines.slice(0, 2).map(l => [l.id, l.displayIntervalCoordinates || {}])),
      displayStations: Object.fromEntries(pkg.lines.slice(0, 2).map(l => [l.id, l.displayStationCoordinates || {}])) },
    candidate: { file: path.join(dir, 'candidate.json') } };
  const candidate = { format: 'jtm-tsushima-sukaguchi-display-candidate-v1', status: 'candidate-only',
    lines: pkg.lines.slice(0, 2).map(l => ({ lineID: l.id,
      candidateIntervals: INTERVAL_INDEXES[l.id].map(i => ({ intervalIndex: i,
        coordinates: structuredClone(l.segments[i][2]) })),
      displayStationCoordinates: l.id === LINE_IDS[0] ? { t3: [139.006, 35.0001] } : { m19: [mainPoints[19][0], 35.0001] } })) };
  candidate.lines[0].candidateIntervals[0].coordinates = [[139, 35], [139.0001, 35], [139.0002, 35], [139.002, 35]];
  candidate.lines[1].candidateIntervals.find(i => i.intervalIndex === 17).coordinates =
    [[139.001, 35], [139.0002, 35], [139.0001, 35], [139, 35]];
  for (const record of candidate.lines) {
    const l = pkg.lines.find(item => item.id === record.lineID);
    for (const item of record.candidateIntervals) {
      const aliases = record.displayStationCoordinates;
      if (aliases[l.stations[item.intervalIndex][0]]) item.coordinates[0] = aliases[l.stations[item.intervalIndex][0]];
      if (aliases[l.stations[item.intervalIndex + 1][0]]) item.coordinates[item.coordinates.length - 1] = aliases[l.stations[item.intervalIndex + 1][0]];
    }
  }
  const bind = () => { const bytes = JSON.stringify(candidate); fs.writeFileSync(e.candidate.file, bytes); e.candidate.sha256 = sha(bytes); };
  bind();
  const rows = deriveNativeRows(pkg, e);
  const lanes = { partsByRegion: { jp: [...rows[LINE_IDS[0]], ...rows[LINE_IDS[1]], ['unrelated', 0]] },
    followsByRegion: { jp: [[LINE_IDS[1], 'reviewed-follow', 'other']] },
    familyWindowsByRegion: { jp: {} } };
  e.baseline.nativeRowsSha256 = Object.fromEntries(LINE_IDS.map(id => [id, jsonSha256(rows[id])]));
  e.baseline.measuredReferences = measuredReferences(lanes);
  return { dir, pkg, e, candidate, lanes, bind };
}

test('display-only repair preserves physical IDs, station rows, mileage, segments and existing Main display', t => {
  const { pkg, e } = fixture(t), original = structuredClone(pkg), repaired = repairPackage(pkg, e);
  assert.deepEqual(pkg, original, 'Input mutated');
  for (const id of LINE_IDS) {
    const i = e.baseline.packageIndices[id];
    assert.deepEqual(physicalLine(repaired.lines[i]), physicalLine(original.lines[i]));
    assert.deepEqual(network.decodeIntervals(repaired.lines[i]), network.decodeIntervals(original.lines[i]));
  }
  assert.deepEqual(repaired.lines[2], original.lines[2]);
  assert.deepEqual(repaired.lines[1].displayIntervalCoordinates[1], original.lines[1].displayIntervalCoordinates[1]);
  assert.deepEqual(repaired.lines[1].displayStationCoordinates.m2, original.lines[1].displayStationCoordinates.m2);
  assert.deepEqual(repaired.geometrySource.manualOverrides.existing, original.geometrySource.manualOverrides.existing);
  assert.deepEqual(repairPackage(repaired, e), repaired, 'Repair must be idempotent');
  const changedPhysical = structuredClone(pkg); changedPhysical.lines[0].stations[0][4] += 0.1;
  assert.throws(() => repairPackage(changedPhysical, e), /Physical dependency changed/);
});

test('every complete owned interval uses its own station endpoints and continuous adjacent seams', t => {
  const f = fixture(t), repaired = repairPackage(f.pkg, f.e);
  for (const id of LINE_IDS) {
    const line = repaired.lines[f.e.baseline.packageIndices[id]];
    for (const i of INTERVAL_INDEXES[id]) {
      const points = line.displayIntervalCoordinates[i];
      for (const [point, stationIndex] of [[points[0], i], [points.at(-1), i + 1]]) {
        const row = line.stations[stationIndex];
        assert.deepEqual(point, line.displayStationCoordinates[row[0]] || row.slice(2, 4));
      }
    }
  }
  f.candidate.lines[0].candidateIntervals[3].coordinates[0] = [139.006, 35.0002]; f.bind();
  assert.throws(() => repairPackage(f.pkg, f.e), /Start anchor changed|Discontinuous end/);
});

test('literal three-point shared stem has the reviewed reverse relation and no reverse U', t => {
  const f = fixture(t);
  const c = loadReviewedCandidate(f.e);
  const main17 = c.lines[1].candidateIntervals.find(i => i.intervalIndex === 17).coordinates;
  assert.deepEqual(main17.slice(-3).reverse(), c.lines[0].candidateIntervals[0].coordinates.slice(0, 3));
  f.candidate.lines[1].candidateIntervals.find(i => i.intervalIndex === 17).coordinates.reverse(); f.bind();
  assert.throws(() => loadReviewedCandidate(f.e), /Shared stem direction changed/);
  const g = fixture(t);
  g.candidate.lines[0].candidateIntervals[0].coordinates[3] = [139.00015, 35]; g.bind();
  assert.throws(() => loadReviewedCandidate(g.e), /reverse U/);
});

test('native replay rebuilds complete owning lines and preserves measured references and unrelated rows', t => {
  const f = fixture(t), pkg = repairPackage(f.pkg, f.e), rows = deriveNativeRows(pkg, f.e);
  const repaired = repairParts(pkg, f.lanes, f.e);
  for (const id of LINE_IDS) assert.deepEqual(repaired.partsByRegion.jp.filter(row => row[0] === id), rows[id]);
  assert.deepEqual(repaired.partsByRegion.jp.at(-1), ['unrelated', 0]);
  assert.deepEqual(repaired.followsByRegion, f.lanes.followsByRegion);
  assert.deepEqual(repairParts(pkg, repaired, f.e), repaired);
  const tampered = structuredClone(f.lanes); tampered.followsByRegion.jp[0][1] = 'unreviewed';
  assert.throws(() => repairParts(pkg, tampered, f.e), /Measured references changed/);
});

test('frozen file binding and exact scope reject substituted candidates and partial review', t => {
  const f = fixture(t), substitute = structuredClone(f.candidate);
  substitute.lines[0].candidateIntervals[1].coordinates.push([139.003, 35]);
  assert.throws(() => loadReviewedCandidate(f.e, substitute), /differs from frozen/);
  f.candidate.lines[1].candidateIntervals.pop(); f.bind();
  assert.throws(() => loadReviewedCandidate(f.e), /Candidate interval scope changed/);
});

test('Main suffix lane and hub ranges move together while their geographic anchors and other members stay fixed', t => {
  const f = fixture(t), pkg = repairPackage(f.pkg, f.e), main = LINE_IDS[1];
  const beforeRows = deriveNativeRows(f.pkg, f.e)[main], afterRows = deriveNativeRows(pkg, f.e)[main];
  assert.equal(beforeRows.length, 1); assert.equal(afterRows.length, 1);
  const oldTotal = beforeRows[0][5], newTotal = afterRows[0][5];
  f.lanes.byRegion = { jp: [[main, 0, oldTotal - 40, oldTotal, -1], ['other', 0, 1, 2, 0.5]] };
  f.lanes.hubReportByRegion = { jp: [{ hubId: 'fixture-hub', name: 'unchanged', members: [
    { lineId: main, partIndex: 0, from: oldTotal - 40, to: oldTotal, previousLane: -1 },
    { lineId: 'other', partIndex: 0, from: 1, to: 2, previousLane: 0.5 },
  ] }] };
  f.e.baseline.measuredReferences = measuredReferences(f.lanes);
  const mapped = deriveCandidateMeasuredReferences(f.pkg, pkg, f.lanes, f.e);
  f.e.nativeReplay = { candidateMeasuredReferences: mapped };
  const repaired = repairParts(pkg, f.lanes, f.e);
  assert.equal(repaired.byRegion.jp[0][3], newTotal, 'Terminal lane endpoint must be the new native total');
  assert.notEqual(repaired.byRegion.jp[0][2], f.lanes.byRegion.jp[0][2], 'Changed prefix length must move suffix measures');
  assert.deepEqual(repaired.byRegion.jp[1], f.lanes.byRegion.jp[1]);
  const member = repaired.hubReportByRegion.jp[0].members[0];
  assert.deepEqual([member.from, member.to], repaired.byRegion.jp[0].slice(2, 4));
  assert.deepEqual(repaired.hubReportByRegion.jp[0].members[1], f.lanes.hubReportByRegion.jp[0].members[1]);
  assert.equal(member.previousLane, -1);
  assert.deepEqual(network.displayPartsForLine(f.pkg.lines[1])[0].at(-1),
    network.displayPartsForLine(pkg.lines[1])[0].at(-1));
  assert.deepEqual(repairParts(pkg, repaired, f.e), repaired, 'Mapped references must be idempotent');
  const changed = structuredClone(f.e);
  changed.nativeReplay.candidateMeasuredReferences.hubReportByRegion[0].members[0].previousLane = 2;
  assert.throws(() => repairParts(pkg, f.lanes, changed), /candidate measured reference mapping/);
});

test('an interior Main lane boundary projects onto its own corrected interval and stays paired with its hub', t => {
  const f = fixture(t), main = LINE_IDS[1], record = f.candidate.lines[1];
  const moved = [f.pkg.lines[1].stations[22][2], 35.0002];
  f.e.owners[main].stationIDs.push('m22');
  record.displayStationCoordinates.m22 = moved;
  record.candidateIntervals.find(i => i.intervalIndex === 21).coordinates[1] = moved;
  record.candidateIntervals.find(i => i.intervalIndex === 22).coordinates[0] = moved;
  f.bind();
  const pkg = repairPackage(f.pkg, f.e), oldRow = deriveNativeRows(f.pkg, f.e)[main][0];
  const edge = 0.001 * 111320 * Math.cos(35 * Math.PI / 180);
  const boundary = oldRow[5] - 2.5 * edge;
  f.lanes.byRegion = { jp: [[main, 0, boundary, oldRow[5], -3]] };
  f.lanes.hubReportByRegion = { jp: [{ hubId: 'interior', members: [
    { lineId: main, partIndex: 0, from: boundary, to: oldRow[5], previousLane: -3 },
  ] }] };
  f.e.baseline.measuredReferences = measuredReferences(f.lanes);
  f.e.nativeReplay = { candidateMeasuredReferences:
    deriveCandidateMeasuredReferences(f.pkg, pkg, f.lanes, f.e) };
  const out = repairParts(pkg, f.lanes, f.e), row = deriveNativeRows(pkg, f.e)[main][0];
  const points = row[7], target = out.byRegion.jp[0][2];
  let measure = 0, point, projectedEdge;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1], b = points[i];
    const metres = Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
      (b[1] - a[1]) * 111320);
    if (measure + metres >= target) {
      const fraction = (target - measure) / metres;
      point = a.map((value, axis) => value + (b[axis] - value) * fraction);
      projectedEdge = [a, b];
      break;
    }
    measure += metres;
  }
  const end = f.pkg.lines[1].stations[23].slice(2, 4);
  assert(point[0] > end[0] && point[0] < moved[0], 'Projection left its own interval');
  assert(point[1] > 35 && point[1] < moved[1], 'Old latitude was copied onto the corrected line');
  let oldMeasure = 0, anchor;
  for (let i = 1; i < oldRow[7].length; i++) {
    const a = oldRow[7][i - 1], b = oldRow[7][i];
    const metres = Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
      (b[1] - a[1]) * 111320);
    if (oldMeasure + metres >= boundary) {
      const fraction = (boundary - oldMeasure) / metres;
      anchor = a.map((value, axis) => value + (b[axis] - value) * fraction);
      break;
    }
    oldMeasure += metres;
  }
  const [a, b] = projectedEdge, cos = Math.cos(anchor[1] * Math.PI / 180);
  const dot = ((anchor[0] - point[0]) * (b[0] - a[0]) * cos * cos +
    (anchor[1] - point[1]) * (b[1] - a[1])) * 111320 ** 2;
  assert(Math.abs(dot) < 15, 'Projection is not normal to the corrected interval');
  assert.deepEqual([out.hubReportByRegion.jp[0].members[0].from,
    out.hubReportByRegion.jp[0].members[0].to], out.byRegion.jp[0].slice(2, 4));
  assert.equal(out.byRegion.jp[0][4], -3);
});

test('apply is rejected before candidate or production reads until all three and Main are accepted', t => {
  const f = fixture(t), evidenceFile = path.join(f.dir, 'evidence.json');
  f.e.candidate.file = path.join(f.dir, 'not-yet-frozen.json');
  fs.writeFileSync(evidenceFile, JSON.stringify(f.e));
  assert.throws(() => prepare(['--evidence', evidenceFile, '--apply']), /accepted-all-three-main/);
  const acceptedStatusOnly = { ...f.e, status: 'accepted-all-three-main' };
  assert.throws(() => assertApplyAccepted(acceptedStatusOnly), /Missing accepted native rows/);
  assert.equal(INTERVAL_IDS.length, 15);
});
