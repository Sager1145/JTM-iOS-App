import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {repairPackage as repairPackageWithAuthority, repairParts as repairPartsWithAuthority, validateCandidateReview} from '../repair-isumi-display.mjs';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const sha = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
// Evidence migrated to the mounted canonical root; the retired internal
// location is only an inventory key, never a supported read path.
const authority = read('/Volumes/JTM Evidence/99 Compatibility/Workspace/JTM-iOS-App/railway-evidence/local/proposals/repair-12b-20261021/authority-isumi-display.json');
const repairPackage = (input, evidence = authority) => repairPackageWithAuthority(input, evidence);
const repairParts = (pkg, input, evidence = authority) => repairPartsWithAuthority(pkg, input, evidence);
const LINE = authority.lineID;
const CAND = 'bd942bf7dea74f886233053f672bb9f067b0ad341a7a3c2d2637bce6b565ecae';
const BASE = '9a37a2ca347f547fe39d77ea734cdd4229d99b145f4ae8f43cbf8146676f4afb';
// Self-contained inputs built from the authority, independent of production state.
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const lanesOf = (rows, follows = authority.baselineFollowRows) => ({partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]},
  followsByRegion: {jp: [['other', 0, 0, 1, 'other2', 0, 0, 1], ...structuredClone(follows)]},
  ...Object.fromEntries(Object.entries(authority.baselineOtherLaneReferences).map(([k, v]) => [k, {jp: Array.isArray(v) && Array.isArray(v[0]) && typeof v[0][0] === 'string' && v[0].length === 2 && typeof v[0][1] === 'object' ? Object.fromEntries(v) : structuredClone(v)}]))});
const own = pkg => pkg.lines.find(l => l.id === LINE);
function distance(point, paths) {
  const xy = p => [(p[0]-point[0])*111320*Math.cos(point[1]*Math.PI/180), (p[1]-point[1])*111320];
  let best = Infinity;
  for (const path of paths) for (let i=1; i<path.length; i++) {
    const a=xy(path[i-1]), b=xy(path[i]), v=b.map((x,k)=>x-a[k]);
    const t=Math.max(0,Math.min(1,-(a[0]*v[0]+a[1]*v[1])/(v[0]**2+v[1]**2||1)));
    best=Math.min(best,Math.hypot(a[0]+t*v[0],a[1]+t*v[1]));
  }
  return best;
}
test('repairPackage turns the baseline into the candidate and is idempotent', () => {
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), CAND);
  assert.equal(sha(authority.baselineLine), BASE);
  assert.equal(out.geometrySource.manualOverrides['isumi-display'].MainCertified, false);
  const again = repairPackage(out);
  assert.equal(sha(own(again)), CAND);
  assert.deepEqual(again, out);
});
test('rejects tampered authority, stale foreign baseline and changed scope', () => {
  const bad = structuredClone(authority);
  const k = String(authority.displayOverrideIntervals[0]);
  bad.candidateLine.displayIntervalCoordinates[k][1][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const foreign = structuredClone(authority.baselineLine);
  foreign.stations[0][4] = foreign.stations[0][4] + ' ';
  assert.throws(() => repairPackage(pkgOf(foreign)), /stale/);
  const scope = structuredClone(authority); scope.intervalIndices = scope.intervalIndices.slice(1);
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
});
test('repairParts leaves lanes unchanged: いすみ線 is stroke-excluded (substitute_bus), so it has no native rows', () => {
  assert.equal(authority.baselineNativeRows.length, 0);
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const input = lanesOf(authority.baselineNativeRows);
  const out = repairParts(pkg, input);
  assert.deepEqual(out, input);
  assert.equal((out.partsByRegion?.jp || []).filter(r => r[0] === LINE).length, 0);
  assert.deepEqual(repairParts(pkg, out), out);
});
test('candidate review receipt must match scope and sha', () => {
  const receipt = {format: 'jtm-r12b-isumi-display-candidate-review-v1', status: 'bounded-candidate-reviewed',
    lineID: LINE, stationIDs: authority.stationIDs, intervalIndices: authority.intervalIndices,
    reviewedOwnLineSha256: CAND, MainCertified: false, wholeLineAccepted: false};
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: BASE}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(undefined, authority.candidateLine));
});
test('all 2906 glyph supports lie within 0.5 m of the candidate public line', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  assert.deepEqual(parts.map(p => p.length), authority.candidatePartCounts);
  assert.equal(authority.supportCoordinates.length, 2906);
  for (const s of authority.supportCoordinates)
    assert(distance(s.longitudeLatitude, parts) <= 0.5, `${s.id} within 0.5m`);
  for (const p of authority.sourceReviews) assert(fs.existsSync(new URL('../../../../' + p, import.meta.url)), p);
});
test('other aliases, intervals and physical source are unchanged from baseline', () => {
  const b = authority.baselineLine, c = authority.candidateLine;
  for (const [id, v] of Object.entries(b.displayStationCoordinates || {}))
    if (!authority.stationIDs.includes(id)) assert.deepEqual(c.displayStationCoordinates[id], v, id);
  for (const [i, v] of Object.entries(b.displayIntervalCoordinates || {}))
    if (!authority.displayOverrideIntervals.includes(+i)) assert.deepEqual(c.displayIntervalCoordinates[i], v);
  assert.deepEqual(net.decodeIntervals(c), net.decodeIntervals(b));
});

test('dated Isumi normal bank retains all thirteen intervals and one historical representation', async () => {
  const { buildTemporalPartsBank } = await import('../build-display-lanes.mjs');
  const line = structuredClone(authority.candidateLine);
  const pkg = { format: 'compact-v1', country: 'jp', version: 1, lines: [line] };
  const history = { schema_version: '2', revision: 'isumi-status-fixture', features: ['service_status_periods'],
    service_status_periods: [{ history_id: 'jp.isumi.derailment-2024.substitute-bus', lineID: LINE,
      scope: 'whole_line', station_membership_ids: line.stations.map(row => row[0]),
      valid_from: '2024-10-05', valid_to: null, serviceStatus: 'substitute_bus',
      source: ['https://isumirail.co.jp/blog/archives/9701'] }] };
  const original = structuredClone(pkg);
  const bank = buildTemporalPartsBank(pkg, null, null, history);
  const before = net.buildNetworkFromCompactPackage(pkg, null, null,
    { era: 'rideDate', today: '2026-10-26', rideDate: '2024-10-04', history });
  assert.equal(line.segments.length, 13);
  assert.equal(line.stations.length, 14);
  assert.equal(before.strokeModel.lines.length, 1);
  assert.equal(before.strokeModel.lines[0].parts.length, bank.temporalPartsByRegion.jp.length);
  assert.equal(before.segments.features.length, 1);
  const after = net.buildNetworkFromCompactPackage(pkg, null, null,
    { era: 'current', today: '2024-10-05', rideDate: null, history });
  assert.equal(after.strokeModel, null);
  assert.equal(after.segments.features.length, 0);
  assert.equal(after.stations.features.length, 0);
  const historical = net.buildNetworkFromCompactPackage(pkg, null, null,
    { era: 'historicalOverlay', today: '2024-10-05', rideDate: null, history });
  assert.equal(historical.segments.features.length, 1);
  assert.equal(historical.segments.features[0].properties.suspended, 1);
  assert.deepEqual(historical.lineById.get(LINE).parts, before.lineById.get(LINE).parts);
  assert.deepEqual(buildTemporalPartsBank(pkg, null, null, history), bank);
  assert.deepEqual(pkg, original);
});
