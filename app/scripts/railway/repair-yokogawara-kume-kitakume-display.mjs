#!/usr/bin/env node
// Bounded manual display authority. Physical stations, topology and mileage stay intact.
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
export const AUTHORITY_PATH = path.join(EV, 'proposals/iyotetsu-yokogawara-remainder-20261020/bounded-kume-kitakume-visible-track-authority-v2.json');
const LINE = 'jp-伊予鉄道-横河原線', KEY = 'yokogawara-kume-kitakume-display';
const STATIONS = ['008801', '008795'], INTERVALS = [8, 9, 10];
const BASELINE_SHA = 'ccf1511ff43c72ebe0fd6cb09a2318ddeac71e212dd73323cda2a0a0f58d579c';
const CANDIDATE_SHA = '705a70292f0be4afeea0d5686112b3218d23f1c153a0651ac13848eaf3412c02';
const NATIVE_SHA = '62437f152fe7fe1a9b2927cd3ff6e88011f05e67f501dbe3c06f4d634c9455c4';
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(value).digest('hex');
const ownSha = line => sha(JSON.stringify(line));

function proposedLine(e) {
  assert.deepEqual([e.format, e.lineID, e.stationIDs, e.intervalIndices,
    e.protectedPrefixCount, e.protectedSuffixCount, e.fullPassengerCapsCertified, e.MainCertified],
  ['jtm-yokogawara-kume-kitakume-visible-track-authority-v2', LINE, STATIONS, INTERVALS, 118, 34, false, false],
  'Yokogawara bounded authority scope changed');
  assert.equal(ownSha(e.baselineLine), BASELINE_SHA, 'Yokogawara baseline authority changed');
  assert.equal(ownSha(e.candidateLine), CANDIDATE_SHA, 'Yokogawara Kume-Kitakume candidate authority changed');
  assert.equal(ownSha(e.baselineNativeRows), NATIVE_SHA, 'Yokogawara baseline native authority changed');
  const before = e.baselineLine, after = e.candidateLine;
  // Ordered literal controls reconstruct the two station approaches. The outgoing
  // interval10 retains its physical remainder after the short Kitakume collar.
  const reconstructed = structuredClone(before), ll = s => s.longitudeLatitude;
  const station = id => e.stationControls.find(s => s.id === id);
  const kume = ll(station('kume-alias')), kitakume = ll(station('kitakume-independent-alias'));
  assert.equal(e.controls8.length, 8); assert.equal(e.controls9.length, 7);
  assert.equal(e.curveRefinements.length, 6); assert.equal(e.stationControls.length, 6);
  reconstructed.displayStationCoordinates[STATIONS[0]] = kume;
  reconstructed.displayStationCoordinates[STATIONS[1]] = kitakume;
  reconstructed.displayIntervalCoordinates[8] = [before.displayStationCoordinates['008802'],
    before.displayIntervalCoordinates[8][1], ...e.controls8.map(ll),
    ...e.curveRefinements.filter(s => s.id.includes('-SE-')).slice().reverse().map(ll),
    ll(e.additionalNortheastStationBranchWitness), ll(station('kume-southeast-flank')), kume];
  reconstructed.displayIntervalCoordinates[9] = [kume, ll(station('kume-northwest-flank')),
    ...e.curveRefinements.filter(s => s.id.includes('-NW-')).map(ll), ...e.controls9.map(ll),
    ll(station('kitakume-independent-east-flank')), kitakume];
  reconstructed.displayIntervalCoordinates[10] = [kitakume,
    ll(station('kitakume-independent-west-flank')), ...net.decodeIntervals(before)[10].slice(1)];
  assert.deepEqual(reconstructed, after, 'Kume-Kitakume ordered authority reconstruction changed');
  for (const support of [...e.controls8, ...e.controls9, ...e.curveRefinements,
    ...e.stationControls, e.additionalNortheastStationBranchWitness]) {
    const view = e.views[support.viewPath];
    assert(view && view.lineID === LINE && view.camera.heading === 0 && view.camera.pitch === 0);
    const q = view.snapshotProjection, W = 2 ** 28, R = Math.PI / 180;
    assert(q?.displayScale === 1 && q.widthPoints === 2400 && q.heightPoints === 2000);
    assert(q.mapPointsPerPointX > 0 && q.mapPointsPerPointY > 0);
    const center = [(view.camera.longitude + 180) / 360 * W,
      (1 - Math.asinh(Math.tan(view.camera.latitude * R)) / Math.PI) / 2 * W];
    const x = center[0] + (support.pixel[0] - q.centerXPoints) * q.mapPointsPerPointX;
    const y = center[1] + (support.pixel[1] - q.centerYPoints) * q.mapPointsPerPointY;
    const coordinate = [x / W * 360 - 180, Math.atan(Math.sinh(Math.PI * (1 - 2 * y / W))) / R];
    assert(support.longitudeLatitude.every((v, i) => Math.abs(v - coordinate[i]) < 1e-10),
      'Actual per-axis snapshot projection disagrees with manual support');
  }
  const physicalFields = line => Object.fromEntries(Object.entries(line).filter(([k]) =>
    !['displayStationCoordinates', 'displayIntervalCoordinates'].includes(k)));
  assert.deepEqual(physicalFields(after), physicalFields(before), 'Yokogawara physical fields changed');
  assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before), 'Yokogawara physical decode changed');
  assert.equal(Object.keys(before.displayStationCoordinates).length, 8, 'Expected eight preserved aliases');
  assert.equal(before.displayIntervalCoordinates[9], undefined);
  assert.equal(before.displayIntervalCoordinates[10], undefined);
  assert.deepEqual(Object.keys(after.displayStationCoordinates).sort(),
    [...Object.keys(before.displayStationCoordinates), ...STATIONS].sort());
  for (const [id, coordinate] of Object.entries(before.displayStationCoordinates))
    assert.deepEqual(after.displayStationCoordinates[id], coordinate, 'Previously reviewed alias changed: ' + id);
  assert.deepEqual(Object.keys(after.displayIntervalCoordinates), Array.from({length: 11}, (_, i) => String(i)));
  for (let i = 0; i < 8; i++)
    assert.deepEqual(after.displayIntervalCoordinates[i], before.displayIntervalCoordinates[i]);
  for (const id of STATIONS) {
    const i = after.stations.findIndex(s => s[0] === id);
    assert(i > 0 && i < after.stations.length - 1);
    assert.deepEqual(after.displayIntervalCoordinates[i - 1].at(-1), after.displayStationCoordinates[id]);
    assert.deepEqual(after.displayIntervalCoordinates[i][0], after.displayStationCoordinates[id]);
  }
  const oldParts = net.displayPartsForLine(before), newParts = net.displayPartsForLine(after);
  assert.equal(oldParts.length, 1); assert.equal(newParts.length, 1);
  assert.equal(newParts[0].length, 198, 'Yokogawara whole public display point count changed');
  assert.deepEqual(newParts[0].slice(0, 118), oldParts[0].slice(0, 118), 'Yokogawara outer prefix changed');
  assert.deepEqual(newParts[0].slice(-34), oldParts[0].slice(-34), 'Yokogawara retained western suffix changed');
  assert.deepEqual(after.displayIntervalCoordinates[8].slice(0, 2), before.displayIntervalCoordinates[8].slice(0, 2));
  assert.deepEqual(after.displayIntervalCoordinates[10].slice(2), net.decodeIntervals(before)[10].slice(1));
  // Retained outer geometry is an unchanged boundary, not an aligned guard.
  // Label-covered centres are reference-assisted. Full caps and Kitakume west
  // beyond the short collar remain open.
  return structuredClone(after);
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), own = input.lines.filter(l => l.id === LINE);
  assert.equal(own.length, 1, 'Yokogawara own line missing/duplicated');
  assert(equal(own[0], e.baselineLine) || equal(own[0], line), 'Yokogawara stale own package baseline');
  const result = structuredClone(input);
  result.lines = result.lines.map(l => l.id === LINE ? line : l);
  const provenance = {lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
    evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
    status: 'bounded-kume-kitakume-display-repair; interval10-remainder-and-full-passenger-caps-open',
    wholeLineAccepted: false, MainCertified: false};
  result.geometrySource ??= {};
  result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Yokogawara provenance changed');
  result.geometrySource.manualOverrides[KEY] = provenance;
  return result;
}

export function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
  const ownLines = pkg.lines.filter(l => l.id === LINE);
  assert.equal(ownLines.length, 1, 'Yokogawara candidate line missing/duplicated');
  const line = ownLines[0];
  assert.deepEqual(line, proposedLine(e));
  const rows = partRowsForLine(line, net.displayPartsForLine(line), null, null);
  assert.equal(rows.length, 1, 'Yokogawara own native fallback must remain one row');
  assert.equal(rows[0][4], 198); assert.deepEqual(rows[0][7], net.displayPartsForLine(line)[0]);
  const own = input.partsByRegion?.jp?.filter(r => r[0] === LINE);
  assert(equal(own, e.baselineNativeRows) || equal(own, rows), 'Yokogawara stale/foreign own native row');
  // Current own line has no active lanes, follows, windows or hub references.
  // Preserve other Iyotetsu tram aliases, branch lead-ins and unrelated native maps.
  for (const [key, value] of Object.entries(input)) if (key !== 'partsByRegion')
    assert(!JSON.stringify(value)?.includes(LINE), 'Yokogawara own native reference requires review: ' + key);
  for (const [region, rs] of Object.entries(input.partsByRegion || {})) if (region !== 'jp')
    assert(!JSON.stringify(rs).includes(LINE), 'Yokogawara foreign-region own reference');
  assert(!(input.excludedOperators || []).includes(line.operator), 'Yokogawara operator excluded');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(r => r[0] === LINE ? rows[0] : r);
  return result;
}

export function validateCandidateReview(receipt, line) {
  assert(receipt, 'Yokogawara scoped candidate-review receipt required before --apply');
  assert.deepEqual([receipt.format, receipt.status, receipt.lineID, receipt.stationIDs,
    receipt.intervalIndices, receipt.MainCertified, receipt.wholeLineAccepted],
  ['jtm-yokogawara-kume-kitakume-candidate-review-v1', 'bounded-candidate-reviewed', LINE,
    STATIONS, INTERVALS, false, false], 'Yokogawara candidate-review scope changed');
  assert.equal(receipt.reviewedOwnLineSha256, CANDIDATE_SHA, 'Yokogawara reviewed authority changed');
  assert.equal(receipt.reviewedOwnLineSha256, ownSha(line), 'Yokogawara reviewed own line changed');
}

function main(args) {
  assert(args.length === 3 && args[0] === '--apply' && args[1] === '--candidate-review',
    'Use --apply --candidate-review <canonical evidence receipt.json>');
  const receiptPath = path.resolve(args[2]);
  assertAllowedCandidateFile(receiptPath);
  assert(fs.realpathSync(receiptPath).startsWith(fs.realpathSync(EV) + path.sep),
    'Yokogawara receipt must use canonical local evidence');
  const snapshot = p => ({path: p, before: fs.readFileSync(p)});
  const authority = snapshot(AUTHORITY_PATH), receipt = snapshot(receiptPath);
  const e = JSON.parse(authority.before);
  const paths = {package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json', ...DEPENDENCY_PATHS};
  const inputs = Object.fromEntries(Object.entries(paths).map(([k, p]) => [k, snapshot(path.join(APP, p))]));
  const load = k => JSON.parse(inputs[k].before);
  const pkg = repairPackage(load('package'), e);
  validateCandidateReview(JSON.parse(receipt.before), pkg.lines.find(l => l.id === LINE));
  const lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k => [k, load(k)])));
  const outputs = {package: JSON.stringify(pkg), lanes: JSON.stringify(lanes) + '\n',
    ...Object.fromEntries(Object.entries(dependencies).map(([k, v]) => [k, JSON.stringify(v, null, 2) + '\n']))};
  const writes = Object.entries(outputs).map(([k, after]) => ({...inputs[k], after: Buffer.from(after)}));
  const implementation = ['public/rail-network.js', 'scripts/railway/build-display-lanes.mjs',
    'scripts/railway/repair-three-reversal-extents.mjs', 'scripts/railway/local-evidence-path.mjs',
    'scripts/railway/repair-yokogawara-kume-kitakume-display.mjs'].map(p => snapshot(path.join(APP, p)));
  applyPreparedWrites(writes, [...Object.values(inputs), authority, receipt, ...implementation]);
  console.log(JSON.stringify({mode: 'applied', lineID: LINE, stationIDs: STATIONS,
    intervalIndices: INTERVALS, nativeRows: lanes.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r.slice(0, 7)),
    fullPassengerCapsCertified: false, outerBoundariesCertified: false,
    wholeLineAccepted: false, MainCertified: false}));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
