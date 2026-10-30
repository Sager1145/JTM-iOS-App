import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {repairPackage, repairParts, validateCandidateReview, AUTHORITY_PATH} from '../repair-yokogawara-kitakume-ishite-display.mjs';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const sha = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
const authority = read(AUTHORITY_PATH);
const LINE = authority.lineID;
const CAND = '29b1ddd2594df8cb3efb3ed8e156612b5c2ea1080516cbf148936eb2b168a766';
const BASE = '7c65c00371857dcbe2343d4c2a3f8adb48f0827357c872b1bc6b6180e4efc83c';
// Self-contained inputs built from the authority, independent of production state.
const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
const lanesOf = rows => ({partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]}});
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
test('repairPackage turns the 182 baseline into the 206 candidate and is idempotent', () => {
  const out = repairPackage(pkgOf(authority.baselineLine));
  assert.equal(sha(own(out)), CAND);
  assert.equal(sha(authority.baselineLine), BASE);
  assert.equal(out.geometrySource.manualOverrides['yokogawara-kitakume-ishite-display'].MainCertified, false);
  const again = repairPackage(out);
  assert.equal(sha(own(again)), CAND);
  assert.deepEqual(again, out);
});
test('rejects tampered authority and stale foreign baseline', () => {
  const bad = structuredClone(authority);
  bad.candidateLine.displayStationCoordinates['008780'][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), bad));
  const foreign = structuredClone(authority.baselineLine);
  foreign.displayStationCoordinates['008801'][0] += 1e-6;
  assert.throws(() => repairPackage(pkgOf(foreign)), /stale/);
  const scope = structuredClone(authority); scope.intervalIndices = [10, 11];
  assert.throws(() => repairPackage(pkgOf(authority.baselineLine), scope));
});
test('repairParts yields one 206-point row and accepts the baseline native row', () => {
  const pkg = repairPackage(pkgOf(authority.baselineLine));
  const out = repairParts(pkg, lanesOf(authority.baselineNativeRows));
  const rows = out.partsByRegion.jp.filter(r => r[0] === LINE);
  assert.equal(rows.length, 1); assert.equal(rows[0][4], 206);
  assert.deepEqual(repairParts(pkg, out), out);
  const stale = structuredClone(authority.baselineNativeRows); stale[0][4] = 181;
  assert.throws(() => repairParts(pkg, lanesOf(stale)), /stale/);
});
test('candidate review receipt must match scope and sha', () => {
  const receipt = {format: 'jtm-yokogawara-kitakume-ishite-candidate-review-v2', status: 'bounded-candidate-reviewed',
    lineID: LINE, stationIDs: ['008791', '008784', '008780'], intervalIndices: [10, 11, 12, 13],
    reviewedOwnLineSha256: CAND, MainCertified: false, wholeLineAccepted: false};
  validateCandidateReview(receipt, authority.candidateLine);
  assert.throws(() => validateCandidateReview({...receipt, reviewedOwnLineSha256: BASE}, authority.candidateLine));
  assert.throws(() => validateCandidateReview(undefined, authority.candidateLine));
});
test('i10-i12 support coordinates (54 witnesses incl. three aliases) lie within 0.5m of the candidate public line', () => {
  const parts = net.displayPartsForLine(authority.candidateLine);
  assert.equal(parts.length, 1); assert.equal(parts[0].length, 206);
  assert(authority.supportCoordinates.length === 54);
  for (const id of ['i10:', 'i11tail:', 'i12mid:', 'alias:008780', 'alias:008791', 'alias:008784']) assert(authority.supportCoordinates.some(s => s.id.startsWith(id)));
  for (const s of authority.supportCoordinates)
    assert(distance(s.longitudeLatitude, parts) <= 0.5, `${s.id} within 0.5m`);
  for (const p of authority.sourceReviews) assert(fs.existsSync(new URL('../../../../' + p, import.meta.url)), p);
});
test('other aliases, intervals and prefix/suffix are unchanged from baseline', () => {
  const b = authority.baselineLine, c = authority.candidateLine;
  for (const [id, v] of Object.entries(b.displayStationCoordinates)) assert.deepEqual(c.displayStationCoordinates[id], v, id);
  assert.deepEqual(Object.keys(c.displayStationCoordinates).slice(10), ['008791', '008784', '008780']);
  assert.match(authority.ishiteAlias.basis, /^reference-assisted/);
  for (let i = 0; i < 14; i++) if (![10, 11, 12].includes(i))  // i13 has no display override; checked at raw stage below
    assert.deepEqual(c.displayIntervalCoordinates[i], b.displayIntervalCoordinates[i]);
  assert.deepEqual(net.decodeIntervals(c), net.decodeIntervals(b));
});
test('i13 is affected only through the 008780 alias: source/physical unchanged, only first raw vertex differs', () => {
  const b = authority.baselineLine, c = authority.candidateLine;
  assert.deepEqual(c.displayIntervalCoordinates[13], b.displayIntervalCoordinates[13]);
  assert.deepEqual(net.decodeIntervals(c)[13], net.decodeIntervals(b)[13]);
  const ctx = {module: {exports: {}}};
  vm.runInNewContext(fs.readFileSync(new URL('../../../public/rail-network.js', import.meta.url), 'utf8')
    .replace('return Object.freeze({', 'return Object.freeze({__audit:{displayLineForCoordinates},'), ctx);
  const a = ctx.module.exports.__audit;
  const raw = l => JSON.parse(JSON.stringify(ctx.module.exports.decodeIntervals(a.displayLineForCoordinates(l))));
  const rb = raw(b)[13], rc = raw(c)[13];
  assert.equal(rb.length, rc.length);
  assert.deepEqual(rc.slice(1), rb.slice(1));
  assert.notDeepEqual(rc[0], rb[0]);
  assert.deepEqual(rc[0], c.displayStationCoordinates['008780']);
  for (let i = 1; i < 3; i++) for (const k of [10, 11, 12])
    assert(c.displayIntervalCoordinates[k][i][0] < c.displayIntervalCoordinates[k][i - 1][0]);
});
