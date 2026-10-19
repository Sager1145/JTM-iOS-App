#!/usr/bin/env node
// Scratch by default; explicit --apply checks exact inputs before scoped writes.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
import { hasShioStage, retainedShioPackage, repairShioPackage, westernPassengerApproach } from './repair-keiyo-shio-transverse-display.mjs';
import { hasMinamiStage, retainedMinamiPackage, repairMinamiPackage } from './repair-keiyo-minami-passenger-centre.mjs';
import { repairParts as repairSharedParts } from './repair-keiyo-midcurve.mjs';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
export const LINES = ['jp-東日本旅客鉄道-京葉線-2', 'jp-東日本旅客鉄道-京葉線-3'];

export function surveyedPath(window, evidence, cache) {
  if (cache) assert(cache.format === 'osm-basemap-cell' && cache.fetchedAt === evidence.source.fetchedAt,
    'Keiyo source changed: cache provenance');
  for (const way of [...window.ways, ...window.corroboratingTracks]) {
    const t = way.tags;
    assert(t.railway === 'rail' && t.name === 'JR京葉線' && t.operator === '東日本旅客鉄道'
      && t.usage === 'main' && t.gauge === '1067' && !t.service,
    'Keiyo source changed: passenger main-track identity');
    if (cache) {
      const actual = cache.elements.find(row => row.id === way.id);
      assert(actual, 'Keiyo source changed: selected passenger way missing');
      assert.deepEqual({ id: actual.id, tags: actual.tags,
        coordinates: actual.geometry.map(point => [point.lon, point.lat]) }, way,
      'Keiyo source changed: selected or corroborating passenger way');
    }
  }
  let coordinates = [];
  for (const [id, reverse] of window.chain) {
    const way = window.ways.find(row => row.id === id);
    assert(way, 'Keiyo source changed: unpinned chain member');
    const points = structuredClone(way.coordinates);
    if (reverse) points.reverse();
    assert(!coordinates.length || same(coordinates.at(-1), points[0]),
      'Keiyo source changed: passenger track chain has a seam');
    coordinates.push(...points.slice(coordinates.length ? 1 : 0));
  }
  const start = projectPointOntoPolyline(window.start, coordinates);
  const end = projectPointOntoPolyline(window.end, coordinates);
  assert(start.distanceM <= 15 && end.distanceM <= 15 && start.insertIndex < end.insertIndex,
    'Keiyo source changed: bounded display seam alias');
  for (const [name, result] of Object.entries({ start, end })) {
    assert.deepEqual([result.insertIndex, result.insertIndex + 1], window.projectionAliases[name].surveyEdge,
      'Keiyo source changed: seam projection edge');
    assert(Math.abs(result.distanceM - window.projectionAliases[name].distanceMetres) < 1e-6,
      'Keiyo source changed: seam projection distance');
  }
  assert.deepEqual(window.surveySlice, [start.insertIndex + 1, end.insertIndex + 1]);
  return { points: coordinates.slice(...window.surveySlice), start, end };
}

export function repairPackage(input, evidence, cache, sections) {
  if (hasShioStage(input)) return repairShioPackage(repairPackage(retainedShioPackage(input), evidence, cache, sections), cache);
  if (hasMinamiStage(input)) return repairMinamiPackage(repairPackage(retainedMinamiPackage(input), evidence, cache, sections), cache);
  assert.equal(evidence.format, 'jtm-keiyo-display-curves-v1');
  assert.deepEqual(evidence.windows.map(row => row.lineId), LINES);
  const pkg = structuredClone(input);
  for (const window of evidence.windows) {
    assert.equal(window.interval, 0);
    if (sections) assert.deepEqual(sections.features[window.rawSource.featureIndex], window.rawSource.feature,
      'Keiyo source changed: original N02 feature');
    if (sections && window.passengerApproach) for (const source of window.passengerApproach.rawSources)
      assert.deepEqual(sections.features[source.featureIndex], source.feature, 'Western approach original N02 feature changed');
    const line = pkg.lines.find(row => row.id === window.lineId);
    assert(line, 'Keiyo source changed: passenger arm missing');
    assert.deepEqual(line.stations, window.stationRows, 'Keiyo source changed: passenger station binding');
    assert.deepEqual(line.segments, window.physicalSegments, 'Keiyo source changed: physical geometry or mileage');
    const original = network.decodeIntervals(line)[0], [a, b] = window.indices;
    assert(same(original[a], window.start) && same(original[b], window.end), 'Keiyo source changed: N02 seams');
    assert.deepEqual(original.slice(a + 1, b), window.replaced, 'Keiyo source changed: reviewed physical window');
    const survey = surveyedPath(window, evidence, cache);
    let display = [...original.slice(0, a + 1), ...survey.points, ...original.slice(b)];
    if (window.passengerApproach) display = westernPassengerApproach(display, window.passengerApproach, cache);
    const savedDisplay = line.displayIntervalCoordinates?.['0'];
    const existing = savedDisplay && window.passengerApproach
      ? westernPassengerApproach(savedDisplay, window.passengerApproach, cache) : savedDisplay;
    // The later midcurve replay continues this exact reviewed eastern tail.
    // Replaying the earlier tail step must preserve its shared representative.
    const later = window.lineId === LINES[0] && pkg.geometrySource?.manualOverrides?.['keiyo-midcurve'] &&
      JSON.parse(fs.readFileSync(path.join(ROOT, 'scripts/railway/keiyo-midcurve-evidence.json')));
    if (existing && later && equal(existing, later.candidate)) continue;
    assert(!existing || equal(existing, display), 'Keiyo display override changed; review before replacing');
    line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates, 0: display };
  }
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['keiyo-display-curves'] = {
    reviewedAt: evidence.reviewedAt, crs: evidence.crs,
    script: 'app/scripts/railway/repair-keiyo-display-curves.mjs',
    evidence: 'app/scripts/railway/keiyo-display-curves-evidence.json',
    source: evidence.source, displayPolicy: evidence.displayPolicy,
    historicalUncertainty: evidence.historicalUncertainty,
    windows: evidence.windows.map(row => ({ lineId: row.lineId, interval: row.interval,
      physicalVertexIndices: row.indices, wayChain: row.chain, surveySlice: row.surveySlice,
      projectionAliases: row.projectionAliases })),
  };
  return pkg;
}

export function repairParts(pkg, input, evidence) {
  let baseline = input;
  if (pkg.geometrySource?.manualOverrides?.['keiyo-shared-corridor']) {
    const midcurve = JSON.parse(fs.readFileSync(path.join(ROOT, 'scripts/railway/keiyo-midcurve-evidence.json')));
    if (hasShioStage(pkg) || hasMinamiStage(pkg) || equal(pkg.lines.find(line => line.id === LINES[0]).displayIntervalCoordinates?.[0], midcurve.candidate))
      baseline = repairSharedParts(pkg, input, midcurve);
  }
  const lanes = structuredClone(baseline);
  for (const window of evidence.windows) {
    // The shared stage owns only the eastern arm and trunk. Continue the
    // independent western tail repair and its measured-reference guards.
    if (baseline !== input && (window.lineId === LINES[0] || pkg.geometrySource?.manualOverrides?.['keiyo-west-shared-corridor'])) continue;
    const line = pkg.lines.find(row => row.id === window.lineId);
    const rows = partRowsForLine(line, network.displayPartsForLine(line), null, null);
    const oldRows = lanes.partsByRegion.jp.filter(row => row[0] === window.lineId);
    assert(equal(oldRows, window.nativePartBaseline) || equal(oldRows, rows),
      'Keiyo native part baseline changed; review before replacing');
    assert(oldRows.length === 1 && rows.length === 1 && !oldRows[0][8]?.length && !rows[0][8]?.length,
      'Keiyo native topology/withheld measure changed');
    for (const key of ['byRegion', 'familyWindowsByRegion', 'loopsByRegion', 'chainBoundariesByRegion', 'hubReportByRegion', 'followsByRegion'])
      assert(!(lanes[key]?.jp || []).some(row => JSON.stringify(row).includes(window.lineId)),
        'Keiyo affected measured reference requires review');
    assert(!(lanes.reversedLoopParts?.jp || []).some(row => row.split('#')[0] === window.lineId),
      'Keiyo affected loop reference requires review');
    lanes.partsByRegion.jp = lanes.partsByRegion.jp.map(row => row[0] === window.lineId ? rows[0] : row);
  }
  assert.deepEqual(lanes.partsByRegion.jp.filter(row => !LINES.includes(row[0])), baseline.partsByRegion.jp.filter(row => !LINES.includes(row[0])));
  for (const key of Object.keys(baseline).filter(key => key !== 'partsByRegion')) assert.deepEqual(lanes[key], baseline[key]);
  for (const region of Object.keys(baseline.partsByRegion).filter(key => key !== 'jp')) assert.deepEqual(lanes.partsByRegion[region], baseline.partsByRegion[region]);
  return lanes;
}

const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360), (b[1] - a[1]) * 111320);
const measure = (points, index) => points.slice(1, index + 1).reduce((sum, point, n) => sum + distance(points[n], point), 0);
export function reviewSummary(before, after, evidence) {
  return evidence.windows.map(window => {
    if (window.lineId === LINES[1] && hasShioStage(after)) {
      retainedShioPackage(after);
      const line = after.lines.find(row => row.id === window.lineId);
      assert.deepEqual(line, before.lines.find(row => row.id === window.lineId), 'Tail replay must retain the exact Shio transverse stage');
      surveyedPath(window, evidence);
      return { lineID:line.id, intervalIndex:0, partIndex:0, retainedDisplayStage:'keiyo-shio-transverse-display',
        nativePartRows:partRowsForLine(line, network.displayPartsForLine(line)).map(row=>row.slice(0,7)),
        limits:'Earlier tail provenance retained; local transverse stage owns displayed station joins. Physical geometry unchanged; native acceptance remains separate.' };
    }
    // A later station centre intentionally replaces the old tail-end alias.
    // Its retained-stage guard validates that exact composition; the earlier
    // source window no longer owns that endpoint or its display ruler.
    if (window.lineId === LINES[0] && hasMinamiStage(after)) {
      retainedMinamiPackage(after);
      const line = after.lines.find(row => row.id === window.lineId);
      assert.deepEqual(line, before.lines.find(row => row.id === window.lineId),
        'Tail replay must retain the exact final passenger centre');
      surveyedPath(window, evidence);
      return { lineID: line.id, intervalIndex: 0, partIndex: 0,
        retainedDisplayStage: 'keiyo-minami-passenger-centre',
        nativePartRows: partRowsForLine(line, network.displayPartsForLine(line)).map(row => row.slice(0, 7)),
        limits: 'Earlier survey provenance retained; final local passenger centre owns the displayed endpoint. Physical geometry unchanged; native visual acceptance remains separate.' };
    }
    const original = network.displayPartsForLine(before.lines.find(row => row.id === window.lineId));
    const line = after.lines.find(row => row.id === window.lineId), parts = network.displayPartsForLine(line);
    assert(original.length === 1 && parts.length === 1);
    const old = original[0], current = parts[0], survey = surveyedPath(window, evidence);
    const locate = (points, target) => points.findIndex(point => same(point, target));
    const indices = { oldStart: locate(old, window.start), oldEnd: locate(old, window.end),
      newStart: locate(current, window.start), newEnd: locate(current, window.end) };
    assert(Object.values(indices).every(index => index >= 0), 'Keiyo display grooming removed a reviewed seam');
    const oldPrefix = old.slice(0, indices.oldStart + 1);
    assert.deepEqual(window.passengerApproach ? westernPassengerApproach(oldPrefix, window.passengerApproach) : oldPrefix,
      current.slice(0, indices.newStart + 1));
    assert.deepEqual(old.slice(indices.oldEnd), current.slice(indices.newEnd));
    assert.deepEqual(current.slice(indices.newStart + 1, indices.newEnd), survey.points,
      'Keiyo display grooming altered exact passenger source points');
    return { lineID: window.lineId, intervalIndex: 0, partIndex: 0,
      chosenWayChain: window.chain, insertedSourceVertices: survey.points.length,
      seamAliasesMetres: { start: survey.start.distanceM, end: survey.end.distanceM },
      partVertexIndices: indices,
      partMeasuresMetres: { oldStart: measure(old, indices.oldStart), oldEnd: measure(old, indices.oldEnd),
        newStart: measure(current, indices.newStart), newEnd: measure(current, indices.newEnd),
        oldTotal: measure(old, old.length - 1), newTotal: measure(current, current.length - 1) },
      ...(window.passengerApproach ? { passengerApproach: {
        wayChain: window.passengerApproach.chain, routeRelation: window.passengerApproach.routeMembership.id,
        prefixMeasureDeltaMetres: measure(current, indices.newStart) - measure(old, indices.oldStart),
        policy: window.passengerApproach.policy } } : {}),
      nativePartRows: partRowsForLine(line, parts, null, null).map(row => row.slice(0, 7)),
      limits: 'Display-only candidate; physical mileage unchanged. Native ruler changes only by reviewed window delta; native visual comparison pending.' };
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const apply = args.length === 1 && args[0] === '--apply';
  const dryRun = !args.length || (args.length === 1 && args[0] === '--dry-run');
  assert(apply || dryRun || (args.length === 2 && args[0] === '--output'),
    'Usage: node repair-keiyo-display-curves.mjs [--dry-run | --output /private/tmp/candidate.json | --apply]');
  const output = path.resolve(args[1] || '/private/tmp/jtm-keiyo-display-candidate.json');
  assert(output.startsWith('/private/tmp/') || output.startsWith('/tmp/'), 'Keiyo output must be scratch-only');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json',
    sections: 'data/rail-sections.json', evidence: 'scripts/railway/keiyo-display-curves-evidence.json',
    shared: 'public/rail/shared-corridors.json', network: 'public/rail-network.js',
    partsBuilder: 'scripts/railway/build-display-lanes.mjs', geo: 'scripts/railway/jp-manual-corrections/geo.mjs',
    dependencyHelper: 'scripts/railway/repair-three-reversal-extents.mjs',
    script: 'scripts/railway/repair-keiyo-display-curves.mjs', ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.resolve(ROOT, relative);
    return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const read = key => JSON.parse(snapshots[key].before);
  const evidence = read('evidence'), input = read('package'), shared = read('shared');
  snapshots.cache = { path: evidence.source.cacheAbsolutePath,
    before: fs.readFileSync(evidence.source.cacheAbsolutePath, 'utf8') };
  const cache = read('cache');
  assert(!LINES.some(id => JSON.stringify(shared).includes(id)), 'Keiyo shared-corridor dependency requires review');
  const candidate = repairPackage(input, evidence, cache, read('sections'));
  const lanes = repairParts(candidate, read('lanes'), evidence);
  const dependencies = refreshDependencyReferences(candidate,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, read(key)])));
  const summary = reviewSummary(input, candidate, evidence);
  fs.writeFileSync(output, JSON.stringify(candidate));
  for (const [suffix, data] of Object.entries({ lanes, review: summary, dependencies }))
    fs.writeFileSync(output.replace(/\.json$/, '') + '.' + suffix + '.json', JSON.stringify(data, null, 2) + '\n');
  if (apply) {
    const writes = [{ ...snapshots.package, after: JSON.stringify(candidate) },
      { ...snapshots.lanes, after: JSON.stringify(lanes) + '\n' },
      ...Object.keys(DEPENDENCY_PATHS).map(key => ({ ...snapshots[key],
        after: JSON.stringify(dependencies[key], null, 2) + '\n' }))];
    applyPreparedWrites(writes, Object.values(snapshots));
  }
  console.log(JSON.stringify({ output, mode: apply ? 'applied' : 'candidate-only', windows: summary,
    refreshedDependencyPaths: Object.values(DEPENDENCY_PATHS) }));
}
