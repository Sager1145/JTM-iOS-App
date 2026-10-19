#!/usr/bin/env node
// Outer display stage after the strict Miinohara/reversal repair.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { partRowsForLine } from './build-display-lanes.mjs';
import { repairPackage as repairStationApproaches } from './repair-passenger-station-approaches.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const same = (a, b) => a[0] === b[0] && a[1] === b[1];
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));

function taperToRetainedBoundary(points, boundary, outside, transition) {
  assert.deepEqual([transition.metres, transition.sampleStepMetres, transition.boundaryTangentGuardMetres], [120, 10, 1]);
  const origin = points.at(-1), longitudeScale = 111320 * Math.cos(origin[1] * Math.PI / 180);
  const toXY = p => [(p[0] - origin[0]) * longitudeScale, (p[1] - origin[1]) * 111320];
  const fromXY = p => [origin[0] + p[0] / longitudeScale, origin[1] + p[1] / 111320];
  const xy = points.map(toXY), cumulative = [0];
  for (let i = 1; i < xy.length; i++) cumulative.push(cumulative.at(-1) + Math.hypot(xy[i][0] - xy[i - 1][0], xy[i][1] - xy[i - 1][1]));
  const total = cumulative.at(-1), start = total - transition.metres;
  assert(start > 0, 'Transition must stay inside the previously affected approach');
  const delta = toXY(boundary);
  assert(Math.hypot(...delta) < 14, 'Transition escaped the reviewed alias bound');
  const result = points.filter((_, i) => cumulative[i] < start).map(p => p.slice());
  const stations = new Set(cumulative.filter(m => m >= start && m < total - 1));
  for (let m = start; m < total - 1; m += transition.sampleStepMetres) stations.add(m);
  for (const metre of [...stations].sort((a, b) => a - b)) {
    let i = 0;
    while (cumulative[i + 1] < metre) i++;
    const fraction = (metre - cumulative[i]) / (cumulative[i + 1] - cumulative[i]);
    const t = (metre - start) / transition.metres;
    const weight = t * t * t * (10 + t * (-15 + 6 * t));
    result.push(fromXY([xy[i][0] + fraction * (xy[i + 1][0] - xy[i][0]) + delta[0] * weight,
      xy[i][1] + fraction * (xy[i + 1][1] - xy[i][1]) + delta[1] * weight]));
  }
  // Match the retained outside ray at the boundary, without an orthogonal step.
  const ray = toXY(outside).map((v, i) => v - delta[i]), magnitude = Math.hypot(...ray);
  result.push(fromXY(delta.map((v, i) => v - ray[i] / magnitude)), boundary.slice());
  return result;
}

function reviewedIntervals(evidence, withTransitions = true) {
  assert.equal(evidence.format, 'jtm-kisuki-minami-daito-display-v1');
  const cache = JSON.parse(fs.readFileSync(evidence.source.cacheAbsolutePath));
  assert.equal(cache.fetchedAt, evidence.source.fetchedAt, 'Passenger cache provenance changed');
  const track = [], nodeIDs = [];
  for (const [id, reverse] of evidence.chain) {
    const way = evidence.ways.find(row => row.id === id);
    const actual = cache.elements.find(row => row.id === id);
    assert.deepEqual({ id: actual?.id, tags: actual?.tags, coordinates: actual?.geometry.map(p => [p.lon, p.lat]) },
      { id: way.id, tags: way.tags, coordinates: way.coordinates }, 'Identified passenger source changed');
    const primary = JSON.parse(fs.readFileSync(path.resolve(ROOT, '..', evidence.source.primarySourceDirectory, `way-${id}-full.json`)));
    const original = primary.elements.find(row => row.type === 'way' && row.id === id);
    assert.deepEqual([original.version, original.timestamp, original.tags, original.nodes],
      [way.version, way.timestamp, way.tags, way.nodes], 'Primary passenger graph changed');
    const nodes = new Map(primary.elements.filter(row => row.type === 'node').map(row => [row.id, row]));
    assert.deepEqual(original.nodes.map(node => [nodes.get(node).lon, nodes.get(node).lat]), way.coordinates);
    assert.equal(way.tags.railway, 'rail');
    assert.equal(way.tags.usage, 'main');
    assert.equal(way.tags.passenger_lines, '1');
    assert.equal(way.tags['KSJ2:LIN'], '木次線');
    assert.equal(way.tags.operator, evidence.baselineLine.operator);
    assert(!way.tags.service && !(reverse && way.tags.oneway === 'yes'), 'Unreviewed service/direction');
    const points = structuredClone(way.coordinates), ids = way.nodes.slice();
    if (reverse) { points.reverse(); ids.reverse(); }
    if (track.length) {
      assert(same(track.at(-1), points[0]) && nodeIDs.at(-1) === ids[0], 'Passenger chain disconnected');
    }
    track.push(...points.slice(track.length ? 1 : 0));
    nodeIDs.push(...ids.slice(nodeIDs.length ? 1 : 0));
    const station = nodes.get(evidence.stationNode.id);
    assert(station, 'Same-line station node missing');
    assert.deepEqual([station.lon, station.lat], evidence.stationNode.coordinate);
    assert.equal(station.version, evidence.stationNode.version);
    assert.deepEqual(station.tags, evidence.stationNode.tags);
    assert.equal(station.tags['KSJ2:LIN'], '木次線');
    assert.equal(station.tags.name, evidence.baselineLine.stations[evidence.stationIndex][1]);
  }
  assert.equal(evidence.stationID, evidence.baselineLine.stations[evidence.stationIndex][0]);
  const projection = projectPointOntoPolyline(evidence.baselineLine.stations[evidence.stationIndex].slice(2, 4), track);
  assert.deepEqual(projection, evidence.anchorProjection, 'Catalog projection on selected leg changed');
  assert.deepEqual(evidence.displayAnchor, projection.point);
  // The catalog-to-rail distance is a reviewed display alias, not a platform-centre proof.
  assert(projection.distanceM < 21);
  const physical = network.decodeIntervals(evidence.baselineLine);
  const incoming = evidence.seamAliases.find(row => row.interval === 4);
  const outgoing = evidence.seamAliases.find(row => row.interval === 5);
  for (const seam of [incoming, outgoing]) {
    assert.deepEqual(physical[seam.interval][seam.physicalIndex], seam.point, 'Frozen outside support changed');
    assert.deepEqual(projectPointOntoPolyline(seam.point, track), seam.projection, 'Reviewed seam changed');
    assert(seam.projection.distanceM < 14, 'Reviewed approach alias exceeded');
  }
  const slot = projection.insertIndex;
  const approach4 = [incoming.projection.point, ...track.slice(incoming.projection.insertIndex + 1, slot + 1), evidence.displayAnchor];
  const approach5 = [evidence.displayAnchor, ...track.slice(slot + 1, outgoing.projection.insertIndex + 1), outgoing.projection.point];
  if (!withTransitions) return {
    4: [...physical[4].slice(0, incoming.physicalIndex + 1), ...approach4],
    5: [...approach5, ...physical[5].slice(outgoing.physicalIndex)]
  };
  const transitioned4 = taperToRetainedBoundary(approach4.toReversed(), incoming.point,
    physical[4][incoming.physicalIndex - 1], evidence.seamTransition).toReversed();
  const transitioned5 = taperToRetainedBoundary(approach5, outgoing.point,
    physical[5][outgoing.physicalIndex + 1], evidence.seamTransition);
  return {
    4: [...physical[4].slice(0, incoming.physicalIndex), ...transitioned4],
    5: [...transitioned5, ...physical[5].slice(outgoing.physicalIndex + 1)]
  };
}

export function repairPackage(input, evidence = read('scripts/railway/kisuki-minami-daito-display-evidence.json'),
  upstream = read('scripts/railway/passenger-station-approaches-evidence.json')) {
  const intervals = reviewedIntervals(evidence);
  const repairedLine = structuredClone(evidence.baselineLine);
  repairedLine.displayStationCoordinates[evidence.stationID] = structuredClone(evidence.displayAnchor);
  repairedLine.displayIntervalCoordinates = { ...repairedLine.displayIntervalCoordinates, ...structuredClone(intervals) };
  const previousLine = structuredClone(evidence.baselineLine);
  previousLine.displayStationCoordinates[evidence.stationID] = structuredClone(evidence.displayAnchor);
  previousLine.displayIntervalCoordinates = { ...previousLine.displayIntervalCoordinates, ...reviewedIntervals(evidence, false) };
  const current = input.lines.find(row => row.id === evidence.lineID);
  assert(equal(current, evidence.baselineLine) || equal(current, previousLine) || equal(current, repairedLine), 'Unreviewed Kisuki dependency changed');
  // Replay the existing strict station stage against its original owned inputs.
  // Do not loosen it to accept this later station or unrelated Hakone changes.
  const legacyItem = upstream.items.find(row => row.lineID === evidence.lineID);
  assert(legacyItem, 'Strict Miinohara evidence missing');
  const checked = repairStationApproaches({ lines: [structuredClone(evidence.baselineLine)], geometrySource: {} },
    { ...upstream, items: [legacyItem] });
  assert.deepEqual(checked.lines[0], evidence.baselineLine, 'Earlier Kisuki stage no longer reproduces reviewed baseline');
  const beforeParts = network.displayPartsForLine(evidence.baselineLine);
  const afterParts = network.displayPartsForLine(repairedLine);
  assert.equal(afterParts.length, beforeParts.length, 'Kisuki fork decomposition changed');
  for (const index of [0, 2]) assert.deepEqual(afterParts[index], beforeParts[index], 'Unrelated reversal/Miinohara part changed');
  const pkg = structuredClone(input);
  pkg.lines[pkg.lines.findIndex(row => row.id === evidence.lineID)] = repairedLine;
  pkg.geometrySource ||= {};
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['kisuki-minami-daito-display'] = {
    reviewedAt: evidence.reviewedAt, lineID: evidence.lineID, stationID: evidence.stationID,
    script: 'app/scripts/railway/repair-kisuki-minami-daito-display.mjs',
    evidence: 'app/scripts/railway/kisuki-minami-daito-display-evidence.json',
    displayAnchor: evidence.displayAnchor, intervals: [4, 5], seamAliases: evidence.seamAliases,
    chain: evidence.chain, source: evidence.source, seamTransition: evidence.seamTransition, physicalTopologyChanged: false,
    policy: 'Identified same-line passenger approach depiction; catalog projection is not a surveyed platform centre.'
  };
  return pkg;
}

export function repairParts(pkg, input, evidence = read('scripts/railway/kisuki-minami-daito-display-evidence.json')) {
  const line = pkg.lines.find(row => row.id === evidence.lineID);
  const parts = network.displayPartsForLine(line);
  const displayLine = { ...line,
    stations: line.stations.map(row => line.displayStationCoordinates?.[row[0]]
      ? [...row.slice(0, 2), ...line.displayStationCoordinates[row[0]], ...row.slice(4)] : row),
    segments: line.segments.map((row, i) => line.displayIntervalCoordinates?.[i]
      ? [row[0], 0, line.displayIntervalCoordinates[i]] : row) };
  const rows = partRowsForLine(line, parts, { stations: displayLine.stations, intervals: network.decodeIntervals(displayLine) }, null);
  const cached = input.partsByRegion.jp.filter(row => row[0] === evidence.lineID);
  assert(equal(cached, evidence.baselineNativeRows) || equal(cached, evidence.previousNativeRows) || equal(cached, rows), 'Kisuki cached part dependency changed');
  assert(rows.every(row => !row[8]?.length), 'Unreviewed withheld measures');
  for (const [key, expected] of Object.entries(evidence.baselineMeasuredReferences))
    assert.deepEqual((input[key]?.jp || []).filter(row => JSON.stringify(row).includes(evidence.lineID)), expected,
      'Kisuki measured references require separate review: ' + key);
  for (const index of [0, 2]) assert.deepEqual(rows[index], evidence.baselineNativeRows[index], 'Unrelated native part changed');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(row => row[0] === evidence.lineID ? rows[row[1]] : row);
  return result;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), apply = equal(args, ['--apply']);
  assert(!args.length || apply, 'Usage: node repair-kisuki-minami-daito-display.mjs [--apply]');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json',
    evidence: 'scripts/railway/kisuki-minami-daito-display-evidence.json',
    upstream: 'scripts/railway/passenger-station-approaches-evidence.json', ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), evidence = load('evidence');
  const pkg = repairPackage(load('package'), evidence, load('upstream'));
  const lanes = repairParts(pkg, load('lanes'), evidence);
  const deps = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  if (apply) applyPreparedWrites([
    { ...snapshots.package, after: JSON.stringify(pkg) },
    { ...snapshots.lanes, after: JSON.stringify(lanes) + '\n' },
    ...Object.keys(DEPENDENCY_PATHS).map(key => ({ ...snapshots[key], after: JSON.stringify(deps[key], null, 2) + '\n' }))
  ], Object.values(snapshots));
  console.log(JSON.stringify({ mode: apply ? 'applied' : 'candidate', lineID: evidence.lineID,
    displayAnchor: evidence.displayAnchor, intervalPointCounts: [4, 5].map(i => pkg.lines.find(row => row.id === evidence.lineID).displayIntervalCoordinates[i].length),
    physicalTopologyChanged: false }));
}
