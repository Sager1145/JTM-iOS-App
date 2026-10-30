#!/usr/bin/env node
// Odakyu Tama v11: Haruhino on the eastern own-track hidden extension through the platform; display intervals [2,3] and alias 004141 only. (ext3)
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
export const AUTHORITY_PATH = path.join(EV, 'proposals/ext3-20261022/tama/refined-v11/odakyu-tama-haruhino-v11-authority-v1.json');
const LINE = 'jp-小田急電鉄-多摩線';
const KEY = 'odakyu-tama-haruhino-v11-display';
const FORMAT = 'jtm-odakyu-tama-haruhino-v11-authority-v1';
const REVIEW_FORMAT = 'jtm-odakyu-tama-haruhino-v11-candidate-review-v1';
const STATIONS = ['004090', '004141', '004168'], INTERVALS = [2, 3];
const DISPLAY_INTERVALS = [2, 3], ALIASES = ['004141'];
const BASELINE_SHA = '12ad9402b0becadcf802a3fccdbb886918bdc828a68a2b58a9df8eb9410c9ec0';
const CANDIDATE_SHA = '0167fe5b9374abac21e7cbc16e35c997aa4b23392c8f349779aea1293b62f15b';
const NATIVE_SHA = '199f6e3e11f04059e97b7ee5c8f3163a7b6726ff544d316ec89a5bd209c94d23';
const BASE_POINTS = 155, POINTS = 184, PREFIX = 50, SUFFIX = 57;
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = file => JSON.parse(fs.readFileSync(file));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

function proposedLine(e) {
  assert.deepEqual(
    [e.format, e.lineID, e.stationIDs, e.intervalIndices, e.nativePointCount, e.MainCertified, e.wholeLineAccepted],
    [FORMAT, LINE, STATIONS, INTERVALS, POINTS, false, false],
    'authority scope changed',
  );
  assert.equal(sha(e.baselineLine), BASELINE_SHA, 'baseline authority changed');
  assert.equal(sha(e.candidateLine), CANDIDATE_SHA, 'candidate authority changed');
  assert.equal(sha({nativeRows: e.baselineNativeRows, laneRows: e.baselineLaneRows}), NATIVE_SHA, 'baseline native authority changed');
  const before = e.baselineLine, after = e.candidateLine, reconstructed = structuredClone(before);
  reconstructed.displayIntervalCoordinates ??= {};
  for (const index of DISPLAY_INTERVALS)
    reconstructed.displayIntervalCoordinates[index] = structuredClone(after.displayIntervalCoordinates[index]);
  reconstructed.displayStationCoordinates ??= {};
  for (const stationID of ALIASES)
    reconstructed.displayStationCoordinates[stationID] = structuredClone(after.displayStationCoordinates[stationID]);
  assert.deepEqual(reconstructed, after, 'only the scoped display intervals/alias may change');
  for (const [stationID, coordinate] of Object.entries(before.displayStationCoordinates || {}))
    if (!ALIASES.includes(stationID)) assert.deepEqual(after.displayStationCoordinates[stationID], coordinate, 'preserved alias changed');
  for (const [index, coordinates] of Object.entries(before.displayIntervalCoordinates || {}))
    if (!DISPLAY_INTERVALS.includes(+index)) assert.deepEqual(after.displayIntervalCoordinates[index], coordinates, 'preserved display interval changed');
  const physical = line => Object.fromEntries(Object.entries(line).filter(([key]) => key !== 'displayIntervalCoordinates' && key !== 'displayStationCoordinates'));
  assert.deepEqual(physical(after), physical(before), 'non-display fields changed');
  assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before), 'physical source changed');
  const oldParts = net.displayPartsForLine(before), parts = net.displayPartsForLine(after);
  assert.equal(oldParts.length, 1);
  assert.equal(oldParts[0].length, BASE_POINTS);
  assert.equal(parts.length, 1);
  assert.equal(parts[0].length, POINTS);
  assert.deepEqual(parts[0].slice(0, PREFIX), oldParts[0].slice(0, PREFIX), 'outer public prefix changed');
  assert.deepEqual(parts[0].slice(-SUFFIX), oldParts[0].slice(-SUFFIX), 'outer public suffix changed');
  return structuredClone(after);
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), own = input.lines.filter(item => item.id === LINE);
  assert.equal(own.length, 1, 'own line missing/duplicated');
  assert(equal(own[0], e.baselineLine) || equal(own[0], line), 'stale own package baseline');
  const result = structuredClone(input);
  result.lines = result.lines.map(item => item.id === LINE ? line : item);
  const provenance = {
    lineID: LINE,
    stationIDs: STATIONS,
    intervalIndices: INTERVALS,
    evidence: path.relative(REPO, AUTHORITY_PATH),
    physicalTopologyChanged: false,
    status: 'bounded-tama-i2-i3-haruhino-hidden-extension',
    wholeLineAccepted: false,
    MainCertified: false,
  };
  result.geometrySource ??= {};
  result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'provenance changed');
  result.geometrySource.manualOverrides[KEY] = provenance;
  return result;
}

export function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
  const ownLines = pkg.lines.filter(line => line.id === LINE);
  assert.equal(ownLines.length, 1, 'candidate line missing/duplicated');
  const line = ownLines[0];
  assert.deepEqual(line, proposedLine(e));
  const parts = net.displayPartsForLine(line), rows = partRowsForLine(line, parts, null, null);
  assert.equal(rows.length, 1);
  assert.equal(rows[0][4], POINTS);
  assert.deepEqual(rows[0][7], parts[0]);
  const own = input.partsByRegion?.jp?.filter(row => row[0] === LINE);
  assert.equal(own?.length, 1, 'own native row missing/duplicated');
  assert(equal(own, e.baselineNativeRows) || equal(own, rows), 'stale/foreign own native row');
  const baseLanes = e.baselineLaneRows;
  const lanes = baseLanes.map(row => [row[0], row[1], row[2], rows[0][5], row[4]]);
  assert(baseLanes.length <= 1 && baseLanes.every(row => row[1] === 0 && row[2] === 0 && row[3] === e.baselineNativeRows[0][5]), 'partial lane rows require review');
  const ownLanes = (input.byRegion?.jp || []).filter(row => row[0] === LINE);
  assert(equal(ownLanes, baseLanes) || equal(ownLanes, lanes), 'stale/foreign own lane row');
  for (const [key, value] of Object.entries(input)) if (key !== 'partsByRegion' && key !== 'byRegion')
    assert(!JSON.stringify(value)?.includes(LINE), 'own native reference requires review: ' + key);
  for (const [region, values] of Object.entries(input.byRegion || {})) if (region !== 'jp')
    assert(!JSON.stringify(values).includes(LINE), 'foreign-region own lane reference');
  for (const [region, values] of Object.entries(input.partsByRegion || {})) if (region !== 'jp')
    assert(!JSON.stringify(values).includes(LINE), 'foreign-region own reference');
  assert(!(input.excludedOperators || []).includes(line.operator), 'operator excluded');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(row => row[0] === LINE ? rows[0] : row);
  if (lanes.length) result.byRegion.jp = result.byRegion.jp.map(row => row[0] === LINE ? lanes[0] : row);
  return result;
}

export function validateCandidateReview(receipt, line) {
  assert(receipt, 'scoped candidate-review receipt required before --apply');
  assert.deepEqual(
    [receipt.format, receipt.status, receipt.lineID, receipt.stationIDs, receipt.intervalIndices, receipt.MainCertified, receipt.wholeLineAccepted],
    [REVIEW_FORMAT, 'bounded-candidate-reviewed', LINE, STATIONS, INTERVALS, false, false],
    'review scope changed',
  );
  assert.equal(receipt.reviewedOwnLineSha256, CANDIDATE_SHA, 'reviewed candidate changed');
  assert.equal(receipt.reviewedOwnLineSha256, sha(line), 'reviewed own line changed');
}

function main(args) {
  assert(args.length === 3 && args[0] === '--apply' && args[1] === '--candidate-review', 'Use --apply --candidate-review <canonical evidence receipt.json>');
  const receiptPath = path.resolve(args[2]);
  assertAllowedCandidateFile(receiptPath);
  assert(fs.realpathSync(receiptPath).startsWith(fs.realpathSync(EV) + path.sep), 'receipt must use canonical local evidence');
  const snapshot = file => ({path: file, before: fs.readFileSync(file)});
  const authority = snapshot(AUTHORITY_PATH), receipt = snapshot(receiptPath), e = JSON.parse(authority.before);
  const paths = {package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json', ...DEPENDENCY_PATHS};
  const inputs = Object.fromEntries(Object.entries(paths).map(([key, relative]) => [key, snapshot(path.join(APP, relative))]));
  const load = key => JSON.parse(inputs[key].before), pkg = repairPackage(load('package'), e);
  validateCandidateReview(JSON.parse(receipt.before), pkg.lines.find(line => line.id === LINE));
  const lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  const outputs = {
    package: JSON.stringify(pkg),
    lanes: JSON.stringify(lanes) + '\n',
    ...Object.fromEntries(Object.entries(dependencies).map(([key, value]) => [key, JSON.stringify(value, null, 2) + '\n'])),
  };
  const writes = Object.entries(outputs).map(([key, after]) => ({...inputs[key], after: Buffer.from(after)}));
  const implementation = [
    'public/rail-network.js',
    'scripts/railway/build-display-lanes.mjs',
    'scripts/railway/repair-three-reversal-extents.mjs',
    'scripts/railway/local-evidence-path.mjs',
    'scripts/railway/repair-odakyu-tama-haruhino-v11-display.mjs',
  ].map(relative => snapshot(path.join(APP, relative)));
  applyPreparedWrites(writes, [...Object.values(inputs), authority, receipt, ...implementation]);
  console.log(JSON.stringify({
    mode: 'applied',
    lineID: LINE,
    stationIDs: STATIONS,
    intervalIndices: INTERVALS,
    nativeRows: lanes.partsByRegion.jp.filter(row => row[0] === LINE).map(row => row.slice(0, 7)),
    wholeLineAccepted: false,
    MainCertified: false,
  }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
