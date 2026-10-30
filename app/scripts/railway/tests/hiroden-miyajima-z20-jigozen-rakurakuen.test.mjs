import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {repairPackage, repairParts, validateCandidateReview, AUTHORITY_PATH} from '../repair-hiroden-miyajima-z20-jigozen-rakurakuen.mjs';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const sha = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
const authority = read(AUTHORITY_PATH);
const LINE = authority.lineID, KEY = 'hiroden-miyajima-z20-jigozen-rakurakuen';
const CAND = 'f50bf81cf5a1e7a7bd806c71b640ca2af2112f16f6f76af8d11c29a0bdeb26c4';
const BASE = 'd7e42d408d8706718e30ecee71d252e7c1b3bc196327ac55c9c3b19cf9ed57aa';
// Self-contained inputs built from the authority, independent of production state.
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const MB = authority.measuredLaneReferences?.baseline || {};
const hubsOf = members => Object.values(members.reduce((a, x) => {
  (a[x.hubId] ??= {hubId: x.hubId, members: []}).members[x.index] = structuredClone(x.member); return a; }, {}))
  .map(h => ({...h, members: Array.from(h.members, m => m ?? {lineId: 'other'})}));
const lanesOf = rows => ({partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]},
  byRegion: {jp: structuredClone(MB.byRegion || [])}, followsByRegion: {jp: structuredClone(MB.followsByRegion || [])},
  hubReportByRegion: {jp: hubsOf(MB.hubMembers || [])}});
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
test('repairPackage turns the baseline into the reviewed candidate and is idempotent', () => {
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), CAND);
  assert.equal(sha(authority.baselineLine), BASE);
  assert.equal(out.geometrySource.manualOverrides[KEY].MainCertified, false);
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
  foreign.stations[0][2] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(foreign)));
  const scope = structuredClone(authority); scope.intervalIndices = scope.intervalIndices.slice(1);
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
});
test('repairParts yields the candidate native rows and accepts the baseline rows', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows));
  const rows = out.partsByRegion.jp.filter(r => r[0] === LINE);
  assert.deepEqual(rows.map(r => r[4]), net.displayPartsForLine(authority.candidateLine).map(p => p.length));
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows); stale[0][4] -= 1;
  assert.throws(() => repairParts(pkg, lanesOf(stale)), /stale/);
});
test('candidate review receipt must match scope and sha', () => {
  const receipt = {format: 'jtm-hiroden-miyajima-z20-jigozen-rakurakuen-candidate-review-v1', status: 'bounded-candidate-reviewed',
    lineID: LINE, stationIDs: authority.stationIDs, intervalIndices: authority.intervalIndices,
    reviewedOwnLineSha256: CAND, MainCertified: false, wholeLineAccepted: false};
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: BASE}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(undefined, authority.candidateLine));
});
test('every own-glyph support and alias lies within 0.5 m of the candidate public line', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  assert(authority.supportCoordinates.length > 0);
  for (const s of authority.supportCoordinates)
    assert(distance(s.longitudeLatitude, parts) <= 0.5, `${s.id} within 0.5m`);
});
test('physical source, other intervals and preserved aliases are unchanged', () => {
  const b = authority.baselineLine, c = authority.candidateLine;
  assert.deepEqual(net.decodeIntervals(c), net.decodeIntervals(b));
  for (const [id, v] of Object.entries(b.displayStationCoordinates || {})) if (!authority.stationIDs.includes(id)) assert.deepEqual(c.displayStationCoordinates[id], v, id);
  for (const [k, v] of Object.entries(b.displayIntervalCoordinates || {}))
    if (!authority.displayOverrideIntervals.includes(+k)) assert.deepEqual(c.displayIntervalCoordinates[k], v, k);
});
test('repairParts carries identity entries unchanged and replaces measured lane references by the authority remap', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const m = authority.measuredLaneReferences;
  const lanes = lanesOf(authority.baselineNativeRows);
  lanes.colorByRegion = {jp: {[LINE]: {color: authority.candidateLine.color, colorDark: authority.candidateLine.colorDark}}};
  lanes.renderGroupByRegion = {jp: {[LINE]: 'group'}};
  for (const key of ['byRegion', 'followsByRegion']) lanes[key].jp.unshift(['other', 0, 0, 1, 0]);
  const out = repairParts(pkg, lanes);
  assert.deepEqual(out.colorByRegion, lanes.colorByRegion); assert.deepEqual(out.renderGroupByRegion, lanes.renderGroupByRegion);
  for (const key of ['byRegion', 'followsByRegion']) assert.deepEqual(out[key].jp.slice(1), m.candidate[key] || []);
  assert.deepEqual(repairParts(pkg, out), out);
  const bad = structuredClone(lanes); bad.colorByRegion.jp[LINE].color = '#000000';
  assert.throws(() => repairParts(pkg, bad), /colour identity/);
  const other = structuredClone(lanes); other.familyWindowsByRegion = {jp: [[LINE]]};
  assert.throws(() => repairParts(pkg, other), /requires review/);
  if (m.baseline.byRegion) { const stale = structuredClone(lanes); stale.byRegion.jp[1][2] += 1; assert.throws(() => repairParts(pkg, stale), /stale/); }
});
