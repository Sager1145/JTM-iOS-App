#!/usr/bin/env node
// Scoped display-only owner. Frozen review inputs are explicit; no default evidence or acceptance.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS }
  from './repair-three-reversal-extents.mjs';

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(APP);
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const PACKAGE = 'public/rail/jp-2025.json', LANES = 'public/rail/display-lanes.json';
const OVERRIDE = 'yodo-shared-stations-display';
export const LINE_IDS = Object.freeze(['jp-四国旅客鉄道-予土線', 'jp-土佐くろしお鉄道-中村線', 'jp-四国旅客鉄道-予讃線']);
export const INTERVAL_INDEXES = Object.freeze({
  [LINE_IDS[0]]: Object.freeze(Array.from({ length: 19 }, (_, i) => i)),
  [LINE_IDS[1]]: Object.freeze([0, 1, 2, 3]),
  [LINE_IDS[2]]: Object.freeze([83, 84, 85, 86, 87, 88]),
});
export const INTERVAL_IDS = Object.freeze(LINE_IDS.flatMap(id => INTERVAL_INDEXES[id].map(i => `${id}#${i}`)));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
export const jsonSha256 = value => sha(JSON.stringify(value));
const resolveFile = file => path.isAbsolute(file) ? file : path.join(REPO, file);
const pointOK = p => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite);
const subset = (map, keys) => Object.fromEntries(Object.entries(map || {}).filter(([key]) => keys.map(String).includes(key)));
const without = (map, keys) => Object.fromEntries(Object.entries(map || {}).filter(([key]) => !keys.map(String).includes(key)));
export function physicalLine(line) {
  const result = structuredClone(line);
  delete result.displayIntervalCoordinates;
  delete result.displayStationCoordinates;
  return result;
}
function frozen(file, digest) {
  assert(typeof file === 'string' && file.length, 'Missing frozen artifact path');
  assert.match(digest || '', /^[a-f0-9]{64}$/, 'Missing frozen artifact SHA-256');
  const target = resolveFile(file), before = fs.readFileSync(target);
  assert.equal(sha(before), digest, `Frozen artifact changed: ${file}`);
  return { path: target, before };
}
function evidence(input) {
  const e = typeof input === 'string' ? JSON.parse(fs.readFileSync(resolveFile(input))) : input;
  assert.equal(e?.format, 'jtm-yodo-shared-stations-display-v1');
  assert(['candidate-only', 'accepted-all-three-main'].includes(e.status), 'Unknown review status');
  assert.deepEqual(Object.keys(e.owners), LINE_IDS, 'Owner scope changed');
  for (const id of LINE_IDS) {
    assert.deepEqual(e.owners[id].intervalIndexes, INTERVAL_INDEXES[id], `Interval scope changed: ${id}`);
    const ids = e.owners[id].stationIDs;
    assert(Array.isArray(ids) && new Set(ids).size === ids.length, `Invalid station scope: ${id}`);
    if (id === LINE_IDS[0]) assert.equal(ids.length, 20, 'Complete Yodo review requires all twenty station aliases');
  }
  return e;
}
export function validateCandidate(candidate, suppliedEvidence) {
  const e = evidence(suppliedEvidence);
  assert.equal(candidate.format, 'jtm-yodo-shared-stations-display-candidate-v1');
  assert.equal(candidate.status, 'candidate-only');
  assert.deepEqual(candidate.lines.map(line => line.lineID), LINE_IDS, 'Candidate owner scope changed');
  for (const record of candidate.lines) {
    const owner = e.owners[record.lineID];
    assert(!record.displayBranchLeadIns?.length, 'Branch lead-ins are not owned');
    assert.deepEqual(record.candidateIntervals.map(item => item.intervalIndex), owner.intervalIndexes,
      `Candidate interval scope changed: ${record.lineID}`);
    assert.deepEqual(Object.keys(record.displayStationCoordinates).sort(), [...owner.stationIDs].sort(),
      `Candidate station scope changed: ${record.lineID}`);
    for (const p of Object.values(record.displayStationCoordinates)) assert(pointOK(p), 'Invalid station alias');
    for (const item of record.candidateIntervals) {
      assert(item.coordinates.length >= 2 && item.coordinates.every(pointOK), 'Invalid candidate interval');
      for (let i = 1; i < item.coordinates.length; i++)
        assert(!equal(item.coordinates[i - 1], item.coordinates[i]), 'Zero-length candidate edge');
    }
  }
  validateSharedStationPassage(candidate);
  return candidate;
}
export function validateSharedStationPassage(candidate) {
  const record = id => candidate.lines.find(line => line.lineID === id);
  const interval = (id, i) => record(id).candidateIntervals.find(item => item.intervalIndex === i).coordinates;
  const yodo = LINE_IDS[0], naka = LINE_IDS[1], yosan = LINE_IDS[2];
  const w = record(yodo).displayStationCoordinates['009535'], k = record(yodo).displayStationCoordinates['009471'];
  assert.deepEqual(w, record(naka).displayStationCoordinates['009535'], 'Wakai owner aliases differ');
  assert.deepEqual(k, record(yosan).displayStationCoordinates['009471'], 'Kita owner aliases differ');
  const y0 = interval(yodo, 0), n0 = interval(naka, 0), n1 = interval(naka, 1);
  const n2 = interval(naka, 2), kain = record(naka).displayStationCoordinates['009571'];
  assert(pointOK(kain), 'Missing Kaina alias');
  assert.deepEqual(n1.at(-1), kain, 'Kaina incoming seam changed');
  assert.deepEqual(n2[0], kain, 'Kaina outgoing seam changed');
  const y18 = interval(yodo, 18), s87 = interval(yosan, 87), s88 = interval(yosan, 88);
  for (const p of [y0[0], n0.at(-1), n1[0]]) assert.deepEqual(p, w, 'Wakai endpoint seam changed');
  for (const p of [y18.at(-1), s87.at(-1), s88[0]]) assert.deepEqual(p, k, 'Kita endpoint seam changed');
  assert.deepEqual(y0.slice(0, 3), n1.slice(0, 3), 'Wakai shared approach changed');
  assert.deepEqual(y18.slice(-4), s87.slice(-4), 'Kita shared approach changed');
  const forward = (a, b, c) => {
    const cos = Math.cos(b[1] * Math.PI / 180);
    return (b[0] - a[0]) * (c[0] - b[0]) * cos * cos + (b[1] - a[1]) * (c[1] - b[1]) > 0;
  };
  for (const triple of [[n0.at(-2), w, y0[1]], [n0.at(-2), w, n1[1]],
    [y18.at(-2), k, s88[1]], [s87.at(-2), k, s88[1]], [n1.at(-2), kain, n2[1]]])
    assert(forward(...triple), 'Shared station has backwards passage');
  for (const points of [y0.slice(0, 3), n1.slice(0, 3), y18.slice(-4), s87.slice(-4), s88.slice(0, 5)])
    for (let i = 1; i + 1 < points.length; i++) assert(forward(points[i - 1], points[i], points[i + 1]),
      'Shared station approach has a sharp reversal');
  return candidate;
}
export function loadReviewedCandidate(suppliedEvidence, suppliedCandidate = null) {
  const e = evidence(suppliedEvidence), binding = frozen(e.candidate.file, e.candidate.sha256);
  const reviewed = JSON.parse(binding.before);
  if (suppliedCandidate != null) {
    const candidate = typeof suppliedCandidate === 'string'
      ? JSON.parse(fs.readFileSync(resolveFile(suppliedCandidate))) : suppliedCandidate;
    assert.deepEqual(candidate, reviewed, 'Supplied candidate differs from frozen artifact');
  }
  return validateCandidate(reviewed, e);
}
function stationPoint(line, aliases, index) {
  const row = line.stations[index];
  assert(row, `Missing station: ${line.id}#${index}`);
  return aliases[row[0]] || [row[2], row[3]];
}
function effectiveIntervals(line) {
  const base = network.decodeIntervals(line);
  return base.map((points, i) => line.displayIntervalCoordinates?.[i] || points);
}
export function repairPackage(input, suppliedEvidence, suppliedCandidate = null) {
  const e = evidence(suppliedEvidence), candidate = loadReviewedCandidate(e, suppliedCandidate);
  const result = structuredClone(input);
  for (const record of candidate.lines) {
    const id = record.lineID, owner = e.owners[id], index = e.baseline.packageIndices[id];
    const current = input.lines[index];
    assert.equal(current?.id, id, `Package index changed: ${id}`);
    const physical = physicalLine(current);
    assert.equal(jsonSha256(physical), e.baseline.lineSha256[id], `Physical dependency changed: ${id}`);
    assert(!current.displayBranchLeadIns?.length, `Unexpected branch lead-in: ${id}`);
    for (const stationID of owner.stationIDs) {
      const si = current.stations.findIndex(row => row[0] === stationID);
      assert(si >= 0, `Station alias belongs to another line: ${id}:${stationID}`);
      const adjacent = [si - 1, si].filter(i => i >= 0 && i < current.segments.length);
      const alias = record.displayStationCoordinates[stationID];
      assert(adjacent.every(i => owner.intervalIndexes.includes(i)) ||
        equal(alias, stationPoint(current, current.displayStationCoordinates || {}, si)),
      `Moved boundary station has unowned adjacent interval: ${id}:${stationID}`);
    }
    const reviewedIntervals = Object.fromEntries(record.candidateIntervals.map(item => [item.intervalIndex, item.coordinates]));
    for (const [key, proposed] of [['displayIntervalCoordinates', reviewedIntervals],
      ['displayStationCoordinates', record.displayStationCoordinates]]) {
      const keys = key === 'displayIntervalCoordinates' ? owner.intervalIndexes : owner.stationIDs;
      const baseline = key === 'displayIntervalCoordinates' ? e.baseline.displayIntervals[id] : e.baseline.displayStations[id];
      assert.deepEqual(without(current[key], keys), without(baseline, keys), `Unowned display dependency changed: ${id}`);
      const owned = subset(current[key], keys);
      assert(equal(owned, subset(baseline, keys)) || equal(owned, proposed), `Owned display dependency changed: ${id}`);
      result.lines[index][key] = { ...(baseline || {}), ...structuredClone(proposed) };
    }
    const line = result.lines[index], displayed = effectiveIntervals(line);
    for (const item of record.candidateIntervals) {
      const i = item.intervalIndex;
      assert.deepEqual(item.coordinates[0], stationPoint(line, line.displayStationCoordinates, i), `Start anchor changed: ${id}#${i}`);
      assert.deepEqual(item.coordinates.at(-1), stationPoint(line, line.displayStationCoordinates, i + 1), `End anchor changed: ${id}#${i}`);
      if (i > 0) assert.deepEqual(displayed[i - 1].at(-1), item.coordinates[0], `Discontinuous start: ${id}#${i}`);
      if (i + 1 < displayed.length) assert.deepEqual(item.coordinates.at(-1), displayed[i + 1][0], `Discontinuous end: ${id}#${i}`);
    }
    assert.deepEqual(physicalLine(line), physical);
    assert.deepEqual(network.decodeIntervals(line), network.decodeIntervals(current));
  }
  result.geometrySource ||= {}; result.geometrySource.manualOverrides ||= {};
  const metadata = { status: e.status, candidate: e.candidate, owners: e.owners,
    reviewedAt: e.reviewedAt, physicalTopologyChanged: false,
    script: 'app/scripts/railway/repair-yodo-shared-stations-display.mjs' };
  if (LINE_IDS.every(id => equal(input.lines[e.baseline.packageIndices[id]], result.lines[e.baseline.packageIndices[id]])) &&
      input.geometrySource?.manualOverrides?.[OVERRIDE])
    assert.deepEqual(input.geometrySource.manualOverrides[OVERRIDE], metadata, 'Accepted metadata changed');
  result.geometrySource.manualOverrides[OVERRIDE] = metadata;
  return result;
}
export function deriveNativeRows(pkg, suppliedEvidence) {
  const e = evidence(suppliedEvidence);
  return Object.fromEntries(LINE_IDS.map(id => {
    const line = pkg.lines[e.baseline.packageIndices[id]];
    assert.equal(line?.id, id);
    const stations = line.stations.map((row, i) => [...row.slice(0, 2),
      ...stationPoint(line, line.displayStationCoordinates || {}, i), ...row.slice(4)]);
    return [id, partRowsForLine(line, network.displayPartsForLine(line),
      { stations, intervals: effectiveIntervals(line) }, null)];
  }));
}
export function measuredReferences(input) {
  const includes = value => LINE_IDS.some(id => JSON.stringify(value).includes(id));
  const result = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === 'partsByRegion') continue;
    if (Array.isArray(value?.jp)) {
      const rows = value.jp.filter(includes); if (rows.length) result[key] = rows;
    } else if (value?.jp && typeof value.jp === 'object') {
      const rows = Object.fromEntries(Object.entries(value.jp).filter(([id, row]) => LINE_IDS.includes(id) || includes(row)));
      if (Object.keys(rows).length) result[key] = rows;
    }
  }
  return result;
}
// Map the final native ruler, including moved station boundaries and disjoint scopes.
// Exact station boundaries follow the new alias; interior points keep their own
// interval identity. Unchanged geographic intervals keep their local measure.
export function createMeasureMapper(before, after, ownedIndexes) {
  const oldParts = network.displayPartsForLine(before), newParts = network.displayPartsForLine(after);
  assert(oldParts.length === 1 && newParts.length === 1, 'Measured owner requires one native part');
  const old = oldParts[0], next = newParts[0];
  const vertex = (points, p) => {
    const matches = points.flatMap((q, i) => equal(p, q) ? [i] : []);
    assert.equal(matches.length, 1, 'Measured station anchor is not unique');
    return matches[0];
  };
  const cumulative = points => {
    const result = [0];
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1], b = points[i];
      result.push(result.at(-1) + Math.hypot((b[0] - a[0]) * 111320 *
        Math.cos((a[1] + b[1]) * Math.PI / 360), (b[1] - a[1]) * 111320));
    }
    return result;
  };
  const om = cumulative(old), nm = cumulative(next);
  const oi = before.stations.map((_, i) => vertex(old, stationPoint(before, before.displayStationCoordinates || {}, i)));
  const ni = after.stations.map((_, i) => vertex(next, stationPoint(after, after.displayStationCoordinates || {}, i)));
  assert(oi.every((v, i) => i === 0 || v > oi[i - 1]) && ni.every((v, i) => i === 0 || v > ni[i - 1]),
    'Native station order reversed');
  const owned = new Set(ownedIndexes);
  for (let i = 0; i + 1 < oi.length; i++) if (!owned.has(i))
    assert.deepEqual(next.slice(ni[i], ni[i + 1] + 1), old.slice(oi[i], oi[i + 1] + 1),
      `Native geometry changed outside owned interval: ${before.id}#${i}`);
  const round = v => Number(v.toFixed(1));
  const map = measure => {
    assert(Number.isFinite(measure) && measure >= 0 && measure <= round(om.at(-1)) + 0.051,
      'Reference outside old native ruler');
    if (measure === round(om.at(-1))) return round(nm.at(-1));
    const station = oi.findIndex(v => Math.abs(om[v] - measure) < 1e-7);
    if (station >= 0) {
      const mapped = nm[ni[station]];
      return Math.abs(mapped - measure) < 1e-7 ? measure : round(mapped);
    }
    const interval = oi.findIndex((v, i) => i + 1 < oi.length && measure >= om[v] && measure < om[oi[i + 1]]);
    assert(interval >= 0, 'Reference has no native station interval');
    if (!owned.has(interval)) {
      const delta = nm[ni[interval]] - om[oi[interval]];
      return Math.abs(delta) < 1e-7 ? measure : round(measure + delta);
    }
    const edge = om.findIndex(v => v >= measure);
    assert(edge > 0, 'Reference has no source edge');
    const t = (measure - om[edge - 1]) / (om[edge] - om[edge - 1]);
    const anchor = old[edge - 1].map((v, axis) => v + (old[edge][axis] - v) * t);
    const cos = Math.cos(anchor[1] * Math.PI / 180);
    const local = p => [(p[0] - anchor[0]) * 111320 * cos, (p[1] - anchor[1]) * 111320];
    let best;
    for (let j = ni[interval] + 1; j <= ni[interval + 1]; j++) {
      const a = local(next[j - 1]), b = local(next[j]), dx = b[0] - a[0], dy = b[1] - a[1];
      const squared = dx * dx + dy * dy;
      if (!squared) continue;
      const u = Math.max(0, Math.min(1, -(a[0] * dx + a[1] * dy) / squared));
      const residual = Math.hypot(a[0] + u * dx, a[1] + u * dy);
      if (!best || residual < best.residual)
        best = { residual, measure: nm[j - 1] + u * (nm[j] - nm[j - 1]) };
    }
    assert(best, 'Reference has no candidate edge in its own interval');
    return round(best.measure);
  };
  return { map, oldTotal: om.at(-1), newTotal: nm.at(-1), suffixDelta: nm.at(-1) - om.at(-1) };
}
export function deriveCandidateMeasuredReferences(beforePkg, afterPkg, input, suppliedEvidence) {
  const e = evidence(suppliedEvidence), references = structuredClone(e.baseline.measuredReferences);
  const current = measuredReferences(input);
  assert(equal(current, references) || equal(current, e.nativeReplay?.candidateMeasuredReferences), 'Measured references changed');
  const maps = Object.fromEntries(LINE_IDS.map(id => {
    const index = e.baseline.packageIndices[id];
    return [id, createMeasureMapper(beforePkg.lines[index], afterPkg.lines[index], INTERVAL_INDEXES[id]).map];
  }));
  for (const row of references.byRegion || []) if (maps[row[0]]) {
    assert.equal(row[1], 0, 'Lane reference part changed');
    row[2] = maps[row[0]](row[2]); row[3] = maps[row[0]](row[3]);
    assert(row[2] <= row[3], 'Mapped lane range reversed');
  }
  for (const hub of references.hubReportByRegion || []) for (const member of hub.members || []) if (maps[member.lineId]) {
    assert.equal(member.partIndex, 0, 'Hub reference part changed');
    member.from = maps[member.lineId](member.from); member.to = maps[member.lineId](member.to);
    assert(member.from <= member.to, 'Mapped hub range reversed');
  }
  // Canonical follows from other owners must retain their geographic locus.
  // Current Yosan-2/-3 ranges are in its unchanged prefix, so these stay exact.
  for (const row of references.followsByRegion || []) {
    assert(!maps[row[0]], 'Owned follows require explicit reviewed remap');
    if (maps[row[4]]) { assert.equal(row[5], 0, "Canonical follow part changed"); row[6] = maps[row[4]](row[6]); row[7] = maps[row[4]](row[7]); }
  }
  assert(!references.familyWindowsByRegion?.length && !references.chainBoundariesByRegion?.length,
    'New family/chain measure users need explicit reviewed mapping');
  return references;
}
export function repairParts(pkg, input, suppliedEvidence) {
  const e = evidence(suppliedEvidence), rows = deriveNativeRows(pkg, e), result = structuredClone(input);
  const reviewed = repairPackage(pkg, e);
  for (const id of LINE_IDS) assert.deepEqual(pkg.lines[e.baseline.packageIndices[id]],
    reviewed.lines[e.baseline.packageIndices[id]], `Package repair missing: ${id}`);
  const baselinePkg = structuredClone(pkg);
  for (const id of LINE_IDS) {
    const line = baselinePkg.lines[e.baseline.packageIndices[id]];
    line.displayIntervalCoordinates = structuredClone(e.baseline.displayIntervals[id]);
    line.displayStationCoordinates = structuredClone(e.baseline.displayStations[id]);
  }
  const mappedReferences = deriveCandidateMeasuredReferences(baselinePkg, pkg, input, e);
  const candidateReferences = e.nativeReplay?.candidateMeasuredReferences || e.baseline.measuredReferences;
  assert.deepEqual(candidateReferences, mappedReferences, 'Missing or changed candidate measured reference mapping');
  for (const id of LINE_IDS) {
    const expected = e.nativeReplay?.candidateRowsSha256?.[id];
    if (expected) assert.equal(jsonSha256(rows[id]), expected, `Native replay changed: ${id}`);
    const current = input.partsByRegion.jp.filter(row => row[0] === id);
    assert([e.baseline.nativeRowsSha256[id], jsonSha256(rows[id])].includes(jsonSha256(current)), `Native baseline changed: ${id}`);
    const indexes = result.partsByRegion.jp.flatMap((row, i) => row[0] === id ? [i] : []);
    assert(indexes.length && indexes.every((i, offset) => i === indexes[0] + offset), `Non-contiguous native rows: ${id}`);
    result.partsByRegion.jp.splice(indexes[0], indexes.length, ...rows[id]);
  }
  for (const id of LINE_IDS) {
    const candidateLanes = candidateReferences.byRegion?.filter(row => row[0] === id) || [];
    let laneIndex = 0;
    for (const row of result.byRegion?.jp || []) if (row[0] === id) {
      const mapped = candidateLanes[laneIndex++];
      assert(mapped, 'Missing candidate lane reference');
      row[2] = mapped[2]; row[3] = mapped[3];
    }
    assert.equal(laneIndex, candidateLanes.length, 'Candidate lane reference count changed');
  }
  for (const hub of result.hubReportByRegion?.jp || []) for (const member of hub.members || []) {
    if (!LINE_IDS.includes(member.lineId)) continue;
    const matches = candidateReferences.hubReportByRegion?.find(item => item.hubId === hub.hubId)?.members
      .filter(item => item.lineId === member.lineId && item.partIndex === member.partIndex);
    assert(matches?.length === 1, 'Missing candidate hub member');
    member.from = matches[0].from; member.to = matches[0].to;
  }
  for (const row of result.followsByRegion?.jp || []) if (LINE_IDS.includes(row[4])) {
    const matches = candidateReferences.followsByRegion?.filter(item => item[0] === row[0] && item[1] === row[1] && item[4] === row[4] && item[5] === row[5]);
    assert(matches?.length === 1, 'Missing candidate canonical follow');
    row[6] = matches[0][6]; row[7] = matches[0][7];
  }
  assert.deepEqual(measuredReferences(result), candidateReferences);
  return result;
}
export function assertApplyAccepted(suppliedEvidence) {
  const e = evidence(suppliedEvidence);
  assert.equal(e.status, 'accepted-all-three-main', 'Apply requires accepted-all-three-main');
  for (const id of LINE_IDS) assert.match(e.nativeReplay?.candidateRowsSha256?.[id] || '', /^[a-f0-9]{64}$/, 'Missing accepted native rows');
  const acceptance = e.acceptance;
  assert.equal(acceptance?.candidateSha256, e.candidate.sha256, 'Acceptance candidate binding changed');
  assert.deepEqual(acceptance.intervalIDs, INTERVAL_IDS, 'Acceptance interval scope changed');
  assert(Array.isArray(acceptance.inspectors) && acceptance.inspectors.length === 3 && acceptance.main,
    'Apply requires three Inspector receipts and Main');
  assert.deepEqual(acceptance.inspectors.map(item => item.id).sort(), ['primary', 'secondary', 'third']);
  for (const receipt of [...acceptance.inspectors, { ...acceptance.main, id: 'main' }]) {
    const actual = JSON.parse(frozen(receipt.file, receipt.sha256).before);
    assert.equal(actual.id, receipt.id, 'Review receipt identity changed');
    assert.equal(actual.status, 'accepted', 'Review receipt is not accepted');
    assert.equal(actual.candidateSha256, e.candidate.sha256, 'Receipt candidate binding changed');
    assert.deepEqual(actual.intervalIDs, INTERVAL_IDS, 'Receipt interval scope changed');
  }
}
export function candidateGeoJSON(pkg, suppliedEvidence) {
  const e = evidence(suppliedEvidence);
  return { type: 'FeatureCollection', features: LINE_IDS.flatMap(id => INTERVAL_INDEXES[id].map(i => ({
    type: 'Feature', properties: { lineID: id, referenceLineID: id, intervalIndex: i,
      referenceIntervalIndex: i, status: e.status, representation: 'display-only' },
    geometry: { type: 'LineString', coordinates: pkg.lines[e.baseline.packageIndices[id]].displayIntervalCoordinates[i] },
  }))) };
}
// Explicit CLI: --evidence FILE [--candidate FILE] (--candidate-root /private/tmp/DIR | --apply).
export function prepare(args) {
  const values = {}, switches = new Set();
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    assert(!switches.has(flag), `Duplicate argument: ${flag}`); switches.add(flag);
    if (flag === '--apply') continue;
    assert(['--evidence', '--candidate', '--candidate-root'].includes(flag), `Unknown argument: ${flag}`);
    assert(args[i + 1] && !args[i + 1].startsWith('--'), `Missing argument: ${flag}`);
    values[flag] = args[++i];
  }
  const apply = switches.has('--apply');
  assert(values['--evidence'] && (apply !== Boolean(values['--candidate-root'])), 'Specify evidence and one output mode');
  const eFile = resolveFile(values['--evidence']), eBefore = fs.readFileSync(eFile), e = evidence(JSON.parse(eBefore));
  if (apply) assertApplyAccepted(e); // Reject before package/dependency reads or output writes.
  loadReviewedCandidate(e, values['--candidate']);
  const sources = [{ path: eFile, before: eBefore }, frozen(e.candidate.file, e.candidate.sha256)];
  if (apply) sources.push(...[...e.acceptance.inspectors, e.acceptance.main].map(item => frozen(item.file, item.sha256)));
  const paths = { package: PACKAGE, lanes: LANES, ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const target = path.join(APP, relative); return [key, { path: target, before: fs.readFileSync(target, 'utf8') }];
  }));
  const read = key => JSON.parse(snapshots[key].before);
  const pkg = repairPackage(read('package'), e), lanes = repairParts(pkg, read('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, read(key)])));
  const outputs = { package: JSON.stringify(pkg), lanes: JSON.stringify(lanes) + '\n',
    ...Object.fromEntries(Object.entries(dependencies).map(([key, value]) => [key, JSON.stringify(value, null, 2) + '\n'])) };
  return { apply, candidateRoot: values['--candidate-root'] && path.resolve(values['--candidate-root']), e, pkg, lanes, outputs, snapshots, sources };
}
function main(args = process.argv.slice(2)) {
  const p = prepare(args);
  if (p.candidateRoot) {
    assert(p.candidateRoot.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
    fs.mkdirSync(p.candidateRoot, { recursive: true });
    for (const [key, contents] of Object.entries(p.outputs)) fs.writeFileSync(path.join(p.candidateRoot, path.basename(p.snapshots[key].path)), contents);
    fs.writeFileSync(path.join(p.candidateRoot, 'yodo-shared-stations-display.geojson'), JSON.stringify(candidateGeoJSON(p.pkg, p.e), null, 2) + '\n');
  } else {
    const writes = Object.entries(p.outputs).filter(([key, after]) => after !== p.snapshots[key].before)
      .map(([key, after]) => ({ ...p.snapshots[key], after }));
    applyPreparedWrites(writes, [...Object.values(p.snapshots), ...p.sources]);
  }
  console.log(JSON.stringify({ mode: p.apply ? 'applied' : 'candidate', status: p.e.status, intervalIDs: INTERVAL_IDS, physicalTopologyChanged: false }));
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
