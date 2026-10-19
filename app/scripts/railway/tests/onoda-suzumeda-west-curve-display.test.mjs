import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { deriveDisplayRows } from '../build-display-lanes.mjs';
import { repairLanes as removeReviewedFollow } from '../repair-onoda-suzumeda-follow.mjs';
import { candidateGeoJSON, loadReviewedCandidate, repairFollowEvidence, repairPackage, repairParts }
  from '../repair-onoda-suzumeda-west-curve-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const e = JSON.parse(fs.readFileSync(new URL('../onoda-suzumeda-west-curve-display-evidence.json', import.meta.url)));
const baseline = e.baseline.followEvidence;
const lineItem = id => baseline.packageLines.find(item => item.line.id === id);
const fixture = () => {
  const lines = Array.from({ length: lineItem(e.lineID).index }, (_, index) => ({ id: `before-${index}` }));
  lines.push(structuredClone(lineItem(e.lineID).line), structuredClone(lineItem(e.branchLineID).line),
    { id: 'unrelated', keep: true });
  return { format: 'compact-v1', country: 'jp', lines,
    geometrySource: { manualOverrides: { concurrent: { keep: true } } } };
};
const lanes = (follows = []) => ({ partsByRegion: { jp: [...structuredClone(baseline.nativeParts),
  ['unrelated', 0, 1]] }, followsByRegion: { jp: structuredClone(follows) },
...Object.fromEntries(Object.entries(baseline.otherReferences).map(([key, rows]) => [key, { jp:
  Array.isArray(rows) ? [...structuredClone(rows), ['unrelated']] : { ...structuredClone(rows), unrelated: true } }])) });

test('reviewed curve artifacts and both native extractions are frozen', () => {
  const coordinates = loadReviewedCandidate(e);
  assert.equal(coordinates.length, 80);
  for (const artifact of e.candidate.artifacts)
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(new URL(`../../../../${artifact.path}`,
      import.meta.url))).digest('hex'), artifact.sha256);
  const candidate = JSON.parse(fs.readFileSync(new URL(`../../../../${e.candidate.artifacts[0].path}`,
    import.meta.url)));
  assert.equal(candidate.sources.length, 6);
  for (const source of candidate.sources)
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(new URL(`../../../../${source.path}`,
      import.meta.url))).digest('hex'), source.sha256);
});

test('repair adds only interval 4 display controls and preserves physical ownership', () => {
  const before = fixture(), after = repairPackage(before, e), base = after.lines[lineItem(e.lineID).index];
  const branch = after.lines[lineItem(e.branchLineID).index], physical = network.decodeIntervals(base)[4];
  const candidate = loadReviewedCandidate(e), guard = e.candidate.guard.sourceIndex;
  assert.deepEqual(base.stations, lineItem(e.lineID).line.stations);
  assert.deepEqual(base.segments, lineItem(e.lineID).line.segments);
  assert.deepEqual(network.decodeIntervals(base), network.decodeIntervals(lineItem(e.lineID).line));
  assert.deepEqual(branch, lineItem(e.branchLineID).line);
  assert.deepEqual(Object.keys(base.displayIntervalCoordinates), ['4']);
  assert.deepEqual(base.displayIntervalCoordinates[4], candidate);
  assert.deepEqual(candidate.slice(0, guard + 1), physical.slice(0, guard + 1));
  assert.deepEqual(candidate.at(-1), physical.at(-1));
  assert.equal(candidate.length - physical.length, 44);
  assert.deepEqual(after.lines.at(-1), before.lines.at(-1));
  assert.deepEqual(after.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.equal(after.geometrySource.manualOverrides['onoda-suzumeda-west-curve-display'].physicalTopologyChanged, false);
  assert.deepEqual(repairPackage(after, e), after);
});

test('only the base native part is recomputed within the groomed owning window', () => {
  const pkg = repairPackage(fixture(), e), before = lanes(), after = repairParts(pkg, before, e);
  const oldBase = baseline.nativeParts.find(row => row[0] === e.lineID);
  const oldBranch = baseline.nativeParts.find(row => row[0] === e.branchLineID);
  const newBase = after.partsByRegion.jp.find(row => row[0] === e.lineID);
  assert.deepEqual(after.partsByRegion.jp.find(row => row[0] === e.branchLineID), oldBranch);
  assert.deepEqual(newBase.slice(0, 4), oldBase.slice(0, 4));
  assert.deepEqual(newBase.slice(6, 7), oldBase.slice(6, 7));
  assert.deepEqual(newBase[8], oldBase[8]);
  assert.deepEqual([oldBase[4], newBase[4]],
    [e.nativeReplay.baselinePointCount, e.nativeReplay.candidatePointCount]);
  let prefix = 0, suffix = 0;
  while (prefix < oldBase[7].length && JSON.stringify(oldBase[7][prefix]) === JSON.stringify(newBase[7][prefix])) prefix++;
  while (suffix < oldBase[7].length - prefix &&
    JSON.stringify(oldBase[7].at(-1 - suffix)) === JSON.stringify(newBase[7].at(-1 - suffix))) suffix++;
  assert.deepEqual([prefix, suffix], [e.nativeReplay.commonPrefixPoints, e.nativeReplay.commonSuffixPoints]);
  assert.deepEqual(newBase[7][prefix - 1], oldBase[7][prefix - 1]);
  assert.deepEqual(newBase[7].at(-suffix), oldBase[7].at(-suffix));
  for (const key of Object.keys(baseline.otherReferences)) assert.deepEqual(after[key], before[key]);
  assert.deepEqual(after.followsByRegion.jp, []);
  assert.deepEqual(repairParts(pkg, after, e), after);
});

test('accepted follow evidence refresh changes only its base line and base native row', () => {
  const pkg = repairPackage(fixture(), e), repairedLanes = repairParts(pkg, lanes(), e);
  const refreshed = repairFollowEvidence(pkg, repairedLanes, structuredClone(baseline), e);
  const scrub = value => { const copy = structuredClone(value);
    copy.packageLines.find(item => item.line.id === e.lineID).line = null;
    copy.nativeParts[copy.nativeParts.findIndex(row => row[0] === e.lineID)] = null; return copy; };
  assert.deepEqual(scrub(refreshed), scrub(baseline));
  assert.deepEqual(refreshed.packageLines.find(item => item.line.id === e.lineID).line,
    pkg.lines[lineItem(e.lineID).index]);
  assert.deepEqual(refreshed.nativeParts.find(row => row[0] === e.lineID),
    repairedLanes.partsByRegion.jp.find(row => row[0] === e.lineID));
  assert.deepEqual(repairFollowEvidence(pkg, repairedLanes, refreshed, e), refreshed);
  const changed = structuredClone(refreshed); changed.observation = 'drift';
  assert.throws(() => repairFollowEvidence(pkg, repairedLanes, changed, e), /outside coordinated slots/);
});

test('scoped producer derives and owner removes only the exact post-curve obsolete follow', () => {
  const pkg = repairPackage(fixture(), e), ids = new Set([e.lineID, e.branchLineID]);
  const policy = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-render-groups.json', import.meta.url)));
  const render = { ...policy, byLineId: Object.fromEntries(Object.entries(policy.byLineId || {})
    .filter(([id]) => ids.has(id))) };
  const derived = deriveDisplayRows('jp', { ...pkg, lines: pkg.lines.filter(line => ids.has(line.id)), lanes: undefined },
    { displayLandlords: [] }, render, {}, [], { reversed: [] });
  assert.deepEqual(derived.follows, [e.producer.obsoleteFollowAfterCurve]);
  const repairedLanes = repairParts(pkg, lanes(), e);
  const refreshed = repairFollowEvidence(pkg, repairedLanes, structuredClone(baseline), e);
  const withDerived = structuredClone(repairedLanes);
  withDerived.followsByRegion.jp = [structuredClone(e.producer.obsoleteFollowAfterCurve)];
  assert.deepEqual(removeReviewedFollow(pkg, withDerived, refreshed).followsByRegion.jp, []);
  const nearMiss = structuredClone(repairedLanes);
  nearMiss.followsByRegion.jp = [[...e.producer.obsoleteFollowAfterCurve.slice(0, 3), 100,
    ...e.producer.obsoleteFollowAfterCurve.slice(4)]];
  assert.throws(() => removeReviewedFollow(pkg, nearMiss, refreshed), /reviewed follow/);
});

test('candidate output is one complete interval 4 feature and baselines fail closed', () => {
  const pkg = repairPackage(fixture(), e), geo = candidateGeoJSON(pkg, e);
  assert.equal(geo.features.length, 1);
  assert.equal(geo.features[0].properties.intervalIndex, 4);
  assert.deepEqual(geo.features[0].geometry.coordinates, loadReviewedCandidate(e));
  const changed = fixture(); changed.lines[lineItem(e.branchLineID).index].segments[0][2][1][0] += .00001;
  assert.throws(() => repairPackage(changed, e), /branch package dependency/);
  const changedLanes = lanes(); changedLanes.partsByRegion.jp.find(row => row[0] === e.branchLineID)[5] += 1;
  assert.throws(() => repairParts(repairPackage(fixture(), e), changedLanes, e), /branch native part/);
});
