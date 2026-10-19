import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const stroke = require('../../../public/rail-stroke.js');
const liveLanes = JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json', import.meta.url)));
const evidence = JSON.parse(fs.readFileSync(new URL('../onoda-suzumeda-follow-evidence.json', import.meta.url)));
const curveEvidence = JSON.parse(fs.readFileSync(new URL('../onoda-suzumeda-west-curve-display-evidence.json', import.meta.url)));
const { repairLanes } = await import('../repair-onoda-suzumeda-follow.mjs');
const reviewedObsolete = evidence.packageLines.find(item => item.line.id === evidence.baseLineID)
  .line.displayIntervalCoordinates?.['4']
  ? curveEvidence.producer.obsoleteFollowAfterCurve : evidence.obsoleteFollow;

const clone = value => structuredClone(value);
const packageFixture = () => {
  const lines = Array.from({ length: Math.max(...evidence.packageLines.map(item => item.index)) + 1 },
    (_, index) => ({ id: `unrelated-${index}` }));
  for (const item of evidence.packageLines) lines[item.index] = clone(item.line);
  return { format: 'compact-v1', country: 'jp', lines };
};
const laneFixture = () => {
  const result = clone(liveLanes), ids = new Set([evidence.baseLineID, evidence.branchLineID]);
  result.partsByRegion.jp = result.partsByRegion.jp.filter(row => !ids.has(row[0]));
  result.partsByRegion.jp.push(...clone(evidence.nativeParts));
  result.followsByRegion.jp = result.followsByRegion.jp.filter(row => !ids.has(row[0]) && !ids.has(row[4]));
  result.followsByRegion.jp.push(clone(reviewedObsolete));
  for (const [key, rows] of Object.entries(evidence.otherReferences)) {
    if (Array.isArray(result[key].jp)) {
      result[key].jp = result[key].jp.filter(row =>
        ![evidence.baseLineID, evidence.branchLineID].some(id => JSON.stringify(row).includes(id)));
      result[key].jp.push(...clone(rows));
    } else Object.assign(result[key].jp, clone(rows));
  }
  return result;
};
const scopedPackage = { format: 'compact-v1', country: 'jp',
  lines: evidence.packageLines.map(item => clone(item.line)) };
const part = (built, id) => built.strokeModel.lines.find(line => line.lineId === id).parts[0];
const render = (source, built, follows) => stroke.buildStroke(
  source.coordinates.map(point => stroke.project(point, 18)), {
    measures: source.measures, rows: source.rows, totalMetres: source.totalMetres,
    laneGapPx: 2.7, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: 3,
    anchors: source.anchors, enforceMinimumCornerRadius: true, shapeBoundaryMeasures: [],
    follows: follows.map(follow => {
      const canonical = part(built, follow.canonLineId);
      return { ...follow, points: canonical.coordinates.map(point => stroke.project(point, 18)),
        measures: canonical.measures, shapeBoundaryMeasures: [] };
    }),
  });
const at = (rendered, metres) => metres === 0 ? rendered.points[0]
  : stroke.sliceStroke(rendered.points, rendered.measures, metres - .001, metres).at(-1);
const pixels = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);

test('reviewed Onoda fork retires only the non-exact Suzumeda follow', () => {
  const before = laneFixture();
  const unrelatedFollow = clone(before.followsByRegion.jp.find(row =>
    row[0] !== evidence.baseLineID && row[0] !== evidence.branchLineID &&
    row[4] !== evidence.baseLineID && row[4] !== evidence.branchLineID));
  const originalFollowCount = before.followsByRegion.jp.length;
  const after = repairLanes(packageFixture(), before, evidence);
  assert(!after.followsByRegion.jp.some(row => JSON.stringify(row) === JSON.stringify(reviewedObsolete)));
  assert.equal(after.followsByRegion.jp.length, originalFollowCount - 1);
  assert(after.followsByRegion.jp.some(row => JSON.stringify(row) === JSON.stringify(unrelatedFollow)),
    'unrelated follow changed');
  const expected = laneFixture();
  expected.followsByRegion.jp = expected.followsByRegion.jp.filter(row =>
    JSON.stringify(row) !== JSON.stringify(reviewedObsolete));
  assert.deepEqual(after, expected);
  assert.deepEqual(repairLanes(packageFixture(), after, evidence), after);
});

test('runtime uses the branch own path for the first 400 metres after follow removal', () => {
  const baseline = laneFixture();
  const repaired = repairLanes(packageFixture(), clone(baseline), evidence);
  const oldBuilt = network.buildNetworkFromCompactPackage(scopedPackage, null, baseline);
  const newBuilt = network.buildNetworkFromCompactPackage(scopedPackage, null, repaired);
  const oldPart = part(oldBuilt, evidence.branchLineID), newPart = part(newBuilt, evidence.branchLineID);
  assert.equal(oldPart.follows.length, 1);
  assert.equal(newPart.follows.length, 0);
  assert.deepEqual(newPart.coordinates, oldPart.coordinates);
  assert.deepEqual(newPart.anchors, oldPart.anchors);
  assert.deepEqual(newPart.coordinates[0], evidence.packageLines[1].line.stations[0].slice(2, 4));
  const own = render(newPart, newBuilt, []), current = render(newPart, newBuilt, newPart.follows);
  for (let metres = 0; metres <= 400; metres += 25)
    assert(pixels(at(current, metres), at(own, metres)) < 1e-7, `own path drifted at ${metres}m`);
  const wrong = render(oldPart, oldBuilt, oldPart.follows), oldOwn = render(oldPart, oldBuilt, []);
  assert(pixels(at(wrong, 100), at(oldOwn, 100)) > 20, 'obsolete follow did not reproduce the observed fork drift');
  assert(pixels(at(wrong, 200), at(oldOwn, 200)) > 20, 'obsolete 300m blend did not retain the observed drift');
});

test('package, native parts, unrelated references, and reviewed follow fail closed', () => {
  const changedPackage = packageFixture();
  changedPackage.lines[evidence.packageLines[1].index].segments[0][2][1][0] += .00001;
  assert.throws(() => repairLanes(changedPackage, laneFixture(), evidence), /package line/);
  const changedPart = laneFixture();
  changedPart.partsByRegion.jp.find(row => row[0] === evidence.branchLineID)[5] += .1;
  assert.throws(() => repairLanes(packageFixture(), changedPart, evidence), /native part/);
  const changedFollow = laneFixture();
  changedFollow.followsByRegion.jp.find(row => row[0] === evidence.branchLineID)[3] += 1;
  assert.throws(() => repairLanes(packageFixture(), changedFollow, evidence), /follow|reference/);
  const newReference = laneFixture();
  newReference.familyWindowsByRegion.jp.push([evidence.branchLineID, 0, 0, 100, 0, 'new-family']);
  assert.throws(() => repairLanes(packageFixture(), newReference, evidence), /reference/);
});
