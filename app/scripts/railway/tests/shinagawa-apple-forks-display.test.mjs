import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import {
  repairPackage, repairParts, validateEvidence,
} from '../repair-shinagawa-apple-forks-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const stroke = require('../../../public/rail-stroke.js');
const read = relative => JSON.parse(fs.readFileSync(new URL(relative, import.meta.url)));
const evidence = read('../shinagawa-apple-forks-display-evidence.json');
const livePackage = read('../../../public/rail/jp-2025.json');
const baselineLanes = () => structuredClone(evidence.baseline.lanes);
const ids = Object.keys(evidence.candidates);
const YAMANOTE = 'jp-東日本旅客鉄道-山手線';
const TOKAIDO = 'jp-東日本旅客鉄道-東海道線';
const OSAKI = 'jp-東日本旅客鉄道-大崎支線';
const SOBU = 'jp-東日本旅客鉄道-総武線-3';
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const metres = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
  (b[1] - a[1]) * 111320);
const cumulative = points => points.reduce((result, point, index) => {
  if (index) result.push(result.at(-1) + metres(points[index - 1], point));
  return result;
}, [0]);
const at = (points, measures, target) => {
  if (target <= 0) return points[0];
  if (target >= measures.at(-1)) return points.at(-1);
  let index = 1;
  while (measures[index] < target) index += 1;
  const fraction = (target - measures[index - 1]) / (measures[index] - measures[index - 1]);
  return points[index - 1].map((value, axis) => value + fraction * (points[index][axis] - value));
};

test('accepted source set and both complete interval candidates are frozen', () => {
  validateEvidence(evidence);
  assert.equal(evidence.source.nativeViews.length, 15);
  assert.deepEqual(evidence.policy.acceptedIntervalIDs, [`${YAMANOTE}#0`, `${TOKAIDO}#6`]);
  assert.deepEqual(ids.map(id => evidence.candidates[id].pointCount), [177, 54]);
  for (const mutate of [
    value => { value.status = 'pending'; },
    value => { value.source.candidateSha256 = '0'.repeat(64); },
    value => { value.candidates[YAMANOTE].coordinates[5][0] += .00001; },
    value => { value.policy.exactOsakiStem[0][0] += .00001; },
  ]) {
    const changed = structuredClone(evidence); mutate(changed);
    assert.throws(() => validateEvidence(changed));
  }
});

test('outer package stage changes only the two accepted display intervals', () => {
  const result = repairPackage(livePackage, evidence);
  for (const id of ids) {
    const before = evidence.baseline.lines[id], after = result.lines[evidence.baseline.packageIndices[id]];
    const interval = evidence.candidates[id].intervalIndex;
    assert.deepEqual(after.displayIntervalCoordinates[interval], evidence.candidates[id].coordinates);
    assert.deepEqual(after.stations, before.stations);
    assert.deepEqual(after.segments, before.segments);
    const expectedOverrides = { ...(before.displayIntervalCoordinates || {}),
      [interval]: evidence.candidates[id].coordinates };
    assert.deepEqual(after.displayIntervalCoordinates, expectedOverrides);
  }
  for (const id of [SOBU, OSAKI, `${OSAKI}-p1`])
    assert.deepEqual(result.lines.find(line => line.id === id), livePackage.lines.find(line => line.id === id));
  assert.deepEqual(repairPackage(result, evidence), result);
  const changed = structuredClone(livePackage);
  changed.lines[evidence.baseline.packageIndices[YAMANOTE]].segments[0][0] += 1;
  assert.throws(() => repairPackage(changed, evidence), /dependency changed/);
});

test('Shinagawa transverse alias removes only the retained-anchor connector and upgrades the exact accepted line', () => {
  const fix = evidence.transverseStationFix, result = repairPackage(livePackage, evidence);
  const before = structuredClone(evidence.baseline.lines[YAMANOTE]);
  before.displayIntervalCoordinates = { ...before.displayIntervalCoordinates,
    0: structuredClone(fix.previousAcceptedCoordinates) };
  const turn = (a, b, c) => {
    const cosine = Math.cos(b[1] * Math.PI / 180);
    const ab = [(b[0] - a[0]) * cosine, b[1] - a[1]];
    const bc = [(c[0] - b[0]) * cosine, c[1] - b[1]];
    return Math.acos(Math.max(-1, Math.min(1, (ab[0] * bc[0] + ab[1] * bc[1]) /
      (Math.hypot(...ab) * Math.hypot(...bc))))) * 180 / Math.PI;
  };
  const after = result.lines.find(line => line.id === YAMANOTE);
  assert.deepEqual(fix.after, [139.73845609051148, 35.628135]);
  assert.deepEqual(after.displayStationCoordinates['004095'], fix.after);
  assert.deepEqual(after.displayIntervalCoordinates[0][0], fix.after);
  assert.ok(Math.abs(turn(...fix.previousAcceptedCoordinates.slice(0, 3)) - 36.57170211819106) < 1e-8);
  assert.ok(turn(...after.displayIntervalCoordinates[0].slice(0, 3)) < 1e-6);
  assert.deepEqual(after.displayIntervalCoordinates[0].slice(1), fix.previousAcceptedCoordinates.slice(1));
  assert.deepEqual(after.stations, before.stations);
  assert.deepEqual(after.segments, before.segments);
  assert.equal(fix.wholePlatformCentre, 'unresolved');
  for (const line of livePackage.lines.filter(line => line.id !== YAMANOTE))
    assert.deepEqual(result.lines.find(row => row.id === line.id)?.displayStationCoordinates,
      line.displayStationCoordinates);
  assert.deepEqual(result.lines.find(line => line.id === TOKAIDO).displayIntervalCoordinates[6],
    evidence.candidates[TOKAIDO].coordinates);
  const previous = structuredClone(livePackage);
  previous.lines[evidence.baseline.packageIndices[YAMANOTE]] = before;
  previous.geometrySource.manualOverrides['shinagawa-apple-forks-display'] = structuredClone(fix.previousStageRecord);
  assert.deepEqual(repairPackage(previous, evidence), result);
  assert.deepEqual(repairPackage(result, evidence), result);
});

test('native parts and every known measured reference remap on its owning station interval', () => {
  const pkg = repairPackage(livePackage, evidence), result = repairParts(pkg, baselineLanes(), evidence);
  for (const id of ids) {
    const oldPart = evidence.baseline.lanes.partsByRegion.jp.find(row => row[0] === id);
    const part = result.partsByRegion.jp.find(row => row[0] === id);
    assert.notDeepEqual(part, oldPart);
    const line = pkg.lines.find(row => row.id === id);
    assert.deepEqual(part, result.partsByRegion.jp.find(row => row[0] === id));
    const displayPart = network.displayPartsForLine(line)[0];
    if (part[7]) assert.deepEqual(part[7], displayPart);
    else assert.deepEqual(part.slice(2, 4), [0, line.stations.length - 2]);
    assert.equal(part[4], displayPart.length);
  }
  const unrelated = row => !ids.includes(row[0]) && !ids.includes(row[4]);
  for (const key of ['byRegion', 'followsByRegion', 'familyWindowsByRegion'])
    assert.deepEqual(result[key].jp.filter(unrelated), evidence.baseline.lanes[key].jp.filter(unrelated));
  assert.deepEqual(result.partsByRegion.jp.filter(row => !ids.includes(row[0])),
    evidence.baseline.lanes.partsByRegion.jp.filter(row => !ids.includes(row[0])));

  const yamanotePart = network.displayPartsForLine(pkg.lines.find(row => row.id === YAMANOTE))[0];
  const yamanoteMeasures = cumulative(yamanotePart);
  for (const branch of [OSAKI, `${OSAKI}-p1`]) {
    const follow = result.followsByRegion.jp.find(row => row[0] === branch && row[4] === YAMANOTE);
    assert.deepEqual(at(yamanotePart, yamanoteMeasures, follow[6]), evidence.policy.exactOsakiStem.at(-1));
    assert.deepEqual(at(yamanotePart, yamanoteMeasures, follow[7]), evidence.policy.exactOsakiStem.at(-3));
  }
  const family = result.familyWindowsByRegion.jp.find(row => row[0] === YAMANOTE && row[5] === '東日本旅客鉄道:大崎支線');
  assert.deepEqual(at(yamanotePart, yamanoteMeasures, family[2]), evidence.policy.exactOsakiStem.at(-3));
  assert.deepEqual(at(yamanotePart, yamanoteMeasures, family[3]), evidence.policy.exactOsakiStem.at(-1));

  const oldTokaido = evidence.baseline.lanes.partsByRegion.jp.find(row => row[0] === TOKAIDO)[7];
  const oldMeasures = cumulative(oldTokaido);
  const newTokaido = network.displayPartsForLine(pkg.lines.find(row => row.id === TOKAIDO))[0];
  const newMeasures = cumulative(newTokaido);
  const downstream = result.followsByRegion.jp.find(row => row[4] === TOKAIDO);
  for (const [oldMeasure, newMeasure] of [[20625, downstream[6]], [23575, downstream[7]]])
    assert.ok(metres(at(oldTokaido, oldMeasures, oldMeasure), at(newTokaido, newMeasures, newMeasure)) < 1e-6);
  assert.deepEqual(repairParts(pkg, result, evidence), result);
});

test('accepted native rows upgrade without changing Tokaido rulers or the Osaki shared coordinates', () => {
  const pkg = repairPackage(livePackage, evidence), old = baselineLanes();
  const fix = evidence.transverseStationFix;
  const owns = (key, row) => ids.includes(row[0]) || (key === 'followsByRegion' && ids.includes(row[4]));
  for (const key of ['partsByRegion', 'byRegion', 'followsByRegion', 'familyWindowsByRegion']) {
    let index = 0;
    old[key].jp = old[key].jp.map(row => owns(key, row) ? structuredClone(fix.previousAcceptedRows[key][index++]) : row);
    assert.equal(index, fix.previousAcceptedRows[key].length);
  }
  let hubIndex = 0;
  for (const hub of old.hubReportByRegion.jp) hub.members = (hub.members || []).map(member =>
    ids.includes(member.lineId) ? structuredClone(fix.previousAcceptedHubs[hubIndex++][1]) : member);
  const result = repairParts(pkg, old, evidence);
  const yamanote = pkg.lines.find(line => line.id === YAMANOTE);
  const points = network.displayPartsForLine(yamanote)[0], measures = cumulative(points);
  const part = result.partsByRegion.jp.find(row => row[0] === YAMANOTE);
  assert.equal(part[6], null, 'keep the current interval-backed native part');
  assert.equal(part[7], null, 'no materialized coordinate override in the interval-backed row');
  assert.deepEqual([points[0], points.at(-1)], [fix.after, yamanote.stations.at(-1).slice(2, 4)]);
  assert.equal(result.byRegion.jp.find(row => row[0] === YAMANOTE)[2], 0);
  const hub = result.hubReportByRegion.jp.find(row => row.hubId === 'jp-shinagawa');
  assert.equal(hub.members.find(row => row.lineId === YAMANOTE).from, 0);
  const built = network.buildNetworkFromCompactPackage(pkg, null, result);
  const nativePart = built.strokeModel.lines.find(row => row.lineId === YAMANOTE).parts[0];
  assert.deepEqual([nativePart.coordinates[0], nativePart.coordinates.at(-1)],
    [fix.after, yamanote.stations.at(-1).slice(2, 4)]);
  for (const key of ['partsByRegion', 'byRegion', 'followsByRegion', 'familyWindowsByRegion']) {
    const tokaido = row => row[0] === TOKAIDO || (key === 'followsByRegion' && row[4] === TOKAIDO);
    assert.deepEqual(result[key].jp.filter(tokaido), old[key].jp.filter(tokaido));
  }
  for (const branch of [OSAKI, `${OSAKI}-p1`]) {
    const before = old.followsByRegion.jp.find(row => row[0] === branch && row[4] === YAMANOTE);
    const after = result.followsByRegion.jp.find(row => row[0] === branch && row[4] === YAMANOTE);
    assert.deepEqual(after.slice(0, 6), before.slice(0, 6));
    assert.notEqual(after[6], before[6]);
    assert.deepEqual(at(points, measures, after[6]), evidence.policy.exactOsakiStem.at(-1));
    assert.deepEqual(at(points, measures, after[7]), evidence.policy.exactOsakiStem.at(-3));
  }
  assert.deepEqual(repairParts(pkg, result, evidence), result);
});

test('production RailStroke retains accepted station ends and the Osaki handoff at z16, z18 and z19', () => {
  const pkg = repairPackage(livePackage, evidence), lanes = repairParts(pkg, baselineLanes(), evidence);
  const built = network.buildNetworkFromCompactPackage(pkg, null, lanes);
  const laneGapPx = 2.7, cornerRadiusPx = 3.6;
  const part = id => built.strokeModel.lines.find(line => line.lineId === id).parts[0];
  const shapeBoundaries = source => [...(source.tenantWindows || []), ...(source.familyWindows || [])]
    .flatMap(window => [window.from, window.to]);
  const render = (id, zoom) => {
    const source = part(id);
    return stroke.buildStroke(source.coordinates.map(point => stroke.project(point, zoom)), {
      measures: source.measures, rows: source.rows, totalMetres: source.totalMetres,
      laneGapPx, minRampPx: 24, cornerRadiusPx, minCornerRadiusPx: 3,
      anchors: source.anchors, enforceMinimumCornerRadius: true,
      follows: source.follows.map(follow => ({ ...follow,
        points: part(follow.canonLineId).coordinates.map(point => stroke.project(point, zoom)),
        measures: part(follow.canonLineId).measures,
        shapeBoundaryMeasures: shapeBoundaries(part(follow.canonLineId)),
      })),
      shapeBoundaryMeasures: shapeBoundaries(source),
    });
  };
  const renderCentreline = (id, zoom) => {
    const source = part(id);
    return stroke.buildStroke(source.coordinates.map(point => stroke.project(point, zoom)), {
      measures: source.measures, rows: [{ from: 0, to: source.totalMetres, lane: 0 }],
      totalMetres: source.totalMetres, laneGapPx, minRampPx: 24,
      cornerRadiusPx, minCornerRadiusPx: 3, anchors: source.anchors,
      enforceMinimumCornerRadius: true, follows: [],
      shapeBoundaryMeasures: shapeBoundaries(source),
    });
  };
  const strokeAt = (rendered, measure) => measure === 0 ? rendered.points[0]
    : stroke.sliceStroke(rendered.points, rendered.measures, measure - .001, measure).at(-1);
  const pixels = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const samples = (from, to) => {
    const result = [];
    for (let measure = from; measure < to; measure += 10) result.push(measure);
    result.push(to);
    return result;
  };
  const diagnostics = [], violations = [];
  for (const zoom of [16, 18, 19]) {
    for (const id of ids) {
      const source = part(id), rendered = render(id, zoom), centreline = renderCentreline(id, zoom);
      const candidate = evidence.candidates[id];
      const line = pkg.lines.find(row => row.id === id), interval = candidate.intervalIndex;
      const startStation = line.stations[interval], endStation = line.stations[interval + 1];
      const startCoordinate = line.displayStationCoordinates?.[startStation[0]] || startStation.slice(2, 4);
      const start = source.coordinates.findIndex(point => equal(point, startCoordinate));
      const end = source.coordinates.findIndex(point => equal(point, endStation.slice(2, 4)));
      assert.ok(start >= 0 && end > start);
      const intervalSamples = samples(source.measures[start], source.measures[end]);
      const corridorMaximum = intervalSamples.reduce((maximum, measure) => {
        const error = pixels(strokeAt(rendered, measure), strokeAt(centreline, measure));
        return error > maximum.error ? { measure, error } : maximum;
      }, { measure: intervalSamples[0], error: 0 });
      const corridorLimit = laneGapPx / 2 + .1;
      diagnostics.push({ zoom, id, samples: intervalSamples.length, corridorMaximum });
      if (corridorMaximum.error > corridorLimit)
        violations.push(`${id} z${zoom} fork corridor drifted ${corridorMaximum.error}px at ${corridorMaximum.measure}m`);
      assert.ok(pixels(strokeAt(rendered, source.measures[start]), stroke.project(candidate.coordinates[0], zoom)) < 2);
      assert.ok(pixels(strokeAt(rendered, source.measures[end]), stroke.project(candidate.coordinates.at(-1), zoom)) < .05);
    }
    const yamanoteStroke = render(YAMANOTE, zoom);
    for (const branchID of [OSAKI, `${OSAKI}-p1`]) {
      const branch = part(branchID), branchStroke = render(branchID, zoom);
      const handoff = branch.follows.find(row => row.canonLineId === YAMANOTE);
      const handoffSamples = samples(handoff.from, handoff.to);
      const handoffMaximum = handoffSamples.reduce((maximum, measure) => {
        const fraction = (measure - handoff.from) / (handoff.to - handoff.from);
        const canonical = handoff.canonFrom + fraction * (handoff.canonTo - handoff.canonFrom);
        const error = pixels(strokeAt(branchStroke, measure), strokeAt(yamanoteStroke, canonical));
        return error > maximum.error ? { measure, canonical, error } : maximum;
      }, { measure: handoff.from, canonical: handoff.canonFrom, error: 0 });
      diagnostics.push({ zoom, id: branchID, samples: handoffSamples.length, handoffMaximum });
      if (handoffMaximum.error > laneGapPx + .05)
        violations.push(`${branchID} z${zoom} handoff drifted ${handoffMaximum.error}px at ${handoffMaximum.measure}m`);
      const ownStroke = renderCentreline(branchID, zoom);
      const continuationSamples = samples(handoff.to, Math.min(branch.totalMetres, handoff.to + 300));
      const continuationMaximum = continuationSamples.reduce((maximum, measure) => {
        const error = pixels(strokeAt(branchStroke, measure), strokeAt(ownStroke, measure));
        return error > maximum.error ? { measure, error } : maximum;
      }, { measure: handoff.to, error: 0 });
      diagnostics.push({ zoom, id: `${branchID}:continuation`, samples: continuationSamples.length,
        continuationMaximum });
      if (continuationMaximum.error > .1)
        violations.push(`${branchID} z${zoom} continuation drifted ${continuationMaximum.error}px at ${continuationMaximum.measure}m`);
    }
  }
  console.log('Shinagawa dense RailStroke maxima', JSON.stringify(diagnostics));
  assert.deepEqual(violations, []);
});

test('unknown measured references and unreviewed source changes fail closed', () => {
  const pkg = repairPackage(livePackage, evidence), lanes = baselineLanes();
  lanes.chainBoundariesByRegion.jp.push([YAMANOTE, 0, 0, 'unknown']);
  assert.throws(() => repairParts(pkg, lanes, evidence), /unknown measured reference/);
  const changed = baselineLanes();
  changed.byRegion.jp.find(row => row[0] === YAMANOTE)[3] += 1;
  assert.throws(() => repairParts(pkg, changed, evidence), /reference changed/);
});

test('a short exact shared prefix stays canonical while both real continuations remain', () => {
  const measures = [0, 100, 200, 300, 400, 500];
  // The shared boundary is also the far bend of a small canonical seam jog.
  const canonical = [[0, 0], [10, 0], [20, 2], [30, 2], [40, 2], [50, 2]];
  const branch = [[0, 0], [10, 0], [20, 2], [30, -10], [40, -10], [50, -10]];
  const options = points => ({
    measures, totalMetres: 500, rows: [{ from: 0, to: 500, lane: 0 }],
    laneGapPx: 2.7, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: 3,
    anchors: [], enforceMinimumCornerRadius: true, follows: [], points,
    shapeBoundaryMeasures: [0, 200],
  });
  const canonicalStroke = stroke.buildStroke(canonical, options(canonical));
  const ownBranchStroke = stroke.buildStroke(branch, options(branch));
  const branchOptions = options(branch);
  branchOptions.follows = [{
    from: 0, to: 200, canonFrom: 0, canonTo: 200,
    points: canonical, measures, shapeBoundaryMeasures: [0, 200],
  }];
  const branchStroke = stroke.buildStroke(branch, branchOptions);
  const point = (rendered, measure) => measure === 0 ? rendered.points[0]
    : stroke.sliceStroke(rendered.points, rendered.measures, measure - .001, measure).at(-1);
  for (let measure = 0; measure <= 200; measure += 10) {
    const a = point(branchStroke, measure), b = point(canonicalStroke, measure);
    const error = Math.hypot(a[0] - b[0], a[1] - b[1]);
    assert.ok(error < .1, `shared prefix drifted ${error}px at ${measure}m`);
  }
  for (let measure = 200; measure <= 500; measure += 10) {
    const a = point(branchStroke, measure), b = point(ownBranchStroke, measure);
    const error = Math.hypot(a[0] - b[0], a[1] - b[1]);
    assert.ok(error < .1, `branch continuation drifted ${error}px at ${measure}m`);
  }
  assert.ok(branchStroke.points.at(-1)[1] < -8, 'branch continuation was replaced');
  assert.ok(canonicalStroke.points.at(-1)[1] > 1, 'canonical continuation was replaced');

  const overlapOptions = options(branch);
  overlapOptions.follows = [branchOptions.follows[0], {
    from: 50, to: 150, canonFrom: 50, canonTo: 150,
    points: canonical.map(([x, y]) => [x, y + 5]), measures,
    shapeBoundaryMeasures: [50, 150],
  }];
  const overlapStroke = stroke.buildStroke(branch, overlapOptions);
  for (let measure = 50; measure <= 150; measure += 10) {
    const a = point(overlapStroke, measure), b = point(canonicalStroke, measure);
    const error = Math.hypot(a[0] - b[0], a[1] - b[1]);
    assert.ok(error < .1, `ordinary overlap diluted exact shared follow by ${error}px at ${measure}m`);
  }

  const nearCanonical = canonical.map(([x, y], index) => [x, index === 1 ? y + .001 : y]);
  const nearOptions = options(branch);
  nearOptions.follows = [{
    from: 0, to: 200, canonFrom: 0, canonTo: 200,
    points: nearCanonical, measures, shapeBoundaryMeasures: [0, 200],
  }];
  const nearStroke = stroke.buildStroke(branch, nearOptions);
  const nearPoint = point(nearStroke, 250), ownPoint = point(ownBranchStroke, 250);
  const nearContinuationError = Math.hypot(
    nearPoint[0] - ownPoint[0], nearPoint[1] - ownPoint[1],
  );
  assert.ok(nearContinuationError > .1,
    'near-but-not-exact prefix incorrectly used exact shared behavior');
});
