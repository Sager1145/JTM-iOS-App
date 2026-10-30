#!/usr/bin/env node
// Move 富良野線 (旭川-富良野) display stroke onto Apple's drawn track; preserve prior repairs and all other aliases.; preserve prior repairs and all other aliases.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {partRowsForLine} from './build-display-lanes.mjs';
import {assertAllowedCandidateFile} from './local-evidence-path.mjs';
import {refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const APP = path.join(REPO, 'app'), EV = path.join(REPO, 'railway-evidence/local');
export const AUTHORITY_PATH = path.join(EV, 'proposals/repair-12h-20261021/authority-furano-asahikawa-furano-display.json');
const LINE = "jp-北海道旅客鉄道-富良野線", KEY = 'furano-asahikawa-furano-display';
const STATIONS = ["000095", "000098", "000101", "000104", "000106", "000108", "000109", "000110", "000112", "000121", "000130", "000132", "000133", "000136", "000137", "000114", "000129"], INTERVALS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
const DISPLAY_INTERVALS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
const BASE_PARTS = [455], CAND_PARTS = [17397], CHANGED = [{"part": 0, "protectedPrefix": 0, "protectedSuffix": 0}];
const BASELINE_SHA = '915a3420bd9407e0bacc47adbcdf60af4ee4b156e1ea37cfe61ce6107b1593e9';
const CANDIDATE_SHA = 'e45d10792d2e9027183df210a6ff7d894637d4ff85070a7a2f7339563073d484';
const NATIVE_SHA = 'f788a75dcd65f42449eb8895fa0b288221205b0fd8d3794612fc546100d6781b';
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const T = 'FuranoAsahikawaFurano';

function proposedLine(e) {
  assert.deepEqual([e.format, e.lineID, e.stationIDs, e.intervalIndices, e.displayOverrideIntervals,
    e.candidatePartCounts, e.MainCertified, e.wholeLineAccepted],
  ['jtm-r12h-furano-asahikawa-furano-display-authority-v1', LINE, STATIONS, INTERVALS, DISPLAY_INTERVALS, CAND_PARTS, false, false], T + ' authority scope changed');
  assert.equal(sha(e.baselineLine), BASELINE_SHA, T + ' baseline authority changed');
  assert.equal(sha(e.candidateLine), CANDIDATE_SHA, T + ' candidate authority changed');
  assert.equal(sha(e.baselineNativeRows), NATIVE_SHA, T + ' baseline native authority changed');
  const before = e.baselineLine, after = e.candidateLine;
  const reconstructed = structuredClone(before);
  reconstructed.displayIntervalCoordinates ??= {};
  for (const i of DISPLAY_INTERVALS) reconstructed.displayIntervalCoordinates[i] = structuredClone(after.displayIntervalCoordinates[i]);
  if (STATIONS.length) reconstructed.displayStationCoordinates ??= {};
  for (const id of STATIONS) reconstructed.displayStationCoordinates[id] = structuredClone(after.displayStationCoordinates[id]);
  assert.deepEqual(reconstructed, after, T + ': only the scoped display intervals and aliases may change');
  assert.equal(Object.keys(before.displayStationCoordinates || {}).length, 0);
  assert.equal(Object.keys(after.displayStationCoordinates || {}).length, 17);
  for (const [id, c] of Object.entries(before.displayStationCoordinates || {}))
    if (!STATIONS.includes(id)) assert.deepEqual(after.displayStationCoordinates[id], c, T + ' preserved aliases changed');
  const physical = l => Object.fromEntries(Object.entries(l).filter(([k]) => k !== 'displayIntervalCoordinates' && k !== 'displayStationCoordinates'));
  assert.deepEqual(physical(after), physical(before), T + ' non-display fields changed');
  assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before), T + ' physical source changed');
  for (const [i, c] of Object.entries(before.displayIntervalCoordinates || {}))
    if (!DISPLAY_INTERVALS.includes(+i)) assert.deepEqual(after.displayIntervalCoordinates[i], c, T + ' other display interval changed');
  const oldParts = net.displayPartsForLine(before), parts = net.displayPartsForLine(after);
  assert.deepEqual(oldParts.map(p => p.length), BASE_PARTS, T + ' baseline parts changed');
  assert.deepEqual(parts.map(p => p.length), CAND_PARTS, T + ' candidate parts changed');
  const changed = new Map(CHANGED.map(c => [c.part, c]));
  parts.forEach((p, j) => {
    const c = changed.get(j);
    if (!c) return assert.deepEqual(p, oldParts[j], T + ' unscoped part changed');
    assert.deepEqual(p.slice(0, c.protectedPrefix), oldParts[j].slice(0, c.protectedPrefix), T + ' outer public prefix changed');
    if (c.protectedSuffix) assert.deepEqual(p.slice(-c.protectedSuffix), oldParts[j].slice(-c.protectedSuffix), T + ' outer public suffix changed');
  });
  return structuredClone(after);
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), own = input.lines.filter(l => l.id === LINE);
  assert.equal(own.length, 1, T + ' own line missing/duplicated');
  assert(equal(own[0], e.baselineLine) || equal(own[0], line), T + ' stale own package baseline');
  const result = structuredClone(input);
  result.lines = result.lines.map(l => l.id === LINE ? line : l);
  const provenance = {lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
    evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
    status: 'bounded-' + KEY + '; full-passenger-caps-open', wholeLineAccepted: false, MainCertified: false};
  result.geometrySource ??= {}; result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), T + ' provenance changed');
  result.geometrySource.manualOverrides[KEY] = provenance;
  return result;
}

export function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
  const ownLines = pkg.lines.filter(l => l.id === LINE);
  assert.equal(ownLines.length, 1, T + ' candidate line missing/duplicated');
  const line = ownLines[0]; assert.deepEqual(line, proposedLine(e));
  const parts = net.displayPartsForLine(line), rows = partRowsForLine(line, parts, null, null);
  assert.deepEqual(rows.map(r => r[4]), CAND_PARTS); rows.forEach((r, j) => assert.deepEqual(r[7], parts[j]));
  assert.deepEqual(rows, e.candidateNativeRows, T + ' candidate native rows changed');
  const own = input.partsByRegion?.jp?.filter(r => r[0] === LINE);
  assert.equal(own?.length, BASE_PARTS.length, T + ' own native rows missing/duplicated');
  assert(equal(own, e.baselineNativeRows) || equal(own, rows), T + ' stale/foreign own native rows');
  const follows = (input.followsByRegion?.jp || []).filter(r => r[0] === LINE || r[4] === LINE);
  assert(equal(follows, e.baselineFollowRows) || equal(follows, e.candidateFollowRows), T + ' stale own follow rows');
  for (const [k, z] of Object.entries(e.measureZones)) assert(Math.abs(z.delta - (rows[+k][5] - e.baselineNativeRows[+k][5])) <= 0.1, T + ' measure delta changed');
  for (const [key, value] of Object.entries(input)) {
    if (key === 'partsByRegion' || key === 'followsByRegion') continue;
    const v = value?.jp;
    const refs = Array.isArray(v) ? v.filter(r => JSON.stringify(r).includes(LINE))
      : v && typeof v === 'object' ? Object.entries(v).filter(([x, y]) => x.includes(LINE) || JSON.stringify(y).includes(LINE))
      : JSON.stringify(value ?? null).includes(LINE) ? 'mentions-line' : null;
    const expected = e.baselineOtherLaneReferences[key] ?? null;
    if (refs === null || (Array.isArray(refs) && !refs.length)) assert.equal(expected, null, T + ' lane reference vanished: ' + key);
    else assert.deepEqual(refs, expected, T + ' own native reference requires review: ' + key);
  }
  for (const [region, values] of Object.entries(input.partsByRegion || {})) if (region !== 'jp')
    assert(!JSON.stringify(values).includes(LINE), T + ' foreign-region own reference');
  assert(!(input.excludedOperators || []).includes(line.operator), T + ' operator excluded');
  const result = structuredClone(input), jp = [];
  let inserted = false;
  for (const r of result.partsByRegion.jp) {
    if (r[0] !== LINE) { jp.push(r); continue; }
    if (!inserted) { jp.push(...rows); inserted = true; }
  }
  result.partsByRegion.jp = jp;
  if (result.followsByRegion?.jp) {
    // own follow rows are replaced as a block (builder-derived rows may differ in count when split points move)
    const fj = [];let done = false;
    for (const r of result.followsByRegion.jp) {
      if (r[0] !== LINE && r[4] !== LINE) { fj.push(r); continue; }
      if (!done) { fj.push(...structuredClone(e.candidateFollowRows)); done = true; }
    }
    if (!done) fj.push(...structuredClone(e.candidateFollowRows));
    result.followsByRegion.jp = fj;
    assert.deepEqual(fj.filter(r => r[0] === LINE || r[4] === LINE), e.candidateFollowRows, T + ' follow rows not replaced');
  }
  return result;
}

export function validateCandidateReview(receipt, line) {
  assert(receipt, T + ' scoped candidate-review receipt required before --apply');
  assert.deepEqual([receipt.format, receipt.status, receipt.lineID, receipt.stationIDs,
    receipt.intervalIndices, receipt.MainCertified, receipt.wholeLineAccepted],
  ['jtm-r12h-furano-asahikawa-furano-display-candidate-review-v1', 'bounded-candidate-reviewed', LINE, STATIONS, INTERVALS, false, false], T + ' review scope changed');
  assert.equal(receipt.reviewedOwnLineSha256, CANDIDATE_SHA, T + ' reviewed candidate changed');
  assert.equal(receipt.reviewedOwnLineSha256, sha(line), T + ' reviewed own line changed');
}

function main(args) {
  assert(args.length === 3 && args[0] === '--apply' && args[1] === '--candidate-review',
    'Use --apply --candidate-review <canonical evidence receipt.json>');
  const receiptPath = path.resolve(args[2]); assertAllowedCandidateFile(receiptPath);
  assert(fs.realpathSync(receiptPath).startsWith(fs.realpathSync(EV) + path.sep), T + ' receipt must use canonical local evidence');
  const snapshot = p => ({path: p, before: fs.readFileSync(p)});
  const authority = snapshot(AUTHORITY_PATH), receipt = snapshot(receiptPath), e = JSON.parse(authority.before);
  const paths = {package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json', ...DEPENDENCY_PATHS};
  const inputs = Object.fromEntries(Object.entries(paths).map(([k, p]) => [k, snapshot(path.join(APP, p))]));
  const load = k => JSON.parse(inputs[k].before), pkg = repairPackage(load('package'), e);
  validateCandidateReview(JSON.parse(receipt.before), pkg.lines.find(l => l.id === LINE));
  const lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k => [k, load(k)])));
  const outputs = {package: JSON.stringify(pkg), lanes: JSON.stringify(lanes) + '\n',
    ...Object.fromEntries(Object.entries(dependencies).map(([k, v]) => [k, JSON.stringify(v, null, 2) + '\n']))};
  const writes = Object.entries(outputs).map(([k, after]) => ({...inputs[k], after: Buffer.from(after)}));
  const implementation = ['public/rail-network.js', 'scripts/railway/build-display-lanes.mjs',
    'scripts/railway/repair-three-reversal-extents.mjs', 'scripts/railway/local-evidence-path.mjs',
    'scripts/railway/repair-furano-asahikawa-furano-display.mjs'].map(p => snapshot(path.join(APP, p)));
  applyPreparedWrites(writes, [...Object.values(inputs), authority, receipt, ...implementation]);
  console.log(JSON.stringify({mode: 'applied', lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
    nativeRows: lanes.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r.slice(0, 7)),
    fullPassengerCapsCertified: false, wholeLineAccepted: false, MainCertified: false}));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
