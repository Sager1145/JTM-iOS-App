import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import * as midcurve from '../repair-keiyo-midcurve.mjs';
import * as minami from '../repair-keiyo-minami-passenger-centre.mjs';
import * as shio from '../repair-keiyo-shio-transverse-display.mjs';
import { partRowsForLine } from '../build-display-lanes.mjs';
import * as tails from '../repair-keiyo-display-curves.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = relative => JSON.parse(fs.readFileSync(new URL(relative, import.meta.url)));
const published = read('../../../public/rail/jp-2025.json');
const beforeShio = midcurve.retainedShioPackage(published);
const input = midcurve.retainedMinamiPackage(beforeShio);
const publishedLanes = read('../../../public/rail/display-lanes.json');
const beforeShioLanes = shio.hasShioStage(published) ? shio.shioPartsForStage(published, publishedLanes, false) : publishedLanes;
const lanes = minami.hasMinamiStage(beforeShio)
  ? minami.minamiPartsForStage(beforeShio, beforeShioLanes, false) : beforeShioLanes;
const evidence = read('../keiyo-midcurve-evidence.json');
// The eastern regressions exercise their retained stage even after the
// western stage is published; the west tests compose it explicitly below.
delete input.lines.find(row => row.id === 'jp-東日本旅客鉄道-京葉線').displayIntervalCoordinates?.[8];
delete input.geometrySource.manualOverrides['keiyo-west-shared-corridor'];
lanes.partsByRegion.jp = lanes.partsByRegion.jp.map(row => row[0] === 'jp-東日本旅客鉄道-京葉線'
  ? partRowsForLine(input.lines.find(line => line.id === row[0]), network.displayPartsForLine(input.lines.find(line => line.id === row[0])))[0] : row);
lanes.followsByRegion.jp = lanes.followsByRegion.jp.filter(row => row[0] !== 'jp-東日本旅客鉄道-京葉線-3');
lanes.familyWindowsByRegion.jp = lanes.familyWindowsByRegion.jp.filter(row => row[0] !== 'jp-東日本旅客鉄道-京葉線-3'
  && !(row[0] === 'jp-東日本旅客鉄道-京葉線' && row[2] > 20500));

const cache = JSON.parse(fs.readFileSync(evidence.source.cacheAbsolutePath));
const trunkID = 'jp-東日本旅客鉄道-京葉線', armID = trunkID + '-2';
const find = (pkg, id) => pkg.lines.find(line => line.id === id);
const repaired = () => midcurve.repairPackage(input, evidence, cache);
const approach = shio.westernApproachEvidence;
const localLength = points => points.slice(1).reduce((sum, b, i) => {
  const a = points[i];
  return sum + Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360), (b[1] - a[1]) * 111320);
}, 0);
const approachDelta = localLength([approach.before, ...approach.candidateWindow, approach.after])
  - localLength([approach.before, ...approach.baselineWindow, approach.after]);

test('the eastern shared window is the same N02 feature chain, not a proximity merge', () => {
  const sections = read('../../../data/rail-sections.json');
  const shared = sections.features[14135], stationTrack = sections.features[14127];
  for (const feature of [shared, stationTrack]) {
    assert.equal(feature.properties.N02_003, '京葉線');
    assert.equal(feature.properties.N02_004, '東日本旅客鉄道');
  }
  const trunk = network.decodeIntervals(find(input, trunkID))[7];
  const arm = network.decodeIntervals(find(input, armID))[0];
  const canonicalShared = [[139.9957, 35.681665], ...shared.geometry.coordinates];
  assert.deepEqual(trunk.slice(0, 25), canonicalShared);
  assert.deepEqual(arm.slice(40).toReversed(), canonicalShared);
  // Both station-clipped legs terminate at the centre of the same final
  // survey edge 14127, rather than selecting two nearby different tracks.
  const [a, b] = stationTrack.geometry.coordinates;
  for (let axis = 0; axis < 2; axis++)
    assert(Math.abs((a[axis] + b[axis]) / 2 - canonicalShared[0][axis]) < 1e-10);
});

// Catches the original defect: only the arm received the reviewed survey,
// so the mainline continued to draw a second, sparse parallel red curve.
test('shared eastern trunk uses the reviewed arm curve while retaining the fork and physical railway', () => {
  const result = repaired(), trunk = find(result, trunkID), arm = find(result, armID);
  const shared = arm.displayIntervalCoordinates[0].slice(40).toReversed();
  const original = network.decodeIntervals(find(input, trunkID))[7];
  assert.deepEqual(trunk.displayIntervalCoordinates?.[7], [...shared, ...original.slice(25)]);
  assert.deepEqual(trunk.segments, find(input, trunkID).segments);
  assert.deepEqual(trunk.stations, find(input, trunkID).stations);
  assert.deepEqual(arm.segments, find(input, armID).segments);
  assert.deepEqual(arm.stations, find(input, armID).stations);
  assert.deepEqual(arm.displayIntervalCoordinates[0].slice(0, 41), evidence.candidate.slice(0, 41));
  assert.deepEqual(result.lines.filter(line => line.id !== trunkID && line.id !== armID),
    input.lines.filter(line => line.id !== trunkID && line.id !== armID));
  assert.deepEqual(midcurve.repairPackage(result, evidence, cache), result);
});

test('same-company shared tail elects one owner and leaves the independent eastern fork drawing', () => {
  const pkg = repaired(), result = midcurve.repairParts(pkg, lanes, evidence);
  const follows = result.followsByRegion.jp.filter(row => row[0] === armID);
  assert.equal(follows.length, 1);
  const follow = follows[0];
  assert.equal(follow[4], trunkID);
  assert(Math.abs(follow[2] - 2068.826) < 0.01);
  assert(Math.abs(follow[3] - 5415.1052) < 0.01);
  assert(follow[6] > follow[7], 'the trunk ruler runs in the opposite direction');
  const windows = result.familyWindowsByRegion.jp.filter(row => [armID, trunkID].includes(row[0]));
  assert.equal(windows.filter(row => row[4] === 0).length, 1);
  assert.equal(windows.filter(row => row[4] === 1).length, 1);
  const tenant = windows.find(row => row[4] === 1);
  assert.equal(tenant[0], armID);
  assert(tenant[2] > follow[2], 'independent fork and the blend stay drawable');
  assert(Math.abs(tenant[3] - follow[3]) < 0.1, 'one representative continues into the common station');
  assert.deepEqual(midcurve.repairParts(pkg, result, evidence), result);
  const unrelated = row => ![trunkID, armID].includes(row[0]);
  for (const key of ['partsByRegion', 'followsByRegion', 'familyWindowsByRegion'])
    assert.deepEqual(result[key].jp.filter(unrelated), lanes[key].jp.filter(unrelated));
  for (const key of Object.keys(lanes).filter(key => !['partsByRegion', 'followsByRegion', 'familyWindowsByRegion'].includes(key)))
    assert.deepEqual(result[key], lanes[key]);
});

test('older tail replay preserves the later reviewed shared corridor and its measured ownership', () => {
  const pkg = repaired(), updated = midcurve.repairParts(pkg, lanes, evidence);
  const tailEvidence = read('../keiyo-display-curves-evidence.json');
  const replay = tails.repairPackage(pkg, tailEvidence, cache, read('../../../data/rail-sections.json'));
  assert.deepEqual(replay, pkg);
  assert.deepEqual(tails.repairParts(replay, updated, tailEvidence), updated);
});

test('shared eastern ownership still refreshes the legal western tail baseline and validates western references', () => {
  const pkg = repaired(), tailEvidence = read('../keiyo-display-curves-evidence.json');
  const baseline = midcurve.repairParts(pkg, lanes, evidence);
  const westID = trunkID + '-3', westWindow = tailEvidence.windows.find(window => window.lineId === westID);
  baseline.partsByRegion.jp = baseline.partsByRegion.jp.map(row =>
    row[0] === westID ? structuredClone(westWindow.nativePartBaseline[row[1]]) : row);
  const result = tails.repairParts(pkg, baseline, tailEvidence);
  const west = result.partsByRegion.jp.find(row => row[0] === westID);
  assert.deepEqual(west.slice(0, 5), [westID, 0, -1, -1, 84]);
  assert(Math.abs(west[5] - (5906.6046 + approachDelta)) < 0.1);
  assert.equal(west[6], 'complex');
  assert.deepEqual(west[7], network.displayPartsForLine(find(pkg, westID))[0]);
  assert.deepEqual(result.followsByRegion, baseline.followsByRegion);
  assert.deepEqual(result.familyWindowsByRegion, baseline.familyWindowsByRegion);
  assert.deepEqual(tails.repairParts(pkg, result, tailEvidence), result);
  const stale = structuredClone(baseline);
  stale.followsByRegion.jp.push([westID, 0, 4700, 5000, 'other', 0, 23000, 23300]);
  assert.throws(() => tails.repairParts(pkg, stale, tailEvidence), /measured reference/);
});

test('western shared corridor reuses exact N02 passenger supports and retains its independent fork', () => {
  const westID = trunkID + '-3', sections = read('../../../data/rail-sections.json');
  const original = network.decodeIntervals(find(input, trunkID))[8];
  const canonical = network.decodeIntervals(find(input, westID))[0];
  assert.deepEqual(original.slice(7), canonical.slice(39));
  assert.deepEqual(original.slice(7, -1), sections.features[14150].geometry.coordinates.toReversed());
  assert.deepEqual(sections.features[14147].geometry.coordinates[0], original[7]);
  const pkg = midcurve.repairWestPackage(repaired());
  assert.deepEqual(find(pkg, trunkID).displayIntervalCoordinates[8],
    [...original.slice(0, 7), ...find(pkg, westID).displayIntervalCoordinates[0].slice(midcurve.sharedEvidence.western.armDisplayForkIndex)]);
  assert.deepEqual(find(pkg, trunkID).segments, find(input, trunkID).segments);
  assert.deepEqual(find(pkg, trunkID).stations, find(input, trunkID).stations);
  assert.deepEqual(find(pkg, westID), find(input, westID));
  assert.deepEqual(find(pkg, trunkID).displayIntervalCoordinates[7], find(repaired(), trunkID).displayIntervalCoordinates[7]);
  assert.deepEqual(midcurve.repairWestPackage(pkg), pkg);
  const physical = structuredClone(pkg);
  find(physical, westID).segments[0][0] += 0.1;
  assert.throws(() => midcurve.repairWestPackage(physical), /physical source/);
  const competing = structuredClone(pkg);
  find(competing, trunkID).displayIntervalCoordinates[8][12][0] += 0.00001;
  assert.throws(() => midcurve.repairWestPackage(competing), /Unreviewed western/);
});

test('west ownership composes with east replay and rejects unknown trunk or west follows', () => {
  const westID = trunkID + '-3', pkg = midcurve.repairWestPackage(repaired());
  const result = midcurve.repairParts(pkg, lanes, evidence);
  const follows = result.followsByRegion.jp.filter(row => row[4] === trunkID);
  assert.equal(follows.length, 2);
  const west = follows.find(row => row[0] === westID);
  assert(Math.abs(west[2] - (2129.8859 + approachDelta)) < 0.01);
  assert(Math.abs(west[3] - (5906.6046 + approachDelta)) < 0.01);
  assert(west[6] < west[7], 'west and trunk use the same direction');
  const windows = result.familyWindowsByRegion.jp.filter(row => [trunkID, armID, westID].includes(row[0]));
  assert.equal(windows.filter(row => row[4] === 0).length, 2);
  const tenant = windows.find(row => row[0] === westID);
  assert(Math.abs(tenant[2] - west[2] - 300) < 0.1);
  assert(Math.abs(tenant[3] - west[3]) < 0.1);
  assert.deepEqual(midcurve.repairPackage(pkg, evidence, cache), pkg);
  assert.deepEqual(midcurve.repairParts(pkg, result, evidence), result);
  const tailEvidence = read('../keiyo-display-curves-evidence.json');
  assert.deepEqual(tails.repairParts(tails.repairPackage(pkg, tailEvidence, cache, read('../../../data/rail-sections.json')), result, tailEvidence), result);
  const alteredRuler = structuredClone(result);
  alteredRuler.partsByRegion.jp.find(row => row[0] === westID)[5] += 1;
  assert.throws(() => midcurve.repairParts(pkg, alteredRuler, evidence), /native cache changed/);
  for (const key of ['hubReportByRegion', 'reversedLoopParts']) {
    const unknown = structuredClone(result);
    unknown[key].jp.push(key === 'reversedLoopParts' ? westID + '#0' : [westID, 0, 100, 500]);
    assert.throws(() => midcurve.repairParts(pkg, unknown, evidence), /measured reference/);
  }
  for (const id of [trunkID, westID]) {
    const unknown = structuredClone(result);
    unknown.followsByRegion.jp.push([id, 0, 100, 500, 'other', 0, 100, 500]);
    assert.throws(() => midcurve.repairParts(pkg, unknown, evidence), /Unreviewed Keiyo measured follow/);
  }
});

// Catches the observed east-side dent made by retaining an off-track N02
// alias immediately before the selected passenger survey began.
test('east survey entrance has no splice dent and retains the real fork', () => {
  const pkg = repaired(), arm = find(pkg, armID), points = arm.displayIntervalCoordinates[0];
  assert.deepEqual(points[45], [139.9623587, 35.6916424]);
  assert.deepEqual(points.slice(0, 45), evidence.baselineLine.displayIntervalCoordinates[0].slice(0, 45));
  assert.deepEqual(points[40], [139.9611, 35.69164]);
  const vector = (a, b) => [(b[0] - a[0]) * Math.cos(a[1] * Math.PI / 180), b[1] - a[1]];
  for (let i = 44; i <= 46; i++) {
    const a = vector(points[i - 1], points[i]), b = vector(points[i], points[i + 1]);
    const angle = Math.abs(Math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1]) * 180 / Math.PI);
    assert(angle < 10, `survey entrance ${i} has artificial turn ${angle}`);
  }
  assert.deepEqual(arm.segments, find(input, armID).segments);
  assert.deepEqual(arm.stations, find(input, armID).stations);
  const result = midcurve.repairParts(pkg, lanes, evidence);
  assert.deepEqual(midcurve.repairParts(pkg, result, evidence), result);
});

// Observed station dot was south of the four passenger tracks. Display-only
// representative coordinates must reach both station approaches and rulers.
test('Minami-Funabashi passenger centre composes through display parts, ownership and older replays', () => {
  const pkg = midcurve.repairPackage(midcurve.repairWestPackage(repaired()), evidence, cache, { minami: true });
  const trunk = find(pkg, trunkID), arm = find(pkg, armID);
  const latAt = (id, lon) => {
    const points = cache.elements.find(way => way.id === id).geometry;
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1], b = points[i];
      if (lon >= Math.min(a.lon, b.lon) && lon <= Math.max(a.lon, b.lon))
        return a.lat + (b.lat - a.lat) * (lon - a.lon) / (b.lon - a.lon);
    }
    assert.fail('Identified passenger track does not cover representative longitude');
  };
  const lon = 139.995806, point = [lon, (latAt(173053168, lon) + latAt(173053163, lon)) / 2];
  assert.deepEqual(trunk.displayStationCoordinates?.['003761'], point);
  assert.deepEqual(arm.displayStationCoordinates?.['003761'], point);
  assert(point[1] < latAt(1424469769, lon) && point[1] > latAt(1424469770, lon), 'centre lies between inner passenger faces');
  assert.deepEqual(trunk.displayIntervalCoordinates[7], [...arm.displayIntervalCoordinates[0].slice(40).toReversed(), ...network.decodeIntervals(trunk)[7].slice(25)]);
  assert.deepEqual(trunk.displayIntervalCoordinates[6].at(-1), point);
  const westBoundary = minami.minamiEvidence.westBoundary;
  const westIndex = evidence.candidate.findIndex(point => JSON.stringify(point) === JSON.stringify(westBoundary));
  assert(westIndex >= 0);
  assert.deepEqual(arm.displayIntervalCoordinates[0].slice(0, westIndex + 1), evidence.candidate.slice(0, westIndex + 1));
  const centreLongitudes = minami.minamiEvidence.supportLongitudes;
  for (const way of [minami.minamiEvidence.platformWays[0], minami.minamiEvidence.platformWays[3]])
    for (const sourcePoint of way.coordinates)
      if (sourcePoint[0] >= centreLongitudes[0] && sourcePoint[0] <= centreLongitudes.at(-1))
        assert(centreLongitudes.includes(sourcePoint[0]), 'both outer track supports must survive in the representative');
  for (const line of [trunk, arm]) {
    const baseline = find(input, line.id);
    assert.deepEqual(line.stations, baseline.stations);
    assert.deepEqual(line.segments, baseline.segments);
    assert(network.displayPartsForLine(line)[0].some(value => JSON.stringify(value) === JSON.stringify(point)));
  }
  const updated = midcurve.repairParts(pkg, lanes, evidence);
  const follow = updated.followsByRegion.jp.find(row => row[0] === armID);
  const parts = updated.partsByRegion.jp;
  const armPart = parts.find(row => row[0] === armID), trunkPart = parts.find(row => row[0] === trunkID);
  assert.deepEqual(armPart[7].at(-1), point);
  assert(trunkPart[7].some(value => JSON.stringify(value) === JSON.stringify(point)));
  assert(Math.abs(follow[3] - armPart[5]) < 0.1);
  assert(follow[6] > follow[7]);
  const locate = (points, target) => points.findIndex(value => JSON.stringify(value) === JSON.stringify(target));
  const fork = midcurve.sharedEvidence.fork;
  assert.deepEqual(armPart[7].slice(locate(armPart[7], fork)).toReversed(),
    trunkPart[7].slice(locate(trunkPart[7], point), locate(trunkPart[7], fork) + 1),
    'actual native parts must share the exact continuous passenger corridor');
  const retainedLanes = midcurve.repairParts(midcurve.retainedMinamiPackage(pkg), lanes, evidence);
  const westID = trunkID + '-3';
  assert.deepEqual(parts.find(row => row[0] === westID), retainedLanes.partsByRegion.jp.find(row => row[0] === westID));
  assert.deepEqual(updated.followsByRegion.jp.find(row => row[0] === westID).slice(0, 6),
    retainedLanes.followsByRegion.jp.find(row => row[0] === westID).slice(0, 6),
    'unaffected western arm ruler remains exact');
  assert.deepEqual(midcurve.repairPackage(pkg, evidence, cache), pkg);
  assert.deepEqual(midcurve.repairParts(pkg, updated, evidence), updated);
  const tailEvidence = read('../keiyo-display-curves-evidence.json');
  assert.deepEqual(tails.repairPackage(pkg, tailEvidence, cache, read('../../../data/rail-sections.json')), pkg);
  assert.deepEqual(tails.repairParts(pkg, updated, tailEvidence), updated);
  assert.equal(tails.reviewSummary(pkg, pkg, tailEvidence)[0].retainedDisplayStage, 'keiyo-minami-passenger-centre');
  const altered = structuredClone(updated);
  altered.followsByRegion.jp.find(row => row[0] === armID)[3] += 1;
  assert.throws(() => midcurve.repairParts(pkg, altered, evidence), /Unreviewed|changed|reference/);
});

test('Minami-Funabashi east approach joins original supports without an artificial reverse pair', () => {
  const pkg = midcurve.repairPackage(midcurve.repairWestPackage(repaired()), evidence, cache, { minami: true });
  const points = find(pkg, trunkID).displayIntervalCoordinates[6];
  const seam = points.findIndex(point => JSON.stringify(point) === JSON.stringify([139.99978, 35.67963]));
  assert(seam > 0, 'bounded original east support must be retained');
  assert.equal(points[seam + 1][0], 139.99874, 'source seam leads directly onto the surveyed corridor centre');
  const vector = (a, b) => [(b[0] - a[0]) * Math.cos(a[1] * Math.PI / 180), b[1] - a[1]];
  for (const i of [seam, seam + 1]) {
    const a = vector(points[i - 1], points[i]), b = vector(points[i], points[i + 1]);
    const angle = Math.abs(Math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1]) * 180 / Math.PI);
    assert(angle < 8, `local source seam creates an artificial ${angle} degree turn`);
  }
});

test('Shiohama transverse display stage preserves both joins, measured ownership and all earlier replays', () => {
  const pkg = midcurve.repairPackage(midcurve.repairWestPackage(repaired()), evidence, cache, { minami: true, shio: true });
  const trunk = find(pkg, trunkID), westID = trunkID + '-3', west = find(pkg, westID);
  const point = [139.9235689842168, 35.66650455364835];
  assert.deepEqual(trunk.displayStationCoordinates?.['003870'], point);
  assert.deepEqual(west.displayStationCoordinates?.['003870'], point);
  assert.deepEqual(trunk.displayIntervalCoordinates[8].at(-1), point);
  assert.deepEqual(trunk.displayIntervalCoordinates[9][0], point);
  assert.deepEqual(west.displayIntervalCoordinates[0].at(-1), point);
  const before = midcurve.repairPackage(midcurve.repairWestPackage(repaired()), evidence, cache, { minami: true });
  for (const [line, prior] of [[trunk, find(before, trunkID)], [west, find(before, westID)]]) {
    assert.deepEqual(line.stations, prior.stations);
    assert.deepEqual(line.segments, prior.segments);
  }
  assert.deepEqual(trunk.displayIntervalCoordinates[6], find(before, trunkID).displayIntervalCoordinates[6]);
  assert.deepEqual(trunk.displayIntervalCoordinates[7], find(before, trunkID).displayIntervalCoordinates[7]);
  assert.deepEqual(find(pkg, armID), find(before, armID));
  const boundary = [139.92561, 35.66991];
  const locate = (points, target) => points.findIndex(value => JSON.stringify(value) === JSON.stringify(target));
  const oldPoints = find(before, westID).displayIntervalCoordinates[0], oldIndex = locate(oldPoints, boundary);
  assert.deepEqual(west.displayIntervalCoordinates[0].slice(0, oldIndex + 1), oldPoints.slice(0, oldIndex + 1));
  const southBoundary = shio.shioEvidence.outboundBoundary;
  const outbound = trunk.displayIntervalCoordinates[9];
  const boundaryIndex = locate(outbound, southBoundary.point);
  assert.deepEqual(outbound.slice(boundaryIndex + 1),
    network.decodeIntervals(find(before, trunkID))[9].slice(southBoundary.insertIndex + 1),
    'all original outbound supports outside the bounded window remain exact');
  assert.deepEqual(trunk.displayIntervalCoordinates[8].slice(0, 7), find(before, trunkID).displayIntervalCoordinates[8].slice(0, 7));
  assert.deepEqual(shio.retainedShioPackage(pkg), before);
  const result = midcurve.repairParts(pkg, midcurve.repairParts(before, lanes, evidence), evidence);
  const armPart = result.partsByRegion.jp.find(row => row[0] === westID), trunkPart = result.partsByRegion.jp.find(row => row[0] === trunkID);
  const fork = midcurve.sharedEvidence.western.fork;
  assert.deepEqual(armPart[7].slice(locate(armPart[7], fork)), trunkPart[7].slice(locate(trunkPart[7], fork), locate(trunkPart[7], point) + 1));
  const follow = result.followsByRegion.jp.find(row => row[0] === westID);
  assert(Math.abs(follow[3] - armPart[5]) < 0.1);
  assert(follow[6] < follow[7]);
  assert.deepEqual(midcurve.repairPackage(pkg, evidence, cache), pkg);
  assert.deepEqual(midcurve.repairWestPackage(pkg), pkg);
  assert.deepEqual(midcurve.repairParts(pkg, result, evidence), result);
  const tailEvidence = read('../keiyo-display-curves-evidence.json');
  assert.deepEqual(tails.repairPackage(pkg, tailEvidence, cache, read('../../../data/rail-sections.json')), pkg);
  assert.deepEqual(tails.repairParts(pkg, result, tailEvidence), result);
  assert.equal(tails.reviewSummary(pkg, pkg, tailEvidence)[1].retainedDisplayStage, 'keiyo-shio-transverse-display');
  const changed = structuredClone(result);
  changed.followsByRegion.jp.find(row => row[0] === westID)[3] += 1;
  assert.throws(() => midcurve.repairParts(pkg, changed, evidence), /Unreviewed|changed|reference/);
});

// Original 004530/000013 showed a dip at the retained N02 alias between
// consecutive supports of the already selected passenger OSM way1436589310.
test('Ebigawa replay removes only the obsolete alias from both shared display paths', () => {
  const pkg = repaired(), alias = [139.98762, 35.6851];
  const guard = [[139.9865736, 35.685471], [139.9879815, 35.6850998]];
  for (const points of [find(pkg, armID).displayIntervalCoordinates[0],
    find(pkg, trunkID).displayIntervalCoordinates[7].toReversed()]) {
    assert(!points.some(point => JSON.stringify(point) === JSON.stringify(alias)));
    const index = points.findIndex(point => JSON.stringify(point) === JSON.stringify(guard[0]));
    assert(index >= 0);
    assert.deepEqual(points.slice(index, index + 2), guard);
  }
  assert.deepEqual(find(pkg, armID).segments, find(input, armID).segments);
  assert.deepEqual(find(pkg, trunkID).segments, find(input, trunkID).segments);
  assert.deepEqual(midcurve.repairPackage(pkg, evidence, cache), pkg);
  const final = midcurve.repairPackage(midcurve.repairWestPackage(pkg), evidence, cache, { minami: true, shio: true });
  const boundary = minami.minamiEvidence.westBoundary;
  const suffix = points => points.slice(points.findIndex(point => JSON.stringify(point) === JSON.stringify(boundary)));
  assert.deepEqual(suffix(find(final, armID).displayIntervalCoordinates[0]),
    suffix(find(published, armID).displayIntervalCoordinates[0]), 'Minami station-tail supports remain exact');
  for (const index of [8, 9])
    assert.deepEqual(find(final, trunkID).displayIntervalCoordinates[index],
      find(published, trunkID).displayIntervalCoordinates[index], 'Shio local supports remain exact');
  const migrated = minami.partsForRetainedKeiyoStage(final, publishedLanes, published);
  const parts = midcurve.repairParts(final, migrated, evidence);
  assert.deepEqual(midcurve.repairParts(final, parts, evidence), parts);
  assert.deepEqual(midcurve.repairPackage(final, evidence, cache), final);
});

test('western approach replay preserves shared trunk8 and Shio station tails across complete older replays', () => {
  const westID = trunkID + '-3', shared = midcurve.sharedEvidence.western;
  const pkg = midcurve.repairWestPackage(midcurve.repairPackage(published, evidence, cache));
  const arm = find(pkg, westID), trunk = find(pkg, trunkID);
  const provenance = pkg.geometrySource.manualOverrides['keiyo-west-shared-corridor'].passengerApproach;
  assert.equal(provenance.routeRelation, 14656632);
  assert.deepEqual(provenance.wayChain.map(row => row[0]), [229030139, 180845372, 180845377, 180845376]);
  assert.deepEqual(provenance.outerGuards, [approach.before, approach.after]);
  assert.deepEqual(provenance.canonicalVertexIndices, [22, 34]);
  assert.equal(provenance.canonicalForkIndex, 39);
  assert.equal(provenance.displayForkIndex, 48);
  assert.equal(provenance.source.publisher, 'OpenStreetMap contributors');
  assert(provenance.policy.includes('Not a surveyed corridor centre'));
  assert.equal(shared.armCanonicalForkIndex, 39);
  assert.equal(shared.armDisplayForkIndex, 48);
  assert.deepEqual(network.decodeIntervals(arm)[0][39], shared.fork);
  assert.deepEqual(arm.displayIntervalCoordinates[0][48], shared.fork);
  assert.deepEqual(arm.displayIntervalCoordinates[0].slice(22, 44), approach.candidateWindow);
  const retainedTail = points => points.slice(points.findIndex(point => JSON.stringify(point) === JSON.stringify(shared.fork)));
  assert.deepEqual(retainedTail(arm.displayIntervalCoordinates[0]),
    retainedTail(find(published, westID).displayIntervalCoordinates[0]));
  for (const index of [8, 9]) assert.deepEqual(trunk.displayIntervalCoordinates[index],
    find(published, trunkID).displayIntervalCoordinates[index], 'approach repair cannot move the shared corridor or Shio station joins');
  assert.deepEqual(find(pkg, armID), find(published, armID), 'Ebigawa and Minami supports remain exact');
  assert.deepEqual(arm.segments, find(published, westID).segments);
  assert.deepEqual(arm.stations, find(published, westID).stations);
  assert.deepEqual(pkg.lines.filter(line => ![trunkID, westID].includes(line.id)),
    published.lines.filter(line => ![trunkID, westID].includes(line.id)));
  const updated = minami.partsForRetainedKeiyoStage(pkg, publishedLanes, published);
  assert.deepEqual(midcurve.repairParts(pkg, updated, evidence), updated);
  assert.deepEqual(midcurve.repairPackage(pkg, evidence, cache), pkg);
  assert.deepEqual(midcurve.repairWestPackage(pkg), pkg);
  const tailEvidence = read('../keiyo-display-curves-evidence.json');
  assert.deepEqual(tails.repairPackage(pkg, tailEvidence, cache, read('../../../data/rail-sections.json')), pkg);
  assert.deepEqual(tails.repairParts(pkg, updated, tailEvidence), updated);
});
