#!/usr/bin/env node
// Two close Kume display collars; preserve the previous repair and all aliases.
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
export const AUTHORITY_PATH = path.join(EV,
  'proposals/iyotetsu-yokogawara-remainder-20261020/bounded-kume-approach-collars-authority-v3.json');
const LINE = 'jp-伊予鉄道-横河原線', KEY = 'yokogawara-kume-approach-collars';
const STATIONS = ['008801'], INTERVALS = [8, 9];
const BASELINE_SHA = '705a70292f0be4afeea0d5686112b3218d23f1c153a0651ac13848eaf3412c02';
const CANDIDATE_SHA = '7c65c00371857dcbe2343d4c2a3f8adb48f0827357c872b1bc6b6180e4efc83c';
const NATIVE_SHA = 'ce28a1d2ab65c55183d13cc1e6fbf88492ef304409591c70f6ec909c3ae8749b';
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

function proposedLine(e) {
  assert.deepEqual([e.format, e.lineID, e.stationIDs, e.intervalIndices,
    e.nativePointCount, e.MainCertified, e.wholeLineAccepted],
  ['jtm-yokogawara-kume-approach-collars-authority-v3', LINE, STATIONS, INTERVALS, 182, false, false],
  'Kume close-collar authority scope changed');
  assert.equal(sha(e.baselineLine), BASELINE_SHA, 'Kume baseline198 authority changed');
  assert.equal(sha(e.candidateLine), CANDIDATE_SHA, 'Kume candidate182 authority changed');
  assert.equal(sha(e.baselineNativeRows), NATIVE_SHA, 'Kume baseline198 native authority changed');
  assert.equal(e.closeControls.length, 2, 'Expected only two close collars');
  const pick = id => e.closeControls.find(c => c.id === id);
  const se = pick('kume-close-southeast-flank'), nw = pick('kume-close-northwest-flank');
  assert(se && nw, 'Kume close-collar identities changed');
  assert.deepEqual(se.pixel, [1220, 1022.5]);
  assert.deepEqual(nw.pixel, [1180, 982]);
  const before = e.baselineLine, after = e.candidateLine;
  for (const support of [se, nw]) {
    const view = e.views[support.viewPath], q = view?.snapshotProjection;
    assert(view?.lineID === LINE && view.camera.heading === 0 && view.camera.pitch === 0,
      'Kume collar projection view changed');
    assert(q?.displayScale === 1 && q.widthPoints === 2400 && q.heightPoints === 2000);
    assert(Math.abs(q.mapPointsPerPointX - 2) < 1e-10 && Math.abs(q.mapPointsPerPointY - 2) < 1e-10,
      'Kume close collars require the actual fresh q2 projection');
    assert.deepEqual([view.camera.longitude, view.camera.latitude], before.displayStationCoordinates['008801'],
      'Kume projection must be centred on the preserved display alias');
    const W = 2 ** 28, R = Math.PI / 180;
    const centre = [(view.camera.longitude + 180) / 360 * W,
      (1 - Math.asinh(Math.tan(view.camera.latitude * R)) / Math.PI) / 2 * W];
    const x = centre[0] + (support.pixel[0] - q.centerXPoints) * q.mapPointsPerPointX;
    const y = centre[1] + (support.pixel[1] - q.centerYPoints) * q.mapPointsPerPointY;
    const coordinate = [x / W * 360 - 180, Math.atan(Math.sinh(Math.PI * (1 - 2 * y / W))) / R];
    assert(support.longitudeLatitude.every((v, i) => Math.abs(v - coordinate[i]) < 1e-10),
      'Kume manual collar disagrees with actual snapshot projection');
  }
  const reconstructed = structuredClone(before);
  reconstructed.displayIntervalCoordinates[8].splice(-1, 0, se.longitudeLatitude);
  reconstructed.displayIntervalCoordinates[9].splice(1, 0, nw.longitudeLatitude);
  assert.deepEqual(reconstructed, after, 'Only the two ordered close-collar insertions are permitted');
  assert.equal(Object.keys(before.displayStationCoordinates).length, 10);
  assert.deepEqual(after.displayStationCoordinates, before.displayStationCoordinates, 'Preserved aliases changed');
  const physical = l => Object.fromEntries(Object.entries(l).filter(([k]) => k !== 'displayIntervalCoordinates'));
  assert.deepEqual(physical(after), physical(before), 'Kume non-interval fields changed');
  assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before), 'Physical source changed');
  for (let i = 0; i < 14; i++) if (!INTERVALS.includes(i))
    assert.deepEqual(after.displayIntervalCoordinates[i], before.displayIntervalCoordinates[i]);
  for (const i of INTERVALS) {
    const coordinates = after.displayIntervalCoordinates[i];
    for (let j = 1; j < coordinates.length; j++)
      assert(coordinates[j][0] < coordinates[j - 1][0], 'Kume collar introduced eastward backtracking');
  }
  const oldParts = net.displayPartsForLine(before), parts = net.displayPartsForLine(after);
  assert.equal(oldParts.length, 1); assert.equal(oldParts[0].length, 198);
  assert.equal(parts.length, 1); assert.equal(parts[0].length, 182);
  assert.deepEqual(parts[0].slice(0, 124), oldParts[0].slice(0, 124), 'Outer public prefix changed');
  assert.deepEqual(parts[0].slice(-42), oldParts[0].slice(-42), 'Outer public suffix changed');
  return structuredClone(after);
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), own = input.lines.filter(l => l.id === LINE);
  assert.equal(own.length, 1, 'Kume own line missing/duplicated');
  assert(equal(own[0], e.baselineLine) || equal(own[0], line), 'Kume stale own package baseline');
  const result = structuredClone(input);
  result.lines = result.lines.map(l => l.id === LINE ? line : l);
  const provenance = {lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
    evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
    status: 'bounded-kume-close-approach-collars; full-passenger-caps-open',
    wholeLineAccepted: false, MainCertified: false};
  result.geometrySource ??= {}; result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Kume close-collar provenance changed');
  result.geometrySource.manualOverrides[KEY] = provenance;
  return result;
}

export function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
  const ownLines = pkg.lines.filter(l => l.id === LINE);
  assert.equal(ownLines.length, 1, 'Kume candidate line missing/duplicated');
  const line = ownLines[0]; assert.deepEqual(line, proposedLine(e));
  const parts = net.displayPartsForLine(line), rows = partRowsForLine(line, parts, null, null);
  assert.equal(rows.length, 1); assert.equal(rows[0][4], 182); assert.deepEqual(rows[0][7], parts[0]);
  const own = input.partsByRegion?.jp?.filter(r => r[0] === LINE);
  assert.equal(own?.length, 1, 'Kume own native row missing/duplicated');
  assert(equal(own, e.baselineNativeRows) || equal(own, rows), 'Kume stale/foreign own native row');
  for (const [key, value] of Object.entries(input)) if (key !== 'partsByRegion')
    assert(!JSON.stringify(value)?.includes(LINE), 'Kume own native reference requires review: ' + key);
  for (const [region, values] of Object.entries(input.partsByRegion || {})) if (region !== 'jp')
    assert(!JSON.stringify(values).includes(LINE), 'Kume foreign-region own reference');
  assert(!(input.excludedOperators || []).includes(line.operator), 'Kume operator excluded');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(r => r[0] === LINE ? rows[0] : r);
  return result;
}

export function validateCandidateReview(receipt, line) {
  assert(receipt, 'Kume scoped candidate-review receipt required before --apply');
  assert.deepEqual([receipt.format, receipt.status, receipt.lineID, receipt.stationIDs,
    receipt.intervalIndices, receipt.MainCertified, receipt.wholeLineAccepted],
  ['jtm-yokogawara-kume-approach-collars-candidate-review-v1', 'bounded-candidate-reviewed',
    LINE, STATIONS, INTERVALS, false, false], 'Kume close-collar review scope changed');
  assert.equal(receipt.reviewedOwnLineSha256, CANDIDATE_SHA, 'Kume reviewed candidate changed');
  assert.equal(receipt.reviewedOwnLineSha256, sha(line), 'Kume reviewed own line changed');
}

function main(args) {
  assert(args.length === 3 && args[0] === '--apply' && args[1] === '--candidate-review',
    'Use --apply --candidate-review <canonical evidence receipt.json>');
  const receiptPath = path.resolve(args[2]); assertAllowedCandidateFile(receiptPath);
  assert(fs.realpathSync(receiptPath).startsWith(fs.realpathSync(EV) + path.sep),
    'Kume receipt must use canonical local evidence');
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
    'scripts/railway/repair-yokogawara-kume-approach-collars.mjs'].map(p => snapshot(path.join(APP, p)));
  applyPreparedWrites(writes, [...Object.values(inputs), authority, receipt, ...implementation]);
  console.log(JSON.stringify({mode: 'applied', lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
    nativeRows: lanes.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r.slice(0, 7)),
    fullPassengerCapsCertified: false, wholeLineAccepted: false, MainCertified: false}));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
