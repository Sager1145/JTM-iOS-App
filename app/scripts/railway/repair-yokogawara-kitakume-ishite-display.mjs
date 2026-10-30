#!/usr/bin/env node
// Kitakume-Fukuonji-Iyotachibana-Ishitegawa display intervals 10-12; preserve prior repairs and all other aliases.
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
  'proposals/iyotetsu-yokogawara-remainder-20261020/bounded-kitakume-ishite-authority-v5.json');
const LINE = 'jp-伊予鉄道-横河原線', KEY = 'yokogawara-kitakume-ishite-display';
const STATIONS = ['008791', '008784', '008780'], INTERVALS = [10, 11, 12, 13];
const DISPLAY_INTERVALS = [10, 11, 12];
const BASELINE_SHA = '7c65c00371857dcbe2343d4c2a3f8adb48f0827357c872b1bc6b6180e4efc83c';
const CANDIDATE_SHA = '29b1ddd2594df8cb3efb3ed8e156612b5c2ea1080516cbf148936eb2b168a766';
const NATIVE_SHA = 'ab68e6d16d2d03637c0dbfa5e750c27a4c6640f041f6384c80293f657fe53330';
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

function proposedLine(e) {
  assert.deepEqual([e.format, e.lineID, e.stationIDs, e.intervalIndices,
    e.nativePointCount, e.MainCertified, e.wholeLineAccepted],
  ['jtm-yokogawara-kitakume-ishite-authority-v5', LINE, STATIONS, INTERVALS, 206, false, false],
  'Kitakume-Ishite authority scope changed');
  assert.equal(sha(e.baselineLine), BASELINE_SHA, 'Kitakume-Ishite baseline182 authority changed');
  assert.equal(sha(e.candidateLine), CANDIDATE_SHA, 'Kitakume-Ishite candidate206 authority changed');
  assert.equal(sha(e.baselineNativeRows), NATIVE_SHA, 'Kitakume-Ishite baseline182 native authority changed');
  const before = e.baselineLine, after = e.candidateLine;
  const reconstructed = structuredClone(before);
  for (const i of DISPLAY_INTERVALS) reconstructed.displayIntervalCoordinates[i] = structuredClone(after.displayIntervalCoordinates[i]);
  for (const id of STATIONS) reconstructed.displayStationCoordinates[id] = structuredClone(after.displayStationCoordinates[id]);
  assert.deepEqual(reconstructed, after, 'Only display intervals 10-12 and the three aliases may change');
  assert.equal(Object.keys(before.displayStationCoordinates).length, 10);
  assert.equal(Object.keys(after.displayStationCoordinates).length, 13);
  for (const [id, c] of Object.entries(before.displayStationCoordinates))
    assert.deepEqual(after.displayStationCoordinates[id], c, 'Preserved aliases changed');
  assert(!('008780' in before.displayStationCoordinates) && '008780' in after.displayStationCoordinates);
  const physical = l => Object.fromEntries(Object.entries(l).filter(([k]) => k !== 'displayIntervalCoordinates' && k !== 'displayStationCoordinates'));
  assert.deepEqual(physical(after), physical(before), 'Kitakume-Ishite non-display fields changed');
  assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before), 'Physical source changed');
  for (let i = 0; i < 14; i++) if (!DISPLAY_INTERVALS.includes(i))
    assert.deepEqual(after.displayIntervalCoordinates[i], before.displayIntervalCoordinates[i]);
  assert('13' in before.displayIntervalCoordinates === '13' in after.displayIntervalCoordinates);
  for (const i of DISPLAY_INTERVALS) {
    const coordinates = after.displayIntervalCoordinates[i];
    for (let j = 1; j < coordinates.length; j++)
      assert(coordinates[j][0] < coordinates[j - 1][0], 'Kitakume-Ishite introduced eastward backtracking');
  }
  const oldParts = net.displayPartsForLine(before), parts = net.displayPartsForLine(after);
  assert.equal(oldParts.length, 1); assert.equal(oldParts[0].length, 182);
  assert.equal(parts.length, 1); assert.equal(parts[0].length, 206);
  assert.deepEqual(parts[0].slice(0, 148), oldParts[0].slice(0, 148), 'Outer public prefix changed');
  assert.deepEqual(parts[0].slice(-13), oldParts[0].slice(-13), 'Outer public suffix changed');
  return structuredClone(after);
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), own = input.lines.filter(l => l.id === LINE);
  assert.equal(own.length, 1, 'Kitakume-Ishite own line missing/duplicated');
  assert(equal(own[0], e.baselineLine) || equal(own[0], line), 'Kitakume-Ishite stale own package baseline');
  const result = structuredClone(input);
  result.lines = result.lines.map(l => l.id === LINE ? line : l);
  const provenance = {lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
    evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
    status: 'bounded-kitakume-ishite-intervals-10-12-alias-13; full-passenger-caps-open',
    wholeLineAccepted: false, MainCertified: false};
  result.geometrySource ??= {}; result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Kitakume-Ishite provenance changed');
  result.geometrySource.manualOverrides[KEY] = provenance;
  return result;
}

export function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
  const ownLines = pkg.lines.filter(l => l.id === LINE);
  assert.equal(ownLines.length, 1, 'Kitakume-Ishite candidate line missing/duplicated');
  const line = ownLines[0]; assert.deepEqual(line, proposedLine(e));
  const parts = net.displayPartsForLine(line), rows = partRowsForLine(line, parts, null, null);
  assert.equal(rows.length, 1); assert.equal(rows[0][4], 206); assert.deepEqual(rows[0][7], parts[0]);
  const own = input.partsByRegion?.jp?.filter(r => r[0] === LINE);
  assert.equal(own?.length, 1, 'Kitakume-Ishite own native row missing/duplicated');
  assert(equal(own, e.baselineNativeRows) || equal(own, rows), 'Kitakume-Ishite stale/foreign own native row');
  for (const [key, value] of Object.entries(input)) if (key !== 'partsByRegion')
    assert(!JSON.stringify(value)?.includes(LINE), 'Kitakume-Ishite own native reference requires review: ' + key);
  for (const [region, values] of Object.entries(input.partsByRegion || {})) if (region !== 'jp')
    assert(!JSON.stringify(values).includes(LINE), 'Kitakume-Ishite foreign-region own reference');
  assert(!(input.excludedOperators || []).includes(line.operator), 'Kitakume-Ishite operator excluded');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(r => r[0] === LINE ? rows[0] : r);
  return result;
}

export function validateCandidateReview(receipt, line) {
  assert(receipt, 'Kitakume-Ishite scoped candidate-review receipt required before --apply');
  assert.deepEqual([receipt.format, receipt.status, receipt.lineID, receipt.stationIDs,
    receipt.intervalIndices, receipt.MainCertified, receipt.wholeLineAccepted],
  ['jtm-yokogawara-kitakume-ishite-candidate-review-v2', 'bounded-candidate-reviewed',
    LINE, STATIONS, INTERVALS, false, false], 'Kitakume-Ishite review scope changed');
  assert.equal(receipt.reviewedOwnLineSha256, CANDIDATE_SHA, 'Kitakume-Ishite reviewed candidate changed');
  assert.equal(receipt.reviewedOwnLineSha256, sha(line), 'Kitakume-Ishite reviewed own line changed');
}

function main(args) {
  assert(args.length === 3 && args[0] === '--apply' && args[1] === '--candidate-review',
    'Use --apply --candidate-review <canonical evidence receipt.json>');
  const receiptPath = path.resolve(args[2]); assertAllowedCandidateFile(receiptPath);
  assert(fs.realpathSync(receiptPath).startsWith(fs.realpathSync(EV) + path.sep),
    'Kitakume-Ishite receipt must use canonical local evidence');
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
    'scripts/railway/repair-yokogawara-kitakume-ishite-display.mjs'].map(p => snapshot(path.join(APP, p)));
  applyPreparedWrites(writes, [...Object.values(inputs), authority, receipt, ...implementation]);
  console.log(JSON.stringify({mode: 'applied', lineID: LINE, stationIDs: STATIONS, intervalIndices: INTERVALS,
    nativeRows: lanes.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r.slice(0, 7)),
    fullPassengerCapsCertified: false, wholeLineAccepted: false, MainCertified: false}));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
