#!/usr/bin/env node
// One display window continuing the already selected passenger tail track.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { hasShioStage, retainedShioPackage, repairShioPackage, hasShioNativeParts, shioPartsForStage, westernPassengerApproach, westernApproachEvidence } from './repair-keiyo-shio-transverse-display.mjs';
export { retainedShioPackage } from './repair-keiyo-shio-transverse-display.mjs';
import { hasMinamiStage, retainedMinamiPackage, repairMinamiPackage, minamiPartsForStage, hasMinamiNativeParts, withoutEbigawaDisplayAlias, partsForRetainedKeiyoStage } from './repair-keiyo-minami-passenger-centre.mjs';
export { retainedMinamiPackage } from './repair-keiyo-minami-passenger-centre.mjs';
import { partRowsForLine, deriveFamilyWindows } from './build-display-lanes.mjs';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export const sharedEvidence = JSON.parse(fs.readFileSync(path.join(ROOT, 'scripts/railway/keiyo-shared-corridor-evidence.json')));
const distance = (a, b) => Math.hypot((b[0]-a[0])*111320*Math.cos((a[1]+b[1])*Math.PI/360), (b[1]-a[1])*111320);
const measures = points => {
  const result = [0];
  for (let i = 1; i < points.length; i++) result.push(result.at(-1) + distance(points[i-1], points[i]));
  return result;
};

function sharedTrunkCoordinates(pkg, evidence) {
  const review = sharedEvidence;
  const trunk = pkg.lines.find(row => row.id === review.trunkID);
  const arm = pkg.lines.find(row => row.id === review.armID);
  assert.equal(trunk.operator, arm.operator, 'Shared passenger corridor company changed');
  assert.deepEqual(trunk.segments[review.trunkInterval], review.physicalIntervalBaseline,
    'Shared passenger corridor physical source changed');
  assert.deepEqual(arm.displayIntervalCoordinates[0], evidence.candidate, 'Reviewed arm display source changed');
  const original = network.decodeIntervals(trunk)[review.trunkInterval];
  assert.deepEqual(original[review.trunkDecodedForkIndex], review.fork);
  assert.deepEqual(evidence.candidate[review.armDisplayForkIndex], review.fork);
  assert.deepEqual(evidence.candidate.at(-1), review.station.slice(1));
  return [...evidence.candidate.slice(review.armDisplayForkIndex).toReversed(),
    ...original.slice(review.trunkDecodedForkIndex + 1)];
}
export function repairPackage(input, evidence, cache, options = {}) {
  input = structuredClone(input);
  for (const [id, interval] of [[evidence.lineID, 0], [sharedEvidence.trunkID, sharedEvidence.trunkInterval]]) {
    const line = input.lines.find(row => row.id === id);
    if (line.displayIntervalCoordinates?.[interval])
      line.displayIntervalCoordinates[interval] = withoutEbigawaDisplayAlias(line.displayIntervalCoordinates[interval]);
  }
  if (hasShioStage(input)) return repairShioPackage(repairPackage(retainedShioPackage(input), evidence, cache), cache);
  if (hasMinamiStage(input)) {
    const pkg = repairMinamiPackage(repairPackage(retainedMinamiPackage(input), evidence, cache), cache);
    return options.shio ? repairShioPackage(pkg, cache) : pkg;
  }
  assert.equal(evidence.format, 'jtm-keiyo-midcurve-v1');
  assert.equal(cache.fetchedAt, evidence.source.fetchedAt);
  const pkg = structuredClone(input), line = pkg.lines.find(row => row.id === evidence.lineID);
  assert(line);
  const baseline = structuredClone(line);
  baseline.displayIntervalCoordinates = evidence.baselineLine.displayIntervalCoordinates;
  assert.deepEqual(baseline, evidence.baselineLine, 'Keiyo identity/physical source changed');
  assert(equal(line.displayIntervalCoordinates, evidence.baselineLine.displayIntervalCoordinates) ||
    equal(line.displayIntervalCoordinates, { 0: evidence.candidate }) ||
    (evidence.previousCandidate && equal(line.displayIntervalCoordinates, { 0: withoutEbigawaDisplayAlias(evidence.previousCandidate) })) ||
    (evidence.retainedSeamCandidate && equal(line.displayIntervalCoordinates, { 0: evidence.retainedSeamCandidate })), 'Unreviewed display override');
  let track = [];
  for (const [id, reverse] of evidence.chain) {
    const pinned = evidence.ways.find(w => w.id === id), actual = cache.elements.find(w => w.id === id);
    assert.deepEqual({ id: actual?.id, tags: actual?.tags, coordinates: actual?.geometry.map(p => [p.lon, p.lat]) }, pinned);
    assert(pinned.tags.railway === 'rail' && pinned.tags.usage === 'main' && !pinned.tags.service &&
      pinned.tags.operator === '東日本旅客鉄道' && pinned.tags.name === 'JR京葉線', 'Passenger track identity changed');
    const points = structuredClone(pinned.coordinates);
    if (reverse) points.reverse();
    assert(!track.length || equal(track.at(-1), points[0]), 'Passenger survey seam disconnected');
    track.push(...points.slice(track.length ? 1 : 0));
  }
  for (const seam of evidence.seams) {
    assert.deepEqual(projectPointOntoPolyline(seam.point, track), seam.projection);
    assert(seam.projection.distanceM <= 15, 'Bounded display alias exceeded');
  }
  const [a, b] = evidence.displayIndices, original = evidence.baselineLine.displayIntervalCoordinates[0];
  let candidate = [...original.slice(0, a + 1),
    ...track.slice(evidence.seams[0].projection.insertIndex + 1, evidence.seams[1].projection.insertIndex + 1),
    ...original.slice(b)];
  if (evidence.surveyEntrance) {
    const entrance = evidence.surveyEntrance;
    assert.equal(entrance.displayIndex, a, 'Survey entrance must be the retained start alias');
    assert.deepEqual(candidate[a], entrance.originalAlias);
    assert.equal(evidence.chain[0][0], entrance.wayID);
    assert.deepEqual(track[0], entrance.trackEndpoint, 'Selected passenger entrance changed');
    assert(distance(candidate[a], track[0]) <= entrance.maxDisplacementM, 'Survey entrance alias exceeded');
    assert.deepEqual(candidate, evidence.previousCandidate, 'Previous reviewed entrance changed');
    candidate[a] = structuredClone(track[0]);
  }
  if (evidence.seamRemoval) {
    assert.deepEqual(candidate, evidence.retainedSeamCandidate, 'Retained Ebigawa source changed');
    candidate = withoutEbigawaDisplayAlias(candidate);
  }
  assert.deepEqual(candidate, evidence.candidate);
  line.displayIntervalCoordinates = { 0: candidate };
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['keiyo-midcurve'] = {
    reviewedAt: evidence.reviewedAt, script: 'app/scripts/railway/repair-keiyo-midcurve.mjs',
    evidence: 'app/scripts/railway/keiyo-midcurve-evidence.json', source: evidence.source,
    sourceIndices: evidence.sourceIndices, chain: evidence.chain, seams: evidence.seams, policy: evidence.policy,
    ...(evidence.seamRemoval ? { seamRemoval: evidence.seamRemoval } : {}),
    ...(evidence.surveyEntrance ? { surveyEntrance: evidence.surveyEntrance } : {}),
    ...(evidence.seamRemoval ? { seamRemoval: evidence.seamRemoval } : {})
  };
  const trunk = pkg.lines.find(row => row.id === sharedEvidence.trunkID);
  const coordinates = sharedTrunkCoordinates(pkg, evidence);
  const existing = trunk.displayIntervalCoordinates?.[sharedEvidence.trunkInterval];
  const previousCoordinates = evidence.previousCandidate && withoutEbigawaDisplayAlias(
    [...evidence.previousCandidate.slice(sharedEvidence.armDisplayForkIndex).toReversed(),
      ...network.decodeIntervals(trunk)[sharedEvidence.trunkInterval].slice(sharedEvidence.trunkDecodedForkIndex + 1)]);
  assert(!existing || equal(existing, coordinates) || (previousCoordinates && equal(existing, previousCoordinates)), 'Unreviewed shared trunk display override');
  trunk.displayIntervalCoordinates = { ...trunk.displayIntervalCoordinates, [sharedEvidence.trunkInterval]: coordinates };
  pkg.geometrySource.manualOverrides['keiyo-shared-corridor'] = {
    reviewedAt: sharedEvidence.reviewedAt, script: 'app/scripts/railway/repair-keiyo-midcurve.mjs',
    evidence: 'app/scripts/railway/keiyo-shared-corridor-evidence.json',
    sourceFeatures: sharedEvidence.sourceFeatures, selectedDisplayEvidence: sharedEvidence.selectedDisplayEvidence,
    from: sharedEvidence.fork, to: sharedEvidence.station.slice(1), policy: sharedEvidence.policy,
  };
  const selected = options.minami ? repairMinamiPackage(pkg, cache) : pkg;
  return options.shio ? repairShioPackage(selected, cache) : selected;
}

function westTrunkCoordinates(pkg) {
  const review = sharedEvidence.western;
  const trunk = pkg.lines.find(row => row.id === review.trunkID);
  const arm = pkg.lines.find(row => row.id === review.armID);
  assert.equal(trunk.operator, arm.operator, 'Shared passenger corridor company changed');
  assert.deepEqual(trunk.segments[review.trunkInterval], review.physicalIntervalBaseline,
    'Shared passenger corridor physical source changed');
  const tails = JSON.parse(fs.readFileSync(path.join(ROOT, '..', review.selectedDisplayEvidence)));
  const window = tails.windows.find(row => row.lineId === review.armID);
  assert.deepEqual(arm.stations, window.stationRows, 'Western passenger station binding changed');
  assert.deepEqual(arm.segments, window.physicalSegments, 'Western passenger physical source changed');
  const sections = JSON.parse(fs.readFileSync(path.join(ROOT, 'data/rail-sections.json')));
  assert.deepEqual(sections.features[window.rawSource.featureIndex], window.rawSource.feature, 'Western shared N02 feature changed');
  for (const source of window.passengerApproach.rawSources)
    assert.deepEqual(sections.features[source.featureIndex], source.feature, 'Western approach original N02 feature changed');
  const originalArm = network.decodeIntervals(arm)[0];
  let survey = [];
  for (const [id, reverse] of window.chain) {
    const way = window.ways.find(row => row.id === id), tags = way.tags;
    assert(tags.railway === 'rail' && tags.usage === 'main' && tags.name === 'JR京葉線' && tags.operator === arm.operator && !tags.service, 'Western passenger track identity changed');
    const points = structuredClone(way.coordinates);
    if (reverse) points.reverse();
    assert(!survey.length || equal(survey.at(-1), points[0]), 'Western passenger survey seam changed');
    survey.push(...points.slice(survey.length ? 1 : 0));
  }
  const [a, b] = window.indices;
  const selected = westernPassengerApproach(
    [...originalArm.slice(0, a + 1), ...survey.slice(...window.surveySlice), ...originalArm.slice(b)], window.passengerApproach);
  assert.deepEqual(arm.displayIntervalCoordinates?.[0], selected, 'Reviewed western arm display source changed');
  const original = network.decodeIntervals(trunk)[review.trunkInterval];
  assert.deepEqual(original.slice(review.trunkDecodedForkIndex), originalArm.slice(review.armCanonicalForkIndex),
    'Western shared canonical source changed');
  assert.equal(original.slice(review.trunkDecodedForkIndex).length, 35, 'Western shared canonical extent changed');
  assert.deepEqual(original[review.trunkDecodedForkIndex], review.fork);
  assert.deepEqual(selected[review.armDisplayForkIndex], review.fork);
  assert.deepEqual(selected.at(-1), review.station.slice(1));
  return [...original.slice(0, review.trunkDecodedForkIndex), ...selected.slice(review.armDisplayForkIndex)];
}

export function repairWestPackage(input) {
  input = structuredClone(input);
  const westernArm = input.lines.find(row => row.id === sharedEvidence.western.armID);
  westernArm.displayIntervalCoordinates[0] = westernPassengerApproach(westernArm.displayIntervalCoordinates[0]);
  if (hasShioStage(input)) return repairShioPackage(repairWestPackage(retainedShioPackage(input)));
  if (hasMinamiStage(input)) return repairMinamiPackage(repairWestPackage(retainedMinamiPackage(input)));
  const pkg = structuredClone(input), review = sharedEvidence.western;
  const trunk = pkg.lines.find(row => row.id === review.trunkID);
  const coordinates = westTrunkCoordinates(pkg);
  const existing = trunk.displayIntervalCoordinates?.[review.trunkInterval];
  assert(!existing || equal(existing, coordinates), 'Unreviewed western shared trunk display override');
  trunk.displayIntervalCoordinates = { ...trunk.displayIntervalCoordinates, [review.trunkInterval]: coordinates };
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['keiyo-west-shared-corridor'] = {
    reviewedAt: sharedEvidence.reviewedAt, script: 'app/scripts/railway/repair-keiyo-midcurve.mjs',
    evidence: 'app/scripts/railway/keiyo-shared-corridor-evidence.json', sourceFeatures: review.sourceFeatures,
    selectedDisplayEvidence: review.selectedDisplayEvidence, from: review.fork, to: review.station.slice(1), policy: review.policy,
    passengerApproach: { source: westernApproachEvidence.source, wayChain: westernApproachEvidence.chain,
      routeRelation: westernApproachEvidence.routeMembership.id, canonicalVertexIndices: westernApproachEvidence.indices,
      outerGuards: [westernApproachEvidence.before, westernApproachEvidence.after],
      canonicalForkIndex: review.armCanonicalForkIndex, displayForkIndex: review.armDisplayForkIndex,
      policy: westernApproachEvidence.policy },
  };
  return pkg;
}

export function repairParts(pkg, input, evidence) {
  if (hasShioStage(pkg)) {
    const retained = retainedShioPackage(pkg);
    const baseline = hasShioNativeParts(pkg, input) ? shioPartsForStage(pkg, input, false) : input;
    return shioPartsForStage(pkg, repairParts(retained, baseline, evidence));
  }
  if (hasMinamiStage(pkg)) {
    const retained = retainedMinamiPackage(pkg);
    const baseline = hasMinamiNativeParts(pkg, input) ? minamiPartsForStage(pkg, input, false) : input;
    return minamiPartsForStage(pkg, repairParts(retained, baseline, evidence));
  }
  const review = sharedEvidence;
  const reviews = [review];
  if (pkg.geometrySource?.manualOverrides?.['keiyo-west-shared-corridor']) {
    assert.deepEqual(pkg, repairWestPackage(pkg), 'Western shared provenance changed');
    reviews.push(review.western);
  }
  const ids = new Set(reviews.flatMap(row => [row.trunkID, row.armID]));
  // Accept only the frozen pre-removal and pre-entrance rulers, including
  // both reviewed shared arms. Other stale measurements remain rejected.
  let previous, previousEasternRows;
  if (evidence.retainedSeamCandidate || evidence.previousCandidate) {
    const previousEvidence = structuredClone(evidence), previousPackage = structuredClone(pkg);
    if (previousEvidence.retainedSeamCandidate) {
      previousEvidence.candidate = previousEvidence.retainedSeamCandidate;
      delete previousEvidence.retainedSeamCandidate;
      delete previousEvidence.seamRemoval;
    } else {
      previousEvidence.candidate = previousEvidence.previousCandidate;
      delete previousEvidence.previousCandidate;
      delete previousEvidence.surveyEntrance;
    }
    previousPackage.lines.find(row => row.id === review.armID).displayIntervalCoordinates = { 0: previousEvidence.candidate };
    previousPackage.lines.find(row => row.id === review.trunkID).displayIntervalCoordinates[review.trunkInterval] = sharedTrunkCoordinates(previousPackage, previousEvidence);
    const previousLanes = structuredClone(input);
    previousLanes.followsByRegion.jp = previousLanes.followsByRegion.jp.filter(row => !ids.has(row[0]) && !ids.has(row[4]));
    previousLanes.familyWindowsByRegion.jp = previousLanes.familyWindowsByRegion.jp.filter(row => !ids.has(row[0]));
    previousLanes.partsByRegion.jp = previousLanes.partsByRegion.jp.map(row => {
      if (!ids.has(row[0])) return row;
      const line = previousPackage.lines.find(line => line.id === row[0]);
      return partRowsForLine(line, network.displayPartsForLine(line))[row[1]];
    });
    previous = repairParts(previousPackage, previousLanes, previousEvidence);
    if (reviews.length === 2) {
      const previousTrunk = structuredClone(previousPackage.lines.find(row => row.id === review.trunkID));
      delete previousTrunk.displayIntervalCoordinates[review.western.trunkInterval];
      previousEasternRows = partRowsForLine(previousTrunk, network.displayPartsForLine(previousTrunk));
    }
  }
  const trunk = pkg.lines.find(row => row.id === review.trunkID);
  assert.deepEqual(trunk.displayIntervalCoordinates[review.trunkInterval], sharedTrunkCoordinates(pkg, evidence));
  const parts = [...ids].map(lineId => {
    const line = pkg.lines.find(row => row.id === lineId), coordinates = network.displayPartsForLine(line);
    assert.equal(coordinates.length, 1, 'Shared corridor part topology changed');
    return { lineId, partIndex: 0, coordinates: coordinates[0], stationPoints: line.stations.map(row => row.slice(2, 4)) };
  });
  const metrics = new Map(parts.map(part => {
    const cumulative = measures(part.coordinates);
    return [part.lineId + '#0', { cumulative, total: cumulative.at(-1) }];
  }));
  const leader = parts.find(part => part.lineId === review.trunkID);
  const locate = (part, point) => {
    const index = part.coordinates.findIndex(value => equal(value, point));
    assert(index >= 0, 'Reviewed shared corridor seam missing');
    return metrics.get(part.lineId + '#0').cumulative[index];
  };
  const follows = reviews.map(row => {
    const arm = parts.find(part => part.lineId === row.armID);
    return [row.armID, 0, locate(arm, row.fork), locate(arm, row.station.slice(1)),
      row.trunkID, 0, locate(leader, row.fork), locate(leader, row.station.slice(1))];
  });
  const groups = { byLineId: Object.fromEntries([...ids].map(id => [id, review.groupID])),
    families: { [review.groupID]: { color: trunk.color } } };
  const windows = deriveFamilyWindows(parts, follows, groups, metrics, input.byRegion.jp);
  assert.equal(windows.length, reviews.length * 2, 'Shared corridor requires one landlord and one tenant per arm');
  const affectedFollow = row => ids.has(row[0]) || ids.has(row[4]);
  const oldFollows = input.followsByRegion.jp.filter(affectedFollow);
  const oldWindows = input.familyWindowsByRegion.jp.filter(row => ids.has(row[0]));
  // The only accepted earlier stage is the exact reviewed eastern stage.
  let eastern;
  if (reviews.length === 2) {
    const baselinePackage = structuredClone(pkg);
    delete baselinePackage.geometrySource.manualOverrides['keiyo-west-shared-corridor'];
    delete baselinePackage.lines.find(row => row.id === review.trunkID).displayIntervalCoordinates[review.western.trunkInterval];
    const baselineLanes = structuredClone(input);
    for (const key of ['followsByRegion', 'familyWindowsByRegion'])
      baselineLanes[key].jp = baselineLanes[key].jp.filter(row => key === 'followsByRegion' ? !affectedFollow(row) : !ids.has(row[0]));
    baselineLanes.partsByRegion.jp = baselineLanes.partsByRegion.jp.map(row => row[0] === review.trunkID
      ? partRowsForLine(baselinePackage.lines.find(line => line.id === row[0]), network.displayPartsForLine(baselinePackage.lines.find(line => line.id === row[0])))[0] : row);
    eastern = repairParts(baselinePackage, baselineLanes, evidence);
  }
  const earlierFollows = eastern?.followsByRegion.jp.filter(affectedFollow);
  const earlierWindows = eastern?.familyWindowsByRegion.jp.filter(row => ids.has(row[0]));
  const previousEastFollows = previous?.followsByRegion.jp.filter(row => row[0] === review.armID);
  const previousEastFollow = previousEastFollows?.[0];
  const previousEastWindows = previousEastFollow && previous.familyWindowsByRegion.jp.filter(row =>
    row[0] === review.armID || (row[0] === review.trunkID && row[2] >= Math.min(previousEastFollow[6], previousEastFollow[7]) - 0.1 &&
      row[3] <= Math.max(previousEastFollow[6], previousEastFollow[7]) + 0.1));
  assert(!oldFollows.length || equal(oldFollows, follows) || (eastern && equal(oldFollows, earlierFollows)) ||
    (previous && equal(oldFollows, previous.followsByRegion.jp.filter(affectedFollow))) ||
    (previousEasternRows && equal(oldFollows, previousEastFollows)), 'Unreviewed Keiyo measured follow');
  assert(!oldWindows.length || equal(oldWindows, windows) || (eastern && equal(oldWindows, earlierWindows)) ||
    (previous && equal(oldWindows, previous.familyWindowsByRegion.jp.filter(row => ids.has(row[0])))) ||
    (previousEasternRows && equal(oldWindows, previousEastWindows)), 'Unreviewed Keiyo family ownership');
  const result = structuredClone(input);
  const rows = parts.flatMap(part => partRowsForLine(pkg.lines.find(line => line.id === part.lineId), [part.coordinates]));
  const originalTrunk = structuredClone(trunk);
  for (const row of reviews) delete originalTrunk.displayIntervalCoordinates[row.trunkInterval];
  const originalTrunkRows = partRowsForLine(originalTrunk, network.displayPartsForLine(originalTrunk));
  for (const id of ids) {
    const current = input.partsByRegion.jp.filter(row => row[0] === id);
    const updated = rows.filter(row => row[0] === id);
    const baseline = id === review.trunkID ? originalTrunkRows : id === review.armID ? evidence.baselineNativeRows : updated;
    const earlier = id !== review.western.armID && eastern?.partsByRegion.jp.filter(row => row[0] === id);
    assert(equal(current, baseline) || equal(current, updated) || (earlier && equal(current, earlier)) ||
      (previous && equal(current, previous.partsByRegion.jp.filter(row => row[0] === id))) ||
      (id === review.trunkID && previousEasternRows && equal(current, previousEasternRows)), 'Keiyo native cache changed; review before replacing');
  }
  for (const key of ['loopsByRegion', 'chainBoundariesByRegion'])
    assert(!(input[key]?.jp || []).some(row => [...ids].some(id => JSON.stringify(row).includes(id))), 'Keiyo measured reference needs review');
  if (reviews.length === 2) assert(!(input.hubReportByRegion?.jp || []).some(row => JSON.stringify(row).includes(review.western.armID)), 'Keiyo measured reference needs review');
  assert(!(input.reversedLoopParts?.jp || []).some(row => ids.has(row.split('#')[0])), 'Keiyo measured reference needs review');
  // All members retain their zero lane: ownership, rather than a new
  // screen offset, removes the duplicate. No unrelated rulers are rebuilt.
  assert(!input.byRegion.jp.some(row => ids.has(row[0])), 'Keiyo lane profile needs review');
  result.partsByRegion.jp = result.partsByRegion.jp.map(row => ids.has(row[0]) ? rows.find(value => value[0] === row[0]) : row);
  result.followsByRegion.jp = [...result.followsByRegion.jp.filter(row => !affectedFollow(row)), ...follows];
  result.familyWindowsByRegion.jp = [...result.familyWindowsByRegion.jp.filter(row => !ids.has(row[0])), ...windows];
  return result;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), candidateIndex = args.indexOf('--candidate-root');
  const candidateRoot = candidateIndex < 0 ? null : path.resolve(args[candidateIndex + 1] || '.');
  const flags = args.filter((_, index) => candidateIndex < 0 || (index !== candidateIndex && index !== candidateIndex + 1));
  const apply = flags.includes('--apply'), west = flags.includes('--west');
  assert(flags.every(arg => ['--apply', '--west'].includes(arg)) && new Set(flags).size === flags.length &&
    (!candidateRoot || (!apply && candidateRoot.startsWith('/private/tmp/'))),
    'Usage: node repair-keiyo-midcurve.mjs [--west] [--apply | --candidate-root /private/tmp/<dir>]');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json',
    evidence: 'scripts/railway/keiyo-midcurve-evidence.json', ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const read = key => JSON.parse(snapshots[key].before), evidence = read('evidence');
  const cache = JSON.parse(fs.readFileSync(evidence.source.cacheAbsolutePath));
  const eastern = repairPackage(read('package'), evidence, cache);
  const pkg = west ? repairWestPackage(eastern) : eastern;
  const currentLanes = partsForRetainedKeiyoStage(pkg, read('lanes'), read('package'));
  const lanes = repairParts(pkg, currentLanes, evidence);
  const lineIDs = [evidence.lineID, sharedEvidence.trunkID,
    ...(west ? [sharedEvidence.western.armID] : [])];
  const rows = lanes.partsByRegion.jp.filter(row => lineIDs.includes(row[0]));
  const dependencies = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, read(key)])));
  const writes = [{ ...snapshots.package, after: JSON.stringify(pkg) },
    { ...snapshots.lanes, after: JSON.stringify(lanes) + '\n' },
    ...Object.keys(DEPENDENCY_PATHS).map(key => ({ ...snapshots[key], after: JSON.stringify(dependencies[key], null, 2) + '\n' }))];
  if (apply) applyPreparedWrites(writes, Object.values(snapshots));
  if (candidateRoot) {
    fs.mkdirSync(candidateRoot, { recursive: true });
    for (const write of writes) fs.writeFileSync(path.join(candidateRoot, path.basename(write.path)), write.after);
  }
  console.log(JSON.stringify({ mode: apply ? 'applied' : 'candidate-only', lineIDs,
    physicalGeometryChanged: false, nativeRows: rows.map(row => row.slice(0, 7)) }));
}
