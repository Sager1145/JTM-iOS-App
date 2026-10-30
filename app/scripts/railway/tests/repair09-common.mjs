// Shared focused tests for repair-09 bounded display repairs (pattern of yokogawara-kitakume-ishite-display.test.mjs).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const sha = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
function distance(point, paths) {
  const xy = p => [(p[0] - point[0]) * 111320 * Math.cos(point[1] * Math.PI / 180), (p[1] - point[1]) * 111320];
  let best = Infinity;
  for (const path of paths) for (let i = 1; i < path.length; i++) {
    const a = xy(path[i - 1]), b = xy(path[i]), v = b.map((x, k) => x - a[k]);
    const t = Math.max(0, Math.min(1, -(a[0] * v[0] + a[1] * v[1]) / (v[0] ** 2 + v[1] ** 2 || 1)));
    best = Math.min(best, Math.hypot(a[0] + t * v[0], a[1] + t * v[1]));
  }
  return best;
}

// mod: the per-line script module; c: its exported CONFIG.
export function registerRepairTests(mod, c) {
  const authority = JSON.parse(fs.readFileSync(c.authorityPath));
  const LINE = c.lineID;
  const pkgOf = line => ({lines: [{id: 'other', operator: 'x'}, line], geometrySource: {}});
  const lanesOf = rows => ({partsByRegion: {jp: [['other', 'x'], ...structuredClone(rows)]}});
  const own = pkg => pkg.lines.find(l => l.id === LINE);
  const receipt = {format: c.receiptFormat, status: 'bounded-candidate-reviewed', lineID: LINE, stationIDs: c.stationIDs,
    intervalIndices: c.intervalIndices, reviewedOwnLineSha256: c.candidateSha, MainCertified: false, wholeLineAccepted: false};

  test(`${c.key}: repairPackage turns the baseline into the candidate and is idempotent`, () => {
    assert.equal(sha(authority.baselineLine), c.baselineSha);
    const out = mod.repairPackage(pkgOf(authority.baselineLine));
    assert.equal(sha(own(out)), c.candidateSha);
    assert.equal(out.geometrySource.manualOverrides[c.key].MainCertified, false);
    assert.deepEqual(mod.repairPackage(out), out);
  });
  test(`${c.key}: rejects tampered authority, scope change and a stale foreign baseline`, () => {
    const bad = structuredClone(authority), k = String(c.displayIntervals[0]);
    bad.candidateLine.displayIntervalCoordinates[k][1][0] += 1e-6;
    assert.throws(() => mod.repairPackage(pkgOf(authority.baselineLine), bad));
    const scope = structuredClone(authority); scope.intervalIndices = scope.intervalIndices.slice(1);
    assert.throws(() => mod.repairPackage(pkgOf(authority.baselineLine), scope));
    const foreign = structuredClone(authority.baselineLine); foreign.stations[0][2] += 1e-6;
    assert.throws(() => mod.repairPackage(pkgOf(foreign)));
  });
  test(`${c.key}: repairParts yields the candidate rows and accepts the baseline native rows`, () => {
    const pkg = mod.repairPackage(pkgOf(authority.baselineLine));
    const out = mod.repairParts(pkg, lanesOf(authority.baselineNativeRows));
    const rows = out.partsByRegion.jp.filter(r => r[0] === LINE);
    assert.deepEqual(rows.map(r => r[4]), c.parts.candidate);
    assert.deepEqual(mod.repairParts(pkg, out), out);
    const stale = structuredClone(authority.baselineNativeRows); stale[0][4] -= 1;
    assert.throws(() => mod.repairParts(pkg, lanesOf(stale)), /stale/);
  });
  test(`${c.key}: candidate review receipt must match scope and sha`, () => {
    mod.validateCandidateReview(receipt, authority.candidateLine);
    assert.throws(() => mod.validateCandidateReview({...receipt, reviewedOwnLineSha256: c.baselineSha}, authority.candidateLine));
    assert.throws(() => mod.validateCandidateReview({...receipt, intervalIndices: []}, authority.candidateLine));
    assert.throws(() => mod.validateCandidateReview(undefined, authority.candidateLine));
  });
  test(`${c.key}: every support witness lies within 0.5 m of the candidate public line`, () => {
    const parts = net.displayPartsForLine(authority.candidateLine);
    assert.deepEqual(parts.map(p => p.length), c.parts.candidate);
    assert.equal(authority.supportCoordinates.length, c.supportCount);
    for (const s of authority.supportCoordinates) assert(distance(s.longitudeLatitude, parts) <= 0.5, `${s.id} within 0.5 m`);
    for (const p of authority.sourceReviews) assert(fs.existsSync(new URL('../../../../' + p, import.meta.url)), p);
  });
  test(`${c.key}: other aliases, intervals and the physical source are unchanged`, () => {
    const b = authority.baselineLine, cand = authority.candidateLine;
    for (const [id, v] of Object.entries(b.displayStationCoordinates || {}))
      if (!c.stationIDs.includes(id)) assert.deepEqual(cand.displayStationCoordinates[id], v, id);
    for (const [k, v] of Object.entries(b.displayIntervalCoordinates || {}))
      if (!c.displayIntervals.includes(Number(k))) assert.deepEqual(cand.displayIntervalCoordinates[k], v, k);
    assert.deepEqual(Object.keys(cand.displayIntervalCoordinates || {}).map(Number).filter(k => !(k in (b.displayIntervalCoordinates || {}))).sort((x, y) => x - y),
      c.displayIntervals.filter(k => !(String(k) in (b.displayIntervalCoordinates || {}))).sort((x, y) => x - y));
    assert.deepEqual(net.decodeIntervals(cand), net.decodeIntervals(b));
  });
}
