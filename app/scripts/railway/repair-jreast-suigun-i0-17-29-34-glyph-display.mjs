#!/usr/bin/env node
// JR East Suigun Line i0, i17, i29, i34 interiors on the Apple Suigun glyph (end stations unchanged); display intervals [0, 17, 29, 34] only, aliases []; physical source and all other lines unchanged. (repair-04)
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
export const AUTHORITY_PATH = path.join(EV, 'proposals/jreast-suigun-20261022/jreast-suigun-i0-17-29-34-glyph-authority-v1.json');
const LINE = 'jp-東日本旅客鉄道-水郡線', KEY = 'jreast-suigun-i0-17-29-34-glyph-display', FORMAT = 'jtm-jreast-suigun-i0-17-29-34-glyph-authority-v1', REVIEW_FORMAT = 'jtm-jreast-suigun-i0-17-29-34-glyph-candidate-review-v1';
const STATIONS = ["002319", "002296", "001899", "001846", "001647", "001634", "001581", "001560"], INTERVALS = [0, 17, 29, 34];
const DISPLAY_INTERVALS = [0, 17, 29, 34], ALIASES = [];
const BASELINE_SHA = '67499bed5fd36d27f36f7cf135376bc163f33f999fb5adc8279e1e0969dfae74';
const CANDIDATE_SHA = 'd55584150b20bc7885797a6e4cd08a364431b0cec980ab23ea4dd3eecfdc404a';
const NATIVE_SHA = '52eb8354ef9ac6debff0387c0c8c49c67d922ed58010d327374425b3391ce0e7';
const BASE_POINTS = 2490, POINTS = 2652, PREFIX = 2, SUFFIX = 247;
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

function proposedLine(e) {
  assert.deepEqual([e.format, e.lineID, e.stationIDs, e.intervalIndices, e.nativePointCount, e.MainCertified, e.wholeLineAccepted],
    [FORMAT, LINE, STATIONS, INTERVALS, POINTS, false, false], 'authority scope changed');
  assert.equal(sha(e.baselineLine), BASELINE_SHA, 'baseline authority changed');
  assert.equal(sha(e.candidateLine), CANDIDATE_SHA, 'candidate authority changed');
  assert.equal(sha({nativeRows: e.baselineNativeRows, laneRows: e.baselineLaneRows}), NATIVE_SHA, 'baseline native authority changed');
  const before = e.baselineLine, after = e.candidateLine, reconstructed = structuredClone(before);
  reconstructed.displayIntervalCoordinates ??= {};
  for (const i of DISPLAY_INTERVALS) reconstructed.displayIntervalCoordinates[i] = structuredClone(after.displayIntervalCoordinates[i]);
  if (ALIASES.length) { reconstructed.displayStationCoordinates ??= {};
    for (const id of ALIASES) reconstructed.displayStationCoordinates[id] = structuredClone(after.displayStationCoordinates[id]); }
  assert.deepEqual(reconstructed, after, 'only the scoped display intervals/aliases may change');
  for (const [id, c] of Object.entries(before.displayStationCoordinates || {}))
    assert.deepEqual(after.displayStationCoordinates[id], c, 'preserved aliases changed');
  for (const [i, c] of Object.entries(before.displayIntervalCoordinates || {})) if (!DISPLAY_INTERVALS.includes(+i))
    assert.deepEqual(after.displayIntervalCoordinates[i], c, 'preserved display intervals changed');
  const physical = l => Object.fromEntries(Object.entries(l).filter(([k]) => k !== 'displayIntervalCoordinates' && k !== 'displayStationCoordinates'));
  assert.deepEqual(physical(after), physical(before), 'non-display fields changed');
  assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before), 'physical source changed');
  const oldParts = net.displayPartsForLine(before), parts = net.displayPartsForLine(after);
  assert.equal(oldParts.length, 1); assert.equal(oldParts[0].length, BASE_POINTS);
  assert.equal(parts.length, 1); assert.equal(parts[0].length, POINTS);
  assert.deepEqual(parts[0].slice(0, PREFIX), oldParts[0].slice(0, PREFIX), 'outer public prefix changed');
  if (SUFFIX > 0) assert.deepEqual(parts[0].slice(-SUFFIX), oldParts[0].slice(-SUFFIX), 'outer public suffix changed');
  return structuredClone(after);
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), own = input.lines.filter(l => l.id === LINE);
  assert.equal(own.length, 1, 'own line missing/duplicated');
  assert(equal(own[0], e.baselineLine) || equal(own[0], line), 'stale own package baseline');
  const result = structuredClone(input);
  result.lines = result.lines.map(l => l.id === LINE ? line : l);
  const provenance = {lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
    evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
    status: 'bounded-suigun; all end stations are boundaries (N02 collars)', wholeLineAccepted: false, MainCertified: false};
  result.geometrySource ??= {}; result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'provenance changed');
  result.geometrySource.manualOverrides[KEY] = provenance;
  return result;
}

export function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
  const ownLines = pkg.lines.filter(l => l.id === LINE);
  assert.equal(ownLines.length, 1, 'candidate line missing/duplicated');
  const line = ownLines[0]; assert.deepEqual(line, proposedLine(e));
  const parts = net.displayPartsForLine(line), rows = partRowsForLine(line, parts, null, null);
  assert.equal(rows.length, 1); assert.equal(rows[0][4], POINTS); assert.deepEqual(rows[0][7], parts[0]);
  const own = input.partsByRegion?.jp?.filter(r => r[0] === LINE);
  assert.equal(own?.length, 1, 'own native row missing/duplicated');
  assert(equal(own, e.baselineNativeRows) || equal(own, rows), 'stale/foreign own native row');
  // A whole-line lane row [LINE, 0, 0, lengthMetres, offset] follows the new public length; anything else needs review.
  const baseLanes = e.baselineLaneRows, lanes = baseLanes.map(r => [r[0], r[1], r[2], rows[0][5], r[4]]);
  assert(baseLanes.length <= 1 && baseLanes.every(r => r[1] === 0 && r[2] === 0 && r[3] === e.baselineNativeRows[0][5]), 'partial lane rows require review');
  const ownLanes = (input.byRegion?.jp || []).filter(r => r[0] === LINE);
  assert(equal(ownLanes, baseLanes) || equal(ownLanes, lanes), 'stale/foreign own lane row');
  for (const [key, value] of Object.entries(input)) if (key !== 'partsByRegion' && key !== 'byRegion')
    assert(!JSON.stringify(value)?.includes(LINE), 'own native reference requires review: ' + key);
  for (const [region, values] of Object.entries(input.byRegion || {})) if (region !== 'jp')
    assert(!JSON.stringify(values).includes(LINE), 'foreign-region own lane reference');
  for (const [region, values] of Object.entries(input.partsByRegion || {})) if (region !== 'jp')
    assert(!JSON.stringify(values).includes(LINE), 'foreign-region own reference');
  assert(!(input.excludedOperators || []).includes(line.operator), 'operator excluded');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(r => r[0] === LINE ? rows[0] : r);
  if (lanes.length) result.byRegion.jp = result.byRegion.jp.map(r => r[0] === LINE ? lanes[0] : r);
  return result;
}

export function validateCandidateReview(receipt, line) {
  assert(receipt, 'scoped candidate-review receipt required before --apply');
  assert.deepEqual([receipt.format, receipt.status, receipt.lineID, receipt.stationIDs,
    receipt.intervalIndices, receipt.MainCertified, receipt.wholeLineAccepted],
  [REVIEW_FORMAT, 'bounded-candidate-reviewed', LINE, STATIONS, INTERVALS, false, false], 'review scope changed');
  assert.equal(receipt.reviewedOwnLineSha256, CANDIDATE_SHA, 'reviewed candidate changed');
  assert.equal(receipt.reviewedOwnLineSha256, sha(line), 'reviewed own line changed');
}

function main(args) {
  assert(args.length === 3 && args[0] === '--apply' && args[1] === '--candidate-review',
    'Use --apply --candidate-review <canonical evidence receipt.json>');
  const receiptPath = path.resolve(args[2]); assertAllowedCandidateFile(receiptPath);
  assert(fs.realpathSync(receiptPath).startsWith(fs.realpathSync(EV) + path.sep), 'receipt must use canonical local evidence');
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
    'scripts/railway/repair-jreast-suigun-i0-17-29-34-glyph-display.mjs'].map(p => snapshot(path.join(APP, p)));
  applyPreparedWrites(writes, [...Object.values(inputs), authority, receipt, ...implementation]);
  console.log(JSON.stringify({mode: 'applied', lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
    nativeRows: lanes.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r.slice(0, 7)),
    wholeLineAccepted: false, MainCertified: false}));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
