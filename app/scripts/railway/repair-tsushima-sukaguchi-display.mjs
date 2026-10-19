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
const OVERRIDE = 'tsushima-sukaguchi-display';
export const LINE_IDS = Object.freeze(['jp-名古屋鉄道-津島線', 'jp-名古屋鉄道-名古屋本線']);
export const INTERVAL_INDEXES = Object.freeze({
  [LINE_IDS[0]]: Object.freeze([0, 1, 2, 3, 4, 5, 6]),
  [LINE_IDS[1]]: Object.freeze([16, 17, 18, 19, 20, 21, 22, 23]),
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
  assert.equal(e?.format, 'jtm-tsushima-sukaguchi-display-v1');
  assert(['candidate-only', 'accepted-all-three-main'].includes(e.status), 'Unknown review status');
  assert.deepEqual(Object.keys(e.owners), LINE_IDS, 'Owner scope changed');
  for (const id of LINE_IDS) {
    assert.deepEqual(e.owners[id].intervalIndexes, INTERVAL_INDEXES[id], `Interval scope changed: ${id}`);
    const ids = e.owners[id].stationIDs;
    assert(Array.isArray(ids) && new Set(ids).size === ids.length, `Invalid station scope: ${id}`);
  }
  return e;
}
export function validateCandidate(candidate, suppliedEvidence) {
  const e = evidence(suppliedEvidence);
  assert.equal(candidate.format, 'jtm-tsushima-sukaguchi-display-candidate-v1');
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
  const tsushima = candidate.lines[0].candidateIntervals[0].coordinates;
  const main = candidate.lines[1].candidateIntervals.find(item => item.intervalIndex === 17).coordinates;
  assert(tsushima.length >= 4 && main.length >= 4, 'Shared stem needs three points and an approach');
  assert.deepEqual(main.slice(-3).reverse(), tsushima.slice(0, 3), 'Shared stem direction changed');
  // The literal shared stem and the next outgoing edge must continue forwards, not make a reverse U.
  const noReverse = (a, b, c) => {
    const cos = Math.cos(b[1] * Math.PI / 180);
    return (b[0] - a[0]) * (c[0] - b[0]) * cos * cos + (b[1] - a[1]) * (c[1] - b[1]) >= 0;
  };
  assert(noReverse(...tsushima.slice(0, 3)) && noReverse(...tsushima.slice(1, 4)) &&
    noReverse(...main.slice(-4, -1)), 'Shared stem has a reverse U');
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
    if (id === LINE_IDS[0]) assert.equal(current.segments.length, 7, 'Tsushima complete interval count changed');
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
    script: 'app/scripts/railway/repair-tsushima-sukaguchi-display.mjs' };
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
// Keep ranges on the same owned corridor when correcting its display geometry.
// Prefix/suffix references retain their geographic locus; an interior reference
// projects onto its own station interval, never an adjacent railway or interval.
export function deriveCandidateMeasuredReferences(beforePkg, afterPkg, input, suppliedEvidence) {
  const e = evidence(suppliedEvidence), id = LINE_IDS[1], index = e.baseline.packageIndices[id];
  const references = structuredClone(e.baseline.measuredReferences);
  const current = measuredReferences(input);
  assert(equal(current, references) || equal(current, e.nativeReplay?.candidateMeasuredReferences),
    'Measured references changed');
  const hasMappedReferences = (references.byRegion || []).some(row => row[0] === id) ||
    (references.hubReportByRegion || []).some(hub => hub.members?.some(member => member.lineId === id));
  if (!hasMappedReferences) return references;
  const before = beforePkg.lines[index], after = afterPkg.lines[index];
  const oldParts = network.displayPartsForLine(before), newParts = network.displayPartsForLine(after);
  assert(oldParts.length === 1 && newParts.length === 1, 'Main measured references require its single part');
  const old = oldParts[0], next = newParts[0];
  const vertex = (points, p) => {
    const matches = points.flatMap((q, i) => equal(p, q) ? [i] : []);
    assert.equal(matches.length, 1, 'Main measured scope anchor is not unique');
    return matches[0];
  };
  const start = stationPoint(before, before.displayStationCoordinates || {}, 16);
  const endStation = INTERVAL_INDEXES[id].at(-1) + 1;
  const end = stationPoint(before, before.displayStationCoordinates || {}, endStation);
  const oldStart = vertex(old, start), oldEnd = vertex(old, end);
  const newStart = vertex(next, start), newEnd = vertex(next, end);
  assert(oldStart < oldEnd && newStart < newEnd, 'Main measured scope direction changed');
  assert.deepEqual(next.slice(0, newStart + 1), old.slice(0, oldStart + 1), 'Main prefix changed outside scope');
  assert.deepEqual(next.slice(newEnd), old.slice(oldEnd), 'Main suffix changed outside scope');
  const cumulative = points => {
    const result = [0];
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1], b = points[i];
      result.push(result.at(-1) + Math.hypot((b[0] - a[0]) * 111320 *
        Math.cos((a[1] + b[1]) * Math.PI / 360), (b[1] - a[1]) * 111320));
    }
    return result;
  };
  const oldMeasures = cumulative(old), newMeasures = cumulative(next);
  const delta = newMeasures[newEnd] - oldMeasures[oldEnd];
  const rounded = value => Number(value.toFixed(1));
  const projectInterior = measure => {
    const interval = INTERVAL_INDEXES[id].find(i => {
      const from = vertex(old, stationPoint(before, before.displayStationCoordinates || {}, i));
      const to = vertex(old, stationPoint(before, before.displayStationCoordinates || {}, i + 1));
      return measure >= oldMeasures[from] && measure <= oldMeasures[to];
    });
    assert(interval != null, 'Main reference has no owned interval');
    const oldVertex = oldMeasures.findIndex(value => value >= measure);
    assert(oldVertex > 0, 'Main interior reference has no source edge');
    const fraction = (measure - oldMeasures[oldVertex - 1]) /
      (oldMeasures[oldVertex] - oldMeasures[oldVertex - 1]);
    const anchor = old[oldVertex - 1].map((v, axis) =>
      v + (old[oldVertex][axis] - v) * fraction);
    const from = vertex(next, stationPoint(after, after.displayStationCoordinates || {}, interval));
    const to = vertex(next, stationPoint(after, after.displayStationCoordinates || {}, interval + 1));
    const cos = Math.cos(anchor[1] * Math.PI / 180);
    const local = p => [(p[0] - anchor[0]) * 111320 * cos, (p[1] - anchor[1]) * 111320];
    let nearest;
    for (let i = from + 1; i <= to; i++) {
      const a = local(next[i - 1]), b = local(next[i]);
      const dx = b[0] - a[0], dy = b[1] - a[1], squared = dx * dx + dy * dy;
      if (!squared) continue;
      const t = Math.max(0, Math.min(1, -(a[0] * dx + a[1] * dy) / squared));
      const residual = Math.hypot(a[0] + t * dx, a[1] + t * dy);
      if (!nearest || residual < nearest.residual)
        nearest = { residual, measure: newMeasures[i - 1] + t * (newMeasures[i] - newMeasures[i - 1]) };
    }
    assert(nearest, 'Main reference has no candidate edge');
    return rounded(nearest.measure);
  };
  const map = measure => {
    assert(Number.isFinite(measure), 'Invalid Main reference measure');
    if (measure <= oldMeasures[oldStart]) return measure;
    if (measure < oldMeasures[oldEnd]) return projectInterior(measure);
    if (measure === rounded(oldMeasures.at(-1))) return rounded(newMeasures.at(-1));
    return rounded(measure + delta);
  };
  for (const row of references.byRegion || []) {
    if (row[0] !== id) continue;
    assert.equal(row[1], 0, 'Main lane reference part changed');
    row[2] = map(row[2]); row[3] = map(row[3]);
    assert(row[2] <= row[3], 'Mapped Main lane range reversed');
  }
  for (const hub of references.hubReportByRegion || []) for (const member of hub.members || []) {
    if (member.lineId !== id) continue;
    assert.equal(member.partIndex, 0, 'Main hub reference part changed');
    member.from = map(member.from); member.to = map(member.to);
    assert(member.from <= member.to, 'Mapped Main hub range reversed');
  }
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
  const main = LINE_IDS[1], candidateLanes = candidateReferences.byRegion?.filter(row => row[0] === main) || [];
  let laneIndex = 0;
  for (const row of result.byRegion?.jp || []) if (row[0] === main) {
    const mapped = candidateLanes[laneIndex++];
    assert(mapped, 'Missing candidate Main lane reference');
    row[2] = mapped[2]; row[3] = mapped[3];
  }
  assert.equal(laneIndex, candidateLanes.length, 'Candidate Main lane reference count changed');
  for (const hub of result.hubReportByRegion?.jp || []) for (const member of hub.members || []) {
    if (member.lineId !== main) continue;
    const mappedHub = candidateReferences.hubReportByRegion?.find(item => item.hubId === hub.hubId);
    const matches = mappedHub?.members.filter(item => item.lineId === main && item.partIndex === member.partIndex);
    assert(matches?.length === 1, 'Missing candidate Main hub member');
    member.from = matches[0].from; member.to = matches[0].to;
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
    fs.writeFileSync(path.join(p.candidateRoot, 'tsushima-sukaguchi-display.geojson'), JSON.stringify(candidateGeoJSON(p.pkg, p.e), null, 2) + '\n');
  } else {
    const writes = Object.entries(p.outputs).filter(([key, after]) => after !== p.snapshots[key].before)
      .map(([key, after]) => ({ ...p.snapshots[key], after }));
    applyPreparedWrites(writes, [...Object.values(p.snapshots), ...p.sources]);
  }
  console.log(JSON.stringify({ mode: p.apply ? 'applied' : 'candidate', status: p.e.status, intervalIDs: INTERVAL_IDS, physicalTopologyChanged: false }));
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
