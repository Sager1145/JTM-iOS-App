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
export const AUTHORITY_PATH = path.join(EV, 'proposals/iyotetsu-yokogawara-remainder-20261020/bounded-danchi-hirai-visible-track-authority-v2.json');
const LINE = 'jp-伊予鉄道-横河原線', KEY = 'yokogawara-danchi-hirai-display';
const STATIONS = ['008818', '008813', '008805'], INTERVALS = [4, 5, 6, 7];
const BASELINE_SHA = '5463bfe78639411b046ab3034f7ffb2c59a8c1c5d7fd8ede853fb9f753c6772e';
const CANDIDATE_SHA = 'b96591261684147bd4f30b9a47ac33f5ef4f5f7bb5508c5fa647a348b6d19006';
const NATIVE_SHA = '3107a24a7f7242f3f214a4b065e62ae40a7a1cd28bd0849624fddd5abc439ecc';
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(value).digest('hex');
const ownSha = line => sha(JSON.stringify(line));

function proposedLine(e) {
  assert.deepEqual([e.format, e.lineID, e.stationIDs, e.intervalIndices,
    e.protectedPrefixCount, e.protectedSuffixCount, e.fullPassengerCapsCertified, e.MainCertified],
  ['jtm-yokogawara-danchi-hirai-visible-track-authority-v1', LINE, STATIONS, INTERVALS, 65, 56, false, false],
  'Yokogawara bounded authority scope changed');
  assert.equal(ownSha(e.baselineLine), BASELINE_SHA, 'Yokogawara baseline authority changed');
  assert.equal(ownSha(e.candidateLine), CANDIDATE_SHA, 'Yokogawara Danchi-Hirai candidate authority changed');
  assert.equal(ownSha(e.baselineNativeRows), NATIVE_SHA, 'Yokogawara baseline native authority changed');
  const before = e.baselineLine, after = e.candidateLine;
  const physicalFields = line => Object.fromEntries(Object.entries(line).filter(([k]) =>
    !['displayStationCoordinates', 'displayIntervalCoordinates'].includes(k)));
  assert.deepEqual(physicalFields(after), physicalFields(before), 'Yokogawara physical fields changed');
  assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before), 'Yokogawara physical decode changed');
  assert.deepEqual(Object.keys(after.displayStationCoordinates).sort(),
    [...Object.keys(before.displayStationCoordinates), ...STATIONS].sort());
  for (const [id, coordinate] of Object.entries(before.displayStationCoordinates))
    assert.deepEqual(after.displayStationCoordinates[id], coordinate, 'Previously reviewed alias changed: ' + id);
  assert.deepEqual(Object.keys(after.displayIntervalCoordinates), Array.from({length: 8}, (_, i) => String(i)));
  for (let i = 0; i < 4; i++)
    assert.deepEqual(after.displayIntervalCoordinates[i], before.displayIntervalCoordinates[i]);
  for (const id of STATIONS) {
    const i = after.stations.findIndex(s => s[0] === id);
    assert(i > 0 && i < after.stations.length - 1);
    assert.deepEqual(after.displayIntervalCoordinates[i - 1].at(-1), after.displayStationCoordinates[id]);
    assert.deepEqual(after.displayIntervalCoordinates[i][0], after.displayStationCoordinates[id]);
  }
  const oldParts = net.displayPartsForLine(before), newParts = net.displayPartsForLine(after);
  assert.equal(oldParts.length, 1); assert.equal(newParts.length, 1);
  assert.equal(newParts[0].length, 162, 'Yokogawara whole public display point count changed');
  assert.deepEqual(newParts[0].slice(0, 65), oldParts[0].slice(0, 65), 'Yokogawara outer prefix changed');
  assert.deepEqual(newParts[0].slice(-56), oldParts[0].slice(-56), 'Yokogawara retained western suffix changed');
  // Retained outer geometry is an unchanged boundary, not an aligned guard.
  // Label-covered centres are reference-assisted. Full caps and Hirai west
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
    status: 'bounded-danchi-umemoto-hirai-display-repair; full-passenger-caps-and-outer-boundaries-open',
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
  assert.equal(rows[0][4], 162); assert.deepEqual(rows[0][7], net.displayPartsForLine(line)[0]);
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
  ['jtm-yokogawara-danchi-hirai-candidate-review-v1', 'bounded-candidate-reviewed', LINE,
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
    'scripts/railway/repair-yokogawara-danchi-hirai-display.mjs'].map(p => snapshot(path.join(APP, p)));
  applyPreparedWrites(writes, [...Object.values(inputs), authority, receipt, ...implementation]);
  console.log(JSON.stringify({mode: 'applied', lineID: LINE, stationIDs: STATIONS,
    intervalIndices: INTERVALS, nativeRows: lanes.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r.slice(0, 7)),
    fullPassengerCapsCertified: false, outerBoundariesCertified: false,
    wholeLineAccepted: false, MainCertified: false}));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
