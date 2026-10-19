#!/usr/bin/env node
// Outer Yamasaki display stage; earlier passenger/reversal stages stay strict.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { partRowsForLine } from './build-display-lanes.mjs';
import { repairPackage as repairCorridor } from './repair-hakone-passenger-corridor.mjs';
import { repairPackage as repairStationApproaches } from './repair-passenger-station-approaches.mjs';
import { refreshDependencyReferences, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.resolve(ROOT, '..');
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360), (b[1] - a[1]) * 111320);
const length = points => points.slice(1).reduce((total, point, i) => total + distance(points[i], point), 0);
const taper = value => value * value * value * (10 + value * (-15 + 6 * value));

function reviewedInterval(e) {
  assert.equal(e.format, 'jtm-hakone-yamasaki-display-v1');
  assert.equal(e.interval, 3);
  assert.deepEqual(e.window.coreIndicesInclusive, [17, 24]);
  assert.deepEqual(e.window.transitionIndicesInclusive, [8, 34]);
  assert.deepEqual([e.window.prefixLastPhysicalIndex, e.window.suffixFirstPhysicalIndex], [13, 35]);
  const cache = JSON.parse(fs.readFileSync(e.source.cacheAbsolutePath));
  assert.equal(cache.fetchedAt, e.source.fetchedAt, 'Passenger cache provenance changed');
  let lastNode, lastCoordinate;
  for (const [id, reverse] of e.chain) {
    const pinned = e.ways.find(w => w.id === id);
    assert.deepEqual(cache.elements.find(w => w.id === id), pinned.cached, 'Retained passenger source changed');
    const primary = JSON.parse(fs.readFileSync(path.join(REPO, e.source.primarySourceDirectory, `way-${id}-full.json`)));
    const way = primary.elements.find(w => w.type === 'way' && w.id === id);
    const nodes = new Map(primary.elements.filter(w => w.type === 'node').map(w => [w.id, w]));
    assert.deepEqual([way.version, way.timestamp, way.nodes, way.tags], [pinned.version, pinned.timestamp, pinned.nodes, pinned.tags]);
    assert.deepEqual(way.nodes.map(n => [nodes.get(n).lon, nodes.get(n).lat]), pinned.coordinates);
    assert.deepEqual(pinned.coordinates, pinned.cached.geometry.map(p => [p.lon, p.lat]));
    assert.equal(way.tags.railway, 'rail'); assert.equal(way.tags.usage, 'main');
    assert(['小田急箱根', '箱根登山鉄道'].includes(way.tags.operator));
    assert(!way.tags.service && !(reverse && way.tags.oneway === 'yes'), 'Unreviewed service/direction');
    const ids = reverse ? pinned.nodes.toReversed() : pinned.nodes;
    const coordinates = reverse ? pinned.coordinates.toReversed() : pinned.coordinates;
    if (lastNode !== undefined) {
      assert.equal(ids[0], lastNode, 'Selected passenger leg disconnected');
      assert.deepEqual(coordinates[0], lastCoordinate);
    }
    lastNode = ids.at(-1); lastCoordinate = coordinates.at(-1);
  }
  const physical = network.decodeIntervals(e.baselineLine)[3];
  assert.deepEqual([physical[13], physical[35]], e.window.physicalGuards);
  const way = e.ways.find(w => w.id === e.window.wayID);
  assert.equal(way.id, 235606888);
  const points = way.coordinates, cumulative = [0];
  for (let i = 1; i < points.length; i++) cumulative.push(cumulative.at(-1) + distance(points[i - 1], points[i]));
  // A zero-slope quintic taper follows the same along-track supports. Both
  // boundary samples project onto unchanged source tangents, never across rail.
  const transition = points.slice(8, 35).map((point, offset) => {
    const i = offset + 8, projection = projectPointOntoPolyline(point, physical);
    assert(projection.insertIndex >= 13 && projection.insertIndex <= 34 && projection.distanceM < 25,
      'Selected support escaped the reviewed source window');
    const weight = i < 17 ? taper((cumulative[i] - cumulative[8]) / (cumulative[17] - cumulative[8]))
      : i > 24 ? taper((cumulative[34] - cumulative[i]) / (cumulative[34] - cumulative[24])) : 1;
    return weight === 1 ? structuredClone(point) : projection.point.map((v, axis) => v + weight * (point[axis] - v));
  });
  return [...physical.slice(0, 14), ...transition, ...physical.slice(35)];
}

export function repairPackage(input, e = read('scripts/railway/hakone-yamasaki-display-evidence.json')) {
  const interval = reviewedInterval(e), repaired = structuredClone(e.baselineLine);
  repaired.displayIntervalCoordinates[3] = interval;
  const current = input.lines.find(line => line.id === e.lineID);
  assert(equal(current, e.baselineLine) || equal(current, repaired), 'Unreviewed Hakone dependency changed');
  const corridor = read('scripts/railway/hakone-passenger-corridor-evidence.json');
  const replay = repairCorridor({ lines: [structuredClone(corridor.baselineLine)], geometrySource: {} }, corridor);
  assert.deepEqual(replay.lines[0], e.baselineLine, 'Earlier Hakone corridor stage changed');
  // Replay the older strict station stage on its own inputs, not this outer line.
  const upstream = read('scripts/railway/passenger-station-approaches-evidence.json');
  const item = upstream.items.find(row => row.lineID === e.lineID);
  assert(item, 'Strict Hakone station evidence missing');
  const stationReplay = repairStationApproaches({ lines: [structuredClone(item.baselineLine)], geometrySource: {} }, { ...upstream, items: [item] });
  assert.deepEqual(stationReplay.lines[0].stations, e.baselineLine.stations);
  assert.deepEqual(stationReplay.lines[0].segments, e.baselineLine.segments);
  const pkg = structuredClone(input);
  pkg.lines[pkg.lines.findIndex(line => line.id === e.lineID)] = repaired;
  pkg.geometrySource ||= {}; pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['hakone-yamasaki-display'] = {
    reviewedAt: e.reviewedAt, lineID: e.lineID, intervals: [3], source: e.source, window: e.window,
    script: 'app/scripts/railway/repair-hakone-yamasaki-display.mjs',
    evidence: 'app/scripts/railway/hakone-yamasaki-display-evidence.json', physicalTopologyChanged: false, policy: e.policy
  };
  return pkg;
}

export function repairParts(pkg, input, e = read('scripts/railway/hakone-yamasaki-display-evidence.json')) {
  const line = pkg.lines.find(row => row.id === e.lineID), parts = network.displayPartsForLine(line);
  const displayLine = { ...line, stations: line.stations.map(s => line.displayStationCoordinates?.[s[0]] ? [...s.slice(0, 2), ...line.displayStationCoordinates[s[0]], ...s.slice(4)] : s),
    segments: line.segments.map((s, i) => line.displayIntervalCoordinates?.[i] ? [s[0], 0, line.displayIntervalCoordinates[i]] : s) };
  const rows = partRowsForLine(line, parts, { stations: displayLine.stations, intervals: network.decodeIntervals(displayLine) }, null);
  const cached = input.partsByRegion.jp.filter(row => row[0] === e.lineID);
  assert(equal(cached, e.baselineNativeRows) || equal(cached, rows), 'Hakone native part dependency changed');
  assert.equal(rows.length, e.baselineNativeRows.length);
  for (const i of [0, 2, 3, 4, 5, 6]) assert.deepEqual(rows[i], e.baselineNativeRows[i], 'Unrelated Hakone native part changed');
  const expected = structuredClone(e.baselineMeasuredReferences);
  const extent = expected.byRegion.find(row => row[0] === e.lineID && row[1] === 1);
  assert(extent && extent[2] === 0 && extent[3] === length(e.baselineNativeRows[1][7]));
  extent[3] = length(parts[1]);
  for (const [key, baseline] of Object.entries(e.baselineMeasuredReferences)) {
    const ours = (input[key]?.jp || []).filter(row => JSON.stringify(row).includes(e.lineID));
    assert(equal(ours, baseline) || equal(ours, expected[key]), 'Unreviewed Hakone measured references: ' + key);
  }
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(row => row[0] === e.lineID ? rows[row[1]] : row);
  result.byRegion.jp = result.byRegion.jp.map(row => row[0] === e.lineID && row[1] === 1 ? extent : row);
  return result;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), apply = equal(args, ['--apply']);
  assert(!args.length || apply, 'Usage: node repair-hakone-yamasaki-display.mjs [--apply]');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json',
    evidence: 'scripts/railway/hakone-yamasaki-display-evidence.json', corridor: 'scripts/railway/hakone-passenger-corridor-evidence.json',
    upstream: 'scripts/railway/passenger-station-approaches-evidence.json', ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const deps = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  if (apply) {
    const writes = [{ ...snapshots.package, after: JSON.stringify(pkg) }, { ...snapshots.lanes, after: JSON.stringify(lanes) + '\n' },
      ...Object.keys(DEPENDENCY_PATHS).map(key => ({ ...snapshots[key], after: JSON.stringify(deps[key], null, 2) + '\n' }))];
    const prepared = writes.filter(w => w.before !== w.after).map(w => ({ ...w, temporary: `${w.path}.yamasaki-${process.pid}.tmp` }));
    try {
      for (const write of prepared) fs.writeFileSync(write.temporary, write.after);
      for (const snapshot of Object.values(snapshots)) assert.equal(fs.readFileSync(snapshot.path, 'utf8'), snapshot.before, 'Concurrent input changed before Yamasaki apply');
      for (const write of prepared) fs.renameSync(write.temporary, write.path);
    } finally { for (const write of prepared) if (fs.existsSync(write.temporary)) fs.unlinkSync(write.temporary); }
  }
  console.log(JSON.stringify({ mode: apply ? 'applied' : 'candidate', lineID: e.lineID, interval: 3,
    pointCount: pkg.lines.find(l => l.id === e.lineID).displayIntervalCoordinates[3].length,
    affectedNativePart: 1, measuredExtentMetres: lanes.byRegion.jp.find(r => r[0] === e.lineID && r[1] === 1)[3], physicalTopologyChanged: false }));
}
