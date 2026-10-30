// Shared owner logic for repair-09 bounded display repairs (pattern of repair-yokogawara-kitakume-ishite-display.mjs).
// Each per-line script supplies a frozen config; this module never writes anything except through main(--apply).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {partRowsForLine} from './build-display-lanes.mjs';
import {assertAllowedCandidateFile} from './local-evidence-path.mjs';
import {refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';

export const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const APP = path.join(REPO, 'app'), EV = path.join(REPO, 'railway-evidence/local');
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

// config: {key, lineID, authorityPath, format, receiptFormat, stationIDs, intervalIndices, displayIntervals,
//          baselineSha, candidateSha, nativeSha, parts: {baseline: [n...], candidate: [n...], prefix, suffix}, script}
export function makeRepair(c) {
  const label = c.key;
  function proposedLine(e) {
    assert.deepEqual([e.format, e.lineID, e.stationIDs, e.intervalIndices, e.displayIntervals, e.MainCertified, e.wholeLineAccepted],
      [c.format, c.lineID, c.stationIDs, c.intervalIndices, c.displayIntervals, false, false], label + ' authority scope changed');
    assert.equal(sha(e.baselineLine), c.baselineSha, label + ' baseline authority changed');
    assert.equal(sha(e.candidateLine), c.candidateSha, label + ' candidate authority changed');
    assert.equal(sha(e.baselineNativeRows), c.nativeSha, label + ' baseline native authority changed');
    const before = e.baselineLine, after = e.candidateLine;
    const rebuilt = structuredClone(before);
    rebuilt.displayIntervalCoordinates = {...(before.displayIntervalCoordinates || {})};
    rebuilt.displayStationCoordinates = {...(before.displayStationCoordinates || {})};
    for (const i of c.displayIntervals) rebuilt.displayIntervalCoordinates[i] = structuredClone(after.displayIntervalCoordinates[i]);
    for (const id of c.stationIDs) rebuilt.displayStationCoordinates[id] = structuredClone(after.displayStationCoordinates[id]);
    if (!Object.keys(rebuilt.displayStationCoordinates).length) delete rebuilt.displayStationCoordinates;
    assert.deepEqual(rebuilt, after, label + ': only the listed display intervals and aliases may change');
    for (const [id, v] of Object.entries(before.displayStationCoordinates || {}))
      if (!c.stationIDs.includes(id)) assert.deepEqual(after.displayStationCoordinates[id], v, label + ' preserved alias changed');
    for (const [k, v] of Object.entries(before.displayIntervalCoordinates || {}))
      if (!c.displayIntervals.includes(Number(k))) assert.deepEqual(after.displayIntervalCoordinates[k], v, label + ' preserved interval changed');
    const physical = l => Object.fromEntries(Object.entries(l).filter(([k]) => k !== 'displayIntervalCoordinates' && k !== 'displayStationCoordinates'));
    assert.deepEqual(physical(after), physical(before), label + ' non-display fields changed');
    assert.deepEqual(net.decodeIntervals(after), net.decodeIntervals(before), label + ' physical source changed');
    const oldParts = net.displayPartsForLine(before), parts = net.displayPartsForLine(after);
    assert.deepEqual(oldParts.map(p => p.length), c.parts.baseline, label + ' baseline public parts changed');
    assert.deepEqual(parts.map(p => p.length), c.parts.candidate, label + ' candidate public parts changed');
    assert.deepEqual(parts[0].slice(0, c.parts.prefix), oldParts[0].slice(0, c.parts.prefix), label + ' outer public prefix changed');
    if (c.parts.suffix) assert.deepEqual(parts.at(-1).slice(-c.parts.suffix), oldParts.at(-1).slice(-c.parts.suffix), label + ' outer public suffix changed');
    return structuredClone(after);
  }

  function repairPackage(input, e = read(c.authorityPath)) {
    const line = proposedLine(e), own = input.lines.filter(l => l.id === c.lineID);
    assert.equal(own.length, 1, label + ' own line missing/duplicated');
    assert(equal(own[0], e.baselineLine) || equal(own[0], line), label + ' stale own package baseline');
    const result = structuredClone(input);
    result.lines = result.lines.map(l => l.id === c.lineID ? line : l);
    const provenance = {lineID: c.lineID, stationIDs: c.stationIDs, intervalIndices: c.intervalIndices,
      evidence: path.relative(REPO, c.authorityPath), physicalTopologyChanged: false,
      status: 'bounded-display-repair-' + c.key + '; full-passenger-caps-open', wholeLineAccepted: false, MainCertified: false};
    result.geometrySource ??= {}; result.geometrySource.manualOverrides ??= {};
    const previous = result.geometrySource.manualOverrides[c.key];
    assert(previous === undefined || equal(previous, provenance), label + ' provenance changed');
    result.geometrySource.manualOverrides[c.key] = provenance;
    return result;
  }

  function repairParts(pkg, input, e = read(c.authorityPath)) {
    const ownLines = pkg.lines.filter(l => l.id === c.lineID);
    assert.equal(ownLines.length, 1, label + ' candidate line missing/duplicated');
    const line = ownLines[0]; assert.deepEqual(line, proposedLine(e));
    const parts = net.displayPartsForLine(line), rows = partRowsForLine(line, parts, null, null);
    assert.equal(rows.length, parts.length);
    rows.forEach((r, i) => { assert.equal(r[4], parts[i].length); assert.deepEqual(r[7], parts[i]); });
    const own = input.partsByRegion?.jp?.filter(r => r[0] === c.lineID);
    assert.equal(own?.length, e.baselineNativeRows.length, label + ' own native rows missing/duplicated');
    assert(equal(own, e.baselineNativeRows) || equal(own, rows), label + ' stale/foreign own native row');
    // colour and render-group entries are keyed by line id but carry no geometry; they pass through unchanged.
    for (const [key, value] of Object.entries(input)) if (!['partsByRegion', 'colorByRegion', 'renderGroupByRegion'].includes(key))
      assert(!JSON.stringify(value)?.includes(c.lineID), label + ' own native reference requires review: ' + key);
    for (const [region, values] of Object.entries(input.partsByRegion || {})) if (region !== 'jp')
      assert(!JSON.stringify(values).includes(c.lineID), label + ' foreign-region own reference');
    assert(!(input.excludedOperators || []).includes(line.operator), label + ' operator excluded');
    const result = structuredClone(input), at = result.partsByRegion.jp.findIndex(r => r[0] === c.lineID);
    result.partsByRegion.jp = [...result.partsByRegion.jp.slice(0, at).filter(r => r[0] !== c.lineID), ...rows,
      ...result.partsByRegion.jp.slice(at).filter(r => r[0] !== c.lineID)];
    return result;
  }

  function validateCandidateReview(receipt, line) {
    assert(receipt, label + ' scoped candidate-review receipt required before --apply');
    assert.deepEqual([receipt.format, receipt.status, receipt.lineID, receipt.stationIDs, receipt.intervalIndices,
      receipt.MainCertified, receipt.wholeLineAccepted],
    [c.receiptFormat, 'bounded-candidate-reviewed', c.lineID, c.stationIDs, c.intervalIndices, false, false], label + ' review scope changed');
    assert.equal(receipt.reviewedOwnLineSha256, c.candidateSha, label + ' reviewed candidate changed');
    assert.equal(receipt.reviewedOwnLineSha256, sha(line), label + ' reviewed own line changed');
  }

  function main(args) {
    assert(args.length === 3 && args[0] === '--apply' && args[1] === '--candidate-review',
      'Use --apply --candidate-review <canonical evidence receipt.json>');
    const receiptPath = path.resolve(args[2]); assertAllowedCandidateFile(receiptPath);
    assert(fs.realpathSync(receiptPath).startsWith(fs.realpathSync(EV) + path.sep), label + ' receipt must use canonical local evidence');
    const snapshot = p => ({path: p, before: fs.readFileSync(p)});
    const authority = snapshot(c.authorityPath), receipt = snapshot(receiptPath), e = JSON.parse(authority.before);
    const paths = {package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json', ...DEPENDENCY_PATHS};
    const inputs = Object.fromEntries(Object.entries(paths).map(([k, p]) => [k, snapshot(path.join(APP, p))]));
    const load = k => JSON.parse(inputs[k].before), pkg = repairPackage(load('package'), e);
    validateCandidateReview(JSON.parse(receipt.before), pkg.lines.find(l => l.id === c.lineID));
    const lanes = repairParts(pkg, load('lanes'), e);
    const dependencies = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k => [k, load(k)])));
    const outputs = {package: JSON.stringify(pkg), lanes: JSON.stringify(lanes) + '\n',
      ...Object.fromEntries(Object.entries(dependencies).map(([k, v]) => [k, JSON.stringify(v, null, 2) + '\n']))};
    const writes = Object.entries(outputs).map(([k, after]) => ({...inputs[k], after: Buffer.from(after)}));
    const implementation = ['public/rail-network.js', 'scripts/railway/build-display-lanes.mjs',
      'scripts/railway/repair-three-reversal-extents.mjs', 'scripts/railway/local-evidence-path.mjs',
      'scripts/railway/repair09-display-common.mjs', 'scripts/railway/' + c.script].map(p => snapshot(path.join(APP, p)));
    applyPreparedWrites(writes, [...Object.values(inputs), authority, receipt, ...implementation]);
    console.log(JSON.stringify({mode: 'applied', lineID: c.lineID, stationIDs: c.stationIDs, intervalIndices: c.intervalIndices,
      nativeRows: lanes.partsByRegion.jp.filter(r => r[0] === c.lineID).map(r => r.slice(0, 7)),
      fullPassengerCapsCertified: false, wholeLineAccepted: false, MainCertified: false}));
  }
  return {proposedLine, repairPackage, repairParts, validateCandidateReview, main};
}
