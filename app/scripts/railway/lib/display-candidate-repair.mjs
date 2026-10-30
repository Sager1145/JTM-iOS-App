// Shared apply path for reviewed display-only candidates (repair-06 pattern of repair-yokogawara-kitakume-ishite-display.mjs).
// The authority JSON freezes the own-line baseline and candidate, the own native part rows, the own lane rows
// (baseline and chainage-carried candidate) and every other lane-file reference to the line.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {partRowsForLine} from '../build-display-lanes.mjs';
import {assertAllowedCandidateFile} from '../local-evidence-path.mjs';
import {refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS} from '../repair-three-reversal-extents.mjs';

export const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
const APP = path.join(REPO, 'app'), EV = path.join(REPO, 'railway-evidence/local');
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const LANE_KEYS = ['partsByRegion', 'byRegion'];
// The parts of one lane-file value that mention LINE (rows, map entries or the scalar), or null.
export function ownLaneReferences(value, LINE) {
  const mentions = v => JSON.stringify(v)?.includes(LINE);
  if (!mentions(value)) return null;
  const pick = v => Array.isArray(v) ? v.filter(mentions) : v && typeof v === 'object'
    ? Object.fromEntries(Object.entries(v).filter(([k, x]) => k.includes(LINE) || mentions(x)).map(([k, x]) => [k, k.includes(LINE) ? x : pick(x)])) : v;
  return pick(value);
}

export function displayCandidateRepair(spec) {
  const {lineID: LINE, key: KEY, authorityPath: AUTHORITY_PATH, format: FORMAT, receiptFormat: RECEIPT_FORMAT,
    stationIDs: STATIONS, intervalIndices: INTERVALS, baselineSha: BASELINE_SHA, candidateSha: CANDIDATE_SHA} = spec;

  function proposedLine(e) {
    assert.deepEqual([e.format, e.lineID, e.stationIDs, e.intervalIndices, e.MainCertified, e.wholeLineAccepted],
      [FORMAT, LINE, STATIONS, INTERVALS, false, false], `${KEY}: authority scope changed`);
    assert.equal(sha(e.baselineLine), BASELINE_SHA, `${KEY}: baseline authority changed`);
    assert.equal(sha(e.candidateLine), CANDIDATE_SHA, `${KEY}: candidate authority changed`);
    const before = e.baselineLine, after = e.candidateLine, reconstructed = structuredClone(before);
    reconstructed.displayIntervalCoordinates ??= {}; reconstructed.displayStationCoordinates ??= {};
    for (const i of INTERVALS) reconstructed.displayIntervalCoordinates[i] = structuredClone(after.displayIntervalCoordinates[i]);
    for (const id of STATIONS) reconstructed.displayStationCoordinates[id] = structuredClone(after.displayStationCoordinates[id]);
    assert.deepEqual(reconstructed, after, `${KEY}: only the scoped display intervals and aliases may change`);
    for (const [id, c] of Object.entries(before.displayStationCoordinates || {}))
      if (!STATIONS.includes(id)) assert.deepEqual(after.displayStationCoordinates[id], c, `${KEY}: preserved alias changed`);
    assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before), `${KEY}: physical source changed`);
    for (const i of INTERVALS) {
      const c = after.displayIntervalCoordinates[i];
      const end = row => after.displayStationCoordinates?.[row[0]] ?? row.slice(2, 4);
      assert.deepEqual([c[0], c.at(-1)], [end(after.stations[i]), end(after.stations[(i + 1) % after.stations.length])],
        `${KEY}: interval ${i} ends are not its aliases/stations`);
    }
    assert.deepEqual(net.displayPartsForLine(after).map(p => p.length), e.candidatePartLengths, `${KEY}: public parts changed`);
    return structuredClone(after);
  }

  function repairPackage(input, e = read(AUTHORITY_PATH)) {
    const line = proposedLine(e), own = input.lines.filter(l => l.id === LINE);
    assert.equal(own.length, 1, `${KEY}: own line missing/duplicated`);
    assert(equal(own[0], e.baselineLine) || equal(own[0], line), `${KEY}: stale own package baseline`);
    const result = structuredClone(input);
    result.lines = result.lines.map(l => l.id === LINE ? line : l);
    const provenance = {lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
      evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
      status: e.status, wholeLineAccepted: false, MainCertified: false};
    result.geometrySource ??= {}; result.geometrySource.manualOverrides ??= {};
    const previous = result.geometrySource.manualOverrides[KEY];
    assert(previous === undefined || equal(previous, provenance), `${KEY}: provenance changed`);
    result.geometrySource.manualOverrides[KEY] = provenance;
    return result;
  }

  function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
    const own = pkg.lines.filter(l => l.id === LINE);
    assert.equal(own.length, 1, `${KEY}: candidate line missing/duplicated`);
    const line = own[0]; assert.deepEqual(line, proposedLine(e));
    const parts = net.displayPartsForLine(line), rows = partRowsForLine(line, parts, null, null);
    assert.deepEqual(rows.map(r => r[4]), e.candidatePartLengths, `${KEY}: native row lengths changed`);
    const current = {partsByRegion: input.partsByRegion?.jp?.filter(r => r[0] === LINE),
      byRegion: (input.byRegion?.jp || []).filter(r => r[0] === LINE)};
    assert(equal(current.partsByRegion, e.baselineNativeRows) || equal(current.partsByRegion, rows), `${KEY}: stale/foreign own native row`);
    assert(equal(current.byRegion, e.baselineLaneRows) || equal(current.byRegion, e.candidateLaneRows), `${KEY}: stale/foreign own lane rows`);
    for (const [k, value] of Object.entries(input)) if (!LANE_KEYS.includes(k))
      assert.deepEqual(ownLaneReferences(value, LINE), e.frozenLaneReferences?.[k] ?? null, `${KEY}: own lane reference changed: ${k}`);
    for (const k of LANE_KEYS) for (const [region, values] of Object.entries(input[k] || {})) if (region !== 'jp')
      assert(!JSON.stringify(values).includes(LINE), `${KEY}: foreign-region own reference`);
    assert(!(input.excludedOperators || []).includes(line.operator), `${KEY}: operator excluded`);
    const result = structuredClone(input);
    let p = 0; result.partsByRegion.jp = result.partsByRegion.jp.map(r => r[0] === LINE ? rows[p++] : r);
    assert.equal(p, rows.length, `${KEY}: native row count changed`);
    let b = 0; if (result.byRegion?.jp) result.byRegion.jp = result.byRegion.jp.map(r => r[0] === LINE ? e.candidateLaneRows[b++] : r);
    assert.equal(b, e.candidateLaneRows.length, `${KEY}: lane row count changed`);
    return result;
  }

  function validateCandidateReview(receipt, line) {
    assert(receipt, `${KEY}: scoped candidate-review receipt required before --apply`);
    assert.deepEqual([receipt.format, receipt.status, receipt.lineID, receipt.stationIDs,
      receipt.intervalIndices, receipt.MainCertified, receipt.wholeLineAccepted],
    [RECEIPT_FORMAT, 'bounded-candidate-reviewed', LINE, STATIONS, INTERVALS, false, false], `${KEY}: review scope changed`);
    assert.equal(receipt.reviewedOwnLineSha256, CANDIDATE_SHA, `${KEY}: reviewed candidate changed`);
    assert.equal(receipt.reviewedOwnLineSha256, sha(line), `${KEY}: reviewed own line changed`);
  }

  function main(args, scriptPath) {
    assert(args.length === 3 && args[0] === '--apply' && args[1] === '--candidate-review',
      'Use --apply --candidate-review <canonical evidence receipt.json>');
    const receiptPath = path.resolve(args[2]); assertAllowedCandidateFile(receiptPath);
    assert(fs.realpathSync(receiptPath).startsWith(fs.realpathSync(EV) + path.sep), `${KEY}: receipt must use canonical local evidence`);
    const snapshot = p => ({path: p, before: fs.readFileSync(p)});
    const authority = snapshot(AUTHORITY_PATH), receipt = snapshot(receiptPath), e = JSON.parse(authority.before);
    const paths = {package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json', ...DEPENDENCY_PATHS};
    const inputs = Object.fromEntries(Object.entries(paths).map(([k, p]) => [k, snapshot(path.join(APP, p))]));
    const load = k => JSON.parse(inputs[k].before), pkg = repairPackage(load('package'), e);
    validateCandidateReview(JSON.parse(receipt.before), pkg.lines.find(l => l.id === LINE));
    const lanes = repairParts(pkg, load('lanes'), e);
    const dependencies = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k => [k, load(k)])));
    const outputs = {package: JSON.stringify(pkg), lanes: JSON.stringify(lanes) + '\n',
      ...Object.fromEntries(Object.entries(dependencies).map(([k, v]) => [k, JSON.stringify(v, null, 2) + '\n']))};
    const writes = Object.entries(outputs).map(([k, after]) => ({...inputs[k], after: Buffer.from(after)}));
    const implementation = ['public/rail-network.js', 'scripts/railway/build-display-lanes.mjs',
      'scripts/railway/repair-three-reversal-extents.mjs', 'scripts/railway/local-evidence-path.mjs',
      'scripts/railway/lib/display-candidate-repair.mjs'].map(p => snapshot(path.join(APP, p))).concat(snapshot(scriptPath));
    applyPreparedWrites(writes, [...Object.values(inputs), authority, receipt, ...implementation]);
    console.log(JSON.stringify({mode: 'applied', lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
      nativeRows: lanes.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r.slice(0, 7)),
      laneRows: (lanes.byRegion?.jp || []).filter(r => r[0] === LINE), wholeLineAccepted: false, MainCertified: false}));
  }

  return {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main};
}
