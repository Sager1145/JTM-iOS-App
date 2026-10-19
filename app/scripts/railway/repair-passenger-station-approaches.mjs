#!/usr/bin/env node
// Repeatable local display repair. Physical topology and source coordinates stay intact.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360), (b[1] - a[1]) * 111320);
const length = p => p.slice(1).reduce((sum, b, i) => sum + distance(p[i], b), 0);

export function repairPackage(input, evidence) {
  assert.equal(evidence.format, 'jtm-passenger-station-approaches-v1');
  const pkg = structuredClone(input);
  for (const item of evidence.items) {
    const line = pkg.lines.find(row => row.id === item.lineID);
    assert(line, 'Reviewed passenger line missing');
    assert.deepEqual(line.stations, item.baselineLine.stations, 'Canonical station identity/coordinates changed');
    assert.deepEqual(line.segments, item.physicalSegments, 'Physical geometry/mileage changed');
    assert.deepEqual(line.reversalTails || [], item.reversalTails, 'Protected reversal changed');
    const stripped = structuredClone(line);
    delete stripped.displayStationCoordinates;
    delete stripped.displayIntervalCoordinates;
    assert.deepEqual(stripped, item.baselineLine, 'Unreviewed line dependency changed');
    const anchors = { [item.stationID]: item.displayAnchor };
    assert(!line.displayStationCoordinates || equal(line.displayStationCoordinates, anchors), 'Unreviewed station override');
    assert(!line.displayIntervalCoordinates || equal(line.displayIntervalCoordinates, item.displayIntervals) ||
      equal(line.displayIntervalCoordinates, item.supersededDisplayIntervals), 'Unreviewed interval override');
    const cache = JSON.parse(fs.readFileSync(item.source.cacheAbsolutePath));
    assert.equal(cache.fetchedAt, item.source.fetchedAt, 'Source cache provenance changed');
    let track = [];
    for (const [id, reverse] of item.chain) {
      const pinned = item.ways.find(way => way.id === id), actual = cache.elements.find(way => way.id === id);
      assert.deepEqual({ id: actual?.id, tags: actual?.tags, coordinates: actual?.geometry.map(p => [p.lon, p.lat]) }, pinned, 'Passenger source changed');
      assert(pinned.tags.railway === 'rail' && !pinned.tags.service && pinned.tags.usage === 'main', 'Non-passenger/service track');
      assert(pinned.tags.operator === item.baselineLine.operator ||
        (item.stationID === '005260' && id === 463441237 && pinned.tags.operator === '箱根登山鉄道'),
      'Passenger operator changed');
      const points = structuredClone(pinned.coordinates);
      if (reverse) points.reverse();
      assert(!track.length || same(track.at(-1), points[0]), 'Source track chain disconnected');
      track.push(...points.slice(track.length ? 1 : 0));
    }
    assert.deepEqual(projectPointOntoPolyline(item.poi, track), item.anchorProjection, 'Station projection changed');
    assert(item.anchorProjection.distanceM < 2, 'Station POI does not corroborate selected track');
    for (const alias of item.seamAliases) {
      assert.deepEqual(projectPointOntoPolyline(alias.point, track), alias.projection, 'Display seam changed');
      assert(alias.projection.distanceM < 18, 'Display seam exceeds reviewed bounded alias');
    }
    line.displayStationCoordinates = anchors;
    line.displayIntervalCoordinates = structuredClone(item.displayIntervals);
    const parts = network.displayPartsForLine(line);
    assert.equal(parts.length, item.baselineParts.length, 'Display fork decomposition changed');
    const changedPart = item.stationID === '005260' ? 0 : 2;
    for (let i = 0; i < parts.length; i++) {
      if (i !== changedPart) assert.deepEqual(parts[i], item.baselineParts[i], 'Unrelated display part changed');
      assert.deepEqual(parts[i][0], item.baselineParts[i][0], 'Shared physical fork endpoint changed');
    }
    if (changedPart === 0) assert.deepEqual(parts[0].slice(0, 2), item.baselineParts[0].slice(0, 2), 'Initial measured follow changed');
    for (const point of item.reversalTails) assert(parts.some(part => part.some(p => same(p, point))), 'Reversal tip lost');
    assert(parts.some(part => part.some(p => same(p, item.displayAnchor))), 'Station is absent from display track');
  }
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['passenger-station-approaches'] = {
    reviewedAt: evidence.reviewedAt, crs: 'WGS84', policy: evidence.policy,
    script: 'app/scripts/railway/repair-passenger-station-approaches.mjs',
    evidence: 'app/scripts/railway/passenger-station-approaches-evidence.json',
    items: evidence.items.map(item => ({ lineID: item.lineID, stationID: item.stationID,
      source: item.source, chain: item.chain, displayAnchor: item.displayAnchor,
      seamAliases: item.seamAliases, physicalTopologyChanged: false }))
  };
  return pkg;
}

export function repairParts(pkg, input, evidence) {
  const result = structuredClone(input);
  for (const item of evidence.items) {
    const line = pkg.lines.find(row => row.id === item.lineID), parts = network.displayPartsForLine(line);
    const displayLine = { ...line, stations: line.stations.map(row => row[0] === item.stationID ? [row[0], row[1], ...item.displayAnchor, ...row.slice(4)] : row),
      segments: line.segments.map((row, i) => item.displayIntervals[i] ? [row[0], 0, item.displayIntervals[i]] : row) };
    const rows = partRowsForLine(line, parts, { stations: displayLine.stations, intervals: network.decodeIntervals(displayLine) }, null);
    const cached = input.partsByRegion.jp.filter(row => row[0] === item.lineID);
    assert(equal(cached, item.baselineNativeRows) || equal(cached, rows) || equal(cached, item.supersededNativeRows), 'Native part dependency changed');
    assert(rows.every(row => !row[8]?.length), 'Unreviewed withheld measures');
    result.partsByRegion.jp = result.partsByRegion.jp.map(row => row[0] === item.lineID ? rows[row[1]] : row);
    if (item.stationID === '005260') {
      const oldTotal = length(item.baselineParts[0]), total = length(parts[0]);
      const window = result.byRegion.jp.find(row => row[0] === item.lineID && row[1] === 0);
      assert(window && window[2] === 0 && (window[3] === oldTotal || window[3] === total ||
        window[3] === item.supersededSpurTotal), 'Station spur lane changed');
      window[3] = total;
    } else {
      for (const key of ['byRegion', 'familyWindowsByRegion', 'followsByRegion', 'loopsByRegion'])
        assert(!(input[key]?.jp || []).some(row => JSON.stringify(row).includes(item.lineID)), 'Unreviewed station measured references');
    }
  }
  return result;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), apply = equal(args, ['--apply']);
  assert(!args.length || apply, 'Usage: node repair-passenger-station-approaches.mjs [--apply]');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json',
    evidence: 'scripts/railway/passenger-station-approaches-evidence.json', ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const read = key => JSON.parse(snapshots[key].before), evidence = read('evidence');
  const pkg = repairPackage(read('package'), evidence), lanes = repairParts(pkg, read('lanes'), evidence);
  const dependencies = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, read(key)])));
  fs.writeFileSync('/private/tmp/jtm-station-approach-candidate.json', JSON.stringify(pkg));
  if (apply) applyPreparedWrites([{ ...snapshots.package, after: JSON.stringify(pkg) },
    { ...snapshots.lanes, after: JSON.stringify(lanes) + '\n' },
    ...Object.keys(DEPENDENCY_PATHS).map(key => ({ ...snapshots[key], after: JSON.stringify(dependencies[key], null, 2) + '\n' }))], Object.values(snapshots));
  console.log(JSON.stringify({ mode: apply ? 'applied' : 'candidate-only', stations: evidence.items.map(item => ({ id: item.stationID,
    displayCoordinate: item.displayAnchor, nativePartRows: lanes.partsByRegion.jp.filter(row => row[0] === item.lineID).map(row => row.slice(0, 7)) })), physicalTopologyChanged: false }));
}
