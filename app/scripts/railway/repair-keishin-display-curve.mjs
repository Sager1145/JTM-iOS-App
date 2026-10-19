#!/usr/bin/env node
// Default is a scratch display candidate; --apply checks exact input snapshots
// before scoped publication. Physical N02 topology and mileage remain intact.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
export const LINE = 'jp-京阪電気鉄道-京津線';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);

export function surveyedPath(evidence, cache) {
  const way = evidence.way, tags = way.tags;
  assert(tags.railway === 'rail' && tags.operator === '京阪電気鉄道' && tags.name === '京阪電気鉄道京津線'
    && tags.gauge === '1435' && tags.passenger_lines === '2' && !tags.service && tags.usage === 'branch',
    'Keishin source changed: selected passenger track identity');
  if (cache) {
    assert(cache.format === 'osm-basemap-cell' && cache.fetchedAt === evidence.source.fetchedAt,
      'Keishin source changed: cached survey provenance');
    const sourceWay = cache.elements.find(row => row.id === way.id);
    assert(sourceWay, 'Keishin source changed: selected cached way absent');
    assert.deepEqual({ id: sourceWay.id, tags: sourceWay.tags,
      coordinates: sourceWay.geometry.map(point => [point.lon, point.lat]) }, way,
      'Keishin source changed: selected cached way');
  }
  const start = projectPointOntoPolyline(evidence.start, way.coordinates);
  const end = projectPointOntoPolyline(evidence.end, way.coordinates);
  assert(start.distanceM <= 15 && end.distanceM <= 15 && start.insertIndex < end.insertIndex,
    'Keishin source changed: display seam alias outside reviewed passenger track');
  assert.deepEqual([start.insertIndex, start.insertIndex + 1], evidence.projectionAliases.start.surveyEdge);
  assert.deepEqual([end.insertIndex, end.insertIndex + 1], evidence.projectionAliases.end.surveyEdge);
  // Use one track's exact consecutive source vertices between the projections.
  // Retained N02 seams are separate display aliases, never physical rail edges.
  assert.deepEqual(evidence.surveySlice, [start.insertIndex + 1, end.insertIndex + 1]);
  return { points: way.coordinates.slice(...evidence.surveySlice), start, end };
}

export function repairPackage(input, evidence, cache, sections) {
  assert.equal(evidence.format, 'jtm-keishin-display-curve-v1');
  assert(evidence.lineId === LINE && evidence.interval === 4);
  if (sections) assert.deepEqual(sections.features[evidence.rawSource.featureIndex], evidence.rawSource.feature,
    'Keishin source changed: original N02 survey feature');
  const pkg = structuredClone(input), line = pkg.lines.find(row => row.id === LINE);
  assert(line, 'Keishin source changed: line missing');
  assert.deepEqual(line.stations.slice(4, 6).map(row => row[0]), evidence.stations,
    'Keishin source changed: passenger interval identity');
  const original = network.decodeIntervals(line)[4];
  const a = original.findIndex(point => same(point, evidence.start));
  const b = original.findIndex(point => same(point, evidence.end));
  assert(a >= 0 && b > a, 'Keishin source changed: reviewed N02 seams missing');
  assert.deepEqual(original.slice(a + 1, b), evidence.replaced, 'Keishin source changed: isolated faulty vertex differs');
  const survey = surveyedPath(evidence, cache);
  const display = [...original.slice(0, a + 1), ...survey.points, ...original.slice(b)];
  const existing = line.displayIntervalCoordinates?.['4'];
  assert(!existing || equal(existing, display), 'Keishin display override changed; review before replacing');
  line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates, 4: display };
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['keishin-display-curve'] = {
    reviewedAt: evidence.reviewedAt, crs: evidence.crs,
    script: 'app/scripts/railway/repair-keishin-display-curve.mjs',
    evidence: 'app/scripts/railway/keishin-display-curve-evidence.json',
    source: evidence.source, wayIds: [evidence.way.id], displayPolicy: evidence.displayPolicy,
    projectionAliases: evidence.projectionAliases, historicalUncertainty: evidence.historicalUncertainty,
    transformation: 'Replace only the inherited off-track display vertex in Otani–Kamisakaemachi with exact ordered vertices of one passenger OSM track; retain both N02 seams, physical segments, station anchors, mileage, identities and dates.',
  };
  return pkg;
}

export function repairParts(pkg, input, evidence) {
  const lanes = structuredClone(input), line = pkg.lines.find(row => row.id === LINE);
  const parts = network.displayPartsForLine(line);
  const rows = partRowsForLine(line, parts, null, null);
  const oldRows = lanes.partsByRegion.jp.filter(row => row[0] === LINE);
  assert(equal(oldRows, evidence.nativePartBaseline) || equal(oldRows, rows),
    'Keishin native part baseline changed; review before replacing');
  assert(oldRows.length === 1 && rows.length === 1 && !oldRows[0][8]?.length && !rows[0][8]?.length,
    'Keishin native part topology or withheld measure changed');
  for (const key of ['byRegion', 'familyWindowsByRegion', 'loopsByRegion', 'chainBoundariesByRegion', 'hubReportByRegion', 'followsByRegion'])
    assert(!(lanes[key]?.jp || []).some(row => JSON.stringify(row).includes(LINE)),
      'Keishin affected measured reference requires review');
  assert(!(lanes.reversedLoopParts?.jp || []).some(row => row.split('#')[0] === LINE),
    'Keishin affected loop reference requires review');
  lanes.partsByRegion.jp = lanes.partsByRegion.jp.map(row => row[0] === LINE ? rows[0] : row);
  assert.deepEqual(lanes.partsByRegion.jp.filter(row => row[0] !== LINE), input.partsByRegion.jp.filter(row => row[0] !== LINE));
  for (const key of Object.keys(input).filter(key => key !== 'partsByRegion')) assert.deepEqual(lanes[key], input[key]);
  for (const region of Object.keys(input.partsByRegion).filter(region => region !== 'jp'))
    assert.deepEqual(lanes.partsByRegion[region], input.partsByRegion[region]);
  return lanes;
}

const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
  (b[1] - a[1]) * 111320);
const measure = (points, index) => points.slice(1, index + 1).reduce((total, point, n) => total + distance(points[n], point), 0);

export function reviewSummary(before, after, evidence) {
  const oldParts = network.displayPartsForLine(before.lines.find(row => row.id === LINE));
  const newLine = after.lines.find(row => row.id === LINE), newParts = network.displayPartsForLine(newLine);
  assert(oldParts.length === 1 && newParts.length === 1);
  const old = oldParts[0], current = newParts[0], survey = surveyedPath(evidence);
  const locate = (points, target) => points.findIndex(point => same(point, target));
  const indices = { oldStart: locate(old, evidence.start), oldEnd: locate(old, evidence.end),
    newStart: locate(current, evidence.start), newEnd: locate(current, evidence.end) };
  assert(Object.values(indices).every(index => index >= 0), 'Keishin display seam was removed by production grooming');
  assert.deepEqual(old.slice(0, indices.oldStart + 1), current.slice(0, indices.newStart + 1));
  assert.deepEqual(old.slice(indices.oldEnd), current.slice(indices.newEnd));
  return {
    lineID: LINE, intervalIndex: 4, partIndex: 0, chosenWay: evidence.way.id,
    surveySlice: evidence.surveySlice, insertedSourceVertices: survey.points.length,
    seamAliases: { start: { metres: survey.start.distanceM, sourceEdge: survey.start.insertIndex },
      end: { metres: survey.end.distanceM, sourceEdge: survey.end.insertIndex },
      metric: 'Local metric projection using mean Earth radius; not Apple pixel residual' },
    partVertexIndices: indices,
    partMeasuresMetres: { oldStart: measure(old, indices.oldStart), oldEnd: measure(old, indices.oldEnd),
      newStart: measure(current, indices.newStart), newEnd: measure(current, indices.newEnd),
      oldTotal: measure(old, old.length - 1), newTotal: measure(current, current.length - 1),
      metric: 'Production display equirectangular ruler,111320m/degree; not physical mileage' },
    nativePartRows: partRowsForLine(newLine, newParts, null, null).map(row => row.slice(0, 7)),
    scope: 'Bounded display correction; physical geometry unchanged; native visual recheck pending',
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const apply = args.length === 1 && args[0] === '--apply';
  const dryRun = !args.length || (args.length === 1 && args[0] === '--dry-run');
  assert(apply || dryRun || (args.length === 2 && args[0] === '--output'),
    'Usage: node repair-keishin-display-curve.mjs [--dry-run | --output /private/tmp/candidate.json | --apply]');
  const output = path.resolve(args[1] || '/private/tmp/jtm-keishin-display-candidate.json');
  assert(output.startsWith('/private/tmp/') || output.startsWith('/tmp/'), 'Keishin output must be scratch-only');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json',
    sections: 'data/rail-sections.json', evidence: 'scripts/railway/keishin-display-curve-evidence.json',
    shared: 'public/rail/shared-corridors.json', network: 'public/rail-network.js',
    partsBuilder: 'scripts/railway/build-display-lanes.mjs', geo: 'scripts/railway/jp-manual-corrections/geo.mjs',
    dependencyHelper: 'scripts/railway/repair-three-reversal-extents.mjs',
    script: 'scripts/railway/repair-keishin-display-curve.mjs', ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.resolve(ROOT, relative);
    return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const read = key => JSON.parse(snapshots[key].before);
  const evidence = read('evidence'), input = read('package'), sections = read('sections'), shared = read('shared');
  snapshots.cache = { path: evidence.source.cacheAbsolutePath,
    before: fs.readFileSync(evidence.source.cacheAbsolutePath, 'utf8') };
  const cache = read('cache');
  assert(!JSON.stringify(shared).includes(LINE), 'Keishin shared-corridor dependency requires review');
  const candidate = repairPackage(input, evidence, cache, sections);
  const lanes = repairParts(candidate, read('lanes'), evidence);
  const dependencies = refreshDependencyReferences(candidate,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, read(key)])));
  const summary = reviewSummary(input, candidate, evidence);
  fs.writeFileSync(output, JSON.stringify(candidate));
  fs.writeFileSync(output.replace(/\.json$/, '') + '.lanes.json', JSON.stringify(lanes) + '\n');
  fs.writeFileSync(output.replace(/\.json$/, '') + '.review.json', JSON.stringify(summary, null, 2) + '\n');
  fs.writeFileSync(output.replace(/\.json$/, '') + '.dependencies.json', JSON.stringify(dependencies, null, 2) + '\n');
  if (apply) {
    const writes = [{ ...snapshots.package, after: JSON.stringify(candidate) },
      { ...snapshots.lanes, after: JSON.stringify(lanes) + '\n' },
      ...Object.keys(DEPENDENCY_PATHS).map(key => ({ ...snapshots[key],
        after: JSON.stringify(dependencies[key], null, 2) + '\n' }))];
    applyPreparedWrites(writes, Object.values(snapshots));
  }
  console.log(output);
  console.log(JSON.stringify({ mode: apply ? 'applied' : 'candidate-only', ...summary,
    refreshedDependencyPaths: Object.values(DEPENDENCY_PATHS) }));
}
